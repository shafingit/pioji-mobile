import 'package:flutter/material.dart';

/// Palette 9 "Assam green iOS". The only place colour values live.
@immutable
class AppColors extends ThemeExtension<AppColors> {
  const AppColors({
    required this.background,
    required this.surface,
    required this.surfaceRaised,
    required this.fill,
    required this.textPrimary,
    required this.textSecondary,
    required this.textTertiary,
    required this.separator,
    required this.accent,
    required this.accentFill,
    required this.onAccent,
    required this.accentTint,
    required this.success,
    required this.warning,
    required this.danger,
    required this.dangerFill,
    required this.barDeep,
    required this.cardShadow,
  });

  final Color background;
  final Color surface;
  final Color surfaceRaised;
  final Color fill;
  final Color textPrimary;
  final Color textSecondary;
  final Color textTertiary;
  final Color separator;
  final Color accent;
  final Color accentFill;
  final Color onAccent;
  final Color accentTint;
  final Color success;
  final Color warning;
  final Color danger;
  final Color dangerFill;

  /// Bottom edge colour of the tab bar shadow.
  final Color barDeep;
  final List<BoxShadow> cardShadow;

  static const light = AppColors(
    background: Color(0xFFF6F8F7),
    surface: Color(0xFFFFFFFF),
    surfaceRaised: Color(0xFFFFFFFF),
    fill: Color(0x1F768079),
    textPrimary: Color(0xFF121815),
    textSecondary: Color(0xFF4F5853),
    textTertiary: Color(0xFF6B756F),
    separator: Color(0xFFE2E7E4),
    accent: Color(0xFF1F5A43),
    accentFill: Color(0xFF1F5A43),
    onAccent: Color(0xFFFFFFFF),
    accentTint: Color(0x141F5A43),
    success: Color(0xFF2E7D4F),
    warning: Color(0xFF9A6200),
    danger: Color(0xFFB3261E),
    dangerFill: Color(0xFFB3261E),
    barDeep: Color(0xFFC9D3CD),
    cardShadow: AppShadow.card,
  );

  static const dark = AppColors(
    background: Color(0xFF0A0D0B),
    surface: Color(0xFF181D1A),
    surfaceRaised: Color(0xFF222824),
    fill: Color(0xFF3A423D),
    textPrimary: Color(0xFFEEF3F0),
    textSecondary: Color(0xFFABB5AF),
    textTertiary: Color(0xFF87918B),
    separator: Color(0xFF28302C),
    accent: Color(0xFF4FB487),
    accentFill: Color(0xFF237A57),
    onAccent: Color(0xFFFFFFFF),
    accentTint: Color(0x244FB487),
    success: Color(0xFF4CC27F),
    warning: Color(0xFFE5B040),
    danger: Color(0xFFFF6B60),
    dangerFill: Color(0xFFB3261E),
    barDeep: Color(0xFF000000),
    cardShadow: AppShadow.none,
  );

  @override
  AppColors copyWith() => this;

  @override
  AppColors lerp(covariant AppColors? other, double t) =>
      t < 0.5 ? this : (other ?? this);
}

abstract final class AppSpace {
  static const xxs = 2.0;
  static const xs = 4.0;
  static const sm = 8.0;
  static const md = 12.0;
  static const lg = 16.0;
  static const xl = 20.0;
  static const xxl = 24.0;
  static const xxxl = 32.0;

  /// Horizontal screen gutter.
  static const screenH = 16.0;

  /// Minimum tap target and list row height.
  static const rowMinH = 48.0;
}

abstract final class AppRadius {
  static const control = 11.0;
  static const card = 14.0;
  static const sheet = 20.0;
  static const tile = 7.0;

  static const controlBorder =
      RoundedSuperellipseBorder(borderRadius: BorderRadius.all(Radius.circular(control)));
  static const cardBorder =
      RoundedSuperellipseBorder(borderRadius: BorderRadius.all(Radius.circular(card)));
}

abstract final class AppShadow {
  static const card = [
    BoxShadow(color: Color(0x0A000000), blurRadius: 2, offset: Offset(0, 1)),
    BoxShadow(color: Color(0x09000000), blurRadius: 16, offset: Offset(0, 6)),
  ];
  /// Lighter than [card], for small tiles like the Home quick actions.
  static const soft = [
    BoxShadow(color: Color(0x05000000), blurRadius: 1, offset: Offset(0, 0.5)),
    BoxShadow(color: Color(0x06000000), blurRadius: 14, offset: Offset(0, 4)),
  ];
  static const none = <BoxShadow>[];
}

/// Colours of one tonal card: a diagonal gradient from [from] to [to] (the
/// same hue, about 10% deeper), with [ink] for the value and icon and
/// [inkSoft] for the secondary text.
@immutable
class TonalColors {
  const TonalColors(this.from, this.to, this.ink, this.inkSoft);
  final Color from;
  final Color to;
  final Color ink;
  final Color inkSoft;

  /// The icon tile behind the icon.
  Color get tile => ink.withValues(alpha: 0.10);

  LinearGradient get gradient => LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [from, to]);
}

/// Muted hues for tonal cards. Light mode uses pale tints; dark mode dim
/// versions with soft light text.
enum CardHue {
  teal(
    TonalColors(Color(0xFFE3F1EE), Color(0xFFD1E6E0), Color(0xFF1E5249), Color(0xFF417067)),
    TonalColors(Color(0xFF1B2926), Color(0xFF15211F), Color(0xFFBFE0D8), Color(0xFF93B5AD)),
  ),
  olive(
    TonalColors(Color(0xFFEDEFDD), Color(0xFFDFE3CA), Color(0xFF485021), Color(0xFF666E3E)),
    TonalColors(Color(0xFF24271B), Color(0xFF1D2015), Color(0xFFD6DCB5), Color(0xFFADB38D)),
  ),
  clay(
    TonalColors(Color(0xFFF5E7E0), Color(0xFFEBD6CB), Color(0xFF7A3F2A), Color(0xFF975B4A)),
    TonalColors(Color(0xFF2D221E), Color(0xFF251B17), Color(0xFFEBC9BC), Color(0xFFBE9F93)),
  ),
  mustard(
    TonalColors(Color(0xFFF6EED6), Color(0xFFECE0BD), Color(0xFF6B520F), Color(0xFF89702F)),
    TonalColors(Color(0xFF2B2618), Color(0xFF242013), Color(0xFFEAD9A6), Color(0xFFBDAE82)),
  ),
  lavender(
    TonalColors(Color(0xFFEDE8F5), Color(0xFFDFD7EC), Color(0xFF4E3F6E), Color(0xFF6A5C88)),
    TonalColors(Color(0xFF26222E), Color(0xFF1F1B26), Color(0xFFD6CCEA), Color(0xFFABA2C0)),
  ),
  periwinkle(
    TonalColors(Color(0xFFE5EAF7), Color(0xFFD4DCF0), Color(0xFF33467A), Color(0xFF536396)),
    TonalColors(Color(0xFF1D2230), Color(0xFF181C28), Color(0xFFC6D1F0), Color(0xFF9CA7C6)),
  );

  const CardHue(this.light, this.dark);
  final TonalColors light;
  final TonalColors dark;

  TonalColors of(Brightness b) => b == Brightness.dark ? dark : light;
}
