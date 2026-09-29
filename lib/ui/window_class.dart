import 'package:flutter/widgets.dart';

/// Shared window-size classes (Material canonical breakpoints), measured on
/// the width available to the page content (inside the desktop nav).
///
/// Pages should prefer reading these from a `LayoutBuilder` over inventing
/// local magic numbers; the shell-level nav thresholds (960/1180) stay in
/// main.dart on purpose — they describe window chrome, not content layout.
enum WindowSizeClass {
  /// < 600 — phones and the narrowest desktop windows.
  compact,

  /// 600–839 — small tablets / half-screen desktop windows.
  medium,

  /// 840–1199 — full desktop panes.
  expanded,

  /// ≥ 1200 — maximized / large monitors.
  large;

  static WindowSizeClass of(double width) {
    if (width < 600) return WindowSizeClass.compact;
    if (width < 840) return WindowSizeClass.medium;
    if (width < 1200) return WindowSizeClass.expanded;
    return WindowSizeClass.large;
  }

  static WindowSizeClass ofContext(BuildContext context) =>
      of(MediaQuery.sizeOf(context).width);

  /// Minimum content width for a page to split into two columns. Chosen so
  /// each column keeps ≥ ~440px of readable width plus a 28px gutter.
  static const double twoColumnMinWidth = 1000;
}
