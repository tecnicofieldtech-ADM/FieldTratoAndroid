import "package:flutter/material.dart";
import "package:package_info_plus/package_info_plus.dart";

/// Rótulo de versão do app (ex.: `Versão v1.0.12 (2018)`).
Future<String> loadAppVersionLabel({bool includeBuild = true}) async {
  final info = await PackageInfo.fromPlatform();
  if (!includeBuild) return "v${info.version}";
  return "v${info.version} (${info.buildNumber})";
}

/// Exibe a versão instalada (lida de `pubspec.yaml` / build).
class AppVersionLabel extends StatelessWidget {
  const AppVersionLabel({
    super.key,
    this.prefix = "Versão ",
    this.includeBuild = true,
    this.style,
    this.textAlign,
  });

  final String prefix;
  final bool includeBuild;
  final TextStyle? style;
  final TextAlign? textAlign;

  @override
  Widget build(BuildContext context) {
    final defaultStyle = TextStyle(
      fontSize: 13,
      fontWeight: FontWeight.w700,
      color: Colors.black.withValues(alpha: 0.65),
    );

    return FutureBuilder<String>(
      future: loadAppVersionLabel(includeBuild: includeBuild),
      builder: (context, snapshot) {
        final label = snapshot.data ?? "…";
        return Text(
          "$prefix$label",
          textAlign: textAlign ?? TextAlign.center,
          style: style ?? defaultStyle,
        );
      },
    );
  }
}
