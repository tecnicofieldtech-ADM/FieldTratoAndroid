import "package:flutter/widgets.dart";

/// Responsive breakpoints and helpers shared across all pages.
class Responsive {
  Responsive._(this.context);

  factory Responsive.of(BuildContext context) => Responsive._(context);

  final BuildContext context;

  double get screenW => MediaQuery.of(context).size.width;
  double get screenH => MediaQuery.of(context).size.height;

  bool get isPhone => screenW < 600 || screenH < 700;
  bool get isSmallPhone => screenW < 400 || screenH < 600;

  double get hPad => isPhone ? 10.0 : 16.0;
  double get vGap => isPhone ? 6.0 : 10.0;

  double get titleSize => isPhone ? 18.0 : 28.0;
  double get subtitleSize => isPhone ? 13.0 : 16.0;
  double get bodySize => isPhone ? 12.0 : 14.0;
  double get labelSize => isPhone ? 10.0 : 12.0;

  double get bigNumberSize => isPhone ? 100.0 : 180.0;
  double get medNumberSize => isPhone ? 22.0 : 34.0;

  double get cardRadius => isPhone ? 14.0 : 22.0;
  double get buttonHeight => isPhone ? 38.0 : 48.0;

  double get iconSm => isPhone ? 14.0 : 18.0;
  double get iconMd => isPhone ? 18.0 : 24.0;

  EdgeInsets get cardPad => isPhone
      ? const EdgeInsets.all(10)
      : const EdgeInsets.all(16);

  EdgeInsets pagePad(double top) => EdgeInsets.fromLTRB(hPad, top, hPad, 0);
}
