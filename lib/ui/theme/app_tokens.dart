import 'package:flutter/material.dart';

/// Design tokens for the Sehat Nigraan visual identity.
/// See docs/ui-ux-plan.md §3 (Design Theme & Visual Identity).
class AppColors {
  AppColors._();

  static const seed = Color(0xFF0D7377);
  static const teal700 = Color(0xFF0D7377);
  static const teal800 = Color(0xFF0A5A5E);

  static const background = Color(0xFF121416);
  static const surface = Color(0xFF1D2125);
  static const border = Color(0xFF333A40);

  static const textPrimary = Color(0xFFECF0F2);
  static const textSubdued = Color(0xFF9AA6AD);

  static const reviewBanner = Color(0xFFFBC02D);

  /// P1-P5 tier palette — LOCKED, spec §14.
  static const tierP1 = Color(0xFFD32F2F);
  static const tierP2 = Color(0xFFF57C00);
  static const tierP3 = Color(0xFFFBC02D);
  static const tierP4 = Color(0xFF388E3C);
  static const tierP5 = Color(0xFF1976D2);
}

/// Touch/size/rhythm constants (spec: adults in emergencies, elderly users).
class AppMetrics {
  AppMetrics._();

  /// Minimum touch target height for interactive answer tiles.
  static const double minTouch = 56;

  /// Primary action buttons.
  static const double bigButtonHeight = 64;

  /// Screen side margins.
  static const double margin = 20;

  /// Gap between tappable elements.
  static const double gap = 12;

  /// Space between answer tiles.
  static const double answerGap = 10;
}

/// Quiz/triage flow constants.
class TriageText {
  TriageText._();

  static const String startTitle = 'Start Triage';
  static const String startSubtitle =
      'Answer a few simple questions. No internet needed.';
}