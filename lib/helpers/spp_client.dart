import "dart:async";
import "dart:convert";
import "dart:typed_data";

import "package:flutter_bluetooth_serial/flutter_bluetooth_serial.dart";

enum SppConnectionStatus {
  disconnected,
  connecting,
  connected,
  error,
}

typedef OnSppStatus = void Function(SppConnectionStatus status, [String? error]);

class SppClient {
  SppClient({this.onStatus});

  final OnSppStatus? onStatus;

  BluetoothConnection? _connection;
  StreamSubscription<Uint8List>? _inputSub;
  SppConnectionStatus _status = SppConnectionStatus.disconnected;
  static const Duration _connectTimeout = Duration(seconds: 15);

  SppConnectionStatus get status => _status;
  bool get isConnected => _connection?.isConnected ?? false;

  Future<void> connect(String address) async {
    if (isConnected) {
      await disconnect();
    }

    _setStatus(SppConnectionStatus.connecting);

    try {
      _connection = await BluetoothConnection.toAddress(address).timeout(
        _connectTimeout,
        onTimeout: () {
          throw TimeoutException(
            "Tempo limite ao conectar em $address (${_connectTimeout.inSeconds}s).",
          );
        },
      );
      _setStatus(SppConnectionStatus.connected);

      _inputSub = _connection!.input?.listen(
        (_) {},
        onError: (Object error) {
          _setStatus(SppConnectionStatus.error, error.toString());
        },
        onDone: () {
          _setStatus(SppConnectionStatus.disconnected);
        },
        cancelOnError: false,
      );
    } catch (error) {
      await _inputSub?.cancel();
      _inputSub = null;
      await _connection?.close();
      _connection = null;
      _setStatus(SppConnectionStatus.error, error.toString());
      rethrow;
    }
  }

  Future<void> sendLatin1(String text) async {
    final output = _connection?.output;
    if (output == null || !isConnected) {
      throw StateError("Conexão Bluetooth inativa.");
    }

    output.add(Uint8List.fromList(latin1.encode(text)));
    await output.allSent;
  }

  Future<void> disconnect() async {
    await _inputSub?.cancel();
    _inputSub = null;

    if (_connection != null) {
      await _connection!.close();
      _connection = null;
    }

    _setStatus(SppConnectionStatus.disconnected);
  }

  void _setStatus(SppConnectionStatus value, [String? error]) {
    _status = value;
    onStatus?.call(value, error);
  }
}
