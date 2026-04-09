// lib/widgets/app_logo.dart
import "package:flutter/material.dart";

class AppLogo extends StatelessWidget {
  final double height;
  const AppLogo({super.key, this.height = 120});

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      "assets/images/logo_Filed_Transparente.png",
      height: height,
      fit: BoxFit.contain,
    );
  }
}


