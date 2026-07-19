import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import '../process_line_stream.dart';
import 'feature_isolate_host.dart';

const _maxLogLines = 10000;

class LogWorkerConfig {
  LogWorkerConfig({
    required this.packageName,
    required this.bundleId,
    required this.deviceId,
  });

  final String packageName;
  final String bundleId;
  final String deviceId;

  Map<String, Object?> toJson() => <String, Object?>{
        'packageName': packageName,
        'bundleId': bundleId,
        'deviceId': deviceId,
      };

  factory LogWorkerConfig.fromJson(Map<String, Object?> json) {
    return LogWorkerConfig(
      packageName: (json['packageName'] as String?) ?? '',
      bundleId: (json['bundleId'] as String?) ?? '',
      deviceId: (json['deviceId'] as String?) ?? '',
    );
  }
}

/// Device log ingestion + search runs in its own isolate (one per monitor session).
@pragma('vm:entry-point')
void deviceLogWorkerMain(SendPort handshakePort) {
  final workerReceive = ReceivePort();
  handshakePort.send(workerReceive.sendPort);

  DeviceLogWorkerEngine? engine;
  SendPort? mainPort;

  workerReceive.listen((Object? message) async {
    if (message is! List || message.isEmpty) {
      return;
    }
    final kind = message[0];
    if (kind == 'init') {
      mainPort = handshakePort;
      final config = LogWorkerConfig.fromJson(
        Map<String, Object?>.from(
          (message[1] as Map<Object?, Object?>?) ?? const {},
        ),
      );
      engine = DeviceLogWorkerEngine(
        config: config,
        onChange: () {
          if (mainPort != null) {
            mainPort!.send(<Object?>['event', 'changed']);
          }
        },
      );
      await engine!.start();
      return;
    }
    if (kind != 'request' || message.length < 4 || engine == null) {
      return;
    }
    final requestId = message[1] as int;
    final command = message[2] as String;
    final args = Map<String, Object?>.from(
      (message[3] as Map<Object?, Object?>?) ?? const {},
    );
    try {
      final result = await engine!.handle(command, args);
      handshakePort.send(<Object?>['response', requestId, result]);
    } on Object catch (error) {
      handshakePort.send(<Object?>[
        'response',
        requestId,
        <String, Object?>{'ok': false, 'error': error.toString()},
      ]);
    }
  });
}

class DeviceLogWorkerEngine {
  DeviceLogWorkerEngine({
    required this.config,
    required this.onChange,
  });

  final LogWorkerConfig config;
  final void Function() onChange;

  final ListQueue<String> _lines = ListQueue();
  Process? _process;
  var _streaming = false;
  String? _error;
  String? _lineFilter;
  var _revision = 0;
  var _sessionRevision = 0;
  Timer? _retryTimer;

  Future<void> start() async {
    if (_streaming || config.deviceId.isEmpty) {
      return;
    }
    if (await _startAndroid()) {
      return;
    }
    if (await _startIos()) {
      return;
    }
    _error = 'Could not start device logs for device ${config.deviceId}';
    _notifyChange();
    _scheduleRetry();
  }

  Future<Object?> handle(String command, Map<String, Object?> args) async {
    switch (command) {
      case 'dispose':
        await _dispose();
        return <String, Object?>{'ok': true};
      case 'stop':
        await stop();
        return <String, Object?>{'ok': true};
      case 'restartForReinstall':
        await restartForReinstall();
        return <String, Object?>{'ok': true};
      case 'reconnect':
        await reconnect();
        return <String, Object?>{'ok': true};
      case 'snapshot':
        return _snapshot(
          query: (args['query'] as String?) ?? '',
          caseSensitive: args['caseSensitive'] == true,
          includeDeployOutput: false,
        );
      case 'search':
        return _searchSnapshot(
          query: (args['query'] as String?) ?? '',
          caseSensitive: args['caseSensitive'] == true,
        );
      default:
        throw StateError('Unknown log worker command: $command');
    }
  }

  Map<String, Object?> _snapshot({
    required String query,
    required bool caseSensitive,
    required bool includeDeployOutput,
  }) {
    final matchedLines = query.isEmpty
        ? const <String>[]
        : _searchLines(query, caseSensitive: caseSensitive);
    final payload = <String, Object?>{
      'lines': List<String>.from(_lines),
      'streaming': _streaming,
      'connected': _streaming && _lines.isNotEmpty,
      'lineCount': _lines.length,
      'revision': _revision,
      'sessionRevision': _sessionRevision,
      'error': _error,
      'searchQuery': query,
      'searchMatches': matchedLines,
      'searchMatchCount': matchedLines.length,
      'reinstallOutput': const <String>[],
      'reinstallRunning': false,
      'deployRevision': 0,
      'flutterDeployGeneration': 0,
      'flutterOutputRevision': 0,
    };
    return <String, Object?>{
      'payload': payload,
      'json': jsonEncode(payload),
    };
  }

  Map<String, Object?> _searchSnapshot({
    required String query,
    required bool caseSensitive,
  }) {
    final matches = _searchLines(query, caseSensitive: caseSensitive);
    final payload = <String, Object?>{
      'query': query,
      'matches': matches,
      'matchCount': matches.length,
      'lineCount': _lines.length,
      'sessionRevision': _sessionRevision,
    };
    return <String, Object?>{
      'payload': payload,
      'json': jsonEncode(payload),
    };
  }

  List<String> _searchLines(String query, {required bool caseSensitive}) {
    final trimmed = query.trim();
    if (trimmed.isEmpty) {
      return const <String>[];
    }
    final needle = caseSensitive ? trimmed : trimmed.toLowerCase();
    return _lines.where((line) {
      final haystack = caseSensitive ? line : line.toLowerCase();
      return haystack.contains(needle);
    }).toList(growable: false);
  }

  void _notifyChange() {
    _revision++;
    onChange();
  }

  Future<void> _dispose() async {
    _retryTimer?.cancel();
    await stop();
  }

  Future<void> stop() async {
    _streaming = false;
    final process = _process;
    _process = null;
    if (process != null) {
      process.kill(ProcessSignal.sigterm);
      try {
        await process.exitCode.timeout(const Duration(seconds: 2));
      } on Object {
        process.kill(ProcessSignal.sigkill);
      }
    }
  }

  Future<void> restartForReinstall() async {
    _retryTimer?.cancel();
    await stop();
    _lines.clear();
    _sessionRevision++;
    _error = null;
    await start();
  }

  Future<void> reconnect() async {
    _retryTimer?.cancel();
    await stop();
    _error = null;
    await start();
  }

  void _scheduleRetry() {
    if (config.deviceId.isEmpty || _streaming) {
      return;
    }
    _retryTimer?.cancel();
    _retryTimer = Timer.periodic(const Duration(seconds: 2), (_) async {
      if (_streaming) {
        _retryTimer?.cancel();
        return;
      }
      if (await _startAndroid() || await _startIos()) {
        _retryTimer?.cancel();
      }
    });
  }

  Future<bool> _startAndroid() async {
    if (config.packageName.isEmpty) {
      return false;
    }
    final adb = await _resolveAdb();
    if (adb == null) {
      return false;
    }
    final serial = await _resolveAndroidSerial(adb);
    if (serial == null) {
      return false;
    }
    final uid = await _resolveAndroidUid(adb, serial, config.packageName);
    final args = <String>['-s', serial, 'logcat', '-v', 'time'];
    if (uid != null && uid.isNotEmpty) {
      args.add('--uid=$uid');
      _lineFilter = null;
    } else {
      _lineFilter = config.packageName;
    }
    try {
      _process = await Process.start(adb, args);
    } on Object catch (error) {
      _error = 'Failed to start adb logcat: $error';
      return false;
    }
    _bindProcess(_process!);
    _streaming = true;
    _error = null;
    _notifyChange();
    return true;
  }

  Future<bool> _startIos() async {
    if (config.bundleId.isEmpty || !Platform.isMacOS) {
      return false;
    }
    final args = <String>[
      'stream',
      '--style',
      'compact',
      '--level',
      'debug',
      '--predicate',
      'subsystem CONTAINS "${config.bundleId}" OR processImagePath CONTAINS "${config.bundleId}"',
    ];
    if (config.deviceId.isNotEmpty) {
      args.insert(0, config.deviceId);
      args.insert(0, '--device-udid');
    }
    try {
      _process = await Process.start('/usr/bin/log', args);
    } on Object catch (error) {
      _error = 'Failed to start iOS log stream: $error';
      return false;
    }
    _bindProcess(_process!);
    _streaming = true;
    _error = null;
    _notifyChange();
    return true;
  }

  void _bindProcess(Process process) {
    bindProcessLines(process.stdout, _appendLine, onError: (error) {
      _error = 'Device log decode error: $error';
      _notifyChange();
    });
    bindProcessLines(
      process.stderr,
      (line) => _appendLine('[stderr] $line'),
      onError: (error) {
        _error = 'Device log stderr error: $error';
        _notifyChange();
      },
    );
    process.exitCode.then((code) {
      _streaming = false;
      if (code != 0) {
        _error = 'Device log process exited with code $code';
      }
      _notifyChange();
      _scheduleRetry();
    });
  }

  void _appendLine(String line) {
    if (_lineFilter != null &&
        !line.contains(_lineFilter!) &&
        !_isInterestingAndroidLine(line)) {
      return;
    }
    final hadLines = _lines.isNotEmpty;
    _lines.addLast(line);
    while (_lines.length > _maxLogLines) {
      _lines.removeFirst();
    }
    if (!hadLines || _lines.length % 5 == 0) {
      _notifyChange();
    }
  }

  bool _isInterestingAndroidLine(String line) {
    final lower = line.toLowerCase();
    return lower.contains('flutter') ||
        lower.contains('dartvm') ||
        line.contains('TripStreamWorker') ||
        line.contains('TripStreamIsolate') ||
        line.contains('TripStreamNavForwarder') ||
        line.contains('TripStreamSession');
  }

  Future<String?> _resolveAdb() async {
    final result = await Process.run('which', ['adb']);
    if (result.exitCode != 0) {
      return null;
    }
    final path = (result.stdout as String).trim();
    return path.isEmpty ? null : path;
  }

  Future<String?> _resolveAndroidSerial(String adb) async {
    final result = await Process.run(adb, ['devices']);
    if (result.exitCode != 0) {
      return null;
    }
    final lines = (result.stdout as String).split('\n');
    for (final line in lines.skip(1)) {
      final parts = line.trim().split(RegExp(r'\s+'));
      if (parts.length >= 2 && parts[1] == 'device') {
        final serial = parts[0];
        if (config.deviceId.isEmpty || serial == config.deviceId) {
          return serial;
        }
      }
    }
    return null;
  }

  Future<String?> _resolveAndroidUid(
    String adb,
    String serial,
    String package,
  ) async {
    final result = await Process.run(
      adb,
      ['-s', serial, 'shell', 'dumpsys', 'package', package],
    );
    if (result.exitCode != 0) {
      return null;
    }
    final match = RegExp(r'userId=(\d+)').firstMatch(result.stdout as String);
    return match?.group(1);
  }
}

/// Main-isolate facade — owns exactly one [deviceLogWorkerMain] isolate.
class DeviceLogWorkerFacade {
  DeviceLogWorkerFacade({
    required this.packageName,
    required this.bundleId,
    required this.deviceId,
  }) : _host = FeatureIsolateHost(
          debugName: 'device-log-worker',
          entryPoint: deviceLogWorkerMain,
        );

  final String packageName;
  final String bundleId;
  final String deviceId;
  final FeatureIsolateHost _host;
  final _changes = StreamController<void>.broadcast();
  StreamSubscription<String>? _eventSub;

  var _lineCount = 0;
  var _revision = 0;
  var _sessionRevision = 0;
  var _streaming = false;
  String? _error;

  Stream<void> get changes => _changes.stream;
  bool get isStreaming => _streaming;
  String? get error => _error;
  int get lineCount => _lineCount;
  int get revision => _revision;
  int get sessionRevision => _sessionRevision;
  List<String> get recentLines => const [];

  Future<void> start() async {
    await _host.start(
      LogWorkerConfig(
        packageName: packageName,
        bundleId: bundleId,
        deviceId: deviceId,
      ).toJson(),
    );
    _eventSub = _host.events.listen((_) {
      _changes.add(null);
    });
  }

  Future<void> dispose() async {
    await _eventSub?.cancel();
    await _host.dispose();
    await _changes.close();
  }

  Future<void> stop() => _host.request<Object?>('stop');

  Future<void> restartForReinstall() =>
      _host.request<Object?>('restartForReinstall');

  Future<void> reconnect() => _host.request<Object?>('reconnect');

  List<String> searchLines(String query, {bool caseSensitive = false}) {
    return const [];
  }

  Future<Map<String, Object?>> fetchLogsPayload({
    String query = '',
    bool caseSensitive = false,
  }) async {
    final result = await _host.request<Map<Object?, Object?>>(
      'snapshot',
      <String, Object?>{
        'query': query,
        'caseSensitive': caseSensitive,
      },
    );
    final payload = Map<String, Object?>.from(
      (result['payload'] as Map<Object?, Object?>?) ?? const {},
    );
    _lineCount = payload['lineCount'] as int? ?? 0;
    _revision = payload['revision'] as int? ?? 0;
    _sessionRevision = payload['sessionRevision'] as int? ?? 0;
    _streaming = payload['streaming'] == true;
    _error = payload['error'] as String?;
    return payload;
  }

  Future<String> fetchLogsJson({
    String query = '',
    bool caseSensitive = false,
  }) async {
    final result = await _host.request<Map<Object?, Object?>>(
      'snapshot',
      <String, Object?>{
        'query': query,
        'caseSensitive': caseSensitive,
      },
    );
    return (result['json'] as String?) ?? '{}';
  }

  Future<String> fetchSearchJson({
    required String query,
    bool caseSensitive = false,
  }) async {
    final result = await _host.request<Map<Object?, Object?>>(
      'search',
      <String, Object?>{
        'query': query,
        'caseSensitive': caseSensitive,
      },
    );
    return (result['json'] as String?) ?? '{}';
  }
}
