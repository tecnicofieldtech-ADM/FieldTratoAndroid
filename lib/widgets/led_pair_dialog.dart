import "dart:async";

import "package:flutter/material.dart";
import "package:flutter_bluetooth_serial/flutter_bluetooth_serial.dart";

import "../helpers/bt_permissions.dart";

/// Diálogo para buscar e parear dispositivo LED via Bluetooth SPP.
class LedPairDialog extends StatefulWidget {
  const LedPairDialog({super.key});

  static Future<BluetoothDevice?> show(BuildContext context) {
    return showDialog<BluetoothDevice>(
      context: context,
      builder: (_) => const LedPairDialog(),
    );
  }

  @override
  State<LedPairDialog> createState() => _LedPairDialogState();
}

class _LedPairDialogState extends State<LedPairDialog> {
  bool _loading = true;
  bool _scanning = false;
  String? _error;
  final List<BluetoothDevice> _devices = [];
  StreamSubscription<BluetoothDiscoveryResult>? _discoverySub;

  @override
  void initState() {
    super.initState();
    unawaited(_loadBonded());
  }

  @override
  void dispose() {
    unawaited(_stopDiscovery());
    super.dispose();
  }

  Future<void> _loadBonded() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      await _ensureBtReady();
      final bonded = await FlutterBluetoothSerial.instance.getBondedDevices();
      if (!mounted) return;
      setState(() {
        _devices
          ..clear()
          ..addAll(bonded);
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _ensureBtReady() async {
    final allowed = await BtPermissions.ensureBluetoothPermissions();
    if (!allowed) {
      throw StateError("Permissões Bluetooth não concedidas.");
    }

    final available = await FlutterBluetoothSerial.instance.isAvailable;
    if (available != true) {
      throw StateError("Bluetooth indisponível neste dispositivo.");
    }

    final enabled = await FlutterBluetoothSerial.instance.isEnabled;
    if (enabled != true) {
      final on = await FlutterBluetoothSerial.instance.requestEnable() ?? false;
      if (!on) {
        throw StateError("Bluetooth desativado.");
      }
    }
  }

  Future<void> _startDiscovery() async {
    if (_scanning) return;

    setState(() {
      _scanning = true;
      _error = null;
    });

    try {
      await _ensureBtReady();
      await _stopDiscovery();

      _discoverySub =
          FlutterBluetoothSerial.instance.startDiscovery().listen((result) {
        final dev = result.device;
        final idx = _devices.indexWhere((d) => d.address == dev.address);
        if (!mounted) return;
        setState(() {
          if (idx >= 0) {
            _devices[idx] = dev;
          } else {
            _devices.add(dev);
          }
        });
      });

      _discoverySub!.onDone(() {
        if (!mounted) return;
        setState(() => _scanning = false);
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _scanning = false;
      });
    }
  }

  Future<void> _stopDiscovery() async {
    await _discoverySub?.cancel();
    _discoverySub = null;
    try {
      await FlutterBluetoothSerial.instance.cancelDiscovery();
    } catch (_) {}
    if (mounted && _scanning) {
      setState(() => _scanning = false);
    }
  }

  Future<void> _pairAndSelect(BluetoothDevice device) async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      if (!device.isBonded) {
        await FlutterBluetoothSerial.instance.bondDeviceAtAddress(device.address);
      }
      if (!mounted) return;
      Navigator.of(context).pop(device);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  String _label(BluetoothDevice d) {
    final name = (d.name ?? "").trim();
    if (name.isEmpty) return d.address;
    return "$name (${d.address})";
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text("Parear conversor BS1C"),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_error != null) ...[
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
              const SizedBox(height: 8),
            ],
            if (_loading)
              const Padding(
                padding: EdgeInsets.all(16),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_devices.isEmpty)
              const Text("Nenhum dispositivo encontrado. Toque em Buscar.")
            else
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: _devices.length,
                  itemBuilder: (_, i) {
                    final d = _devices[i];
                    return ListTile(
                      leading: Icon(
                        d.isBonded
                            ? Icons.bluetooth_connected
                            : Icons.bluetooth,
                      ),
                      title: Text(_label(d)),
                      subtitle: Text(
                        d.isBonded ? "Pareado" : "Toque para parear",
                      ),
                      onTap: _loading ? null : () => _pairAndSelect(d),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _loading ? null : () => Navigator.of(context).pop(),
          child: const Text("Cancelar"),
        ),
        TextButton(
          onPressed: _loading || _scanning ? null : _startDiscovery,
          child: Text(_scanning ? "Buscando…" : "Buscar"),
        ),
        TextButton(
          onPressed: _loading ? null : _loadBonded,
          child: const Text("Atualizar"),
        ),
      ],
    );
  }
}
