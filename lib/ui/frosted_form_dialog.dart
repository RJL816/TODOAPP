import 'package:flutter/material.dart';

import 'app_theme.dart';
import 'glass_panel.dart';

/// A bounded glass surface for forms shown over an ambient scene.
/// The backdrop filter stays inside the dialog instead of blurring the route.
class FrostedDialogSurface extends StatelessWidget {
  const FrostedDialogSurface({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).colorScheme.brightness == Brightness.dark;
    if (!dark) return Dialog(child: child);
    final theme = Theme.of(context);
    return Dialog(
      elevation: 0,
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
      child: Theme(
        data: theme.copyWith(
          inputDecorationTheme: theme.inputDecorationTheme.copyWith(
            filled: true,
            fillColor: const Color(0xFF172B36).withValues(alpha: .55),
            labelStyle: const TextStyle(color: Color(0xFFF1F4F2)),
            floatingLabelStyle: const TextStyle(color: AppColors.actionFill),
            hintStyle: TextStyle(color: Colors.white.withValues(alpha: .70)),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide:
                  BorderSide(color: Colors.white.withValues(alpha: .28)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide:
                  const BorderSide(color: AppColors.actionFill, width: 1.5),
            ),
          ),
          textSelectionTheme: const TextSelectionThemeData(
            cursorColor: AppColors.actionFill,
            selectionHandleColor: AppColors.actionFill,
          ),
        ),
        child: GlassPanel(
          level: GlassSurfaceLevel.dark,
          radius: 24,
          opacity: .78,
          blur: 10,
          shadow: true,
          child: child,
        ),
      ),
    );
  }
}

class FrostedFormDialog extends StatelessWidget {
  const FrostedFormDialog({
    super.key,
    required this.title,
    required this.content,
    required this.actions,
    this.maxWidth = 460,
  });

  final Widget title;
  final Widget content;
  final List<Widget> actions;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    if (Theme.of(context).colorScheme.brightness != Brightness.dark) {
      return AlertDialog(title: title, content: content, actions: actions);
    }
    final availableHeight = MediaQuery.sizeOf(context).height -
        MediaQuery.viewInsetsOf(context).bottom -
        40;
    return FrostedDialogSurface(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: maxWidth,
          maxHeight: availableHeight.clamp(220, double.infinity),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 21, 20, 14),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              DefaultTextStyle.merge(
                style: const TextStyle(
                  color: Color(0xFFF8F5EE),
                  fontSize: 21,
                  fontWeight: FontWeight.w600,
                ),
                child: title,
              ),
              const SizedBox(height: 18),
              Flexible(child: content),
              const SizedBox(height: 14),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  for (final action in actions) ...[
                    action,
                    const SizedBox(width: 6),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
