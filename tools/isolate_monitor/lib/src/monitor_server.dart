import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_router/shelf_router.dart';
import 'package:shelf_static/shelf_static.dart';

import 'android_screen_mirror.dart';
import 'adb_device_manager.dart';
import 'backend_preference.dart';
import 'device_log_streamer.dart';
import 'file_opener.dart';
import 'flutter_deployer.dart';
import 'flutter_device_discovery.dart';
import 'native_threads.dart';
import 'project_paths.dart';
import 'vm_connector.dart';
import 'workers/feature_isolate_host.dart';

class MonitorServer {
  MonitorServer({
    required this.connector,
    required this.packageName,
    required this.bundleId,
    required this.deviceSerial,
    required this.monitorMode,
    this.logStreamer,
    this.deployer,
    this.projectPaths,
    this.fileOpener,
    this.screenMirror,
    this.adbDevices,
    this.deviceDiscovery,
    this.flutterAvailable = false,
    this.bindHost = '127.0.0.1',
    this.lanAddress,
    this.deployEnvFile,
    this.deployAppEnv,
    this.deployVmServicePort = 58888,
    this.deployUseFvm = true,
  });

  final VmConnector connector;
  final String packageName;
  final String bundleId;
  String deviceSerial;
  String monitorMode;
  DeviceLogStreamer? logStreamer;
  FlutterDeployer? deployer;
  final ProjectPaths? projectPaths;
  final FileOpener? fileOpener;
  AndroidScreenMirror? screenMirror;
  final AdbDeviceManager? adbDevices;
  final FlutterDeviceDiscovery? deviceDiscovery;
  final bool flutterAvailable;
  final String bindHost;
  final String? lanAddress;
  final String? deployEnvFile;
  final String? deployAppEnv;
  final int deployVmServicePort;
  final bool deployUseFvm;
  String activeScreenSerial = '';
  int? _port;
  String? _screenMirrorInitError;
  DateTime? _lastMirrorRetryAt;

  String? _lanUrl() {
    if (lanAddress == null || lanAddress!.isEmpty || _port == null) {
      return null;
    }
    return 'http://$lanAddress:$_port';
  }

  Future<void> _ensureScreenMirror({bool force = false}) async {
    if (screenMirror?.isAvailable == true) {
      _screenMirrorInitError = null;
      return;
    }

    final now = DateTime.now();
    if (!force &&
        _lastMirrorRetryAt != null &&
        now.difference(_lastMirrorRetryAt!) <
            const Duration(seconds: 2)) {
      return;
    }
    _lastMirrorRetryAt = now;

    final target = activeScreenSerial.isNotEmpty
        ? activeScreenSerial
        : deviceSerial.trim();
    if (target.isEmpty || !isLikelyAndroidFlutterDevice(target)) {
      return;
    }

    final mirror = AndroidScreenMirror(deviceId: target);
    final ready = await mirror.initialize();
    if (ready) {
      screenMirror?.dispose();
      screenMirror = mirror;
      activeScreenSerial = mirror.serial ?? target;
      _screenMirrorInitError = null;
      return;
    }

    _screenMirrorInitError = mirror.error;
    mirror.dispose();
  }

  Future<void> ensureScreenMirror({bool force = false}) =>
      _ensureScreenMirror(force: force);

  bool _isAndroidMirrorCandidate(String serial) {
    final target = serial.trim();
    if (target.isEmpty) {
      return false;
    }
    return isLikelyAndroidFlutterDevice(target) ||
        target.contains(':') ||
        target.startsWith('emulator-');
  }

  Future<void> _rebindLogStreamer(String serial) async {
    final existing = logStreamer;
    if (existing != null) {
      await existing.dispose();
    }
    final next = DeviceLogStreamer(
      packageName: packageName,
      bundleId: bundleId,
      deviceId: serial,
    );
    logStreamer = next;
    await next.start();
  }

  Future<void> _rebindDeployer(String serial) async {
    final root = projectPaths?.projectRoot ?? '';
    if (root.isEmpty || serial.trim().isEmpty) {
      return;
    }
    final existing = deployer;
    if (existing != null) {
      await existing.stop();
    }
    deployer = FlutterDeployer(
      projectRoot: root,
      deviceId: serial,
      buildMode: monitorMode,
      envFile: existing?.envFile ?? deployEnvFile,
      appEnv: existing?.appEnv ?? deployAppEnv,
      vmServicePort: existing?.vmServicePort ?? deployVmServicePort,
      useFvm: existing?.useFvm ?? deployUseFvm,
    );
  }

  String? _normalizeMode(String raw) {
    switch (raw.trim().toLowerCase()) {
      case 'debug':
        return 'debug';
      case 'profile':
        return 'profile';
      case 'release':
      case 'release-build':
      case 'store':
        return 'release';
      default:
        return null;
    }
  }

  Future<Map<String, Object?>> _setMonitorMode(String rawMode) async {
    final mode = _normalizeMode(rawMode);
    if (mode == null) {
      return <String, Object?>{
        'ok': false,
        'error': 'mode must be debug, profile, or release',
      };
    }
    monitorMode = mode;
    final serial = deviceSerial.trim();
    if (serial.isNotEmpty) {
      await _rebindDeployer(serial);
    }
    final hint = mode == 'release'
        ? 'Release mode: device logs + native threads (no Dart VM / isolates)'
        : mode == 'profile'
            ? 'Profile mode: near-release with VM isolates + device logs'
            : 'Debug mode: hot reload + isolates + device logs';
    return <String, Object?>{
      'ok': true,
      'mode': monitorMode,
      'message': hint,
    };
  }

  /// Binds logs, threads, deploy, and screen mirror to [serial].
  Future<Map<String, Object?>> _selectActiveDevice(
    String serial, {
    String? mode,
  }) async {
    final target = serial.trim();
    if (target.isEmpty) {
      return <String, Object?>{
        'ok': false,
        'error': 'device (or serial) required',
      };
    }

    if (mode != null && mode.trim().isNotEmpty) {
      final modeResult = await _setMonitorMode(mode);
      if (modeResult['ok'] != true) {
        return modeResult;
      }
    }

    deviceSerial = target;
    await _rebindLogStreamer(target);
    await _rebindDeployer(target);

    var message = 'Connected to $target (${monitorMode})';
    if (_isAndroidMirrorCandidate(target)) {
      final mirrorResult = await _switchScreenMirror(target);
      if (mirrorResult['ok'] != true) {
        final mirrorError = mirrorResult['error']?.toString();
        if (mirrorError != null && mirrorError.isNotEmpty) {
          message =
              'Connected to $target (${monitorMode}; screen mirror unavailable: $mirrorError)';
        }
      }
    } else {
      screenMirror?.dispose();
      screenMirror = null;
      activeScreenSerial = '';
      message =
          'Connected to $target (${monitorMode}; screen mirror is Android-only)';
    }

    return <String, Object?>{
      'ok': true,
      'message': message,
      'device': deviceSerial,
      'mode': monitorMode,
      'screenMirrorAvailable': screenMirror?.isAvailable ?? false,
      'screenDevice': activeScreenSerial,
    };
  }

  Future<Map<String, Object?>> _switchScreenMirror(String serial) async {
    final target = serial.trim();
    screenMirror?.dispose();
    screenMirror = null;
    activeScreenSerial = '';

    if (target.isEmpty) {
      return <String, Object?>{
        'ok': true,
        'screenMirrorAvailable': false,
        'screenDevice': '',
      };
    }

    if (!isLikelyAndroidFlutterDevice(target) &&
        !target.contains(':') &&
        !target.startsWith('emulator-')) {
      return <String, Object?>{
        'ok': false,
        'error': 'Screen mirror supports Android devices only',
      };
    }

    final mirror = AndroidScreenMirror(deviceId: target);
    final ready = await mirror.initialize();
    if (!ready) {
      final error = mirror.error ?? 'Failed to initialize screen mirror';
      _screenMirrorInitError = error;
      mirror.dispose();
      return <String, Object?>{
        'ok': false,
        'error': error,
        'screenMirrorAvailable': false,
      };
    }

    screenMirror = mirror;
    activeScreenSerial = mirror.serial ?? target;
    _screenMirrorInitError = null;
    return <String, Object?>{
      'ok': true,
      'screenMirrorAvailable': true,
      'screenDevice': activeScreenSerial,
      'screenWidth': mirror.width,
      'screenHeight': mirror.height,
    };
  }

  Map<String, Object?> _statusBody() {
    final logCount = logStreamer?.lineCount ?? 0;
    final logsStreaming = logStreamer?.isStreaming ?? false;
    return <String, Object?>{
      'mode': monitorMode,
      'backend': kBackendDart,
      'preferredBackend': readPreferredBackend(),
      'availableBackends': kAvailableBackends,
      'runnableBackends': <String>[kBackendDart, kBackendGo],
      'backendHint': backendDirectoryHint(readPreferredBackend()),
      'vmConnected': connector.isConnected,
      'vmUri': connector.vmUri,
      'logsStreaming': logsStreaming,
      'logsConnected': logsStreaming && logCount > 0,
      'logLineCount': logCount,
      'logsRevision': logStreamer?.revision ?? 0,
      'logSessionRevision': logStreamer?.sessionRevision ?? 0,
      'deployRevision': deployer?.outputRevision ?? 0,
      'flutterDeployGeneration': deployer?.deployGeneration ?? 0,
      'flutterOutputRevision': deployer?.outputRevision ?? 0,
      'logsError': logStreamer?.error,
      'package': packageName,
      'bundleId': bundleId,
      'device': deviceSerial,
      'deviceLogsEnabled': logStreamer != null,
      'canReinstall': deployer?.canDeploy ?? false,
      'reinstallRunning': deployer?.isRunning ?? false,
      'reinstallError': deployer?.error,
      'projectRoot': projectPaths?.projectRoot ?? '',
      'dartPackageName': projectPaths?.dartPackageName ?? '',
      'fileOpener': fileOpener?.activeOpener ?? '',
      'canOpenFiles': fileOpener != null && (projectPaths?.projectRoot.isNotEmpty ?? false),
      'screenMirrorAvailable': screenMirror?.isAvailable ?? false,
      'screenMirrorError': screenMirror?.error ?? _screenMirrorInitError,
      'screenWidth': screenMirror?.width ?? 0,
      'screenHeight': screenMirror?.height ?? 0,
      'screenFrameSequence': screenMirror?.frameSequence ?? 0,
      'screenTargetFps': screenMirror?.targetFps ?? 0,
      'screenDevice': activeScreenSerial,
      'adbAvailable': adbDevices?.isAvailable ?? false,
      'flutterAvailable': flutterAvailable,
      'bindHost': bindHost,
      'lanUrl': _lanUrl(),
      'networkAccessEnabled':
          bindHost != '127.0.0.1' && bindHost != 'localhost',
      'flutterRunActive': deployer?.hasActiveProcess ?? false,
      'canHotReload': _canHotReload(),
      'canHotRestart': _canHotRestart(),
      'canStopFlutter': _canStopFlutter(),
      'workerIsolates': true,
    };
  }

  bool _supportsHotReloadRestart() =>
      monitorMode == 'debug' || monitorMode == 'profile';

  bool _canHotReload() =>
      _supportsHotReloadRestart() &&
      ((deployer?.hasActiveProcess ?? false) || connector.isConnected);

  bool _canHotRestart() =>
      _supportsHotReloadRestart() &&
      ((deployer?.hasActiveProcess ?? false) || connector.isConnected);

  bool _canStopFlutter() =>
      (deployer?.hasActiveProcess ?? false) ||
      (_supportsHotReloadRestart() && connector.isConnected);

  Future<Map<String, Object?>> _hotReload() async {
    if (!_canHotReload()) {
      return <String, Object?>{
        'ok': false,
        'error':
            'Hot reload needs a running debug/profile flutter session (or VM)',
      };
    }

    final deployer = this.deployer;
    if (deployer?.hasActiveProcess == true) {
      final ok = await deployer!.hotReload();
      return <String, Object?>{
        'ok': ok,
        'method': 'flutter-run',
        'message': ok ? 'Hot reload sent (r)' : deployer.error,
        'error': ok ? null : deployer.error ?? 'Failed to send hot reload',
      };
    }

    return connector.hotReload();
  }

  Future<Map<String, Object?>> _hotRestart() async {
    if (!_canHotRestart()) {
      return <String, Object?>{
        'ok': false,
        'error':
            'Hot restart needs a running debug/profile flutter session (or VM)',
      };
    }

    final deployer = this.deployer;
    if (deployer?.hasActiveProcess == true) {
      final ok = await deployer!.hotRestart();
      return <String, Object?>{
        'ok': ok,
        'method': 'flutter-run',
        'message': ok ? 'Hot restart sent (R)' : deployer.error,
        'error': ok ? null : deployer.error ?? 'Failed to send hot restart',
      };
    }

    return connector.hotRestart();
  }

  Future<Map<String, Object?>> _stopFlutter() async {
    if (!_canStopFlutter()) {
      return <String, Object?>{
        'ok': false,
        'error': 'Stop is only available for a running Flutter session',
      };
    }

    final deployer = this.deployer;
    if (deployer?.hasActiveProcess == true) {
      final quitOk = await deployer!.quit();
      if (quitOk) {
        await Future<void>.delayed(const Duration(seconds: 2));
        if (!deployer.isRunning) {
          await connector.resetConnection();
          return <String, Object?>{
            'ok': true,
            'method': 'flutter-run',
            'message': 'Flutter run stopped (q)',
          };
        }
      }

      await deployer.stop();
      await connector.resetConnection();
      return <String, Object?>{
        'ok': true,
        'method': 'process-kill',
        'message': 'Flutter run process stopped',
      };
    }

    final result = await connector.quitApp();
    return result;
  }

  Future<void> serve({required int port}) async {
    _port = port;
    final router = Router();

    router.get('/api/status', (Request request) async {
      await _ensureScreenMirror();
      return Response.ok(
        jsonEncode(_statusBody()),
        headers: {'content-type': 'application/json'},
      );
    });

    router.post('/api/backend', (Request request) async {
      try {
        final raw = await request.readAsString();
        final body = raw.isEmpty
            ? <String, dynamic>{}
            : jsonDecode(raw) as Map<String, dynamic>;
        final requested = normalizeBackendLanguage(
          (body['backend'] as String?) ?? '',
        );
        final restart = body['restart'] != false;
        await writePreferredBackend(requested);
        final runnable = isBackendRunnable(requested);
        if (restart) {
          // Let the HTTP response flush, then ask the launcher to relaunch us.
          unawaited(
            Future<void>.delayed(const Duration(milliseconds: 250), () {
              exit(kMonitorRestartExitCode);
            }),
          );
        }
        return Response.ok(
          jsonEncode(<String, Object?>{
            'ok': true,
            'backend': kBackendDart,
            'preferredBackend': requested,
            'runnable': runnable,
            'directory': backendDirectoryHint(requested),
            'message': backendStatusMessage(requested),
            'restarting': restart,
            'needsRestart': false,
          }),
          headers: {'content-type': 'application/json'},
        );
      } on Object catch (error) {
        return Response.internalServerError(
          body: jsonEncode(<String, Object?>{
            'ok': false,
            'error': 'Failed to set backend preference: $error',
          }),
          headers: {'content-type': 'application/json'},
        );
      }
    });

    router.post('/api/mode', (Request request) async {
      final body = await request.readAsString();
      late final Map<String, dynamic> payload;
      try {
        payload = body.isEmpty
            ? <String, dynamic>{}
            : jsonDecode(body) as Map<String, dynamic>;
      } on Object {
        return Response(
          400,
          body: jsonEncode(<String, Object?>{
            'ok': false,
            'error': 'Invalid JSON body',
          }),
          headers: {'content-type': 'application/json'},
        );
      }

      final modeResult = await _setMonitorMode(
        (payload['mode'] as String?) ?? '',
      );
      final ok = modeResult['ok'] == true;
      return Response(
        ok ? 200 : 400,
        body: jsonEncode(<String, Object?>{
          ...modeResult,
          ..._statusBody(),
        }),
        headers: {'content-type': 'application/json'},
      );
    });

    router.get('/api/isolates', (Request request) async {
      final isolates = await connector.listIsolates();
      return Response.ok(
        jsonEncode(<String, Object?>{'isolates': isolates}),
        headers: {'content-type': 'application/json'},
      );
    });

    router.get('/api/threads', (Request request) async {
      final payload = await fetchNativeThreads(
        deviceSerial: deviceSerial,
        packageName: packageName,
      );
      return Response.ok(
        jsonEncode(payload),
        headers: {'content-type': 'application/json'},
      );
    });

    router.get('/api/logs', (Request request) async {
      final streamer = logStreamer;
      final deployer = this.deployer;
      final query = request.url.queryParameters['q']?.trim() ?? '';
      final caseSensitive =
          request.url.queryParameters['case'] == 'sensitive';

      if (streamer == null) {
        return Response.ok(
          '{}',
          headers: {'content-type': 'application/json'},
        );
      }

      final body = await streamer.fetchLogsJson(
        query: query,
        caseSensitive: caseSensitive,
      );
      final payload = Map<String, Object?>.from(
        jsonDecode(body) as Map<Object?, Object?>,
      );
      payload['reinstallOutput'] = deployer?.recentOutput ?? const <String>[];
      payload['reinstallRunning'] = deployer?.isRunning ?? false;
      payload['deployRevision'] = deployer?.outputRevision ?? 0;
      payload['flutterDeployGeneration'] = deployer?.deployGeneration ?? 0;
      payload['flutterOutputRevision'] = deployer?.outputRevision ?? 0;

      return Response.ok(
        await encodeLogsPayloadInIsolate(payload),
        headers: {'content-type': 'application/json'},
      );
    });

    router.get('/api/logs/search', (Request request) async {
      final streamer = logStreamer;
      if (streamer == null) {
        return Response.ok(
          jsonEncode(<String, Object?>{
            'query': '',
            'matches': <String>[],
            'matchCount': 0,
            'lineCount': 0,
            'sessionRevision': 0,
          }),
          headers: {'content-type': 'application/json'},
        );
      }

      final query = request.url.queryParameters['q']?.trim() ?? '';
      final caseSensitive =
          request.url.queryParameters['case'] == 'sensitive';

      return Response.ok(
        await streamer.fetchSearchJson(
          query: query,
          caseSensitive: caseSensitive,
        ),
        headers: {'content-type': 'application/json'},
      );
    });

    router.get('/api/events', (Request request) {
      late final StreamController<List<int>> controller;
      final subscriptions = <StreamSubscription<void>>[];

      void pushEvent(String event, Map<String, Object?> data) {
        if (controller.isClosed) {
          return;
        }
        final payload = 'event: $event\ndata: ${jsonEncode(data)}\n\n';
        controller.add(utf8.encode(payload));
      }

      Future<void> pushStatus(String event) async {
        if (event == 'ready' || event == 'deploy') {
          await _ensureScreenMirror();
        }
        pushEvent(event, _statusBody());
      }

      controller = StreamController<List<int>>(
        onCancel: () async {
          for (final subscription in subscriptions) {
            await subscription.cancel();
          }
        },
      );

      subscriptions.add(
        connector.changes.listen((_) => pushStatus('vm')),
      );

      final streamer = logStreamer;
      if (streamer != null) {
        subscriptions.add(
          streamer.changes.listen((_) => pushStatus('logs')),
        );
      }

      final deployer = this.deployer;
      if (deployer != null) {
        subscriptions.add(
          deployer.changes.listen((_) => pushStatus('deploy')),
        );
      }

      pushStatus('ready');

      return Response.ok(
        controller.stream,
        headers: {
          'content-type': 'text/event-stream',
          'cache-control': 'no-cache',
          'connection': 'keep-alive',
        },
      );
    });

    router.get('/api/devices', (Request request) async {
      final manager = adbDevices;
      final discovery = deviceDiscovery;
      if (manager == null && discovery == null) {
        return Response.ok(
          jsonEncode(<String, Object?>{
            'adbAvailable': false,
            'flutterAvailable': false,
            'devices': <Object?>[],
            'android': <Object?>[],
            'ios': <Object?>[],
            'discoveredAndroid': <Object?>[],
            'selected': deviceSerial,
            'activeSerial': activeScreenSerial.isNotEmpty
                ? activeScreenSerial
                : deviceSerial,
            'screenMirrorAvailable': screenMirror?.isAvailable ?? false,
          }),
          headers: {'content-type': 'application/json'},
        );
      }

      final catalog = discovery != null
          ? await discovery.buildCatalog(manager)
          : DeviceCatalog(
              android: const <MonitorDevice>[],
              ios: const <MonitorDevice>[],
              discoveredAndroid: const <MonitorDevice>[],
              adbDevices: manager != null && await manager.ensureAdb()
                  ? await manager.listDevices()
                  : const <AdbDevice>[],
              adbAvailable: manager?.isAvailable ?? false,
            );

      final selected = activeScreenSerial.isNotEmpty
          ? activeScreenSerial
          : deviceSerial;
      return Response.ok(
        jsonEncode(<String, Object?>{
          ...catalog.toJson(),
          'selected': selected,
          'activeSerial': selected,
          'screenMirrorAvailable': screenMirror?.isAvailable ?? false,
        }),
        headers: {'content-type': 'application/json'},
      );
    });

    router.post('/api/devices/connect', (Request request) async {
      final manager = adbDevices;
      if (manager == null) {
        return Response(
          400,
          body: jsonEncode(<String, Object?>{
            'ok': false,
            'error': 'adb is not available on this machine',
          }),
          headers: {'content-type': 'application/json'},
        );
      }

      final body = await request.readAsString();
      late final Map<String, dynamic> payload;
      try {
        payload = jsonDecode(body) as Map<String, dynamic>;
      } on Object {
        return Response(
          400,
          body: jsonEncode(<String, Object?>{
            'ok': false,
            'error': 'Invalid JSON body',
          }),
          headers: {'content-type': 'application/json'},
        );
      }

      final address = (payload['address'] as String?)?.trim() ?? '';
      final result = await manager.connect(address);
      return Response(
        result.ok ? 200 : 400,
        body: jsonEncode(result.toJson()),
        headers: {'content-type': 'application/json'},
      );
    });

    router.post('/api/devices/pair', (Request request) async {
      final manager = adbDevices;
      if (manager == null) {
        return Response(
          400,
          body: jsonEncode(<String, Object?>{
            'ok': false,
            'error': 'adb is not available on this machine',
          }),
          headers: {'content-type': 'application/json'},
        );
      }

      final body = await request.readAsString();
      late final Map<String, dynamic> payload;
      try {
        payload = jsonDecode(body) as Map<String, dynamic>;
      } on Object {
        return Response(
          400,
          body: jsonEncode(<String, Object?>{
            'ok': false,
            'error': 'Invalid JSON body',
          }),
          headers: {'content-type': 'application/json'},
        );
      }

      final result = await manager.pair(
        host: (payload['host'] as String?) ?? '',
        port: (payload['port'] as String?) ?? '',
        code: (payload['code'] as String?) ?? '',
      );
      return Response(
        result.ok ? 200 : 400,
        body: jsonEncode(result.toJson()),
        headers: {'content-type': 'application/json'},
      );
    });

    router.post('/api/devices/disconnect', (Request request) async {
      final manager = adbDevices;
      if (manager == null) {
        return Response(
          400,
          body: jsonEncode(<String, Object?>{
            'ok': false,
            'error': 'adb is not available on this machine',
          }),
          headers: {'content-type': 'application/json'},
        );
      }

      final body = await request.readAsString();
      late final Map<String, dynamic> payload;
      try {
        payload = jsonDecode(body) as Map<String, dynamic>;
      } on Object {
        return Response(
          400,
          body: jsonEncode(<String, Object?>{
            'ok': false,
            'error': 'Invalid JSON body',
          }),
          headers: {'content-type': 'application/json'},
        );
      }

      final serial = (payload['serial'] as String?)?.trim() ??
          (payload['device'] as String?)?.trim() ??
          '';
      final result = await manager.disconnect(serial);
      if (result.ok &&
          (serial == activeScreenSerial || serial == deviceSerial)) {
        screenMirror?.dispose();
        screenMirror = null;
        activeScreenSerial = '';
      }
      return Response(
        result.ok ? 200 : 400,
        body: jsonEncode(result.toJson()),
        headers: {'content-type': 'application/json'},
      );
    });

    router.post('/api/devices/select', (Request request) async {
      final body = await request.readAsString();
      late final Map<String, dynamic> payload;
      try {
        payload = jsonDecode(body) as Map<String, dynamic>;
      } on Object {
        return Response(
          400,
          body: jsonEncode(<String, Object?>{
            'ok': false,
            'error': 'Invalid JSON body',
          }),
          headers: {'content-type': 'application/json'},
        );
      }

      final serial = (payload['device'] as String?)?.trim() ??
          (payload['serial'] as String?)?.trim() ??
          '';
      final mode = (payload['mode'] as String?)?.trim();
      final selectResult = await _selectActiveDevice(
        serial,
        mode: mode,
      );
      final ok = selectResult['ok'] == true;
      return Response(
        ok ? 200 : 400,
        body: jsonEncode(<String, Object?>{
          ...selectResult,
          ..._statusBody(),
        }),
        headers: {'content-type': 'application/json'},
      );
    });

    router.get('/api/screen/frame', (Request request) async {
      final mirror = screenMirror;
      if (mirror == null || !mirror.isAvailable) {
        return Response.notFound('Screen mirror unavailable');
      }

      final frame = await mirror.currentFrame();
      if (frame == null || frame.isEmpty) {
        return Response.internalServerError(
          body: mirror.error ?? 'Failed to capture screen',
        );
      }

      return Response.ok(
        frame,
        headers: {
          'content-type': 'image/png',
          'cache-control': 'no-store',
          'x-frame-sequence': '${mirror.frameSequence}',
        },
      );
    });

    router.post('/api/screen/tap', (Request request) async {
      final mirror = screenMirror;
      if (mirror == null || !mirror.isAvailable) {
        return Response(
          400,
          body: jsonEncode(<String, Object?>{
            'ok': false,
            'error': 'Screen mirror unavailable',
          }),
          headers: {'content-type': 'application/json'},
        );
      }

      final body = await request.readAsString();
      late final Map<String, dynamic> payload;
      try {
        payload = jsonDecode(body) as Map<String, dynamic>;
      } on Object {
        return Response(
          400,
          body: jsonEncode(<String, Object?>{
            'ok': false,
            'error': 'Invalid JSON body',
          }),
          headers: {'content-type': 'application/json'},
        );
      }

      final x = (payload['x'] as num?)?.toDouble() ?? -1;
      final y = (payload['y'] as num?)?.toDouble() ?? -1;
      if (x < 0 || y < 0) {
        return Response(
          400,
          body: jsonEncode(<String, Object?>{
            'ok': false,
            'error': 'Missing normalized x/y (0..1)',
          }),
          headers: {'content-type': 'application/json'},
        );
      }

      final ok = await mirror.tapNormalized(x, y);
      return Response.ok(
        jsonEncode(<String, Object?>{'ok': ok}),
        headers: {'content-type': 'application/json'},
      );
    });

    router.post('/api/screen/swipe', (Request request) async {
      final mirror = screenMirror;
      if (mirror == null || !mirror.isAvailable) {
        return Response(
          400,
          body: jsonEncode(<String, Object?>{
            'ok': false,
            'error': 'Screen mirror unavailable',
          }),
          headers: {'content-type': 'application/json'},
        );
      }

      final body = await request.readAsString();
      late final Map<String, dynamic> payload;
      try {
        payload = jsonDecode(body) as Map<String, dynamic>;
      } on Object {
        return Response(
          400,
          body: jsonEncode(<String, Object?>{
            'ok': false,
            'error': 'Invalid JSON body',
          }),
          headers: {'content-type': 'application/json'},
        );
      }

      final x1 = (payload['x1'] as num?)?.toDouble() ?? -1;
      final y1 = (payload['y1'] as num?)?.toDouble() ?? -1;
      final x2 = (payload['x2'] as num?)?.toDouble() ?? -1;
      final y2 = (payload['y2'] as num?)?.toDouble() ?? -1;
      if (x1 < 0 || y1 < 0 || x2 < 0 || y2 < 0) {
        return Response(
          400,
          body: jsonEncode(<String, Object?>{
            'ok': false,
            'error': 'Missing normalized swipe coordinates (0..1)',
          }),
          headers: {'content-type': 'application/json'},
        );
      }

      final ok = await mirror.swipeNormalized(x1, y1, x2, y2);
      return Response.ok(
        jsonEncode(<String, Object?>{'ok': ok}),
        headers: {'content-type': 'application/json'},
      );
    });

    router.post('/api/screen/scrcpy', (Request request) async {
      final mirror = screenMirror;
      if (mirror == null || !mirror.isAvailable) {
        return Response(
          400,
          body: jsonEncode(<String, Object?>{
            'ok': false,
            'error': 'Screen mirror unavailable',
          }),
          headers: {'content-type': 'application/json'},
        );
      }

      final ok = await mirror.launchScrcpy();
      return Response(
        ok ? 200 : 500,
        body: jsonEncode(<String, Object?>{
          'ok': ok,
          'error': ok ? null : 'Could not launch scrcpy (install via brew install scrcpy)',
        }),
        headers: {'content-type': 'application/json'},
      );
    });

    router.post('/api/open-file', (Request request) async {
      final opener = fileOpener;
      if (opener == null) {
        return Response(
          400,
          body: jsonEncode(<String, Object?>{
            'ok': false,
            'error': 'File opening is not configured for this monitor session',
          }),
          headers: {'content-type': 'application/json'},
        );
      }

      final body = await request.readAsString();
      late final Map<String, dynamic> payload;
      try {
        payload = jsonDecode(body) as Map<String, dynamic>;
      } on Object {
        return Response(
          400,
          body: jsonEncode(<String, Object?>{
            'ok': false,
            'error': 'Invalid JSON body',
          }),
          headers: {'content-type': 'application/json'},
        );
      }

      final reference = (payload['reference'] as String?)?.trim() ?? '';
      if (reference.isEmpty) {
        return Response(
          400,
          body: jsonEncode(<String, Object?>{
            'ok': false,
            'error': 'Missing file reference',
          }),
          headers: {'content-type': 'application/json'},
        );
      }

      final result = await opener.openReference(reference);
      return Response(
        result.ok ? 200 : 404,
        body: jsonEncode(<String, Object?>{
          'ok': result.ok,
          'path': result.path,
          'line': result.line,
          'column': result.column,
          'opener': result.opener,
          'error': result.error,
        }),
        headers: {'content-type': 'application/json'},
      );
    });

    router.post('/api/flutter/hot-reload', (Request request) async {
      final result = await _hotReload();
      final ok = result['ok'] == true;
      return Response(
        ok ? 200 : 400,
        body: jsonEncode(<String, Object?>{
          ...result,
          ..._statusBody(),
        }),
        headers: {'content-type': 'application/json'},
      );
    });

    router.post('/api/flutter/hot-restart', (Request request) async {
      final result = await _hotRestart();
      final ok = result['ok'] == true;
      return Response(
        ok ? 200 : 400,
        body: jsonEncode(<String, Object?>{
          ...result,
          ..._statusBody(),
        }),
        headers: {'content-type': 'application/json'},
      );
    });

    router.post('/api/flutter/stop', (Request request) async {
      final result = await _stopFlutter();
      final ok = result['ok'] == true;
      return Response(
        ok ? 200 : 400,
        body: jsonEncode(<String, Object?>{
          ...result,
          ..._statusBody(),
        }),
        headers: {'content-type': 'application/json'},
      );
    });

    router.post('/api/reinstall', (Request request) async {
      final deployer = this.deployer;
      if (deployer == null || !deployer.canDeploy) {
        return Response(
          400,
          body: jsonEncode(<String, Object?>{
            'ok': false,
            'error': 'Reinstall is not configured for this monitor session',
          }),
          headers: {'content-type': 'application/json'},
        );
      }
      if (deployer.isRunning) {
        return Response(
          409,
          body: jsonEncode(<String, Object?>{
            'ok': false,
            'error': 'Reinstall already in progress',
          }),
          headers: {'content-type': 'application/json'},
        );
      }

      final started = await deployer.reinstall();
      if (!started) {
        return Response(
          500,
          body: jsonEncode(<String, Object?>{
            'ok': false,
            'error': deployer.error ?? 'Failed to start reinstall',
          }),
          headers: {'content-type': 'application/json'},
        );
      }

      final streamer = logStreamer;
      if (streamer != null) {
        unawaited(streamer.restartForReinstall());
      }

      return Response.ok(
        jsonEncode(<String, Object?>{
          'ok': true,
          'message': 'Reinstall started',
        }),
        headers: {'content-type': 'application/json'},
      );
    });

    final webDir = Directory(
      '${Directory.current.path}${Platform.pathSeparator}web',
    );
    final staticHandler = createStaticHandler(
      webDir.path,
      defaultDocument: 'index.html',
    );

    final handler = Pipeline().addHandler((Request request) {
      if (request.url.path.startsWith('api/')) {
        return router(request);
      }
      return staticHandler(request);
    });

    final server = await shelf_io.serve(
      handler,
      _resolveBindAddress(bindHost),
      port,
    );
    server.autoCompress = true;
  }

  InternetAddress _resolveBindAddress(String host) {
    final normalized = host.trim().toLowerCase();
    if (normalized.isEmpty ||
        normalized == 'loopback' ||
        normalized == 'localhost' ||
        normalized == '127.0.0.1') {
      return InternetAddress.loopbackIPv4;
    }
    if (normalized == 'lan' || normalized == 'all' || normalized == '0.0.0.0') {
      return InternetAddress.anyIPv4;
    }
    return InternetAddress(host);
  }
}
