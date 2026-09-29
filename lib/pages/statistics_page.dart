import 'package:flutter/material.dart';
import 'package:flutter_heatmap_calendar/flutter_heatmap_calendar.dart';
import 'package:intl/intl.dart';
import '../services/isar_service.dart';
import '../services/focus_analytics_service.dart';
import '../services/training_service.dart';
import '../services/expense_service.dart';
import 'expense_page.dart' show formatCents;
import '../models/todo_item.dart';
import '../ui/app_theme.dart';
import '../ui/ambient_palette.dart';
import '../ui/glass_panel.dart';
import '../ui/window_class.dart';
import 'focus_insights_page.dart';

class StatisticsPage extends StatefulWidget {
  const StatisticsPage({
    super.key,
    this.darkBackground = false,
    this.onOpenToday,
  });

  final bool darkBackground;
  final VoidCallback? onOpenToday;

  @override
  State<StatisticsPage> createState() => _StatisticsPageState();
}

class _StatisticsPageState extends State<StatisticsPage> {
  final IsarService _db = IsarService.instance;
  List<DateStatistics> _weekStats = [];
  DateStatistics? _selectedDateStats;
  DateStatistics? _todayStats;
  bool _dateExpanded = false;
  List<TodoItem> _selectedDateTodos = [];
  int _currentStreak = 0;
  DateTime _focusedMonth = DateTime.now();
  bool _isLoading = true;

  // 今日专注统计（独立指标，不与完成率混合）
  int _focusMinutes = 0;

  // 本周训练次数（独立指标）
  int _weekWorkouts = 0;
  int _monthExpenseCents = 0;

  // 坚持足迹热力图：每日完成条数
  Map<DateTime, int> _heatmapData = {};

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);

    final now = DateTime.now();
    final weekStats = await _db.getRecentStatistics(7);
    final streak = await _db.getCurrentStreak();
    final todayStats = await _db.getStatisticsForDate(now);
    final todayTodos = await _db.getTodayTodos();
    final focusStats = await FocusAnalyticsService.forDay(now);
    final weekWorkouts =
        await TrainingService.instance.workoutCountThisWeek(now);
    final monthExpenses = await ExpenseService.instance.getForMonth(now);
    final monthExpenseCents = ExpenseService.summarize(monthExpenses).netCents;
    final heatmapData = await _db.getDailyCompletionCounts(days: 140);

    setState(() {
      _weekStats = weekStats;
      _selectedDateStats = todayStats;
      _todayStats = todayStats;
      _selectedDateTodos = todayTodos;
      _currentStreak = streak;
      _focusedMonth = now;
      _focusMinutes = focusStats.totalSeconds ~/ 60;
      _weekWorkouts = weekWorkouts;
      _monthExpenseCents = monthExpenseCents;
      _heatmapData = heatmapData;
      _isLoading = false;
    });
  }

  Future<void> _selectDate(DateTime date) async {
    final stats = await _db.getStatisticsForDate(date);
    // 修复：使用 getTodosForDate 而不是 getTodosByDate
    // getTodosForDate 会正确处理每日习惯的历史完成状态
    final todos = await _db.getTodosForDate(date);

    setState(() {
      _selectedDateStats = stats;
      _selectedDateTodos = todos;
      _dateExpanded = true;
    });
  }

  void _previousMonth() {
    setState(() {
      _focusedMonth = DateTime(_focusedMonth.year, _focusedMonth.month - 1);
      _dateExpanded = false;
    });
  }

  void _nextMonth() {
    setState(() {
      _focusedMonth = DateTime(_focusedMonth.year, _focusedMonth.month + 1);
      _dateExpanded = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primary = widget.darkBackground
        ? AmbientPaletteScope.maybeOf(context)?.palette.primaryText ??
            Colors.white
        : AppColors.ink;
    final secondary = widget.darkBackground
        ? AmbientPaletteScope.maybeOf(context)?.palette.secondaryText ??
            Colors.white.withValues(alpha: .82)
        : AppColors.muted;
    if (_isLoading) return const Center(child: CircularProgressIndicator());
    final metrics = <({String label, String value, Color color})>[];
    if ((_todayStats?.total ?? 0) > 0) {
      metrics.add((
        label: '今日完成',
        value: '${_todayStats!.completed}/${_todayStats!.total}',
        color: AppColors.forest
      ));
    }
    if (_currentStreak > 0) {
      metrics.add(
          (label: '连续打卡', value: '$_currentStreak 天', color: AppColors.forest));
    }
    if (_focusMinutes > 0) {
      metrics.add((
        label: '今日投入 · 专注与训练',
        value: '$_focusMinutes 分钟',
        color: AppColors.clay
      ));
    }
    if (_weekWorkouts > 0) {
      metrics.add(
          (label: '本周训练', value: '$_weekWorkouts 次', color: AppColors.olive));
    }
    if (_monthExpenseCents != 0) {
      metrics.add((
        label: '本月净支出',
        value: formatCents(_monthExpenseCents),
        color: AppColors.ink
      ));
    }
    final narrow = MediaQuery.sizeOf(context).width < 680;
    return LayoutBuilder(builder: (context, bounds) {
      final twoColumn = bounds.maxWidth >= WindowSizeClass.twoColumnMinWidth;
      return ListView(
        padding:
            EdgeInsets.fromLTRB(narrow ? 18 : 32, 28, narrow ? 18 : 32, 42),
        children: [
          Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: twoColumn ? 1120 : 780),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  twoColumn
                      ? _reviewTwoColumn(
                          theme, primary, secondary, metrics, narrow)
                      : _reviewSingleColumn(
                          theme, primary, secondary, metrics, narrow),
                  const SizedBox(height: 36),
                  _reviewHeatmapSection(theme, primary, secondary),
                ],
              ),
            ),
          ),
        ],
      );
    });
  }

  Widget _reviewHeading(ThemeData theme, Color primary, Color secondary) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('学习回顾',
          style: theme.textTheme.headlineMedium?.copyWith(color: primary)),
      TextButton.icon(
        onPressed: () => Navigator.push(context,
            MaterialPageRoute(builder: (_) => const FocusInsightsPage())),
        icon: const Icon(Icons.pie_chart_outline, size: 18),
        label: const Text('查看今日时间分布'),
        style: TextButton.styleFrom(foregroundColor: primary),
      ),
      const SizedBox(height: 4),
      Text('看见最近的节奏，再决定下一步。',
          style: theme.textTheme.bodyMedium?.copyWith(color: secondary)),
    ]);
  }

  Widget _reviewMetrics(ThemeData theme, Color primary, Color secondary,
      List<({String label, String value, Color color})> metrics,
      {int maxMetrics = 3}) {
    if (metrics.isEmpty) {
      return GlassPanel(
        level: widget.darkBackground
            ? GlassSurfaceLevel.dark
            : GlassSurfaceLevel.light,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.insights_outlined, size: 28, color: primary),
              const SizedBox(height: 10),
              Text('完成一件事，进展会从这里开始。',
                  style: theme.textTheme.titleSmall?.copyWith(color: primary)),
              const SizedBox(height: 4),
              Text('先写下一件今天想做的事。',
                  style: theme.textTheme.bodySmall?.copyWith(color: secondary)),
              if (widget.onOpenToday != null) ...[
                const SizedBox(height: 6),
                TextButton.icon(
                  onPressed: widget.onOpenToday,
                  icon: const Icon(Icons.arrow_forward, size: 16),
                  label: const Text('回到今天'),
                  style: TextButton.styleFrom(foregroundColor: primary),
                ),
              ],
            ],
          ),
        ),
      );
    }
    return LayoutBuilder(builder: (context, constraints) {
      final columns = constraints.maxWidth < 560 ? 2 : 3;
      final cellWidth = (constraints.maxWidth - (columns - 1) * 20) / columns;
      return GlassPanel(
        level: widget.darkBackground
            ? GlassSurfaceLevel.dark
            : GlassSurfaceLevel.light,
        opacity: widget.darkBackground ? .52 : .56,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Wrap(spacing: 20, runSpacing: 18, children: [
            for (final metric in metrics.take(maxMetrics))
              SizedBox(
                  width: cellWidth,
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(metric.label,
                            style: theme.textTheme.bodySmall
                                ?.copyWith(color: secondary)),
                        const SizedBox(height: 4),
                        Text(metric.value,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.headlineSmall?.copyWith(
                                color: widget.darkBackground
                                    ? Colors.white
                                    : metric.color,
                                fontWeight: FontWeight.w700)),
                      ])),
          ]),
        ),
      );
    });
  }

  /// [tall] 为 true 时柱体加大，供宽屏双列使用。
  Widget _reviewWeekSection(ThemeData theme, Color primary, bool tall) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('最近七天',
          style: theme.textTheme.titleMedium?.copyWith(color: primary)),
      const SizedBox(height: 9),
      GlassPanel(
        level: widget.darkBackground
            ? GlassSurfaceLevel.dark
            : GlassSurfaceLevel.light,
        opacity: widget.darkBackground ? .52 : .56,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 14, 12, 12),
          child: _WeekView(
              stats: _weekStats,
              onDateTap: _selectDate,
              darkBackground: widget.darkBackground,
              selectedDate: _dateExpanded ? _selectedDateStats?.date : null,
              barMaxHeight: tall ? 76 : 34,
              barWidth: tall ? 24 : 18),
        ),
      ),
    ]);
  }

  Widget _reviewCalendarSection(ThemeData theme, Color primary, bool narrow) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('日期回顾',
          style: theme.textTheme.titleMedium?.copyWith(color: primary)),
      const SizedBox(height: 12),
      SizedBox(
          height: narrow ? 300 : 340,
          child: _MonthCalendar(
            focusedMonth: _focusedMonth,
            onDateTap: _selectDate,
            onPreviousMonth: _previousMonth,
            onNextMonth: _nextMonth,
            darkBackground: widget.darkBackground,
            selectedDate: _dateExpanded ? _selectedDateStats?.date : null,
          )),
      if (_dateExpanded && _selectedDateStats != null) ...[
        const SizedBox(height: 16),
        _MobileDayDetail(
            stats: _selectedDateStats!,
            todos: _selectedDateTodos,
            onTodoToggle: (id) async {
              await _db.toggleTodo(id, _selectedDateStats!.date);
              _selectDate(_selectedDateStats!.date);
            },
            onTodoDelete: (id) async {
              await _db.deleteTodo(id);
              _selectDate(_selectedDateStats!.date);
            }),
      ],
    ]);
  }

  Widget _reviewSingleColumn(ThemeData theme, Color primary, Color secondary,
      List<({String label, String value, Color color})> metrics, bool narrow) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _reviewHeading(theme, primary, secondary),
      const SizedBox(height: 24),
      _reviewMetrics(theme, primary, secondary, metrics),
      const SizedBox(height: 30),
      _reviewWeekSection(theme, primary, false),
      const SizedBox(height: 26),
      _reviewCalendarSection(theme, primary, narrow),
    ]);
  }

  Widget _reviewTwoColumn(ThemeData theme, Color primary, Color secondary,
      List<({String label, String value, Color color})> metrics, bool narrow) {
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Expanded(
        flex: 5,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _reviewHeading(theme, primary, secondary),
          const SizedBox(height: 24),
          _reviewMetrics(theme, primary, secondary, metrics, maxMetrics: 5),
          const SizedBox(height: 34),
          _reviewWeekSection(theme, primary, true),
        ]),
      ),
      const SizedBox(width: 40),
      Expanded(
        flex: 4,
        child: _reviewCalendarSection(theme, primary, narrow),
      ),
    ]);
  }

  /// 坚持足迹：GitHub 风格的每日完成热力图（最近 20 周）
  Widget _reviewHeatmapSection(
      ThemeData theme, Color primary, Color secondary) {
    final today = DateTime.now();
    final end = DateTime(today.year, today.month, today.day);
    final start = end.subtract(const Duration(days: 20 * 7 - 1));
    final dark = widget.darkBackground;
    final colorsets = <int, Color>{
      1: dark
          ? AppColors.actionFill.withValues(alpha: .30)
          : AppColors.forest.withValues(alpha: .22),
      2: dark
          ? AppColors.actionFill.withValues(alpha: .52)
          : AppColors.forest.withValues(alpha: .42),
      3: dark
          ? AppColors.actionFill.withValues(alpha: .74)
          : AppColors.forest.withValues(alpha: .66),
      4: dark ? AppColors.actionFill : AppColors.forest,
    };
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('坚持足迹',
          style: theme.textTheme.titleMedium?.copyWith(color: primary)),
      const SizedBox(height: 4),
      Text('每天完成的事项数，格子越满越亮。',
          style: theme.textTheme.bodySmall?.copyWith(color: secondary)),
      const SizedBox(height: 16),
      GlassPanel(
        level: dark ? GlassSurfaceLevel.dark : GlassSurfaceLevel.light,
        opacity: dark ? .52 : .56,
        child: Padding(
          padding: const EdgeInsets.all(12),
          // 横铺整个面板：按可用宽度反算格子尺寸（20 周 + 星期标签列）
          child: LayoutBuilder(builder: (context, bounds) {
            final weeks = 20;
            final labelWidth = 34.0;
            final usable = bounds.maxWidth - 24 - labelWidth;
            final cell = ((usable / weeks) - 4).clamp(9.0, 20.0);
            return Center(
              child: HeatMap(
                startDate: start,
                endDate: end,
                datasets: _heatmapData,
                defaultColor: dark
                    ? Colors.white.withValues(alpha: .17)
                    : AppColors.line.withValues(alpha: .45),
                textColor: dark
                    ? Colors.white.withValues(alpha: .88)
                    : AppColors.muted,
                size: cell,
                fontSize: 9,
                showText: false,
                showColorTip: false,
                scrollable: false,
                margin: const EdgeInsets.all(2),
                colorsets: colorsets,
                borderRadius: 4,
              ),
            );
          }),
        ),
      ),
    ]);
  }
}

class _WeekView extends StatelessWidget {
  final List<DateStatistics> stats;
  final Function(DateTime) onDateTap;
  final DateTime? selectedDate;
  final bool darkBackground;
  final double barMaxHeight;
  final double barWidth;

  const _WeekView(
      {required this.stats,
      required this.onDateTap,
      required this.darkBackground,
      this.selectedDate,
      this.barMaxHeight = 34,
      this.barWidth = 18});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(children: [
      for (final stat in stats)
        Expanded(
            child: InkWell(
          onTap: () => onDateTap(stat.date),
          borderRadius: BorderRadius.circular(8),
          child: Column(children: [
            Text(DateFormat('E', 'zh_CN').format(stat.date),
                style: theme.textTheme.labelSmall?.copyWith(
                    color: darkBackground
                        ? Colors.white.withValues(alpha: .78)
                        : AppColors.muted)),
            const SizedBox(height: 8),
            SizedBox(
                height: barMaxHeight,
                child: Align(
                    alignment: Alignment.bottomCenter,
                    child: Container(
                      width: barWidth,
                      height: stat.total == 0
                          ? 3
                          : 4 + (barMaxHeight - 4) * stat.completionRate,
                      decoration: BoxDecoration(
                          color: stat.total == 0
                              ? (darkBackground
                                  ? Colors.white.withValues(alpha: .36)
                                  : AppColors.line)
                              : (darkBackground
                                  ? AppColors.actionFill
                                  : AppColors.forest),
                          borderRadius: BorderRadius.circular(4)),
                    ))),
            const SizedBox(height: 5),
            Text('${stat.date.day}',
                style: theme.textTheme.bodySmall?.copyWith(
                    color: selectedDate != null &&
                            selectedDate!.year == stat.date.year &&
                            selectedDate!.month == stat.date.month &&
                            selectedDate!.day == stat.date.day
                        ? (darkBackground
                            ? AppColors.actionFill
                            : AppColors.forest)
                        : (darkBackground
                            ? Colors.white.withValues(alpha: .78)
                            : AppColors.muted),
                    fontWeight: FontWeight.w600)),
          ]),
        )),
    ]);
  }
}

// 月历组件 - 响应式设计，适配手机和桌面
class _MonthCalendar extends StatelessWidget {
  final DateTime focusedMonth;
  final Function(DateTime) onDateTap;
  final VoidCallback onPreviousMonth;
  final VoidCallback onNextMonth;
  final DateTime? selectedDate;
  final bool darkBackground;

  const _MonthCalendar({
    required this.focusedMonth,
    required this.onDateTap,
    required this.onPreviousMonth,
    required this.onNextMonth,
    required this.darkBackground,
    this.selectedDate,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final now = DateTime.now();

    // 获取月份天数
    final firstDayOfMonth = DateTime(focusedMonth.year, focusedMonth.month, 1);
    final lastDayOfMonth =
        DateTime(focusedMonth.year, focusedMonth.month + 1, 0);
    final startWeekday = firstDayOfMonth.weekday - 1; // Monday = 0

    // 计算所有日期（包括占位）
    final allDates = <DateTime?>[];
    for (int i = 0; i < startWeekday; i++) {
      allDates.add(null); // 空白占位
    }
    for (int day = 1; day <= lastDayOfMonth.day; day++) {
      allDates.add(DateTime(focusedMonth.year, focusedMonth.month, day));
    }
    // 补齐最后一行
    while (allDates.length % 7 != 0) {
      allDates.add(null);
    }
    final rowCount = allDates.length ~/ 7;

    return GlassPanel(
      level: darkBackground ? GlassSurfaceLevel.dark : GlassSurfaceLevel.light,
      opacity: darkBackground ? .52 : .56,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 月份切换
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                IconButton(
                  icon: Icon(Icons.chevron_left,
                      size: 24, color: darkBackground ? Colors.white : null),
                  onPressed: onPreviousMonth,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
                Text(
                  '${focusedMonth.year}年${focusedMonth.month}月',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: darkBackground ? Colors.white : null,
                  ),
                ),
                IconButton(
                  icon: Icon(Icons.chevron_right,
                      size: 24, color: darkBackground ? Colors.white : null),
                  onPressed: onNextMonth,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ],
            ),
            const SizedBox(height: 8),
            // 星期标题
            Row(
              children: ['一', '二', '三', '四', '五', '六', '日'].map((day) {
                return Expanded(
                  child: Center(
                    child: Text(
                      day,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: darkBackground
                            ? Colors.white.withValues(alpha: .76)
                            : theme.colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 8),
            // 日期网格 - 使用 Table 布局确保均匀分布
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final cellWidth = constraints.maxWidth / 7;
                  final cellHeight = (constraints.maxHeight - 4) / rowCount;
                  final cellSize =
                      cellWidth < cellHeight ? cellWidth : cellHeight;

                  return Column(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: List.generate(rowCount, (rowIndex) {
                      return Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: List.generate(7, (colIndex) {
                          final index = rowIndex * 7 + colIndex;
                          final date = allDates[index];

                          if (date == null) {
                            return SizedBox(width: cellSize, height: cellSize);
                          }

                          final isToday = date.year == now.year &&
                              date.month == now.month &&
                              date.day == now.day;
                          final isSelected = selectedDate != null &&
                              date.year == selectedDate!.year &&
                              date.month == selectedDate!.month &&
                              date.day == selectedDate!.day;

                          return GestureDetector(
                            onTap: () => onDateTap(date),
                            child: Container(
                              width: cellSize,
                              height: cellSize,
                              decoration: BoxDecoration(
                                color: isSelected
                                    ? (darkBackground
                                        ? AppColors.actionFill
                                        : theme.colorScheme.primary)
                                    : isToday
                                        ? (darkBackground
                                            ? Colors.white
                                                .withValues(alpha: .16)
                                            : theme
                                                .colorScheme.primaryContainer)
                                        : Colors.transparent,
                                borderRadius:
                                    BorderRadius.circular(cellSize / 4),
                                border: isSelected
                                    ? null
                                    : Border.all(
                                        color: isToday
                                            ? theme.colorScheme.primary
                                                .withValues(alpha: 0.5)
                                            : Colors.transparent,
                                        width: 1.5,
                                      ),
                              ),
                              child: Center(
                                child: FittedBox(
                                  fit: BoxFit.scaleDown,
                                  child: Padding(
                                    padding: const EdgeInsets.all(4),
                                    child: Text(
                                      '${date.day}',
                                      style: TextStyle(
                                        fontSize: 14,
                                        color: isSelected
                                            ? (darkBackground
                                                ? AppColors.ink
                                                : theme.colorScheme.onPrimary)
                                            : isToday
                                                ? (darkBackground
                                                    ? Colors.white
                                                    : theme.colorScheme.primary)
                                                : (darkBackground
                                                    ? Colors.white
                                                    : theme
                                                        .colorScheme.onSurface),
                                        fontWeight: isToday || isSelected
                                            ? FontWeight.bold
                                            : FontWeight.normal,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          );
                        }),
                      );
                    }),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// 手机端简化版当日详情
class _MobileDayDetail extends StatelessWidget {
  final DateStatistics stats;
  final List<TodoItem> todos;
  final Function(int) onTodoToggle;
  final Function(int) onTodoDelete;

  const _MobileDayDetail({
    required this.stats,
    required this.todos,
    required this.onTodoToggle,
    required this.onTodoDelete,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // 标题行
          Row(
            children: [
              Expanded(
                child: Text(
                  DateFormat('MM月dd日 EEEE', 'zh_CN').format(stats.date),
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              // 完成率
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.forestSoft,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '${stats.completed}/${stats.total} (${(stats.completionRate * 100).toInt()}%)',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: AppColors.forest,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),

          if (todos.isEmpty) ...[
            const SizedBox(height: 16),
            Center(
              child: Text(
                '当日无任务',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ] else ...[
            const SizedBox(height: 8),
            // 任务列表
            ...todos.map((todo) => _MobileTodoItem(
                  todo: todo,
                  canToggle: _canToggle(todo),
                  onToggle: () => onTodoToggle(todo.id),
                  onDelete: () => onTodoDelete(todo.id),
                )),
          ],
        ],
      ),
    );
  }

  // 与桌面端一致：历史日期的每日习惯禁用切换
  bool _canToggle(TodoItem todo) {
    if (!todo.taskType.isRecurring) return true;
    final now = DateTime.now();
    final date = stats.date;
    return date.year == now.year &&
        date.month == now.month &&
        date.day == now.day;
  }
}

// 手机端任务列表项
class _MobileTodoItem extends StatelessWidget {
  final TodoItem todo;
  final bool canToggle;
  final VoidCallback onToggle;
  final VoidCallback onDelete;

  const _MobileTodoItem({
    required this.todo,
    required this.canToggle,
    required this.onToggle,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return GestureDetector(
      onTap: canToggle ? onToggle : null,
      onLongPress: onDelete,
      child: Container(
        margin: const EdgeInsets.only(top: 6),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: todo.isCompleted
              ? theme.colorScheme.primaryContainer.withValues(alpha: 0.3)
              : theme.colorScheme.surfaceContainerHighest
                  .withValues(alpha: 0.3),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            Icon(
              todo.isCompleted ? Icons.check_circle : Icons.circle_outlined,
              size: 18,
              color: todo.isCompleted
                  ? theme.colorScheme.primary
                  : theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                todo.title,
                style: theme.textTheme.bodySmall?.copyWith(
                  decoration:
                      todo.isCompleted ? TextDecoration.lineThrough : null,
                  color: todo.isCompleted
                      ? theme.colorScheme.onSurfaceVariant
                          .withValues(alpha: 0.6)
                      : theme.colorScheme.onSurface,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
