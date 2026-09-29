import 'package:flutter/material.dart';
import 'package:isar/isar.dart';

import '../models/diet_log.dart';
import '../models/pomodoro_session.dart';
import '../models/todo_item.dart';
import '../models/training.dart';
import '../services/expense_service.dart';
import '../services/isar_service.dart';
import '../services/focus_analytics_service.dart';
import '../services/memo_service.dart';
import '../ui/app_theme.dart';
import '../ui/ambient_palette.dart';
import '../ui/glass_panel.dart';
import 'expense_page.dart' show formatCents;

/// 轨迹：这个月的生活节奏 + 最近发生的事 + 工具入口。
class MorePage extends StatefulWidget {
  final VoidCallback onOpenMemo;
  final VoidCallback onOpenPomodoro;
  final VoidCallback onOpenFitness;
  final VoidCallback onOpenDiet;
  final VoidCallback onOpenExpense;
  final bool darkBackground;
  final bool summaryOnly;

  const MorePage({
    super.key,
    required this.onOpenMemo,
    required this.onOpenPomodoro,
    required this.onOpenFitness,
    required this.onOpenDiet,
    required this.onOpenExpense,
    this.darkBackground = false,
    this.summaryOnly = false,
  });

  @override
  State<MorePage> createState() => _MorePageState();
}

class _MorePageState extends State<MorePage> {
  Color get _ambientPrimary =>
      AmbientPaletteScope.maybeOf(context)?.palette.primaryText ?? Colors.white;
  Color get _ambientSecondary =>
      AmbientPaletteScope.maybeOf(context)?.palette.secondaryText ??
      Colors.white.withValues(alpha: .78);

  late final Future<_TraceBrief> _brief = _load();

  Future<_TraceBrief> _load() async {
    final now = DateTime.now();
    final monthStart = DateTime(now.year, now.month);
    final monthEnd = DateTime(now.year, now.month + 1);
    final isar = IsarService.instance.isar;

    var focusSeconds = 0;
    var monthSessions = <PomodoroSession>[];
    var monthWorkouts = <WorkoutLog>[];
    final activeDays = <DateTime>{};
    final recent = <_TraceEvent>[];

    try {
      final sessions = await isar.pomodoroSessions
          .filter()
          .startedAtBetween(monthStart, monthEnd,
              includeLower: true, includeUpper: false)
          .completedEqualTo(true)
          .typeEqualTo(PomodoroPhaseType.focus)
          .findAll();
      monthSessions = sessions;
      for (final s in sessions) {
        activeDays.add(
            DateTime(s.startedAt.year, s.startedAt.month, s.startedAt.day));
        recent.add(_TraceEvent(
            s.startedAt, _TraceKind.focus, '专注 ${s.durationSeconds ~/ 60} 分钟'));
      }
    } catch (_) {}

    var workoutCount = 0;
    try {
      final logs = await isar.workoutLogs
          .filter()
          .dateBetween(monthStart, monthEnd,
              includeLower: true, includeUpper: false)
          .completedEqualTo(true)
          .findAll();
      monthWorkouts = logs;
      workoutCount = logs.length;
      for (final log in logs) {
        activeDays.add(DateTime(
            log.startedAt.year, log.startedAt.month, log.startedAt.day));
        recent.add(_TraceEvent(
            log.startedAt, _TraceKind.workout, '完成训练 ${log.title}'));
      }
    } catch (_) {}

    for (var day = monthStart;
        day.isBefore(monthEnd);
        day = day.add(const Duration(days: 1))) {
      focusSeconds +=
          FocusAnalyticsService.fromRecords(day, monthSessions, monthWorkouts)
              .totalSeconds;
    }

    var dietDays = 0;
    try {
      final logs = await isar.dietLogs
          .filter()
          .dateBetween(monthStart, monthEnd,
              includeLower: true, includeUpper: false)
          .findAll();
      final days = logs
          .map((log) => DateTime(log.date.year, log.date.month, log.date.day))
          .toSet();
      dietDays = days.length;
      activeDays.addAll(days);
    } catch (_) {}

    var netCents = 0;
    try {
      final items = await ExpenseService.instance.getForMonth(now);
      final summary = ExpenseService.summarize(items);
      netCents = summary.netCents;
      for (final item in items) {
        activeDays
            .add(DateTime(item.date.year, item.date.month, item.date.day));
        recent.add(_TraceEvent(
            DateTime(item.date.year, item.date.month, item.date.day, 12),
            _TraceKind.expense,
            '${item.counterparty.isNotEmpty ? item.counterparty : item.category} '
            '${formatCents(item.amountCents)}'));
      }
    } catch (_) {}

    try {
      final todos = await isar.todoItems
          .filter()
          .isCompletedEqualTo(true)
          .completedAtBetween(monthStart, monthEnd,
              includeLower: true, includeUpper: false)
          .findAll();
      for (final todo in todos) {
        final at = todo.completedAt!;
        activeDays.add(DateTime(at.year, at.month, at.day));
        recent.add(_TraceEvent(at, _TraceKind.task, '完成 ${todo.title}'));
      }
    } catch (_) {}

    String? memoRecent;
    try {
      final memos = await MemoService.instance.getAllMemos();
      if (memos.isNotEmpty) {
        final title = memos.first.title.trim();
        memoRecent = title.isEmpty || title == '新备忘录' || title == '无标题'
            ? '一篇未命名笔记'
            : title;
      }
    } catch (_) {}

    recent.sort((a, b) => b.at.compareTo(a.at));
    return _TraceBrief(
      month: monthStart,
      focusMinutes: focusSeconds ~/ 60,
      workoutCount: workoutCount,
      dietDays: dietDays,
      netCents: netCents,
      activeDays: activeDays,
      recent: recent.take(14).toList(),
      memoRecent: memoRecent,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    const monthNames = [
      '',
      '一月',
      '二月',
      '三月',
      '四月',
      '五月',
      '六月',
      '七月',
      '八月',
      '九月',
      '十月',
      '十一月',
      '十二月'
    ];
    return FutureBuilder<_TraceBrief>(
      future: _brief,
      builder: (context, snapshot) {
        final brief = snapshot.data;
        return LayoutBuilder(builder: (context, constraints) {
          final side = constraints.maxWidth < 680 ? 20.0 : 36.0;
          return ListView(
            padding: EdgeInsets.fromLTRB(side, 32, side, 44),
            children: [
              Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 760),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // 月度大字
                      if (brief != null) ...[
                        Text(
                            '${widget.summaryOnly ? '生活总结' : '生活记录'}  /  ${brief.month.year}',
                            style: AppType.overline(
                                color: widget.darkBackground
                                    ? _ambientSecondary
                                    : AppColors.muted)),
                        const SizedBox(height: 6),
                        Text(monthNames[brief.month.month],
                            style: AppType.display(
                                size: 40,
                                weight: FontWeight.w600,
                                color: widget.darkBackground
                                    ? _ambientPrimary
                                    : AppColors.ink)),
                        const SizedBox(height: 26),
                        _monthNumbers(theme, brief),
                        const SizedBox(height: 30),
                        _rhythmGrid(theme, brief),
                        if (brief.activeDays.isEmpty &&
                            brief.focusMinutes == 0 &&
                            brief.workoutCount == 0 &&
                            brief.dietDays == 0 &&
                            brief.netCents == 0) ...[
                          const SizedBox(height: 18),
                          GlassPanel(
                            level: widget.darkBackground
                                ? GlassSurfaceLevel.dark
                                : GlassSurfaceLevel.light,
                            child: Padding(
                              padding: const EdgeInsets.all(20),
                              child: Row(children: [
                                Icon(Icons.draw_outlined,
                                    size: 28,
                                    color: widget.darkBackground
                                        ? _ambientPrimary
                                        : AppColors.ink),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text('这个月还没有可统计的记录',
                                          style: theme.textTheme.titleSmall
                                              ?.copyWith(
                                                  color: widget.darkBackground
                                                      ? _ambientPrimary
                                                      : AppColors.ink)),
                                      const SizedBox(height: 4),
                                      Text('记录一笔，日历和总结就会留下第一处痕迹。',
                                          style: theme.textTheme.bodySmall
                                              ?.copyWith(
                                                  color: widget.darkBackground
                                                      ? _ambientSecondary
                                                      : AppColors.muted)),
                                    ],
                                  ),
                                ),
                                TextButton(
                                  onPressed: widget.onOpenExpense,
                                  style: TextButton.styleFrom(
                                      foregroundColor: widget.darkBackground
                                          ? _ambientPrimary
                                          : AppColors.navy),
                                  child: const Text('去记录第一笔'),
                                ),
                              ]),
                            ),
                          ),
                        ],
                        const SizedBox(height: 34),
                      ],
                      // 最近
                      if (!widget.summaryOnly &&
                          brief != null &&
                          brief.recent.isNotEmpty) ...[
                        Text('最近',
                            style: AppType.display(
                                size: 22,
                                weight: FontWeight.w600,
                                color: widget.darkBackground
                                    ? _ambientPrimary
                                    : AppColors.ink)),
                        const SizedBox(height: 14),
                        GlassPanel(
                          level: widget.darkBackground
                              ? GlassSurfaceLevel.dark
                              : GlassSurfaceLevel.solid,
                          opacity: widget.darkBackground ? .48 : .69,
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(20, 10, 20, 18),
                            child: _recentList(theme, brief.recent),
                          ),
                        ),
                        const SizedBox(height: 34),
                      ],
                      // 工具入口
                      if (!widget.summaryOnly)
                        Text('工具',
                            style: AppType.display(
                                size: 22,
                                weight: FontWeight.w600,
                                color: widget.darkBackground
                                    ? _ambientPrimary
                                    : AppColors.ink)),
                      if (!widget.summaryOnly) const SizedBox(height: 10),
                      if (!widget.summaryOnly)
                        GlassPanel(
                          level: widget.darkBackground
                              ? GlassSurfaceLevel.dark
                              : GlassSurfaceLevel.light,
                          opacity: .48,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 18),
                            child: Column(children: [
                              _entry(
                                  theme,
                                  Icons.edit_note_outlined,
                                  AppColors.slate,
                                  '备忘录',
                                  brief?.memoRecent ?? '随手记下想法和资料',
                                  widget.onOpenMemo),
                              _entry(
                                  theme,
                                  Icons.timer_outlined,
                                  AppColors.amber,
                                  '番茄钟',
                                  '专注计时与休息节奏',
                                  widget.onOpenPomodoro),
                              _entry(
                                  theme,
                                  Icons.fitness_center_outlined,
                                  AppColors.moss,
                                  '健身',
                                  '计划训练并记录完成情况',
                                  widget.onOpenFitness),
                              _entry(
                                  theme,
                                  Icons.restaurant_outlined,
                                  AppColors.moss,
                                  '饮食',
                                  '按餐次记录每天的饮食',
                                  widget.onOpenDiet),
                              _entry(
                                  theme,
                                  Icons.receipt_long_outlined,
                                  AppColors.navy,
                                  '消费记录',
                                  '记一笔，回看月度支出',
                                  widget.onOpenExpense),
                            ]),
                          ),
                        ),
                    ],
                  ),
                ),
              )
            ],
          );
        });
      },
    );
  }

  Widget _monthNumbers(ThemeData theme, _TraceBrief brief) {
    Widget stat(String label, String value) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppType.display(
                    size: 25,
                    weight: FontWeight.w600,
                    color: widget.darkBackground
                        ? _ambientPrimary
                        : AppColors.ink)),
            const SizedBox(height: 5),
            Text(label,
                style: theme.textTheme.labelSmall?.copyWith(
                    color: widget.darkBackground
                        ? _ambientSecondary
                        : AppColors.muted)),
          ],
        );
    final focusText = brief.focusMinutes >= 60
        ? '${brief.focusMinutes ~/ 60}h ${brief.focusMinutes % 60}m'
        : '${brief.focusMinutes}m';
    final values = [
      stat('专注', focusText),
      stat('训练', '${brief.workoutCount} 次'),
      stat('饮食', '${brief.dietDays} 天'),
      stat('支出', formatCents(brief.netCents)),
    ];
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 23),
      child: LayoutBuilder(builder: (context, bounds) {
        final columns = bounds.maxWidth < 500 ? 2 : 4;
        return Wrap(
          runSpacing: 20,
          children: [
            for (final value in values)
              SizedBox(width: bounds.maxWidth / columns, child: value),
          ],
        );
      }),
    );
  }

  /// Compact month calendar: dates carry the activity, not an oversized dot grid.
  Widget _rhythmGrid(ThemeData theme, _TraceBrief brief) {
    final first = DateTime(brief.month.year, brief.month.month, 1);
    final daysInMonth =
        DateTime(brief.month.year, brief.month.month + 1, 0).day;
    final leading = first.weekday - 1;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final activeCount =
        brief.activeDays.where((day) => !day.isAfter(today)).length;
    const weekdays = ['一', '二', '三', '四', '五', '六', '日'];
    final cellCount = ((leading + daysInMonth + 6) ~/ 7) * 7;
    final calendar = ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 354),
      child: Column(children: [
        Row(children: [
          for (final weekday in weekdays)
            Expanded(
              child: Center(
                child: Text(weekday,
                    style: theme.textTheme.labelSmall
                        ?.copyWith(color: _ambientSecondary)),
              ),
            ),
        ]),
        const SizedBox(height: 10),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: cellCount,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 7,
            mainAxisExtent: 39,
            mainAxisSpacing: 3,
          ),
          itemBuilder: (context, index) {
            final day = index - leading + 1;
            if (day < 1 || day > daysInMonth) {
              return const SizedBox.shrink();
            }
            final date = DateTime(first.year, first.month, day);
            final active = brief.activeDays.contains(date);
            final isToday = date == today;
            final future = date.isAfter(today);
            return Center(
              child: Container(
                width: 32,
                height: 32,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: active ? AppColors.actionFill : Colors.transparent,
                  border: isToday
                      ? Border.all(color: AppColors.amber, width: 2)
                      : null,
                ),
                child: Text('$day',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: active
                          ? AppColors.ink
                          : future
                              ? _ambientSecondary.withValues(alpha: .60)
                              : _ambientPrimary,
                      fontWeight:
                          active || isToday ? FontWeight.w700 : FontWeight.w500,
                    )),
              ),
            );
          },
        ),
      ]),
    );
    final insight = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('$activeCount',
            style: AppType.display(
                size: 44, weight: FontWeight.w600, color: _ambientPrimary)),
        const SizedBox(height: 4),
        Text(activeCount == 0 ? '这个月的记录，从今天开始。' : '天留下了生活记录',
            style:
                theme.textTheme.bodyMedium?.copyWith(color: _ambientPrimary)),
        const SizedBox(height: 13),
        Text('专注、训练、餐食、消费和完成的任务，都会点亮对应日期。',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: _ambientSecondary, height: 1.5)),
        const SizedBox(height: 14),
        Text('浅色为有记录的日子 · 琥珀圈是今天',
            style:
                theme.textTheme.labelSmall?.copyWith(color: _ambientSecondary)),
      ],
    );
    return GlassPanel(
      level: GlassSurfaceLevel.dark,
      opacity: .48,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 23, 24, 26),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('本月节奏',
                style:
                    theme.textTheme.titleMedium?.copyWith(color: Colors.white)),
            const SizedBox(height: 19),
            LayoutBuilder(builder: (context, bounds) {
              if (bounds.maxWidth < 620) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [calendar, const SizedBox(height: 19), insight],
                );
              }
              return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    calendar,
                    const SizedBox(width: 42),
                    Expanded(child: insight),
                  ]);
            }),
          ],
        ),
      ),
    );
  }

  Widget _recentList(ThemeData theme, List<_TraceEvent> events) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    String? lastGroup;
    final rows = <Widget>[];
    for (final event in events) {
      final day = DateTime(event.at.year, event.at.month, event.at.day);
      final group = day == today
          ? '今天'
          : (day == yesterday ? '昨天' : '${day.month}月${day.day}日');
      if (group != lastGroup) {
        rows.add(Padding(
          padding: const EdgeInsets.only(top: 12, bottom: 6),
          child: Text(group,
              style: theme.textTheme.labelSmall?.copyWith(
                  color: widget.darkBackground
                      ? _ambientSecondary
                      : AppColors.muted,
                  letterSpacing: 1.2)),
        ));
        lastGroup = group;
      }
      rows.add(Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(children: [
          Text(event.kind.glyph,
              style: TextStyle(
                  color: event.kind.color,
                  fontSize: 13,
                  fontWeight: FontWeight.w700)),
          const SizedBox(width: 10),
          Text(
              '${event.at.hour.toString().padLeft(2, '0')}:${event.at.minute.toString().padLeft(2, '0')}',
              style: theme.textTheme.bodySmall?.copyWith(
                  color: widget.darkBackground
                      ? _ambientSecondary
                      : AppColors.muted,
                  fontFeatures: const [FontFeature.tabularFigures()])),
          const SizedBox(width: 12),
          Expanded(
              child: Text(event.text,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(
                      color: widget.darkBackground ? _ambientPrimary : null))),
        ]),
      ));
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: rows);
  }

  Widget _entry(ThemeData theme, IconData icon, Color color, String title,
          String detail, VoidCallback onTap) =>
      Column(children: [
        Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(10),
            child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Row(children: [
                  Container(
                      width: 38,
                      height: 38,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                          color: color.withValues(alpha: 0.10),
                          borderRadius: BorderRadius.circular(10)),
                      child: Icon(icon, color: color, size: 20)),
                  const SizedBox(width: 14),
                  Expanded(
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                        Text(title,
                            style: theme.textTheme.titleSmall?.copyWith(
                                color: widget.darkBackground
                                    ? _ambientPrimary
                                    : null)),
                        const SizedBox(height: 2),
                        Text(detail,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(
                                color: widget.darkBackground
                                    ? _ambientSecondary
                                    : AppColors.muted)),
                      ])),
                  const Icon(Icons.chevron_right,
                      size: 19, color: Colors.white70),
                ])),
          ),
        ),
        Divider(
            height: 1,
            color: widget.darkBackground
                ? Colors.white.withValues(alpha: .16)
                : AppColors.line),
      ]);
}

class _TraceBrief {
  final DateTime month;
  final int focusMinutes;
  final int workoutCount;
  final int dietDays;
  final int netCents;
  final Set<DateTime> activeDays;
  final List<_TraceEvent> recent;
  final String? memoRecent;

  const _TraceBrief({
    required this.month,
    required this.focusMinutes,
    required this.workoutCount,
    required this.dietDays,
    required this.netCents,
    required this.activeDays,
    required this.recent,
    this.memoRecent,
  });
}

enum _TraceKind { task, focus, workout, expense }

extension _TraceKindStyle on _TraceKind {
  String get glyph {
    switch (this) {
      case _TraceKind.task:
        return '✓';
      case _TraceKind.focus:
        return '●';
      case _TraceKind.workout:
        return '■';
      case _TraceKind.expense:
        return '¥';
    }
  }

  Color get color {
    switch (this) {
      case _TraceKind.task:
        return AppColors.ink;
      case _TraceKind.focus:
        return AppColors.amber;
      case _TraceKind.workout:
        return AppColors.moss;
      case _TraceKind.expense:
        return AppColors.navy;
    }
  }
}

class _TraceEvent {
  final DateTime at;
  final _TraceKind kind;
  final String text;
  const _TraceEvent(this.at, this.kind, this.text);
}
