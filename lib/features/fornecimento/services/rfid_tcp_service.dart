import 'dart:async';
import 'dart:convert';
import 'dart:io';

class RfidTcpService {
  Socket? _sock;
  StreamSubscription? _sub;
  final _controller = StreamController<String>.broadcast();

  Stream<String> get lines => _controller.stream;

  Future<void> connect(String host, int port) async {
    await disconnect();
    _sock = await Socket.connect(host, port, timeout: const Duration(seconds: 3));
    _sock!.setOption(SocketOption.tcpNoDelay, true);

    final decoder = const Utf8Decoder(allowMalformed: true);
    final sb = StringBuffer();

    _sub = _sock!.listen((data) {
      final chunk = decoder.convert(data);
      sb.write(chunk);

      final text = sb.toString();
      final parts = text.split(RegExp(r'[\r\n]+'));
      if (!text.endsWith('\n') && !text.endsWith('\r')) {
        sb
          ..clear()
          ..write(parts.removeLast());
      } else {
        sb.clear();
      }

      for (final line in parts) {
        final t = line.trim();
        if (t.isNotEmpty) _controller.add(t);
      }
    }, onError: (_) {}, onDone: () {});
  }

  static String extractEpc(String s) {
    final t = s.trim();
    if (t.toUpperCase().startsWith(';EPC:')) {
      return t.substring(5).replaceAll(';', '').trim();
    }
    return t;
  }

  Future<void> disconnect() async {
    await _sub?.cancel();
    _sub = null;
    try { _sock?.destroy(); } catch (_) {}
    _sock = null;
  }

  void dispose() {
    disconnect();
    _controller.close();
  }
}
