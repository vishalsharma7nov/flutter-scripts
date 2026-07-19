import 'dart:async';
import 'dart:collection';
import 'dart:isolate';
import 'dart:io';

import '../process_line_stream.dart';
import 'feature_isolate_host.dart';

const _maxDeployLines = 500;

class DeployWorkerConfig {
  DeployWorkerConfig({
    required this.projectRoot,
    required this.deviceId,
    required this.buildMode,
    this.envFile,
    this.appEnv,
    required this.vmServicePort,
    required this.useFvm,
  });

  final String projectRoot;
  final String deviceId;
  final String buildMode;
  final String? envFile;
  final String? appEnv;
  final int vmServicePort;
  final bool useFvm;

  Map<String, Object?> toJson() => <String, Object?>{
        'projectRoot': projectRoot,
        'deviceId': deviceId,
        'buildMode': buildMode,
        'envFile': envFile,
        'appEnv': appEnv,
        'vmServicePort': vmServicePort,
        'useFvm': useFvm,
      };

  factory DeployWorkerConfig.fromJson(Map<String, Object?> json) {
    return DeployWorkerConfig(
      projectRoot: (json['projectRoot'] as String?) ?? '',
      deviceId: (json['deviceId'] as String?) ?? '',
      buildMode: (json['buildMode'] as String?) ?? 'debug',
      envFile: json['envFile'] as String?,
      appEnv: json['appEnv'] as String?,
      vmServicePort: json['vmServicePort'] as int? ?? 58888,
      useFvm: json['useFvm'] == true,
    );
  }
}

@pragma('vm:entry-point')
void deployWorkerMain(SendPort handshakePort) {
  final workerReceive = ReceivePort();
  handshakePort.send(workerReceive.sendPort);

  DeployWorkerEngine? engine;

  workerReceive.listen((Object? message) async {
    if (message is! List || message.isEmpty) {
      return;
    }
    final kind = message[0];
    if (kind == 'init') {
      final config = DeployWorkerConfig.fromJson(
        Map<String, Object?>.from(
          (message[1] as Map<Object?, Object?>?) ?? const {},
        ),
      );
      engine = DeployWorkerEngine(
        config: config,
        onChange: () => handshakePort.send(<Object?>['event', 'changed']),
      );
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

class DeployWorkerEngine {
  DeployWorkerEngine({
    required this.config,
    required this.onChange,
  });

  final DeployWorkerConfig config;
  final void Function() onChange;

  Process? _process;
  var _running = false;
  String? _error;
  var _deployGeneration = 0;
  var _outputRevision = 0;
  final ListQueue<String> _output = ListQueue();

  bool get canDeploy =>
      config.projectRoot.isNotEmpty && config.deviceId.isNotEmpty;

  Future<Object?> handle(String command, Map<String, Object?> args) async {
    switch (command) {
      case 'dispose':
        await stop();
        return <String, Object?>{'ok': true};
      case 'reinstall':
        final ok = await reinstall();
        return <String, Object?>{'ok': ok};
      case 'hotReload':
        return <String, Object?>{'ok': await _sendRunKey('r')};
      case 'hotRestart':
        return <String, Object?>{'ok': await _sendRunKey('R')};
      case 'quit':
        return <String, Object?>{'ok': await _sendRunKey('q')};
      case 'stop':
        await stop();
        return <String, Object?>{'ok': true};
      case 'status':
        return _status();
      default:
        throw StateError('Unknown deploy worker command: $command');
    }
  }

  Map<String, Object?> _status() {
    return <String, Object?>{
      'canDeploy': canDeploy,
      'isRunning': _running,
      'hasActiveProcess': _process != null && _running,
      'error': _error,
      'deployGeneration': _deployGeneration,
      'outputRevision': _outputRevision,
      'recentOutput': List<String>.from(_output),
    };
  }

  Future<bool> reinstall() async {
    if (!canDeploy) {
      _error = 'Missing project root or device id for reinstall';
      return false;
    }
    if (_running) {
      return false;
    }
    await stop();
    _error = null;
    _output.clear();
    _deployGeneration++;

    final flutterArgs = <String>['run', '-d', config.deviceId];
    switch (config.buildMode) {
      case 'profile':
        flutterArgs.add('--profile');
        flutterArgs.addAll([
          '--host-vmservice-port=${config.vmServicePort}',
          '--disable-service-auth-codes',
        ]);
      case 'release':
        flutterArgs.add('--release');
      default:
        flutterArgs.addAll([
          '--debug',
          '--host-vmservice-port=${config.vmServicePort}',
          '--disable-service-auth-codes',
        ]);
    }
    final envPath = config.envFile?.trim() ?? '';
    if (envPath.isNotEmpty) {
      flutterArgs.add('--dart-define-from-file=$envPath');
      final envValue = config.appEnv?.trim() ?? '';
      if (envValue.isNotEmpty) {
        flutterArgs.add('--dart-define=APP_ENV=$envValue');
      }
    }

    final executable = config.useFvm ? 'fvm' : 'flutter';
    final processArgs =
        config.useFvm ? <String>['flutter', ...flutterArgs] : flutterArgs;

    try {
      _process = await Process.start(
        executable,
        processArgs,
        workingDirectory: config.projectRoot,
      );
    } on Object catch (error) {
      _error = 'Failed to start flutter reinstall: $error';
      return false;
    }

    _running = true;
    _appendLine('> $executable ${processArgs.join(' ')}');
    _notifyChange();

    bindProcessLines(_process!.stdout, _appendLine, onError: (error) {
      _error = 'Flutter output decode error: $error';
      _appendLine(_error!);
    });
    bindProcessLines(
      _process!.stderr,
      (line) => _appendLine('[stderr] $line'),
      onError: (error) {
        _error = 'Flutter stderr decode error: $error';
        _appendLine(_error!);
      },
    );
    unawaited(
      _process!.exitCode.then((code) {
        _running = false;
        if (code != 0) {
          _error = 'Flutter reinstall exited with code $code';
          _appendLine(_error!);
        } else {
          _appendLine('Flutter reinstall finished.');
        }
        _notifyChange();
      }),
    );
    return true;
  }

  Future<bool> _sendRunKey(String key) async {
    final process = _process;
    if (process == null || !_running) {
      return false;
    }
    try {
      process.stdin.writeln(key);
      await process.stdin.flush();
      _appendLine('> $key');
      _notifyChange();
      return true;
    } on Object catch (error) {
      _error = 'Failed to send flutter command "$key": $error';
      _appendLine(_error!);
      _notifyChange();
      return false;
    }
  }

  Future<void> stop() async {
    final process = _process;
    _process = null;
    if (process != null) {
      process.kill(ProcessSignal.sigterm);
      try {
        await process.exitCode.timeout(const Duration(seconds: 3));
      } on Object {
        process.kill(ProcessSignal.sigkill);
      }
    }
    _running = false;
  }

  void _appendLine(String line) {
    if (line.trim().isEmpty) {
      return;
    }
    _output.addLast(line);
    while (_output.length > _maxDeployLines) {
      _output.removeFirst();
    }
    if (_output.length == 1 || _output.length % 3 == 0) {
      _notifyChange();
    }
  }

  void _notifyChange() {
    _outputRevision++;
    onChange();
  }
}

class DeployWorkerFacade {
  DeployWorkerFacade({
    required this.projectRoot,
    required this.deviceId,
    required this.buildMode,
    this.envFile,
    this.appEnv,
    required this.vmServicePort,
    required this.useFvm,
  }) : _host = FeatureIsolateHost(
          debugName: 'deploy-worker',
          entryPoint: deployWorkerMain,
        );

  final String projectRoot;
  final String deviceId;
  final String buildMode;
  final String? envFile;
  final String? appEnv;
  final int vmServicePort;
  final bool useFvm;
  final FeatureIsolateHost _host;
  final _changes = StreamController<void>.broadcast();
  StreamSubscription<String>? _eventSub;

  var _canDeploy = false;
  var _isRunning = false;
  var _hasActiveProcess = false;
  String? _error;
  var _deployGeneration = 0;
  var _outputRevision = 0;
  List<String> _recentOutput = const [];

  Stream<void> get changes => _changes.stream;
  bool get canDeploy => _canDeploy;
  bool get isRunning => _isRunning;
  bool get hasActiveProcess => _hasActiveProcess;
  String? get error => _error;
  int get deployGeneration => _deployGeneration;
  int get outputRevision => _outputRevision;
  int get revision => _outputRevision;
  List<String> get recentOutput => _recentOutput;

  Future<void> start() async {
    await _host.start(
      DeployWorkerConfig(
        projectRoot: projectRoot,
        deviceId: deviceId,
        buildMode: buildMode,
        envFile: envFile,
        appEnv: appEnv,
        vmServicePort: vmServicePort,
        useFvm: useFvm,
      ).toJson(),
    );
    _eventSub = _host.events.listen((_) {
      unawaited(_refreshStatus());
    });
    await _refreshStatus();
  }

  Future<void> _refreshStatus() async {
    final status = await _host.request<Map<Object?, Object?>>('status');
    _canDeploy = status['canDeploy'] == true;
    _isRunning = status['isRunning'] == true;
    _hasActiveProcess = status['hasActiveProcess'] == true;
    _error = status['error'] as String?;
    _deployGeneration = status['deployGeneration'] as int? ?? 0;
    _outputRevision = status['outputRevision'] as int? ?? 0;
    _recentOutput = List<String>.from(
      (status['recentOutput'] as List<Object?>?)?.whereType<String>() ??
          const <String>[],
    );
    _changes.add(null);
  }

  Future<void> dispose() async {
    await _eventSub?.cancel();
    await _host.dispose();
    await _changes.close();
  }

  Future<bool> reinstall() async {
    final result = await _host.request<Map<Object?, Object?>>('reinstall');
    await _refreshStatus();
    return result['ok'] == true;
  }

  Future<bool> hotReload() async {
    final result = await _host.request<Map<Object?, Object?>>('hotReload');
    return result['ok'] == true;
  }

  Future<bool> hotRestart() async {
    final result = await _host.request<Map<Object?, Object?>>('hotRestart');
    return result['ok'] == true;
  }

  Future<bool> quit() async {
    final result = await _host.request<Map<Object?, Object?>>('quit');
    return result['ok'] == true;
  }

  Future<void> stop() => _host.request<Object?>('stop');
}
