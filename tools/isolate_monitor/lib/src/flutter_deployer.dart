import 'dart:async';

import 'workers/deploy_worker.dart';

/// Flutter deploy / run output — one dedicated worker isolate per monitor session.
class FlutterDeployer {
  FlutterDeployer({
    required this.projectRoot,
    required this.deviceId,
    required this.buildMode,
    this.envFile,
    this.appEnv,
    this.vmServicePort = 58888,
    this.useFvm = true,
  }) : _facade = DeployWorkerFacade(
          projectRoot: projectRoot,
          deviceId: deviceId,
          buildMode: buildMode,
          envFile: envFile,
          appEnv: appEnv,
          vmServicePort: vmServicePort,
          useFvm: useFvm,
        );

  final String projectRoot;
  final String deviceId;
  final String buildMode;
  final String? envFile;
  final String? appEnv;
  final int vmServicePort;
  final bool useFvm;
  final DeployWorkerFacade _facade;
  var _started = false;

  Stream<void> get changes => _facade.changes;
  bool get canDeploy => _facade.canDeploy;
  bool get isRunning => _facade.isRunning;
  bool get hasActiveProcess => _facade.hasActiveProcess;
  String? get error => _facade.error;
  int get deployGeneration => _facade.deployGeneration;
  int get outputRevision => _facade.outputRevision;
  int get revision => _facade.revision;
  List<String> get recentOutput => _facade.recentOutput;

  Future<void> _ensureStarted() async {
    if (_started) {
      return;
    }
    await _facade.start();
    _started = true;
  }

  Future<bool> reinstall() async {
    await _ensureStarted();
    return _facade.reinstall();
  }

  Future<bool> hotReload() async {
    await _ensureStarted();
    return _facade.hotReload();
  }

  Future<bool> hotRestart() async {
    await _ensureStarted();
    return _facade.hotRestart();
  }

  Future<bool> quit() async {
    await _ensureStarted();
    return _facade.quit();
  }

  Future<void> stop() async {
    await _ensureStarted();
    await _facade.stop();
  }
}
