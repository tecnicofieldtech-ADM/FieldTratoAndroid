import "package:flutter/material.dart";

import "../helpers/rfid_comm.dart";
import "../helpers/scale_comm.dart";

/// Card destacado com peso da balança e, opcionalmente, um segundo valor (ex.: previsto total).
class ScalePesoHighlightCard extends StatelessWidget {
  const ScalePesoHighlightCard({
    super.key,
    required this.pesoKg,
    this.pesoLabel = "Balança",
    this.secondaryLabel,
    this.secondaryKg,
    this.secondarySubtitle,
    this.statusIcon,
    this.statusText,
    this.statusColor,
    this.trailing,
    this.pesoInlineActions,
    this.connectionSlots,
    this.statusBar,
    this.footer,
  });

  final double pesoKg;
  final String pesoLabel;
  final String? secondaryLabel;
  final double? secondaryKg;
  final String? secondarySubtitle;
  final IconData? statusIcon;
  final String? statusText;
  final Color? statusColor;
  final Widget? trailing;
  /// Botões na mesma área do peso (ex.: Pausar), alinhados à direita do valor.
  final Widget? pesoInlineActions;
  /// Cards de conexão alinhados ao lado do peso (ex.: balança, RFID, espelho).
  final List<Widget>? connectionSlots;
  /// @deprecated Prefer [connectionSlots] na mesma linha do peso.
  final Widget? statusBar;
  final Widget? footer;

  static const double _valorRowHeight = 52;

  Widget _metricBox({
    required String label,
    required String value,
    String? sub,
    required CrossAxisAlignment align,
    Widget? inlineActions,
    Widget? bottom,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.teal.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.teal.shade100),
      ),
      child: Column(
        crossAxisAlignment: align,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              color: Colors.teal.shade800,
            ),
          ),
          const SizedBox(height: 4),
          SizedBox(
            height: _valorRowHeight,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              mainAxisAlignment: align == CrossAxisAlignment.end
                  ? MainAxisAlignment.end
                  : MainAxisAlignment.start,
              children: [
                Flexible(
                  child: Text(
                    value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: align == CrossAxisAlignment.end
                        ? TextAlign.right
                        : TextAlign.left,
                    style: const TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w900,
                      height: 1.05,
                    ),
                  ),
                ),
                if (inlineActions != null) ...[
                  const SizedBox(width: 8),
                  Flexible(
                    fit: FlexFit.loose,
                    child: inlineActions,
                  ),
                ],
              ],
            ),
          ),
          if (bottom != null) ...[
            const SizedBox(height: 8),
            bottom,
          ],
          if (sub != null && sub.trim().isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              sub,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: Colors.grey.shade700,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _slotShell(Widget child) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.teal.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.teal.shade100),
      ),
      child: child,
    );
  }

  @override
  Widget build(BuildContext context) {
    final hasSecondary =
        secondaryLabel != null && secondaryLabel!.trim().isNotEmpty;
    final inline = pesoInlineActions ?? trailing;
    final slots = connectionSlots ?? const <Widget>[];
    final hasSlots = slots.isNotEmpty;

    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (hasSecondary) ...[
                    Expanded(
                      child: _metricBox(
                        label: secondaryLabel!,
                        value: secondaryKg != null && secondaryKg! > 0
                            ? "${secondaryKg!.toStringAsFixed(0)} kg"
                            : "—",
                        sub: secondarySubtitle,
                        align: CrossAxisAlignment.start,
                      ),
                    ),
                    const SizedBox(width: 10),
                  ],
                  Expanded(
                    flex: hasSlots ? 2 : 1,
                    child: _metricBox(
                      label: pesoLabel,
                      value: "${pesoKg.toStringAsFixed(0)} kg",
                      align: CrossAxisAlignment.start,
                      inlineActions: inline,
                      bottom: !hasSlots && statusBar != null
                          ? statusBar
                          : (!hasSlots &&
                                  statusText != null &&
                                  statusText!.trim().isNotEmpty
                              ? Row(
                                  children: [
                                    if (statusIcon != null)
                                      Icon(statusIcon,
                                          size: 16, color: statusColor),
                                    if (statusIcon != null)
                                      const SizedBox(width: 6),
                                    Expanded(
                                      child: Text(
                                        statusText!,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontWeight: FontWeight.w700,
                                          color: statusColor,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ),
                                  ],
                                )
                              : null),
                    ),
                  ),
                  for (var i = 0; i < slots.length; i++) ...[
                    const SizedBox(width: 8),
                    Expanded(
                      child: _slotShell(
                        Align(
                          alignment: Alignment.topLeft,
                          child: slots[i],
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (footer != null) ...[
              const SizedBox(height: 8),
              footer!,
            ],
          ],
        ),
      ),
    );
  }
}

/// Labels/cores de status da balança (enum, sem ambiguidade de substring).
({Color color, IconData icon, String label, String detail}) scaleConnectionUi(
  ScaleStatus status, {
  String? message,
}) {
  switch (status) {
    case ScaleStatus.connected:
      return (
        color: Colors.green,
        icon: Icons.check_circle,
        label: "Conectada",
        detail: (message ?? "").trim().isNotEmpty ? message!.trim() : "OK",
      );
    case ScaleStatus.connecting:
      return (
        color: Colors.orange,
        icon: Icons.wifi_tethering,
        label: "Conectando",
        detail: (message ?? "").trim().isNotEmpty ? message!.trim() : "…",
      );
    case ScaleStatus.error:
      return (
        color: Colors.red,
        icon: Icons.error_outline,
        label: "Erro",
        detail: (message ?? "").trim().isNotEmpty ? message!.trim() : "Falha",
      );
    case ScaleStatus.disconnected:
      return (
        color: Colors.grey,
        icon: Icons.portable_wifi_off,
        label: "Desconectada",
        detail: (message ?? "").trim().isNotEmpty ? message!.trim() : "OFF",
      );
  }
}

/// Labels/cores de status do RFID.
({Color color, IconData icon, String label, String detail}) rfidConnectionUi(
  RfidStatus status, {
  String? message,
  bool pausado = false,
}) {
  if (pausado) {
    return (
      color: Colors.blueGrey,
      icon: Icons.pause_circle_filled,
      label: "Pausado",
      detail: "Leitura pausada pelo operador",
    );
  }

  final base = switch (status) {
    RfidStatus.connected => (
      color: Colors.green,
      icon: Icons.nfc,
      label: "Conectado",
      detail: "OK",
    ),
    RfidStatus.connecting => (
      color: Colors.orange,
      icon: Icons.wifi_tethering,
      label: "Conectando",
      detail: "…",
    ),
    RfidStatus.error => (
      color: Colors.red,
      icon: Icons.error_outline,
      label: "Erro",
      detail: "Falha",
    ),
    RfidStatus.disconnected => (
      color: Colors.grey,
      icon: Icons.nfc_outlined,
      label: "Desconectado",
      detail: "OFF",
    ),
  };
  final detail =
      (message ?? "").trim().isNotEmpty ? message!.trim() : base.detail;
  return (
    color: base.color,
    icon: base.icon,
    label: base.label,
    detail: detail,
  );
}

/// Chip de status de conexão (balança, espelho, etc.).
class ScaleConnectionStatusChip extends StatelessWidget {
  const ScaleConnectionStatusChip({
    super.key,
    required this.title,
    required this.detail,
    required this.icon,
    required this.color,
  });

  final String title;
  final String detail;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 6),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: color.withValues(alpha: 0.9),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  detail,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: color,
                    height: 1.2,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
