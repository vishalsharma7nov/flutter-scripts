import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:http/http.dart' as http;
import 'package:vm_service/vm_service.dart';
import 'package:vm_service/vm_service_io.dart';

import 'feature_isolate_host.dart';

class VmWorkerConfig {
  VmWorkerConfig({
    required this.vmPort,
    this.uriOverride,
  });

  final int vmPort;
  final String? uriOverride;

  Map<String, Object?> toJson() => <String, Object?>{
        'vmPort': vmPort,
        'uriOverride': uriOverride,
      };

  factory VmWorkerConfig.fromJson(Map<String, Object?> json) {
    return VmWorkerConfig(
      vmPort: json['vmPort'] as int? ?? 58888,
      uriOverride: json['uriOverride'] as String?,
    );
  }
}

@pragma('vm:entry-point')
void vmInspectorWorkerMain(SendPort handshakePort) {
  final workerReceive = ReceivePort();
  handshakePort.send(workerReceive.sendPort);

  VmInspectorEngine? engine;

  workerReceive.listen((Object? message) async {
    if (message is! List || message.isEmpty) {
      return;
    }
    final kind = message[0];
    if (kind == 'init') {
      final config = VmWorkerConfig.fromJson(
        Map<String, Object?>.from(
          (message[1] as Map<Object?, Object?>?) ?? const {},
        ),
      );
      engine = VmInspectorEngine(
        config: config,
        onChange: () => handshakePort.send(<Object?>['event', 'changed']),
      );
      await engine!.startPolling();
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

class VmInspectorEngine {
  VmInspectorEngine({
    required this.config,
    required this.onChange,
  });

  final VmWorkerConfig config;
  final void Function() onChange;

  VmService? _service;
  String? _vmUri;
  Timer? _timer;
  List<Map<String, Object?>>? _cachedIsolates;
  DateTime? _isolatesCachedAt;
  static const _isolatesCacheTtl = Duration(seconds: 2);

  Future<void> startPolling() async {
    await _poll();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _poll());
  }

  Future<void> dispose() async {
    _timer?.cancel();
    await _service?.dispose();
  }

  Future<Object?> handle(String command, Map<String, Object?> args) async {
    switch (command) {
      case 'dispose':
        await dispose();
        return <String, Object?>{'ok': true};
      case 'status':
        return <String, Object?>{
          'connected': _service != null,
          'vmUri': _vmUri,
        };
      case 'listIsolates':
        return await listIsolates();
      case 'hotReload':
        return await hotReload();
      case 'hotRestart':
        return await hotRestart();
      case 'quitApp':
        return await quitApp();
      case 'resetConnection':
        await resetConnection();
        return <String, Object?>{'ok': true};
      default:
        throw StateError('Unknown VM worker command: $command');
    }
  }

  Future<void> _poll() async {
    if (_service != null) {
      return;
    }
    final uri = config.uriOverride ?? await _discoverVmUri(config.vmPort);
    if (uri == null) {
      return;
    }
    try {
      final service = await vmServiceConnectUri(uri);
      _service = service;
      _vmUri = uri;
      onChange();
    } on Object {
      // VM not ready yet.
    }
  }

  Future<List<Map<String, Object?>>> listIsolates() async {
    final service = _service;
    if (service == null) {
      _cachedIsolates = null;
      _isolatesCachedAt = null;
      return const [];
    }

    final cachedAt = _isolatesCachedAt;
    final cached = _cachedIsolates;
    if (cached != null &&
        cachedAt != null &&
        DateTime.now().difference(cachedAt) < _isolatesCacheTtl) {
      return cached;
    }

    final vm = await service.getVM();
    final refs = vm.isolates ?? const [];
    if (refs.isEmpty) {
      _cachedIsolates = const [];
      _isolatesCachedAt = DateTime.now();
      return const [];
    }

    final rows = await Future.wait(
      refs.map((ref) async {
        final id = ref.id;
        if (id == null || id.isEmpty) {
          return _isolateRowFromRef(ref);
        }
        try {
          final isolate = await service
              .getIsolate(id)
              .timeout(const Duration(seconds: 2));
          return _isolateRow(isolate);
        } on Object {
          return _isolateRowFromRef(ref);
        }
      }),
    );
    _cachedIsolates = rows;
    _isolatesCachedAt = DateTime.now();
    return rows;
  }

  Future<Map<String, Object?>> hotReload() async {
    final service = _service;
    if (service == null) {
      return <String, Object?>{'ok': false, 'error': 'VM service is not connected'};
    }
    final isolateId = await _mainIsolateId();
    if (isolateId == null) {
      return <String, Object?>{'ok': false, 'error': 'No Dart isolate available for hot reload'};
    }
    try {
      final extension = await service.callServiceExtension(
        'ext.flutter.hotReload',
        isolateId: isolateId,
      );
      final type = extension.json?['type'] as String? ?? '';
      final ok = type != 'Error' && extension.json?['success'] != false;
      return <String, Object?>{
        'ok': ok,
        'method': 'vm-service',
        'message': ok ? 'Hot reload sent' : 'Hot reload failed',
        'detail': extension.json,
        'error': ok ? null : 'Hot reload rejected by VM service',
      };
    } on Object catch (error) {
      try {
        final report = await service.reloadSources(isolateId, force: true);
        final success = report.success == true;
        return <String, Object?>{
          'ok': success,
          'method': 'reloadSources',
          'message': success ? 'Hot reload complete' : 'Hot reload failed',
          'error': success ? null : 'reloadSources returned failure',
        };
      } on Object catch (fallbackError) {
        return <String, Object?>{
          'ok': false,
          'error': 'Hot reload failed: $error ($fallbackError)',
        };
      }
    }
  }

  Future<Map<String, Object?>> hotRestart() async {
    final service = _service;
    if (service == null) {
      return <String, Object?>{'ok': false, 'error': 'VM service is not connected'};
    }
    final isolateId = await _mainIsolateId();
    if (isolateId == null) {
      return <String, Object?>{'ok': false, 'error': 'No Dart isolate available for hot restart'};
    }
    try {
      final extension = await service.callServiceExtension(
        'ext.flutter.hotRestart',
        isolateId: isolateId,
      );
      final type = extension.json?['type'] as String? ?? '';
      final ok = type != 'Error' && extension.json?['success'] != false;
      return <String, Object?>{
        'ok': ok,
        'method': 'vm-service',
        'message': ok ? 'Hot restart sent' : 'Hot restart failed',
        'detail': extension.json,
        'error': ok ? null : 'Hot restart rejected by VM service',
      };
    } on Object catch (error) {
      return <String, Object?>{'ok': false, 'error': 'Hot restart failed: $error'};
    }
  }

  Future<Map<String, Object?>> quitApp() async {
    final service = _service;
    if (service == null) {
      return <String, Object?>{'ok': false, 'error': 'VM service is not connected'};
    }
    final isolateId = await _mainIsolateId();
    if (isolateId == null) {
      return <String, Object?>{'ok': false, 'error': 'No Dart isolate available to stop'};
    }
    try {
      await service.callServiceExtension(
        'ext.flutter.exit',
        isolateId: isolateId,
      );
      await resetConnection();
      return <String, Object?>{
        'ok': true,
        'method': 'vm-service',
        'message': 'Stop sent to Flutter app',
      };
    } on Object catch (error) {
      return <String, Object?>{'ok': false, 'error': 'Stop failed: $error'};
    }
  }

  Future<void> resetConnection() async {
    await _service?.dispose();
    _service = null;
    _vmUri = null;
    _cachedIsolates = null;
    _isolatesCachedAt = null;
    onChange();
  }

  Future<String?> _mainIsolateId() async {
    final service = _service;
    if (service == null) {
      return null;
    }
    final vm = await service.getVM();
    final isolates = vm.isolates ?? const [];
    for (final isolate in isolates) {
      if (isolate.isSystemIsolate == true) {
        continue;
      }
      if (isolate.name == 'main') {
        return isolate.id;
      }
    }
    for (final isolate in isolates) {
      if (isolate.isSystemIsolate != true) {
        return isolate.id;
      }
    }
    return isolates.isEmpty ? null : isolates.first.id;
  }

  Map<String, Object?> _isolateRow(Isolate isolate) {
    final status = _describeIsolateStatus(isolate);
    return <String, Object?>{
      'id': isolate.id,
      'name': isolate.name,
      'number': isolate.number,
      'isSystemIsolate': isolate.isSystemIsolate,
      'status': status.label,
      'statusClass': status.cssClass,
      'pauseKind': isolate.pauseEvent?.kind,
      'runnable': isolate.runnable,
    };
  }

  Map<String, Object?> _isolateRowFromRef(IsolateRef ref) {
    return <String, Object?>{
      'id': ref.id,
      'name': ref.name,
      'number': ref.number,
      'isSystemIsolate': ref.isSystemIsolate,
      'status': 'unknown',
      'statusClass': 'unknown',
      'pauseKind': null,
      'runnable': null,
    };
  }

  ({String label, String cssClass}) _describeIsolateStatus(Isolate isolate) {
    if (isolate.error != null) {
      return (label: 'error', cssClass: 'error');
    }
    final pauseKind = isolate.pauseEvent?.kind ?? '';
    if (pauseKind.isNotEmpty && pauseKind != EventKind.kResume) {
      return (label: _pauseKindLabel(pauseKind), cssClass: 'paused');
    }
    if (isolate.runnable == true) {
      return (label: 'running', cssClass: 'running');
    }
    if (isolate.runnable == false) {
      return (label: 'not runnable', cssClass: 'paused');
    }
    return (label: 'unknown', cssClass: 'unknown');
  }

  String _pauseKindLabel(String kind) {
    switch (kind) {
      case EventKind.kPauseBreakpoint:
        return 'paused (breakpoint)';
      case EventKind.kPauseException:
        return 'paused (exception)';
      case EventKind.kPauseInterrupted:
        return 'paused (interrupted)';
      case EventKind.kPausePostRequest:
        return 'paused';
      case EventKind.kPauseStart:
        return 'paused (start)';
      case EventKind.kPauseExit:
        return 'paused (exit)';
      default:
        if (kind.startsWith('Pause')) {
          return 'paused';
        }
        return kind;
    }
  }

  static Future<String?> _discoverVmUri(int port) async {
    const hosts = <String>['127.0.0.1', 'localhost'];
    const paths = <String>['/json/version', '/json/list', '/json', '/ws'];
    for (final host in hosts) {
      for (final path in paths) {
        try {
          final response = await http
              .get(Uri.parse('http://$host:$port$path'))
              .timeout(const Duration(milliseconds: 800));
          if (response.statusCode != 200) {
            continue;
          }
          final body = response.body.trim();
          if (body.isEmpty) {
            continue;
          }
          final decoded = jsonDecode(body);
          final uri = _extractVmUri(decoded, host, port);
          if (uri != null) {
            return uri;
          }
        } on Object {
          continue;
        }
      }
      try {
        final socket = await Socket.connect(
          InternetAddress.loopbackIPv4,
          port,
          timeout: const Duration(milliseconds: 400),
        );
        await socket.close();
        return 'ws://$host:$port/ws';
      } on Object {
        continue;
      }
    }
    return null;
  }

  static String? _extractVmUri(Object? decoded, String host, int port) {
    if (decoded is Map<String, dynamic>) {
      for (final key in ['uri', 'webSocketDebuggerUrl', 'vmServiceUri']) {
        final value = decoded[key];
        if (value is String && value.isNotEmpty) {
          return _normalizeVmUri(value, host, port);
        }
      }
    }
    if (decoded is List) {
      for (final entry in decoded) {
        final uri = _extractVmUri(entry, host, port);
        if (uri != null) {
          return uri;
        }
      }
    }
    return 'ws://$host:$port/ws';
  }

  static String _normalizeVmUri(String raw, String host, int port) {
    if (raw.startsWith('ws://') || raw.startsWith('wss://')) {
      return raw;
    }
    if (raw.startsWith('http://') || raw.startsWith('https://')) {
      return raw
          .replaceFirst('http://', 'ws://')
          .replaceFirst('https://', 'wss://')
          .replaceAll(RegExp(r'/+$'), '');
    }
    if (raw.startsWith('/')) {
      return 'ws://$host:$port$raw';
    }
    return 'ws://$host:$port/$raw';
  }
}

class VmInspectorFacade {
  VmInspectorFacade({
    required this.vmPort,
    this.uriOverride,
  }) : _host = FeatureIsolateHost(
          debugName: 'vm-inspector-worker',
          entryPoint: vmInspectorWorkerMain,
        );

  final int vmPort;
  final String? uriOverride;
  final FeatureIsolateHost _host;
  final _changes = StreamController<void>.broadcast();
  StreamSubscription<String>? _eventSub;

  var _connected = false;
  String? _vmUri;

  Stream<void> get changes => _changes.stream;
  bool get isConnected => _connected;
  String? get vmUri => _vmUri;

  Future<void> startPolling() async {
    await _host.start(
      VmWorkerConfig(vmPort: vmPort, uriOverride: uriOverride).toJson(),
    );
    _eventSub = _host.events.listen((_) {
      unawaited(_refreshStatus());
    });
    await _refreshStatus();
  }

  Future<void> _refreshStatus() async {
    final status = await _host.request<Map<Object?, Object?>>('status');
    _connected = status['connected'] == true;
    _vmUri = status['vmUri'] as String?;
    _changes.add(null);
  }

  Future<void> dispose() async {
    await _eventSub?.cancel();
    await _host.dispose();
    await _changes.close();
  }

  Future<List<Map<String, Object?>>> listIsolates() async {
    final rows = await _host.request<List<Object?>>('listIsolates');
    return rows
        .whereType<Map<Object?, Object?>>()
        .map((row) => Map<String, Object?>.from(row))
        .toList(growable: false);
  }

  Future<Map<String, Object?>> hotReload() async {
    return Map<String, Object?>.from(
      await _host.request<Map<Object?, Object?>>('hotReload'),
    );
  }

  Future<Map<String, Object?>> hotRestart() async {
    return Map<String, Object?>.from(
      await _host.request<Map<Object?, Object?>>('hotRestart'),
    );
  }

  Future<Map<String, Object?>> quitApp() async {
    return Map<String, Object?>.from(
      await _host.request<Map<Object?, Object?>>('quitApp'),
    );
  }

  Future<void> resetConnection() => _host.request<Object?>('resetConnection');
}
