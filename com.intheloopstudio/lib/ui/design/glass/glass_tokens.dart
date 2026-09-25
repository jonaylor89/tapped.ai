import 'package:flutter/widgets.dart';

/// Tokens for the Liquid Glass material.
///
/// Liquid Glass is a translucent, refractive surface that sits *above*
/// content rather than being part of it. Controls float, content scrolls
/// underneath, and the material picks up the colour of whatever is behind it.
abstract final class GlassBlur {
  /// Toolbars, tab bars, floating controls.
  static const double regular = 24;

  /// Thin overlays such as chips or badges sitting on imagery.
  static const double thin = 14;

  /// Sheets, popovers and menus — heavier so text underneath never competes.
  static const double thick = 40;
}

/// Radii follow the iOS 26 concentric-corner system: every nested corner is
/// the parent radius minus the inset, and interactive controls are capsules.
abstract final class GlassRadius {
  static const double control = 22;
  static const double card = 26;
  static const double sheet = 38;
  static const double capsule = 999;

  static final BorderRadius controlAll = BorderRadius.circular(control);
  static final BorderRadius cardAll = BorderRadius.circular(card);
  static final BorderRadius sheetTop = BorderRadius.vertical(
    top: Radius.circular(sheet),
  );
  static final BorderRadius capsuleAll = BorderRadius.circular(capsule);
}

/// Layout metrics for floating chrome.
abstract final class GlassMetrics {
  /// Diameter of a circular icon control (back, close, more).
  static const double iconControl = 44;

  /// Height of a capsule button / search field.
  static const double control = 50;

  /// Gap between floating controls and the screen edge.
  static const double edgeInset = 16;

  /// Height reserved under a floating bottom bar so lists scroll clear of it.
  static const double bottomBarClearance = 96;

  /// Height of the inline (collapsed) navigation title row.
  static const double navBarInline = 52;

  /// Extra height for the large title row above content.
  static const double navBarLargeTitle = 56;
}

/// Motion follows Apple's spring feel: quick in, gently settled.
abstract final class GlassMotion {
  static const Duration press = Duration(milliseconds: 120);
  static const Duration release = Duration(milliseconds: 320);
  static const Duration reveal = Duration(milliseconds: 260);
  static const Curve spring = Cubic(0.2, 0.9, 0.3, 1.1);
  static const Curve ease = Curves.easeOutCubic;
  static const double pressedScale = 0.96;
}
