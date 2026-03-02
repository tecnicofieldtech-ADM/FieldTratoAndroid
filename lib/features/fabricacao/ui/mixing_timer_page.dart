import 'dart:async';
import 'package:flutter/material.dart';

class MixingTimerPage extends StatefulWidget {
  const MixingTimerPage({super.key, required this.seconds});
  final int seconds;

  @override
  State<MixingTimerPage> createState() => _MixingTimerPageState();
}

class _MixingTimerPageState extends State<MixingTimerPage> {
  late int left;
  Timer? t;

  @override
  void initState() {
    super.initState();
    left = widget.seconds;
    t = Timer.periodic(const Duration(seconds: 1), (_) {
      setState(() => left--);
      if (left <= 0) {
        t?.cancel();
        t = null;
      }
    });
  }

  @override
  void dispose() {
    t?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final mm = (left ~/ 60).toString().padLeft(2, '0');
    final ss = (left % 60).toString().padLeft(2, '0');

    return Scaffold(
      appBar: AppBar(title: const Text('Tempo de Mistura')),
      body: Center(
        child: Text(
          '$mm:$ss',
          style: const TextStyle(fontSize: 72, fontWeight: FontWeight.w900),
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: ElevatedButton(
            onPressed: left <= 0 ? () => Navigator.pop(context) : null,
            child: const Text('Fornecer'),
          ),
        ),
      ),
    );
  }
}


