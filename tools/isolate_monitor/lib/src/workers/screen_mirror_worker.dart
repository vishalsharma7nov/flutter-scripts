import 'dart:async';
import 'dart:isolate';
import 'dart:io';
import 'dart:typed_data';

import 'feature_isolate_host.dart';

class ScreenWorkerConfig {
  ScreenWorkerConfig({required this.deviceId, this.targetFps = 12});

  final String deviceId;
  final int targetFps;

  Map<String, Object?> toJson() => <String, Object?>{
        'deviceId': deviceId,
        'targetFps': targetFps,
      };

  factory ScreenWorkerConfig.fromJson(Map<String, Object?> json) {
    return ScreenWorkerConfig(
      deviceId: (json['deviceId'] as String?) ?? '',
      targetFps: json['targetFps'] as int? ?? 12,
    );
  }
}

@pragma('vm:entry-point')
void screenMirrorWorkerMain(SendPort handshakePort) {
  final workerReceive = ReceivePort();
  handshakePort.send(workerReceive.sendPort);

  ScreenMirrorEngine? engine;

  workerReceive.listen((Object? message) async {
    if (message is! List || message.isEmpty) {
      return;
    }
    final kind = message[0];
    if (kind == 'init') {
      final config = ScreenWorkerConfig.fromJson(
        Map<String, Object?>.from(
          (message[1] as Map<Object?, Object?>?) ?? const {},
        ),
      );
      engine = ScreenMirrorEngine(config: config);
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

class ScreenMirrorEngine {
  ScreenMirrorEngine({required this.config});

  final ScreenWorkerConfig config;
  String? _adb;
  String? _serial;
  var _width = 1080;
  var _height = 1920;
  var _available = false;
  String? _error;
  Timer? _captureTimer;
  var _captureInProgress = false;
  Uint8List? _latestFrame;
  var _frameSequence = 0;

  int get targetFrameIntervalMs => (1000 / config.targetFps).round();

  Future<Object?> handle(String command, Map<String, Object?> args) async {
    switch (command) {
      case 'dispose':
        dispose();
        return <String, Object?>{'ok': true};
      case 'initialize':
        final ok = await initialize();
        return <String, Object?>{'ok': ok, ...status()};
      case 'status':
        return status();
      case 'currentFrame':
        final frame = await currentFrame();
        return <String, Object?>{
          'frame': frame == null ? null : TransferableTypedData.fromList([frame]),
          'frameSequence': _frameSequence,
        };
      case 'tap':
        return <String, Object?>{
          'ok': await tapNormalized(
            (args['x'] as num?)?.toDouble() ?? 0,
            (args['y'] as num?)?.toDouble() ?? 0,
          ),
        };
      case 'swipe':
        return <String, Object?>{
          'ok': await swipeNormalized(
            (args['x1'] as num?)?.toDouble() ?? 0,
            (args['y1'] as num?)?.toDouble() ?? 0,
            (args['x2'] as num?)?.toDouble() ?? 0,
            (args['y2'] as num?)?.toDouble() ?? 0,
            durationMs: args['durationMs'] as int? ?? 250,
          ),
        };
      case 'launchScrcpy':
        return <String, Object?>{'ok': await launchScrcpy()};
      default:
        throw StateError('Unknown screen worker command: $command');
    }
  }

  Map<String, Object?> status() => <String, Object?>{
        'available': _available,
        'error': _error,
        'serial': _serial,
        'width': _width,
        'height': _height,
        'frameSequence': _frameSequence,
        'targetFps': config.targetFps,
      };

  Future<bool> initialize() async {
    _adb = await _resolveCommand('adb');
    if (_adb == null) {
      _error = 'adb not found on PATH';
      return false;
    }
    _serial = await _resolveSerial(_adb!, config.deviceId);
    if (_serial == null) {
      _error = 'No adb device found for ${config.deviceId}';
      return false;
    }
    await _refreshDisplaySize();
    _available = true;
    _error = null;
    startRealtimeCapture();
    return true;
  }

  void startRealtimeCapture() {
    if (!_available) {
      return;
    }
    _captureTimer?.cancel();
    _captureTimer = Timer.periodic(
      Duration(milliseconds: targetFrameIntervalMs),
      (_) => unawaited(_captureTick()),
    );
    unawaited(_captureTick());
  }

  void dispose() {
    _captureTimer?.cancel();
    _captureTimer = null;
    _available = false;
    _latestFrame = null;
  }

  Future<void> _captureTick() async {
    if (_captureInProgress || !_available) {
      return;
    }
    _captureInProgress = true;
    try {
      final frame = await capturePng();
      if (frame != null && frame.isNotEmpty) {
        _latestFrame = frame;
        _frameSequence++;
      }
    } finally {
      _captureInProgress = false;
    }
  }

  Future<Uint8List?> capturePng() async {
    if (!_available || _adb == null || _serial == null) {
      return null;
    }
    try {
      final process = await Process.start(
        _adb!,
        ['-s', _serial!, 'exec-out', 'screencap', '-p'],
      );
      final builder = BytesBuilder(copy: false);
      await for (final chunk in process.stdout) {
        builder.add(chunk);
      }
      final exitCode = await process.exitCode;
      if (exitCode != 0) {
        return null;
      }
      final bytes = builder.takeBytes();
      return bytes.isEmpty ? null : bytes;
    } on Object catch (error) {
      _error = 'Screen capture failed: $error';
      return null;
    }
  }

  Future<Uint8List?> currentFrame() async {
    final cached = _latestFrame;
    if (cached != null && cached.isNotEmpty) {
      return cached;
    }
    await _captureTick();
    return _latestFrame;
  }

  Future<bool> tapNormalized(double x, double y) async {
    final px = (x.clamp(0.0, 1.0) * (_width - 1)).round();
    final py = (y.clamp(0.0, 1.0) * (_height - 1)).round();
    return _runInput(['tap', '$px', '$py']);
  }

  Future<bool> swipeNormalized(
    double x1,
    double y1,
    double x2,
    double y2, {
    int durationMs = 250,
  }) async {
    final px1 = (x1.clamp(0.0, 1.0) * (_width - 1)).round();
    final py1 = (y1.clamp(0.0, 1.0) * (_height - 1)).round();
    final px2 = (x2.clamp(0.0, 1.0) * (_width - 1)).round();
    final py2 = (y2.clamp(0.0, 1.0) * (_height - 1)).round();
    return _runInput([
      'swipe',
      '$px1',
      '$py1',
      '$px2',
      '$py2',
      '$durationMs',
    ]);
  }

  Future<bool> launchScrcpy() async {
    if (_serial == null) {
      return false;
    }
    final scrcpy = await _resolveCommand('scrcpy');
    if (scrcpy == null) {
      return false;
    }
    try {
      await Process.start(scrcpy, ['-s', _serial!, '--stay-awake', '--max-fps=60']);
      return true;
    } on Object {
      return false;
    }
  }

  Future<void> _refreshDisplaySize() async {
    if (_adb == null || _serial == null) {
      return;
    }
    final result = await Process.run(
      _adb!,
      ['-s', _serial!, 'shell', 'wm', 'size'],
    );
    if (result.exitCode != 0) {
      return;
    }
    final output = result.stdout as String;
    final match = RegExp(r'Physical size:\s*(\d+)x(\d+)').firstMatch(output);
    if (match != null) {
      _width = int.tryParse(match.group(1) ?? '') ?? _width;
      _height = int.tryParse(match.group(2) ?? '') ?? _height;
    }
  }

  Future<bool> _runInput(List<String> args) async {
    if (_adb == null || _serial == null) {
      return false;
    }
    final result = await Process.run(
      _adb!,
      ['-s', _serial!, 'shell', 'input', ...args],
    );
    return result.exitCode == 0;
  }

  Future<String?> _resolveCommand(String command) async {
    final result = await Process.run('which', [command]);
    if (result.exitCode != 0) {
      return null;
    }
    final path = (result.stdout as String).trim();
    return path.isEmpty ? null : path;
  }

  Future<String?> _resolveSerial(String adb, String deviceId) async {
    final result = await Process.run(adb, ['devices']);
    if (result.exitCode != 0) {
      return null;
    }
    final target = deviceId.trim();
    final online = <String>[];
    for (final line in (result.stdout as String).split('\n').skip(1)) {
      final parts = line.trim().split(RegExp(r'\s+'));
      if (parts.length < 2 || parts[1] != 'device') {
        continue;
      }
      final serial = parts[0];
      online.add(serial);
      if (target.isEmpty || serial == target) {
        return serial;
      }
    }
    if (target.isNotEmpty) {
      for (final serial in online) {
        if (serial.contains(target) || target.contains(serial)) {
          return serial;
        }
      }
    }
    return online.length == 1 ? online.first : null;
  }
}

class ScreenMirrorFacade {
  ScreenMirrorFacade({required this.deviceId, this.targetFps = 12})
      : _host = FeatureIsolateHost(
          debugName: 'screen-mirror-worker',
          entryPoint: screenMirrorWorkerMain,
        );

  final String deviceId;
  final int targetFps;
  final FeatureIsolateHost _host;
  var _started = false;

  var _available = false;
  String? _error;
  String? _serial;
  var _width = 1080;
  var _height = 1920;
  var _frameSequence = 0;
  Uint8List? _latestFrame;

  bool get isAvailable => _available;
  String? get error => _error;
  String? get serial => _serial;
  int get width => _width;
  int get height => _height;
  int get frameSequence => _frameSequence;
  int get targetFpsValue => targetFps;
  Uint8List? get latestFrame => _latestFrame;

  Future<void> _ensureStarted() async {
    if (_started) {
      return;
    }
    await _host.start(
      ScreenWorkerConfig(deviceId: deviceId, targetFps: targetFps).toJson(),
    );
    _started = true;
  }

  Future<bool> initialize() async {
    await _ensureStarted();
    final result = await _host.request<Map<Object?, Object?>>('initialize');
    _applyStatus(result);
    return result['ok'] == true;
  }

  void dispose() {
    if (_started) {
      unawaited(_host.request<Object?>('dispose'));
      unawaited(_host.dispose());
    }
    _available = false;
    _latestFrame = null;
  }

  void startRealtimeCapture() {}

  void stopRealtimeCapture() {}

  Future<Uint8List?> currentFrame() async {
    if (!_started) {
      return null;
    }
    final result = await _host.request<Map<Object?, Object?>>('currentFrame');
    final transferable = result['frame'];
    if (transferable is TransferableTypedData) {
      _latestFrame = transferable.materialize().asUint8List();
      _frameSequence = result['frameSequence'] as int? ?? _frameSequence;
    }
    return _latestFrame;
  }

  Future<bool> tapNormalized(double x, double y) async {
    await _ensureStarted();
    final result = await _host.request<Map<Object?, Object?>>(
      'tap',
      <String, Object?>{'x': x, 'y': y},
    );
    return result['ok'] == true;
  }

  Future<bool> swipeNormalized(
    double x1,
    double y1,
    double x2,
    double y2, {
    int durationMs = 250,
  }) async {
    await _ensureStarted();
    final result = await _host.request<Map<Object?, Object?>>(
      'swipe',
      <String, Object?>{
        'x1': x1,
        'y1': y1,
        'x2': x2,
        'y2': y2,
        'durationMs': durationMs,
      },
    );
    return result['ok'] == true;
  }

  Future<bool> launchScrcpy() async {
    await _ensureStarted();
    final result = await _host.request<Map<Object?, Object?>>('launchScrcpy');
    return result['ok'] == true;
  }

  void _applyStatus(Map<Object?, Object?> result) {
    _available = result['available'] == true;
    _error = result['error'] as String?;
    _serial = result['serial'] as String?;
    _width = result['width'] as int? ?? _width;
    _height = result['height'] as int? ?? _height;
    _frameSequence = result['frameSequence'] as int? ?? _frameSequence;
  }
}
