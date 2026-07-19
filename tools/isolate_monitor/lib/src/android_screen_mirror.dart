import 'dart:async';
import 'dart:typed_data';

import 'workers/screen_mirror_worker.dart';

bool isLikelyAndroidFlutterDevice(String deviceId) {
  final id = deviceId.trim().toLowerCase();
  if (id.isEmpty) {
    return false;
  }
  const nonAndroid = {
    'macos',
    'chrome',
    'linux',
    'windows',
    'web-server',
    'web-javascript',
  };
  if (nonAndroid.contains(id) || id.startsWith('web-')) {
    return false;
  }
  return true;
}

/// Android screen mirror — one dedicated worker isolate per mirror session.
class AndroidScreenMirror {
  AndroidScreenMirror({required this.deviceId, this.targetFps = 12})
      : _facade = ScreenMirrorFacade(deviceId: deviceId, targetFps: targetFps);

  final String deviceId;
  final int targetFps;
  final ScreenMirrorFacade _facade;

  bool get isAvailable => _facade.isAvailable;
  int get width => _facade.width;
  int get height => _facade.height;
  String? get error => _facade.error;
  Uint8List? get latestFrame => _facade.latestFrame;
  int get frameSequence => _facade.frameSequence;
  int get targetFrameIntervalMs => (1000 / targetFps).round();
  String? get serial => _facade.serial;

  Future<bool> initialize() => _facade.initialize();

  void startRealtimeCapture() => _facade.startRealtimeCapture();

  void stopRealtimeCapture() => _facade.stopRealtimeCapture();

  void dispose() => _facade.dispose();

  Future<Uint8List?> currentFrame() => _facade.currentFrame();

  Future<bool> tapNormalized(double x, double y) =>
      _facade.tapNormalized(x, y);

  Future<bool> swipeNormalized(
    double x1,
    double y1,
    double x2,
    double y2, {
    int durationMs = 250,
  }) =>
      _facade.swipeNormalized(x1, y1, x2, y2, durationMs: durationMs);

  Future<bool> launchScrcpy() => _facade.launchScrcpy();
}
