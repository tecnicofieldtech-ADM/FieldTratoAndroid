import "package:flutter/material.dart";

class UltimoToast {
  static DateTime? _last;
  static void show(BuildContext context, String msg) {
    final now = DateTime.now();
    if (_last != null && now.difference(_last!) < const Duration(milliseconds: 900)) {
      return;
    }
    _last = now;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        duration: const Duration(seconds: 2),
      ),
    );
  }
}


