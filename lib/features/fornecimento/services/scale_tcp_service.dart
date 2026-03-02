import 'dart:async';
import 'dart:convert';
import 'dart:io';

class ScaleTcpService {
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

      // normaliza controles < 32 (menos \r \n) para \n
      final normalized = chunk.split('').map((c) {
        final code = c.codeUnitAt(0);
        if (c != '\r' && c != '\n' && code < 32) return '\n';
        return c;
      }).join();

      sb.write(normalized);

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


