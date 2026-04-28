import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../services/isar_service.dart';
import '../models/todo_item.dart';

class StatisticsPage extends StatefulWidget {
  const StatisticsPage({super.key});

  @override
  State<StatisticsPage> createState() => _StatisticsPageState();
}

class _StatisticsPageState extends State<StatisticsPage> {
  final IsarService _db = IsarService.instance;
  List<DateStatistics> _weekStats = [];
  DateStatistics? _selectedDateStats;
  List<TodoItem> _selectedDateTodos = [];
  int _currentStreak = 0;
  DateTime _focusedMonth = DateTime.now();
  bool _isLoading = true;

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

    setState(() {
      _weekStats = weekStats;
      _selectedDateStats = todayStats;
      _selectedDateTodos = todayTodos;
      _currentStreak = streak;
      _focusedMonth = now;
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
    });
  }

  void _previousMonth() {
    setState(() {
      _focusedMonth = DateTime(_focusedMonth.year, _focusedMonth.month - 1);
    });
  }

  void _nextMonth() {
    setState(() {
      _focusedMonth = DateTime(_focusedMonth.year, _focusedMonth.month + 1);
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    return Container(
      color: theme.colorScheme.surface.withOpacity(0.5),
      child: Column(
        children: [
          // 统计概览卡片
          Container(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Expanded(
                  child: _StreakCard(streak: _currentStreak),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _CompletionCard(
                    completed: _selectedDateStats?.completed ?? 0,
                    total: _selectedDateStats?.total ?? 0,
                    rate: _selectedDateStats?.completionRate ?? 0.0,
                  ),
                ),
              ],
            ),
          ),

          // 周视图
          _WeekView(
            stats: _weekStats,
            onDateTap: _selectDate,
            selectedDate: _selectedDateStats?.date,
          ),

          // 月历和详情 - 响应式布局
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  // 手机端（窄屏）使用垂直布局，桌面端使用水平布局
                  final isNarrow = constraints.maxWidth < 500;
                  
                  if (isNarrow) {
                    // 手机端：可滚动的垂直布局
                    return SingleChildScrollView(
                      child: Column(
                        children: [
                          // 月历 - 紧凑版
                          SizedBox(
                            height: 240,
                            child: _MonthCalendar(
                              focusedMonth: _focusedMonth,
                              onDateTap: _selectDate,
                              onPreviousMonth: _previousMonth,
                              onNextMonth: _nextMonth,
                              selectedDate: _selectedDateStats?.date,
                            ),
                          ),
                          const SizedBox(height: 12),
                          // 当日任务详情 - 手机端简化版
                          if (_selectedDateStats != null)
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
                              },
                            )
                          else
                            const Padding(
                              padding: EdgeInsets.all(20),
                              child: Text('选择日期查看详情'),
                            ),
                        ],
                      ),
                    );
                  } else {
                    // 桌面端：左右布局
                    return Row(
                      children: [
                        // 月历
                        Flexible(
                          flex: 2,
                          child: _MonthCalendar(
                            focusedMonth: _focusedMonth,
                            onDateTap: _selectDate,
                            onPreviousMonth: _previousMonth,
                            onNextMonth: _nextMonth,
                            selectedDate: _selectedDateStats?.date,
                          ),
                        ),
                        const SizedBox(width: 16),
                        // 当日任务详情
                        Expanded(
                          flex: 3,
                          child: _selectedDateStats == null
                              ? const Center(child: Text('选择日期查看详情'))
                              : _DayDetailCard(
                                  stats: _selectedDateStats!,
                                  todos: _selectedDateTodos,
                                  onTodoToggle: (id) async {
                                    await _db.toggleTodo(id, _selectedDateStats!.date);
                                    _selectDate(_selectedDateStats!.date);
                                  },
                                  onTodoDelete: (id) async {
                                    await _db.deleteTodo(id);
                                    _selectDate(_selectedDateStats!.date);
                                  },
                                ),
                        ),
                      ],
                    );
                  }
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// 连续打卡卡片
class _StreakCard extends StatelessWidget {
  final int streak;

  const _StreakCard({required this.streak});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.orange[400]!, Colors.orange[600]!],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.orange.withOpacity(0.3),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.local_fire_department, color: Colors.white, size: 20),
              const SizedBox(width: 8),
              Text(
                '连续打卡',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: Colors.white70,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            '$streak',
            style: theme.textTheme.headlineMedium?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.bold,
            ),
          ),
          Text(
            '天',
            style: theme.textTheme.bodySmall?.copyWith(
              color: Colors.white70,
            ),
          ),
        ],
      ),
    );
  }
}

// 完成率卡片
class _CompletionCard extends StatelessWidget {
  final int completed;
  final int total;
  final double rate;

  const _CompletionCard({
    required this.completed,
    required this.total,
    required this.rate,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final percentage = (rate * 100).toStringAsFixed(0);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withOpacity(0.3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.task_alt,
                color: theme.colorScheme.primary,
                size: 20,
              ),
              const SizedBox(width: 8),
              Text(
                '今日完成',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                percentage,
                style: theme.textTheme.headlineSmall?.copyWith(
                  color: theme.colorScheme.primary,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(width: 4),
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(
                  '%',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              const Spacer(),
              Text('$completed/$total',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: rate,
              backgroundColor: theme.colorScheme.surfaceContainerHighest,
              valueColor: AlwaysStoppedAnimation<Color>(theme.colorScheme.primary),
              minHeight: 6,
            ),
          ),
        ],
      ),
    );
  }
}

// 周视图
class _WeekView extends StatelessWidget {
  final List<DateStatistics> stats;
  final Function(DateTime) onDateTap;
  final DateTime? selectedDate;

  const _WeekView({
    required this.stats,
    required this.onDateTap,
    this.selectedDate,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final now = DateTime.now();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: stats.map((stat) {
          final isToday = stat.date.year == now.year &&
              stat.date.month == now.month &&
              stat.date.day == now.day;
          final isSelected = selectedDate != null &&
              stat.date.year == selectedDate!.year &&
              stat.date.month == selectedDate!.month &&
              stat.date.day == selectedDate!.day;

          return Expanded(
            child: GestureDetector(
              onTap: () => onDateTap(stat.date),
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 4),
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  color: isSelected
                      ? theme.colorScheme.primary
                      : isToday
                          ? theme.colorScheme.primaryContainer.withOpacity(0.5)
                          : theme.colorScheme.surface,
                  borderRadius: BorderRadius.circular(12),
                  border: isSelected
                      ? null
                      : Border.all(
                          color: theme.colorScheme.outlineVariant.withOpacity(0.3),
                        ),
                  boxShadow: isSelected
                      ? [
                          BoxShadow(
                            color: theme.colorScheme.primary.withOpacity(0.3),
                            blurRadius: 8,
                            offset: const Offset(0, 4),
                          ),
                        ]
                      : null,
                ),
                child: Column(
                  children: [
                    Text(
                      DateFormat('E', 'zh_CN').format(stat.date),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: isSelected
                            ? theme.colorScheme.onPrimary
                            : theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${stat.date.day}',
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: isSelected
                            ? theme.colorScheme.onPrimary
                            : theme.colorScheme.onSurface,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 6),
                    if (stat.total > 0)
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: stat.completionRate >= 1.0
                              ? Colors.green
                              : Colors.grey,
                          shape: BoxShape.circle,
                        ),
                      )
                    else
                      Container(
                        width: 6,
                        height: 6,
                        decoration: BoxDecoration(
                          color: Colors.grey[300],
                          shape: BoxShape.circle,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

// 月历组件 - 响应式设计，适配手机和桌面
class _MonthCalendar extends StatelessWidget {
  final DateTime focusedMonth;
  final Function(DateTime) onDateTap;
  final VoidCallback onPreviousMonth;
  final VoidCallback onNextMonth;
  final DateTime? selectedDate;

  const _MonthCalendar({
    required this.focusedMonth,
    required this.onDateTap,
    required this.onPreviousMonth,
    required this.onNextMonth,
    this.selectedDate,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final now = DateTime.now();

    // 获取月份天数
    final firstDayOfMonth = DateTime(focusedMonth.year, focusedMonth.month, 1);
    final lastDayOfMonth = DateTime(focusedMonth.year, focusedMonth.month + 1, 0);
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

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withOpacity(0.3),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 月份切换
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              IconButton(
                icon: const Icon(Icons.chevron_left, size: 24),
                onPressed: onPreviousMonth,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
              Text(
                '${focusedMonth.year}年${focusedMonth.month}月',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.chevron_right, size: 24),
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
                      color: theme.colorScheme.onSurfaceVariant,
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
                final cellSize = cellWidth < cellHeight ? cellWidth : cellHeight;
                
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
                                  ? theme.colorScheme.primary
                                  : isToday
                                      ? theme.colorScheme.primaryContainer
                                      : Colors.transparent,
                              borderRadius: BorderRadius.circular(cellSize / 4),
                              border: isSelected
                                  ? null
                                  : Border.all(
                                      color: isToday
                                          ? theme.colorScheme.primary.withOpacity(0.5)
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
                                          ? theme.colorScheme.onPrimary
                                          : isToday
                                              ? theme.colorScheme.primary
                                              : theme.colorScheme.onSurface,
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
          color: theme.colorScheme.outlineVariant.withOpacity(0.3),
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
                  color: stats.completionRate >= 0.8
                      ? Colors.green.withOpacity(0.15)
                      : stats.completionRate >= 0.5
                          ? Colors.orange.withOpacity(0.15)
                          : Colors.red.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '${stats.completed}/${stats.total} (${(stats.completionRate * 100).toInt()}%)',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: stats.completionRate >= 0.8
                        ? Colors.green[700]
                        : stats.completionRate >= 0.5
                            ? Colors.orange[700]
                            : Colors.red[700],
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
              onToggle: () => onTodoToggle(todo.id),
              onDelete: () => onTodoDelete(todo.id),
            )),
          ],
        ],
      ),
    );
  }
}

// 手机端任务列表项
class _MobileTodoItem extends StatelessWidget {
  final TodoItem todo;
  final VoidCallback onToggle;
  final VoidCallback onDelete;

  const _MobileTodoItem({
    required this.todo,
    required this.onToggle,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return GestureDetector(
      onTap: onToggle,
      onLongPress: onDelete,
      child: Container(
        margin: const EdgeInsets.only(top: 6),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: todo.isCompleted
              ? theme.colorScheme.primaryContainer.withOpacity(0.3)
              : theme.colorScheme.surfaceContainerHighest.withOpacity(0.3),
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
                  decoration: todo.isCompleted ? TextDecoration.lineThrough : null,
                  color: todo.isCompleted
                      ? theme.colorScheme.onSurfaceVariant.withOpacity(0.6)
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

// 当日详情卡片
class _DayDetailCard extends StatefulWidget {
  final DateStatistics stats;
  final List<TodoItem> todos;
  final Function(int) onTodoToggle;
  final Function(int) onTodoDelete;

  const _DayDetailCard({
    required this.stats,
    required this.todos,
    required this.onTodoToggle,
    required this.onTodoDelete,
  });

  @override
  State<_DayDetailCard> createState() => _DayDetailCardState();
}

class _DayDetailCardState extends State<_DayDetailCard> {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.all(16),
      child: Card(
        elevation: 0,
        color: theme.colorScheme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(
            color: theme.colorScheme.outlineVariant.withOpacity(0.3),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 标题栏
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          DateFormat('yyyy年MM月dd日 EEEE', 'zh_CN').format(widget.stats.date),
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '共 ${widget.stats.total} 个任务',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  // 完成率徽章
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: widget.stats.completionRate >= 1.0
                          ? Colors.green[100]
                          : widget.stats.completionRate >= 0.5
                              ? Colors.blue[100]
                              : Colors.orange[100],
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      '${(widget.stats.completionRate * 100).toStringAsFixed(0)}%',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: widget.stats.completionRate >= 1.0
                            ? Colors.green[800]
                            : widget.stats.completionRate >= 0.5
                                ? Colors.blue[800]
                                : Colors.orange[800],
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            // 任务列表
            Expanded(
              child: widget.todos.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.task_alt_outlined,
                            size: 48,
                            color: theme.colorScheme.outlineVariant,
                          ),
                          const SizedBox(height: 12),
                          Text(
                            '这一天没有任务',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: widget.todos.length,
                      itemBuilder: (context, index) {
                        final todo = widget.todos[index];
                        return _TodoListItem(
                          todo: todo,
                          onToggle: () => widget.onTodoToggle(todo.id),
                          onDelete: () => widget.onTodoDelete(todo.id),
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

// 任务列表项
class _TodoListItem extends StatelessWidget {
  final TodoItem todo;
  final VoidCallback onToggle;
  final VoidCallback onDelete;

  const _TodoListItem({
    required this.todo,
    required this.onToggle,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: todo.isCompleted
            ? theme.colorScheme.primaryContainer.withOpacity(0.3)
            : theme.colorScheme.surfaceContainerHighest.withOpacity(0.3),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: todo.isCompleted
              ? theme.colorScheme.primary.withOpacity(0.3)
              : Colors.transparent,
        ),
      ),
      child: Row(
        children: [
          Checkbox(
            value: todo.isCompleted,
            onChanged: (_) => onToggle(),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(6),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              todo.title,
              style: theme.textTheme.bodyMedium?.copyWith(
                decoration:
                    todo.isCompleted ? TextDecoration.lineThrough : null,
                color: todo.isCompleted
                    ? theme.colorScheme.onSurfaceVariant.withOpacity(0.6)
                    : theme.colorScheme.onSurface,
              ),
            ),
          ),
          IconButton(
            icon: Icon(
              Icons.delete_outline,
              color: theme.colorScheme.error.withOpacity(0.7),
              size: 20,
            ),
            onPressed: onDelete,
            tooltip: '删除',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
        ],
      ),
    );
  }
}
