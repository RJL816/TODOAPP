import 'dart:ui';

import 'package:flutter/material.dart';

import 'app_theme.dart';
import 'ambient_palette.dart';

/// Layered frosted glass, implemented with Flutter filters and painted light.
/// 材质分层：
///  - light  浅玻璃（输入 / 轻信息）：高透光，暗面提亮
///  - solid  半实玻璃（内容承载）：足够遮蔽，长文本可读
///  - dark   深色玻璃（强调 / 沉浸）：深墨蓝底、暖光反射、照片透出
/// 光照语言：顶边 specular 高光更亮，顶左角环境反射，底部带极弱暖光回弹。
/// Surface levels retain their existing foreground contract (light ink / white).
enum GlassSurfaceLevel { light, solid, dark }

/// One appearance control for glass surfaces across all routes.
/// A higher value keeps more of the scene's detail visible behind the panel.
abstract final class GlassTuning {
  static const defaultClarity = .55;
  static final ValueNotifier<double> clarity = ValueNotifier(defaultClarity);

  static double tintScale(double value) =>
      lerpDouble(1.12, .30, value.clamp(0.0, 1.0))!;

  static double blurScale(double value) =>
      lerpDouble(1.15, .20, value.clamp(0.0, 1.0))!;
}

class GlassPanel extends StatelessWidget {
  const GlassPanel({
    super.key,
    required this.child,
    this.level = GlassSurfaceLevel.light,
    this.radius = 24,
    this.blur,
    this.opacity,
    this.shadow = false,
  });

  final Widget child;
  final GlassSurfaceLevel level;
  final double radius;
  final double? blur;
  final double? opacity;
  final bool shadow;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<double>(
        valueListenable: GlassTuning.clarity,
        builder: (context, clarity, _) => _buildPanel(context, clarity),
      );

  Widget _buildPanel(BuildContext context, double clarity) {
    final sceneScope = AmbientPaletteScope.maybeOf(context);
    final scene = sceneScope?.enabled == true ? sceneScope!.palette : null;
    final isDark = level == GlassSurfaceLevel.dark ||
        Theme.of(context).brightness == Brightness.dark;
    final thinGlass = level == GlassSurfaceLevel.dark;
    final strength = (opacity ??
            switch (level) {
              GlassSurfaceLevel.light => .42,
              GlassSurfaceLevel.solid => .70,
              GlassSurfaceLevel.dark => .56,
            })
        .clamp(0.0, 1.0);
    final requestedBlur = (blur ??
            switch (level) {
              GlassSurfaceLevel.light => 12.0,
              GlassSurfaceLevel.solid => 16.0,
              GlassSurfaceLevel.dark => 9.0,
            })
        .clamp(0.0, 22.0)
        .toDouble();
    // Keep the scene visible through local glass; reading surfaces retain ink contrast.
    final softness =
        (thinGlass ? requestedBlur.clamp(0.0, 9.0) : requestedBlur) *
            GlassTuning.blurScale(clarity);
    final baseTint = thinGlass
        ? strength * .44
        : level == GlassSurfaceLevel.light
            ? strength * .72
            : strength * .88;
    final tint = scene != null && isDark
        ? (scene.tintOpacity *
                strength /
                .56 *
                GlassTuning.tintScale(clarity) /
                GlassTuning.tintScale(GlassTuning.defaultClarity))
            .clamp(0.0, .76)
        : baseTint * GlassTuning.tintScale(clarity);

    // 三段对角渐变：深玻璃走 墨蓝（冷天光）→ 暗底；浅玻璃走 暖白纸 → 米色底。
    final List<Color> gradient;
    if (scene != null && isDark) {
      gradient = [
        Color.lerp(scene.tint, Colors.white, .07)!.withValues(alpha: tint),
        scene.tint.withValues(alpha: tint * .97),
        Color.lerp(scene.tint, Colors.black, .12)!
            .withValues(alpha: tint * .93),
      ];
    } else if (isDark) {
      gradient = [
        const Color(0xFF233947).withValues(alpha: tint),
        const Color(0xFF172D3A).withValues(alpha: tint * .96),
        const Color(0xFF10212E).withValues(alpha: tint * .90),
      ];
    } else {
      gradient = [
        const Color(0xFFFCFBF8).withValues(alpha: tint),
        const Color(0xFFF5F2EB).withValues(alpha: tint * .96),
        const Color(0xFFEDE9DF).withValues(alpha: tint * .92),
      ];
    }
    final edge = scene != null && isDark
        ? scene.edge
        : Colors.white.withValues(alpha: isDark ? .30 : .48);
    final highlight = Colors.white.withValues(
        alpha: scene == AmbientPalette.night ? .34 : (isDark ? .56 : .70));
    final reduceEffects =
        MediaQuery.maybeOf(context)?.accessibleNavigation ?? false;
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        boxShadow: shadow
            ? [
                // 环境影 + 贴合影两层，营造悬浮景深
                BoxShadow(
                  color: AppColors.ink.withValues(alpha: isDark ? .18 : .12),
                  blurRadius: 34,
                  offset: const Offset(0, 13),
                ),
                BoxShadow(
                  color: AppColors.ink.withValues(alpha: isDark ? .10 : .07),
                  blurRadius: 9,
                  offset: const Offset(0, 3),
                ),
              ]
            : null,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: BackdropFilter(
          enabled: !reduceEffects,
          filter: ImageFilter.blur(sigmaX: softness, sigmaY: softness),
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(radius),
              border: Border.all(color: edge),
              gradient: reduceEffects
                  ? LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: isDark
                          ? [
                              const Color(0xFF25313B),
                              const Color(0xFF1B242D),
                            ]
                          : [
                              const Color(0xFFF0F3F0),
                              const Color(0xFFE5EBE7),
                            ],
                    )
                  : LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      stops: const [0, .52, 1],
                      colors: gradient,
                    ),
            ),
            child: Stack(
              fit: StackFit.passthrough,
              children: [
                // 环境反射：顶左角一束极弱的天光
                if (!reduceEffects)
                  Positioned.fill(
                    child: IgnorePointer(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: RadialGradient(
                            center: const Alignment(-.9, -1.1),
                            radius: 1.15,
                            colors: [
                              Colors.white
                                  .withValues(alpha: isDark ? .085 : .13),
                              Colors.white.withValues(alpha: 0),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                // 深玻璃底缘的暖光回弹（室内灯光打在玻璃下沿）
                if (isDark && !reduceEffects)
                  Positioned.fill(
                    child: IgnorePointer(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: RadialGradient(
                            center: const Alignment(.85, 1.25),
                            radius: 1.05,
                            colors: [
                              AppColors.warmAmber.withValues(alpha: .05),
                              Colors.transparent,
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                child,
                // 内侧发丝描边，压住渐变的边
                Positioned.fill(
                  child: IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(radius),
                        border: Border.all(
                          color:
                              highlight.withValues(alpha: isDark ? .14 : .24),
                          strokeAlign: BorderSide.strokeAlignInside,
                        ),
                      ),
                    ),
                  ),
                ),
                // 顶部 specular 高光：整宽渐隐，上缘更亮
                Positioned(
                  top: 0,
                  left: radius * .45,
                  right: radius * .45,
                  height: 1.2,
                  child: IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            highlight.withValues(alpha: .05),
                            highlight.withValues(alpha: isDark ? .60 : .72),
                            highlight.withValues(alpha: .05),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
