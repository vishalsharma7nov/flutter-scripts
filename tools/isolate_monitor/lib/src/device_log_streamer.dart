import 'dart:async';

import 'workers/device_log_worker.dart';

/// Device log streaming — one dedicated worker isolate per session.
class DeviceLogStreamer {
  DeviceLogStreamer({
    required this.packageName,
    required this.bundleId,
    required this.deviceId,
  }) : _facade = DeviceLogWorkerFacade(
          packageName: packageName,
          bundleId: bundleId,
          deviceId: deviceId,
        );

  final String packageName;
  final String bundleId;
  final String deviceId;
  final DeviceLogWorkerFacade _facade;

  Stream<void> get changes => _facade.changes;
  bool get isStreaming => _facade.isStreaming;
  String? get error => _facade.error;
  int get lineCount => _facade.lineCount;
  int get revision => _facade.revision;
  int get sessionRevision => _facade.sessionRevision;
  List<String> get recentLines => _facade.recentLines;

  Future<void> start() => _facade.start();

  Future<void> dispose() => _facade.dispose();

  Future<void> stop() => _facade.stop();

  Future<void> restartForReinstall() => _facade.restartForReinstall();

  Future<void> reconnect() => _facade.reconnect();

  List<String> searchLines(String query, {bool caseSensitive = false}) {
    return _facade.searchLines(query, caseSensitive: caseSensitive);
  }

  Future<Map<String, Object?>> fetchLogsPayload({
    String query = '',
    bool caseSensitive = false,
  }) =>
      _facade.fetchLogsPayload(query: query, caseSensitive: caseSensitive);

  Future<String> fetchLogsJson({
    String query = '',
    bool caseSensitive = false,
  }) =>
      _facade.fetchLogsJson(query: query, caseSensitive: caseSensitive);

  Future<String> fetchSearchJson({
    required String query,
    bool caseSensitive = false,
  }) =>
      _facade.fetchSearchJson(query: query, caseSensitive: caseSensitive);
}
