import 'package:flutter/material.dart';

import 'app_theme.dart';
import 'ambient_palette.dart';

/// Gives existing form-heavy pages readable ink over a dark ambient scene.
/// It changes presentation only; pages keep their own data and actions.
class AmbientReadingTheme extends StatelessWidget {
  const AmbientReadingTheme({
    super.key,
    required this.enabled,
    required this.child,
  });

  final bool enabled;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!enabled) return child;
    final base = Theme.of(context);
    final selected = AmbientPaletteScope.maybeOf(context)?.foregroundOverride;
    final foreground = selected ?? const Color(0xFFF8F5EE);
    final secondary = foreground.withValues(alpha: .82);
    final scheme = base.colorScheme.copyWith(
      brightness: Brightness.dark,
      primary: AppColors.actionFill,
      onPrimary: AppColors.actionInk,
      primaryContainer: const Color(0xFF46515A),
      onPrimaryContainer: foreground,
      surface: const Color(0xFF202B33),
      onSurface: foreground,
      onSurfaceVariant: secondary,
      outline: foreground.withValues(alpha: .52),
      outlineVariant: foreground.withValues(alpha: .18),
      surfaceContainerHighest: const Color(0xFF34404A),
    );
    return Theme(
      data: base.copyWith(
        colorScheme: scheme,
        iconTheme: IconThemeData(color: foreground),
        canvasColor: Colors.transparent,
        dividerColor: foreground.withValues(alpha: .18),
        textTheme: base.textTheme.apply(
          bodyColor: foreground,
          displayColor: foreground,
        ),
        inputDecorationTheme: base.inputDecorationTheme.copyWith(
          fillColor: const Color(0xFF1B2730).withValues(alpha: .44),
          hintStyle: TextStyle(color: secondary),
          labelStyle: TextStyle(color: secondary),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: foreground.withValues(alpha: .28)),
          ),
        ),
        popupMenuTheme: base.popupMenuTheme.copyWith(
          color: const Color(0xF234404A),
          surfaceTintColor: Colors.transparent,
          textStyle: base.textTheme.bodyMedium?.copyWith(color: foreground),
        ),
        // 环境模式下弹窗改深墨蓝底 + 浅字：否则纸色对话框配浅米白文字不可读
        dialogTheme: base.dialogTheme.copyWith(
          backgroundColor: const Color(0xF21B2730),
          surfaceTintColor: Colors.transparent,
          titleTextStyle: base.textTheme.titleLarge
              ?.copyWith(color: foreground, fontWeight: FontWeight.w600),
          contentTextStyle: base.textTheme.bodyMedium
              ?.copyWith(color: foreground, height: 1.5),
        ),
      ),
      child: child,
    );
  }
}
