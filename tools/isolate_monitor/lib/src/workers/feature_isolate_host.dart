import 'dart:async';
import 'dart:convert';
import 'dart:isolate';

/// RPC host for exactly one long-lived worker [Isolate] per feature.
class FeatureIsolateHost {
  FeatureIsolateHost({
    required this.debugName,
    required this.entryPoint,
  });

  final String debugName;
  final void Function(SendPort mainPort) entryPoint;

  Isolate? _isolate;
  SendPort? _workerPort;
  final _ready = Completer<SendPort>();
  final _events = StreamController<String>.broadcast();
  var _nextRequestId = 0;
  final _pending = <int, Completer<Object?>>{};
  StreamSubscription<Object?>? _subscription;

  Stream<String> get events => _events.stream;

  Future<void> start(Object? initMessage) async {
    if (_isolate != null) {
      return;
    }
    final handshake = ReceivePort();
    _isolate = await Isolate.spawn(
      entryPoint,
      handshake.sendPort,
      debugName: debugName,
      errorsAreFatal: false,
    );
    _subscription = handshake.listen(_onMessage);
    _workerPort = await _ready.future;
    _workerPort!.send(<Object?>['init', initMessage]);
  }

  void _onMessage(Object? message) {
    if (message is SendPort && !_ready.isCompleted) {
      _ready.complete(message);
      return;
    }
    if (message is! List || message.isEmpty) {
      return;
    }
    final kind = message[0];
    if (kind == 'event' && message.length >= 2) {
      _events.add(message[1] as String);
      return;
    }
    if (kind == 'response' && message.length >= 3) {
      final requestId = message[1] as int;
      _pending.remove(requestId)?.complete(message[2]);
    }
  }

  Future<T> request<T>(String command, [Map<String, Object?> args = const {}]) async {
    final port = _workerPort ?? await _ready.future;
    final requestId = _nextRequestId++;
    final completer = Completer<Object?>();
    _pending[requestId] = completer;
    port.send(<Object?>['request', requestId, command, args]);
    return (await completer.future) as T;
  }

  Future<void> dispose() async {
    if (_workerPort != null) {
      try {
        await request<Object?>('dispose');
      } on Object {
        // Worker may already be gone.
      }
    }
    await _subscription?.cancel();
    _isolate?.kill(priority: Isolate.immediate);
    _isolate = null;
    _workerPort = null;
    await _events.close();
  }
}

/// Encodes a large logs payload off the main isolate when needed.
Future<String> encodeLogsPayloadInIsolate(Map<String, Object?> payload) {
  return Isolate.run(() => jsonEncode(payload));
}
