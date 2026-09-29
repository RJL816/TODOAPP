import 'package:flutter/material.dart';

/// Scene colors are independent of the photograph and never dim foreground
/// widgets. A custom photograph uses the neutral palette; the existing shade
/// and glass clarity controls remain available for fine tuning.
@immutable
class AmbientPalette {
  const AmbientPalette({
    required this.tint,
    required this.tintOpacity,
    required this.edge,
    required this.primaryText,
    required this.secondaryText,
    required this.textShadow,
  });

  final Color tint;
  final double tintOpacity;
  final Color edge;
  final Color primaryText;
  final Color secondaryText;
  final Shadow textShadow;

  static const daylight = AmbientPalette(
    tint: Color(0xFF0F172A),
    tintOpacity: .27,
    edge: Color(0x40FFFFFF),
    primaryText: Color(0xFFFFFFFF),
    secondaryText: Color(0xD9FFFFFF),
    textShadow:
        Shadow(color: Color(0x99070F18), blurRadius: 4, offset: Offset(0, 1)),
  );

  static const dusk = AmbientPalette(
    tint: Color(0xFF1C1326),
    tintOpacity: .37,
    edge: Color(0x33FFC896),
    primaryText: Color(0xFFFFF8F0),
    secondaryText: Color(0xD9FFEBD7),
    textShadow:
        Shadow(color: Color(0x990E0B15), blurRadius: 4, offset: Offset(0, 1)),
  );

  static const night = AmbientPalette(
    tint: Color(0xFF0A0F1A),
    tintOpacity: .52,
    edge: Color(0x24FFFFFF),
    primaryText: Color(0xFFE2E8F0),
    secondaryText: Color(0xBFE2E8F0),
    textShadow:
        Shadow(color: Color(0x9903070F), blurRadius: 3, offset: Offset(0, 1)),
  );

  static const custom = AmbientPalette(
    tint: Color(0xFF14222C),
    tintOpacity: .40,
    edge: Color(0x38FFFFFF),
    primaryText: Color(0xFFF5F7F6),
    secondaryText: Color(0xCEF5F7F6),
    textShadow:
        Shadow(color: Color(0x99070F18), blurRadius: 4, offset: Offset(0, 1)),
  );

  static AmbientPalette forScene(int sceneIndex) => switch (sceneIndex) {
        1 => dusk,
        2 => night,
        0 || 3 => daylight,
        _ => custom,
      };

  /// 用户自定义字体颜色覆盖：替换前景文字两色，阴影按文字亮度自适应
  ///（浅色文字配深阴影、深色文字配浅光晕，避免黑字配黑影更看不清）。
  AmbientPalette withFontColor(Color primary, Color secondary) {
    final dark = primary.computeLuminance() < 0.5;
    return AmbientPalette(
      tint: tint,
      tintOpacity: tintOpacity,
      edge: edge,
      primaryText: primary,
      secondaryText: secondary,
      textShadow: dark
          ? const Shadow(
              color: Color(0x40FFFFFF), blurRadius: 3, offset: Offset(0, 1))
          : textShadow,
    );
  }
}

class AmbientPaletteScope extends InheritedWidget {
  const AmbientPaletteScope({
    super.key,
    required this.palette,
    required this.enabled,
    this.foregroundOverride,
    required super.child,
  });

  final AmbientPalette palette;
  final bool enabled;

  /// Explicit user selection. Null means the scene's original reading colors.
  final Color? foregroundOverride;

  static AmbientPaletteScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AmbientPaletteScope>();

  @override
  bool updateShouldNotify(AmbientPaletteScope oldWidget) =>
      palette != oldWidget.palette ||
      enabled != oldWidget.enabled ||
      foregroundOverride != oldWidget.foregroundOverride;
}
