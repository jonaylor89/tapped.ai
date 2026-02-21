import 'package:flutter/material.dart';

/// Design tokens for the Tapped app.
abstract final class TappedSpacing {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 20;
  static const double xxl = 24;
  static const double xxxl = 32;
}

abstract final class TappedRadius {
  static const double sm = 6;
  static const double md = 10;
  static const double lg = 15;
  static const double xl = 20;
  static const double full = 999;

  static final BorderRadius smAll = BorderRadius.circular(sm);
  static final BorderRadius mdAll = BorderRadius.circular(md);
  static final BorderRadius lgAll = BorderRadius.circular(lg);
  static final BorderRadius xlAll = BorderRadius.circular(xl);
}

abstract final class TappedColors {
  // Brand
  static const Color accent = Color(0xff0086CC);

  // Semantic
  static const Color success = Color(0xff34C759);
  static const Color error = Color(0xffFF3B30);
  static const Color warning = Color(0xffFF9500);

  // Surfaces
  static const Color backgroundLight = Color(0xfff8f6Fb);
  static const Color backgroundDark = Color(0xff010F16);

  // On-image overlays (use instead of Colors.white / Colors.black.withOpacity)
  static const Color textOnImage = Colors.white;
  static const Color textOnImageMuted = Color(0xCCFFFFFF);
  static const Color scrim = Color(0x80000000);
  static const Color scrimLight = Color(0x33000000);
}

abstract final class TappedTypography {
  // Display — hero text on profile, onboarding
  static const TextStyle displayLg = TextStyle(
    fontSize: 36,
    fontWeight: FontWeight.w800,
  );
  static const TextStyle displayMd = TextStyle(
    fontSize: 32,
    fontWeight: FontWeight.w800,
  );

  // Headings — section titles in sheets/pages
  static const TextStyle headingLg = TextStyle(
    fontSize: 28,
    fontWeight: FontWeight.bold,
  );
  static const TextStyle headingMd = TextStyle(
    fontSize: 22,
    fontWeight: FontWeight.bold,
  );
  static const TextStyle headingSm = TextStyle(
    fontSize: 18,
    fontWeight: FontWeight.w600,
  );

  // Body
  static const TextStyle bodyLg = TextStyle(fontSize: 16);
  static const TextStyle bodyMd = TextStyle(fontSize: 14);
  static const TextStyle bodySm = TextStyle(fontSize: 12);

  // Labels — chips, badges, captions
  static const TextStyle label = TextStyle(fontSize: 13);
  static const TextStyle caption = TextStyle(fontSize: 10);
}
