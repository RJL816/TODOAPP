import 'dart:io';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import '../services/focus_analytics_service.dart';
import '../ui/ambient_backdrop.dart';
import '../ui/app_theme.dart';
import '../ui/glass_panel.dart';

const _insightWhite = Color(0xFFF7F8F6);
const _focusAccent = Color(0xFF92BBC2);
const _workoutAccent = Color(0xFFD2AD9B);
const _sceneShadow = [
  Shadow(color: Color(0x99172731), blurRadius: 12),
];

class FocusInsightsPage extends StatefulWidget {
  const FocusInsightsPage({super.key});
  @override
  State<FocusInsightsPage> createState() => _FocusInsightsPageState();
}

class _FocusInsightsPageState extends State<FocusInsightsPage> {
  DateTime _day = DateTime.now();
  late Future<FocusDayStats> _stats = FocusAnalyticsService.forDay(_day);

  void _move(int days) {
    final next = _day.add(Duration(days: days));
    if (DateTime(next.year, next.month, next.day).isAfter(DateTime.now())) {
      return;
    }
    setState(() {
      _day = next;
      _stats = FocusAnalyticsService.forDay(_day);
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBodyBehindAppBar: true,
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(kToolbarHeight),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onPanStart:
              Platform.isWindows ? (_) => windowManager.startDragging() : null,
          child: AppBar(
            title: const Text('专注时间'),
            foregroundColor: _insightWhite,
            backgroundColor: Colors.transparent,
            surfaceTintColor: Colors.transparent,
            scrolledUnderElevation: 0,
            elevation: 0,
            titleTextStyle: theme.textTheme.titleMedium?.copyWith(
              color: _insightWhite,
              fontWeight: FontWeight.w600,
            ),
            flexibleSpace: ClipRect(
              child: BackdropFilter(
                filter: ImageFilter.blur(
                  sigmaX: 7 * GlassTuning.blurScale(GlassTuning.clarity.value),
                  sigmaY: 7 * GlassTuning.blurScale(GlassTuning.clarity.value),
                ),
                child: ColoredBox(
                  color: const Color(0xFF172B36).withValues(alpha: .34),
                ),
              ),
            ),
          ),
        ),
      ),
      body: Stack(
        children: [
          const Positioned.fill(child: AmbientBackdrop()),
          FutureBuilder<FocusDayStats>(
              future: _stats,
              builder: (context, snapshot) {
                final stats = snapshot.data;
                return ListView(
                    // 顶部始终让出 AppBar 区域：宽窗口下日期切换按钮
                    // 若伸进 AppBar 会被其不透明的窗口拖拽手势层挡住
                    padding: EdgeInsets.fromLTRB(
                        22,
                        MediaQuery.paddingOf(context).top +
                            kToolbarHeight +
                            20,
                        22,
                        24),
                    children: [
                      Center(
                          child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 850),
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(children: [
                                IconButton(
                                    onPressed: () => _move(-1),
                                    icon: const Icon(Icons.chevron_left,
                                        color: _insightWhite)),
                                Text('${_day.month}月${_day.day}日',
                                    style: theme.textTheme.titleMedium
                                        ?.copyWith(
                                            color: _insightWhite,
                                            shadows: _sceneShadow)),
                                IconButton(
                                    onPressed: () => _move(1),
                                    icon: const Icon(Icons.chevron_right,
                                        color: _insightWhite)),
                                const Spacer(),
                                Text('今天的时间分布',
                                    style: theme.textTheme.bodySmall?.copyWith(
                                        color: _insightWhite.withValues(
                                            alpha: .76),
                                        shadows: _sceneShadow)),
                              ]),
                              const SizedBox(height: 15),
                              Text('时间，花在了哪里',
                                  style: AppType.display(
                                          size: 34, color: _insightWhite)
                                      .copyWith(shadows: _sceneShadow)),
                              const SizedBox(height: 8),
                              Text('专注与训练共用一条时间线；重叠时间只计算一次。',
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                      color:
                                          _insightWhite.withValues(alpha: .84),
                                      shadows: _sceneShadow)),
                              const SizedBox(height: 30),
                              if (snapshot.hasError)
                                const Text('暂时无法读取今天的记录',
                                    style: TextStyle(color: _insightWhite))
                              else if (stats == null)
                                const Center(
                                    child: CircularProgressIndicator(
                                        color: _focusAccent))
                              else if (stats.totalSeconds == 0)
                                Padding(
                                    padding: const EdgeInsets.symmetric(
                                        vertical: 65),
                                    child: Column(children: [
                                      const Icon(Icons.hourglass_empty_rounded,
                                          size: 38, color: _focusAccent),
                                      const SizedBox(height: 15),
                                      Text('今天还没有完成的专注或训练',
                                          style: theme.textTheme.titleMedium
                                              ?.copyWith(color: _insightWhite)),
                                      const SizedBox(height: 6),
                                      Text('结束一次专注或保存一次训练后，这里会出现时间分布。',
                                          style: theme.textTheme.bodySmall
                                              ?.copyWith(
                                                  color: _insightWhite
                                                      .withValues(alpha: .76))),
                                    ]))
                              else ...[
                                GlassPanel(
                                  level: GlassSurfaceLevel.dark,
                                  opacity: .58,
                                  child: Padding(
                                    padding: const EdgeInsets.all(20),
                                    child: LayoutBuilder(
                                        builder: (context, bounds) {
                                      final wide = bounds.maxWidth >= 650;
                                      final chartWidth =
                                          math.min(310.0, bounds.maxWidth);
                                      final chart = SizedBox(
                                        width: chartWidth,
                                        child: Column(children: [
                                          CustomPaint(
                                              size: Size(
                                                  chartWidth, chartWidth * .84),
                                              painter: _DepthPiePainter(
                                                  stats.slices)),
                                          const SizedBox(height: 5),
                                          Text('总投入',
                                              style: theme.textTheme.bodySmall
                                                  ?.copyWith(
                                                      color: _insightWhite
                                                          .withValues(
                                                              alpha: .72))),
                                          Text(_duration(stats.totalSeconds),
                                              style: AppType.display(
                                                  size: 30,
                                                  color: _insightWhite)),
                                        ]),
                                      );
                                      final details = Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            _number(
                                                theme,
                                                '专注',
                                                stats.focusSeconds,
                                                _focusAccent),
                                            const SizedBox(height: 18),
                                            _number(
                                                theme,
                                                '训练',
                                                stats.workoutSeconds,
                                                _workoutAccent),
                                            const SizedBox(height: 28),
                                            Text('事项分布',
                                                style: theme
                                                    .textTheme.titleMedium
                                                    ?.copyWith(
                                                        color: _insightWhite)),
                                            const SizedBox(height: 12),
                                            for (var i = 0;
                                                i < stats.slices.length;
                                                i++)
                                              Padding(
                                                  padding:
                                                      const EdgeInsets.only(
                                                          bottom: 12),
                                                  child: Row(children: [
                                                    Container(
                                                        width: 10,
                                                        height: 10,
                                                        decoration: BoxDecoration(
                                                            color: _pieColor(
                                                                i,
                                                                stats.slices[i]
                                                                    .isWorkout),
                                                            shape: BoxShape
                                                                .circle)),
                                                    const SizedBox(width: 11),
                                                    Expanded(
                                                        child: Text(
                                                            stats.slices[i]
                                                                .title,
                                                            maxLines: 1,
                                                            overflow:
                                                                TextOverflow
                                                                    .ellipsis,
                                                            style: theme
                                                                .textTheme
                                                                .bodyMedium
                                                                ?.copyWith(
                                                                    color:
                                                                        _insightWhite))),
                                                    Text(
                                                        _duration(stats
                                                            .slices[i].seconds),
                                                        style: theme.textTheme
                                                            .bodyMedium
                                                            ?.copyWith(
                                                                color:
                                                                    _insightWhite,
                                                                fontWeight:
                                                                    FontWeight
                                                                        .w700)),
                                                  ])),
                                          ]);
                                      return wide
                                          ? Row(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.center,
                                              children: [
                                                  chart,
                                                  const SizedBox(width: 44),
                                                  Expanded(child: details),
                                                ])
                                          : Column(children: [
                                              chart,
                                              const SizedBox(height: 24),
                                              details
                                            ]);
                                    }),
                                  ),
                                ),
                                const SizedBox(height: 32),
                                Text('训练时间按开始和结束时间计算。旧版训练记录没有结束时间，仍保留在历史中。',
                                    style: theme.textTheme.bodySmall?.copyWith(
                                        color: _insightWhite.withValues(
                                            alpha: .72),
                                        shadows: _sceneShadow)),
                              ],
                            ]),
                      )),
                    ]);
              }),
        ],
      ),
    );
  }

  Widget _number(ThemeData theme, String label, int seconds, Color color) =>
      Row(children: [
        Container(width: 3, height: 36, color: color),
        const SizedBox(width: 13),
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: _insightWhite.withValues(alpha: .74))),
          Text(_duration(seconds),
              style: AppType.display(size: 26, color: _insightWhite)),
        ]),
      ]);
}

String _duration(int seconds) {
  if (seconds < 60) return '$seconds 秒';
  final minutes = seconds ~/ 60;
  return minutes >= 60
      ? '${minutes ~/ 60} 小时 ${minutes % 60} 分'
      : '$minutes 分钟';
}

Color _pieColor(int index, bool workout) {
  const focusColors = [
    Color(0xFF8DBBC2),
    Color(0xFFADC8C3),
    Color(0xFF8FA9BE),
    Color(0xFFB2B5C9),
  ];
  const workoutColors = [
    Color(0xFFC99F8C),
    Color(0xFFD5B6A7),
    Color(0xFFB38D85),
  ];
  return workout
      ? workoutColors[index % workoutColors.length]
      : focusColors[index % focusColors.length];
}

class _DepthPiePainter extends CustomPainter {
  final List<FocusSlice> slices;
  _DepthPiePainter(this.slices);

  @override
  void paint(Canvas canvas, Size size) {
    final total = slices.fold<int>(0, (sum, s) => sum + s.seconds);
    if (total == 0) return;
    final center = Offset(size.width / 2, size.height / 2 - 6);
    final radius = math.min(size.width, size.height) * .34;
    final thickness = radius * .43;
    final rect = Rect.fromCircle(center: center, radius: radius);
    canvas.drawOval(
      Rect.fromCenter(
          center: center.translate(0, radius + 15),
          width: radius * 2.1,
          height: radius * .42),
      Paint()
        ..color = AppColors.ink.withValues(alpha: .20)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 15),
    );
    var angle = -math.pi / 2;
    for (var i = 0; i < slices.length; i++) {
      final sweep = slices[i].seconds / total * math.pi * 2;
      final color = _pieColor(i, slices[i].isWorkout);
      final gap = slices.length == 1 ? 0.0 : math.min(.025, sweep * .16);
      final start = angle + gap / 2;
      final visibleSweep = sweep - gap;
      canvas.drawArc(
        rect.shift(const Offset(0, 7)),
        start,
        visibleSweep,
        false,
        Paint()
          ..color = Color.lerp(color, const Color(0xFF20323B), .43)!
          ..style = PaintingStyle.stroke
          ..strokeWidth = thickness,
      );
      canvas.drawArc(
        rect,
        start,
        visibleSweep,
        false,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color.lerp(color, Colors.white, .24)!,
              color,
              Color.lerp(color, const Color(0xFF24404A), .18)!,
            ],
          ).createShader(rect)
          ..style = PaintingStyle.stroke
          ..strokeWidth = thickness,
      );
      angle += sweep;
    }
    canvas.drawCircle(
      center,
      radius + thickness / 2,
      Paint()
        ..color = Colors.white.withValues(alpha: .28)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
    canvas.drawCircle(
      center,
      radius - thickness / 2,
      Paint()
        ..color = Colors.white.withValues(alpha: .17)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
  }

  @override
  bool shouldRepaint(covariant _DepthPiePainter oldDelegate) =>
      oldDelegate.slices != slices;
}
