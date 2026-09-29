import 'package:flutter/material.dart';

import '../models/class_time_config.dart';
import '../models/course.dart';
import '../models/todo_item.dart';
import '../models/training.dart';
import '../services/course_service.dart';
import '../services/isar_service.dart';
import '../services/training_service.dart';
import '../ui/app_theme.dart';
import '../ui/ambient_palette.dart';
import '../ui/glass_panel.dart';
import 'schedule_page.dart';

/// Weekly navigation with one readable day at a time.
class PlanPage extends StatefulWidget {
  const PlanPage({super.key, this.darkBackground = false});

  final bool darkBackground;

  @override
  State<PlanPage> createState() => _PlanPageState();
}

class _PlanPageState extends State<PlanPage> {
  Color get _primary => widget.darkBackground
      ? AmbientPaletteScope.maybeOf(context)?.palette.primaryText ??
          Colors.white
      : AppColors.ink;
  Color get _secondary => widget.darkBackground
      ? AmbientPaletteScope.maybeOf(context)?.palette.secondaryText ??
          Colors.white.withValues(alpha: .82)
      : AppColors.muted;

  ThemeData get _contentTheme {
    final theme = Theme.of(context);
    return widget.darkBackground
        ? theme.copyWith(
            textTheme: theme.textTheme
                .apply(bodyColor: _primary, displayColor: _primary))
        : theme;
  }

  DateTime _monday = _weekStart(DateTime.now());
  int _selectedWeekday = DateTime.now().weekday - 1;
  bool _showTimetable = false;
  late Future<List<_PlanDay>> _days = _loadWeek();

  static DateTime _weekStart(DateTime date) {
    final day = DateTime(date.year, date.month, date.day);
    return day.subtract(Duration(days: day.weekday - 1));
  }

  void _moveWeek(int amount) {
    setState(() {
      _monday = _monday.add(Duration(days: amount * 7));
      _days = _loadWeek();
    });
  }

  void _backToThisWeek() {
    setState(() {
      _monday = _weekStart(DateTime.now());
      _selectedWeekday = DateTime.now().weekday - 1;
      _days = _loadWeek();
    });
  }

  Future<List<_PlanDay>> _loadWeek() async {
    final monday = _monday;
    final semester = await CourseService.instance.ensureActiveSemester();
    final inTerm = !monday.isBefore(_weekStart(semester.startDate)) &&
        monday.isBefore(semester.getEndDate().add(const Duration(days: 1)));
    final courses = inTerm
        ? await CourseService.instance.getWeeklySchedule(
            semester.getWeekOf(monday),
            semester: semester.name,
          )
        : <int, List<Course>>{};
    final times = await CourseService.instance.getTimeConfigs();
    final days = <_PlanDay>[];
    for (var index = 0; index < 7; index++) {
      final date = monday.add(Duration(days: index));
      final todos = await IsarService.instance.getTodosForDate(date);
      final training =
          await TrainingService.instance.getPlansForWeekday(date.weekday);
      days.add(_PlanDay(
        date,
        courses[date.weekday] ?? [],
        todos,
        training.where((plan) => plan.isEnabled).toList(),
        times,
      ));
    }
    return days;
  }

  @override
  Widget build(BuildContext context) {
    final theme = _contentTheme;
    return LayoutBuilder(builder: (context, bounds) {
      final side = bounds.maxWidth < 680 ? 20.0 : 38.0;
      if (_showTimetable) {
        return Column(children: [
          Padding(
            padding: EdgeInsets.fromLTRB(side, 20, side, 8),
            child: Row(children: [
              TextButton.icon(
                onPressed: () => setState(() => _showTimetable = false),
                icon: const Icon(Icons.arrow_back, size: 18),
                label: const Text('返回计划'),
                style: TextButton.styleFrom(foregroundColor: _primary),
              ),
              const Spacer(),
              Text('完整课表', style: theme.textTheme.titleMedium),
            ]),
          ),
          const Expanded(child: SchedulePage()),
        ]);
      }
      return ListView(
        key: const PageStorageKey<String>('plan-scroll'),
        padding: EdgeInsets.fromLTRB(side, 28, side, 48),
        children: [
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1100),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('计划',
                              style: AppType.display(
                                  size: 34,
                                  weight: FontWeight.w600,
                                  color: _primary)),
                          const SizedBox(height: 5),
                          Text('先选一天，再看这一天的课程与安排。',
                              style: theme.textTheme.bodyMedium
                                  ?.copyWith(color: _secondary)),
                        ],
                      ),
                    ),
                    TextButton.icon(
                      onPressed: () => setState(() => _showTimetable = true),
                      icon: const Icon(Icons.table_chart_outlined, size: 18),
                      label: Text(bounds.maxWidth < 560 ? '课表' : '完整课表'),
                      style: TextButton.styleFrom(foregroundColor: _primary),
                    ),
                  ]),
                  const SizedBox(height: 27),
                  _weekControls(theme),
                  const SizedBox(height: 14),
                  FutureBuilder<List<_PlanDay>>(
                    future: _days,
                    builder: (context, snapshot) {
                      if (snapshot.hasError) {
                        return Padding(
                          padding: const EdgeInsets.only(top: 30),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('计划暂时无法加载。'),
                              TextButton(
                                onPressed: () =>
                                    setState(() => _days = _loadWeek()),
                                child: const Text('重试'),
                              ),
                            ],
                          ),
                        );
                      }
                      if (!snapshot.hasData) {
                        return const Padding(
                          padding: EdgeInsets.only(top: 20),
                          child: LinearProgressIndicator(minHeight: 2),
                        );
                      }
                      final days = snapshot.data!;
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          GlassPanel(
                            level: widget.darkBackground
                                ? GlassSurfaceLevel.dark
                                : GlassSurfaceLevel.light,
                            opacity: widget.darkBackground ? .46 : .38,
                            radius: 20,
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 8),
                              child: _weekPicker(days),
                            ),
                          ),
                          const SizedBox(height: 30),
                          GlassPanel(
                            level: widget.darkBackground
                                ? GlassSurfaceLevel.dark
                                : GlassSurfaceLevel.solid,
                            opacity: widget.darkBackground ? .54 : .68,
                            child: Padding(
                              padding: EdgeInsets.all(
                                  bounds.maxWidth < 680 ? 18 : 26),
                              child: _selectedDayDetail(days[_selectedWeekday]),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        ],
      );
    });
  }

  Widget _weekControls(ThemeData theme) {
    final end = _monday.add(const Duration(days: 6));
    return LayoutBuilder(builder: (context, bounds) {
      final compact = bounds.maxWidth < 350;
      final label = compact
          ? '${_monday.month}/${_monday.day}—${end.month}/${end.day}'
          : '${_monday.month}月${_monday.day}日 - ${end.month}月${end.day}日';
      Widget action(VoidCallback onPressed, IconData icon, String tooltip) =>
          SizedBox(
            width: compact ? 38 : 44,
            child: IconButton(
              onPressed: onPressed,
              icon: Icon(icon, size: 20),
              color: _primary,
              tooltip: tooltip,
              padding: EdgeInsets.zero,
            ),
          );
      return Row(children: [
        Expanded(
          child: Text(label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: compact
                  ? theme.textTheme.bodyMedium
                      ?.copyWith(fontWeight: FontWeight.w600)
                  : theme.textTheme.titleMedium),
        ),
        action(() => _moveWeek(-1), Icons.chevron_left, '上一周'),
        action(_backToThisWeek, Icons.today_outlined, '回到本周'),
        action(() => _moveWeek(1), Icons.chevron_right, '下一周'),
      ]);
    });
  }

  Widget _weekPicker(List<_PlanDay> days) {
    final theme = _contentTheme;
    const weekday = ['一', '二', '三', '四', '五', '六', '日'];
    return Row(children: [
      for (var index = 0; index < days.length; index++)
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: Material(
              color: _selectedWeekday == index
                  ? (widget.darkBackground
                      ? Colors.white.withValues(alpha: .18)
                      : AppColors.ink)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(10),
              child: InkWell(
                onTap: () => setState(() => _selectedWeekday = index),
                borderRadius: BorderRadius.circular(10),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: Column(children: [
                    Text(weekday[index],
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: _selectedWeekday == index
                              ? Colors.white70
                              : _secondary,
                        )),
                    const SizedBox(height: 5),
                    Text('${days[index].date.day}',
                        style: AppType.display(
                          size: 23,
                          weight: FontWeight.w600,
                          color: _selectedWeekday == index
                              ? Colors.white
                              : _primary,
                        )),
                    const SizedBox(height: 4),
                    Text(
                      days[index].courses.isEmpty &&
                              days[index]
                                  .todos
                                  .where((t) => !t.isCompleted)
                                  .isEmpty &&
                              days[index].training.isEmpty
                          ? ' '
                          : '${days[index].courses.length + days[index].todos.where((t) => !t.isCompleted).length + days[index].training.length} 项',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: _selectedWeekday == index
                            ? Colors.white70
                            : _secondary,
                      ),
                    ),
                  ]),
                ),
              ),
            ),
          ),
        ),
    ]);
  }

  Widget _selectedDayDetail(_PlanDay day) {
    final theme = _contentTheme;
    final pending = day.todos.where((todo) => !todo.isCompleted).toList();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
        Expanded(
          child: Text('${day.date.month}月${day.date.day}日',
              style: AppType.display(
                  size: 27, weight: FontWeight.w600, color: _primary)),
        ),
        Text('${day.courses.length} 节课程  /  ${pending.length} 项待办',
            style: theme.textTheme.bodySmall?.copyWith(color: _secondary)),
      ]),
      const SizedBox(height: 17),
      Divider(
          height: 1,
          color: widget.darkBackground
              ? Colors.white.withValues(alpha: .18)
              : AppColors.line),
      const SizedBox(height: 24),
      LayoutBuilder(builder: (context, bounds) {
        if (bounds.maxWidth < 650) {
          return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _courseTimeline(day),
                const SizedBox(height: 30),
                _taskRail(day, pending),
              ]);
        }
        return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(flex: 7, child: _courseTimeline(day)),
          const SizedBox(width: 36),
          Expanded(flex: 4, child: _taskRail(day, pending)),
        ]);
      }),
    ]);
  }

  ClassTimeConfig? _slotFor(List<ClassTimeConfig> times, int period) {
    for (final slot in times) {
      if (slot.firstPeriod <= period && slot.lastPeriod >= period) {
        return slot;
      }
    }
    return null;
  }

  Widget _courseTimeline(_PlanDay day) {
    final theme = _contentTheme;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('课程时间轴', style: theme.textTheme.titleMedium),
      const SizedBox(height: 15),
      if (day.courses.isEmpty)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 18),
          child: Text('当天没有课程，可以留给自主安排。',
              style: theme.textTheme.bodyMedium?.copyWith(color: _secondary)),
        )
      else
        for (final course in day.courses) _courseEvent(day, course),
    ]);
  }

  Widget _courseEvent(_PlanDay day, Course course) {
    final theme = _contentTheme;
    final start = _slotFor(day.times, course.startPeriod);
    final end = _slotFor(day.times, course.endPeriod);
    return IntrinsicHeight(
      child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        SizedBox(
          width: 58,
          child: Text(start?.startLabel ?? '第${course.startPeriod}节',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: _primary, fontWeight: FontWeight.w600)),
        ),
        const SizedBox(width: 12),
        Column(children: [
          Container(
            width: 9,
            height: 9,
            margin: const EdgeInsets.only(top: 5),
            decoration: BoxDecoration(
                shape: BoxShape.circle, color: Color(course.colorArgb)),
          ),
          Expanded(
            child: Container(
              width: 1,
              margin: const EdgeInsets.only(top: 6),
              color: widget.darkBackground
                  ? Colors.white.withValues(alpha: .18)
                  : AppColors.line,
            ),
          ),
        ]),
        const SizedBox(width: 15),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(bottom: 28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(course.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyLarge
                        ?.copyWith(fontWeight: FontWeight.w600)),
                const SizedBox(height: 5),
                Text(
                  [
                    if (start != null && end != null)
                      '${start.startLabel} - ${end.endLabel}',
                    if (course.location.isNotEmpty) course.location,
                  ].join('  ·  '),
                  style: theme.textTheme.bodySmall?.copyWith(color: _secondary),
                ),
              ],
            ),
          ),
        ),
      ]),
    );
  }

  Widget _taskRail(_PlanDay day, List<TodoItem> pending) {
    final theme = _contentTheme;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('待办与训练', style: theme.textTheme.titleMedium),
      const SizedBox(height: 15),
      if (pending.isEmpty && day.training.isEmpty)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 18),
          child: Text('这一天还没有安排待办或训练。',
              style: theme.textTheme.bodyMedium?.copyWith(color: _secondary)),
        )
      else ...[
        for (final todo in pending)
          _railRow(todo.title, todo.category.displayName,
              Icons.radio_button_unchecked, AppColors.navy),
        for (final plan in day.training)
          _railRow(
              plan.name, '训练计划', Icons.fitness_center_outlined, AppColors.moss),
      ],
      if (day.todos.any((todo) => todo.isCompleted))
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(
            '已完成 ${day.todos.where((todo) => todo.isCompleted).length} 项',
            style: theme.textTheme.bodySmall?.copyWith(color: _secondary),
          ),
        ),
    ]);
  }

  Widget _railRow(String title, String detail, IconData icon, Color color) {
    final theme = _contentTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 13),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, size: 17, color: widget.darkBackground ? _secondary : color),
        const SizedBox(width: 10),
        Expanded(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium
                    ?.copyWith(fontWeight: FontWeight.w600)),
            const SizedBox(height: 2),
            Text(detail,
                style: theme.textTheme.bodySmall?.copyWith(color: _secondary)),
          ]),
        ),
      ]),
    );
  }
}

class _PlanDay {
  final DateTime date;
  final List<Course> courses;
  final List<TodoItem> todos;
  final List<TrainingPlan> training;
  final List<ClassTimeConfig> times;
  const _PlanDay(
      this.date, this.courses, this.todos, this.training, this.times);
}
