import 'dart:async';

import 'workers/vm_inspector_worker.dart';

/// VM service inspection — one dedicated worker isolate per monitor session.
class VmConnector {
  VmConnector({
    required this.vmPort,
    this.uriOverride,
  }) : _facade = VmInspectorFacade(
          vmPort: vmPort,
          uriOverride: uriOverride,
        );

  final int vmPort;
  final String? uriOverride;
  final VmInspectorFacade _facade;

  Stream<void> get changes => _facade.changes;
  bool get isConnected => _facade.isConnected;
  String? get vmUri => _facade.vmUri;

  Future<void> startPolling() => _facade.startPolling();

  Future<void> dispose() => _facade.dispose();

  Future<List<Map<String, Object?>>> listIsolates() => _facade.listIsolates();

  Future<Map<String, Object?>> hotReload() => _facade.hotReload();

  Future<Map<String, Object?>> hotRestart() => _facade.hotRestart();

  Future<Map<String, Object?>> quitApp() => _facade.quitApp();

  Future<void> resetConnection() => _facade.resetConnection();
}
