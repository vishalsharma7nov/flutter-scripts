import 'dart:async';
import 'dart:convert';

const _utf8LineDecoder = Utf8Decoder(allowMalformed: true);

StreamSubscription<String> bindProcessLines(
  Stream<List<int>> byteStream,
  void Function(String line) onLine, {
  void Function(Object error)? onError,
}) {
  return byteStream
      .transform(_utf8LineDecoder)
      .transform(const LineSplitter())
      .listen(
        onLine,
        onError: onError,
        cancelOnError: false,
      );
}
