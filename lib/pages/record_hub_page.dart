import 'package:flutter/material.dart';

import '../ui/app_theme.dart';
import '../ui/ambient_palette.dart';
import '../ui/glass_panel.dart';

/// Direct access to records. Monthly totals live on the separate summary page.
class RecordHubPage extends StatelessWidget {
  const RecordHubPage({
    super.key,
    required this.darkBackground,
    required this.onOpenMemo,
    required this.onOpenFitness,
    required this.onOpenDiet,
    required this.onOpenExpense,
    required this.onOpenSummary,
  });

  final bool darkBackground;
  final VoidCallback onOpenMemo;
  final VoidCallback onOpenFitness;
  final VoidCallback onOpenDiet;
  final VoidCallback onOpenExpense;
  final VoidCallback onOpenSummary;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = AmbientPaletteScope.maybeOf(context)?.palette;
    final primary =
        darkBackground ? palette?.primaryText ?? Colors.white : AppColors.ink;
    final secondary = darkBackground
        ? palette?.secondaryText ?? Colors.white.withValues(alpha: .76)
        : AppColors.muted;
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 28, 20, 40),
      children: [
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('你的生活', style: AppType.overline(color: secondary)),
                const SizedBox(height: 7),
                Text('记下来', style: AppType.display(size: 36, color: primary)),
                const SizedBox(height: 7),
                Text('想法、训练、饮食和花销，都从这里进入。',
                    style:
                        theme.textTheme.bodyMedium?.copyWith(color: secondary)),
                const SizedBox(height: 26),
                GlassPanel(
                  level: darkBackground
                      ? GlassSurfaceLevel.dark
                      : GlassSurfaceLevel.solid,
                  opacity: .62,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Column(children: [
                      _item(context, Icons.edit_note_outlined, '备忘录', '写下想法与资料',
                          onOpenMemo),
                      _divider(),
                      _item(context, Icons.fitness_center_outlined, '健身',
                          '训练循环与完成记录', onOpenFitness),
                      _divider(),
                      _item(context, Icons.restaurant_outlined, '饮食',
                          '按餐次记下吃了什么', onOpenDiet),
                      _divider(),
                      _item(context, Icons.receipt_long_outlined, '消费记录',
                          '记录支出与收入', onOpenExpense),
                    ]),
                  ),
                ),
                const SizedBox(height: 20),
                GlassPanel(
                  level: darkBackground
                      ? GlassSurfaceLevel.dark
                      : GlassSurfaceLevel.light,
                  opacity: .47,
                  child: _item(context, Icons.auto_graph_outlined, '生活总结',
                      '回看本月的时间与生活节奏', onOpenSummary),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _divider() => Divider(
        height: 1,
        color: darkBackground
            ? Colors.white.withValues(alpha: .14)
            : AppColors.line.withValues(alpha: .65),
      );

  Widget _item(BuildContext context, IconData icon, String title,
      String subtitle, VoidCallback onTap) {
    final theme = Theme.of(context);
    final palette = AmbientPaletteScope.maybeOf(context)?.palette;
    final primary =
        darkBackground ? palette?.primaryText ?? Colors.white : AppColors.ink;
    final secondary = darkBackground
        ? palette?.secondaryText ?? Colors.white.withValues(alpha: .75)
        : AppColors.muted;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 17),
          child: Row(children: [
            Icon(icon, size: 22, color: primary),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: theme.textTheme.titleMedium
                          ?.copyWith(color: primary)),
                  const SizedBox(height: 3),
                  Text(subtitle,
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: secondary)),
                ],
              ),
            ),
            Icon(Icons.chevron_right, size: 19, color: secondary),
          ]),
        ),
      ),
    );
  }
}
