import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/course_service.dart';
import '../services/course_import_service.dart';
import '../services/reminder_service.dart';
import '../models/course.dart';
import '../models/class_time_config.dart';
import '../ui/app_theme.dart';

class SchedulePage extends StatefulWidget {
  const SchedulePage({super.key});

  @override
  State<SchedulePage> createState() => _SchedulePageState();
}

class _SchedulePageState extends State<SchedulePage> {
  final CourseService _courseService = CourseService.instance;

  int _currentWeek = 1;
  Map<int, List<Course>>? _weeklySchedule;
  SemesterConfig? _semesterConfig;
  List<SemesterConfig> _semesters = [];
  List<ClassTimeConfig> _timeConfigs = [];
  List<Exam> _upcomingExams = [];
  bool _isLoading = true;
  bool _isCountdownExpanded = true; // 控制倒计时区域是否展开
  bool _remindEnabled = true; // 课程与考试提醒开关

  @override
  void initState() {
    super.initState();
    _loadData();
    _loadRemindEnabled();
  }

  // 读取提醒开关（默认开）
  Future<void> _loadRemindEnabled() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final enabled =
          prefs.getBool(ReminderService.courseRemindEnabledKey) ?? true;
      if (mounted) setState(() => _remindEnabled = enabled);
    } catch (_) {}
  }

  Future<void> _toggleRemind(bool value) async {
    setState(() => _remindEnabled = value);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(ReminderService.courseRemindEnabledKey, value);
    } catch (_) {}
    ReminderService.instance.requestReschedule();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(value ? '已开启课程与考试提醒' : '已关闭课程与考试提醒')),
      );
    }
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);

    try {
      _semesterConfig = await _courseService.ensureActiveSemester();
      _semesters = await _courseService.getAllSemesters();
      _timeConfigs = await _courseService.getTimeConfigs();
      _currentWeek = _semesterConfig!.getCurrentWeek();
      _weeklySchedule = await _courseService.getWeeklySchedule(_currentWeek);
      _upcomingExams = await _courseService.getUpcomingExams();
    } catch (e) {
      // 如果是第一次使用，可能没有数据
      _weeklySchedule = {};
      for (int i = 1; i <= 7; i++) {
        _weeklySchedule![i] = [];
      }
      _upcomingExams = [];
      _timeConfigs = CourseService.defaultTimeConfigs();
    }

    setState(() => _isLoading = false);

    // 课程/考试/学期/节次配置任一变化都会走到这里：统一触发提醒重排
    ReminderService.instance.requestReschedule();
  }

  void _previousWeek() {
    if (_currentWeek > 1) {
      setState(() => _currentWeek--);
      _loadScheduleForWeek(_currentWeek);
    }
  }

  void _nextWeek() {
    if (_semesterConfig != null && _currentWeek < _semesterConfig!.totalWeeks) {
      setState(() => _currentWeek++);
      _loadScheduleForWeek(_currentWeek);
    }
  }

  void _goToCurrentWeek() async {
    final semester = await _courseService.ensureActiveSemester();
    if (!mounted) return;
    setState(() => _currentWeek = semester.getCurrentWeek());
    _loadScheduleForWeek(_currentWeek);
  }

  Future<void> _loadScheduleForWeek(int week) async {
    _weeklySchedule = await _courseService.getWeeklySchedule(week);
    setState(() {});
  }

  /// 导入课表：解析 → 预览（含重复提示）→ 确认入库
  Future<void> _importSchedule() async {
    // 选择文件 - 支持 .xlsx 和 .xls 格式
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['xlsx', 'xls'],
      dialogTitle: '选择课表文件',
    );

    if (result != null && result.files.single.path != null) {
      final filePath = result.files.single.path!;

      // 显示加载对话框
      if (!mounted) return;
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const Center(
          child: Card(
            child: Padding(
              padding: EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('正在解析课表...'),
                ],
              ),
            ),
          ),
        ),
      );

      List<Course> courses;
      try {
        courses = await CourseImportService.instance.importFromExcel(filePath);
      } catch (e) {
        if (!mounted) return;
        Navigator.pop(context); // 关闭加载对话框
        _showErrorDialog('导入失败: $e');
        return;
      }

      if (!mounted) return;
      Navigator.pop(context); // 关闭加载对话框

      if (courses.isEmpty) {
        _showErrorDialog('未能解析到任何课程，请确认文件格式正确');
        return;
      }

      // 与现有课程比对，预览确认
      final active = await _courseService.ensureActiveSemester();
      final existing = await _courseService.getAllCourses();
      if (!mounted) return;

      final confirmed = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (context) => _ImportPreviewDialog(
          courses: courses,
          existingCourses: existing,
          semesterName: active.name,
        ),
      );

      if (confirmed != true) return;

      // 跳过与现有课程重复的项（同名 + 同星期 + 节次重叠）
      final skipped = courses
          .where(
              (c) => existing.any((e) => CourseService.isDuplicateCourse(e, c)))
          .length;
      final importList = courses
          .where((c) =>
              !existing.any((e) => CourseService.isDuplicateCourse(e, c)))
          .toList();

      await _courseService.importCourses(importList, active.name);

      // 刷新数据
      await _loadData();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(skipped > 0
                ? '成功导入 ${importList.length} 门课程（跳过 $skipped 门重复）'
                : '成功导入 ${importList.length} 门课程'),
            backgroundColor: AppColors.navy,
          ),
        );
      }
    }
  }

  void _showErrorDialog(String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('导入失败'),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }

  /// 学期设置（编辑活跃学期）；[createNew] 为 true 时新建学期并激活
  Future<void> _showSemesterSettings({bool createNew = false}) async {
    final editing = createNew ? null : _semesterConfig;
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => _SemesterSettingsDialog(config: editing),
    );

    if (result != null) {
      if (createNew) {
        final config = SemesterConfig.create(
          name: (result['name'] as String).isEmpty
              ? '新学期'
              : result['name'] as String,
          startDate: result['startDate'] as DateTime,
          totalWeeks: result['totalWeeks'] as int,
        );
        await _courseService.createSemester(config);
      } else if (_semesterConfig != null) {
        if (result['startDate'] != null) {
          _semesterConfig!.startDate = result['startDate'] as DateTime;
        }
        if (result['totalWeeks'] != null) {
          _semesterConfig!.totalWeeks = result['totalWeeks'] as int;
        }
        if (result['name'] != null) {
          _semesterConfig!.name = result['name'] as String;
        }
        await _courseService.updateSemesterConfig(_semesterConfig!);
      }
      await _loadData();
    }
  }

  /// 切换活跃学期
  Future<void> _switchSemester(SemesterConfig config) async {
    await _courseService.setActiveSemester(config);
    await _loadData();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已切换到学期：${config.name}')),
      );
    }
  }

  /// 节次时间设置
  Future<void> _showTimeSettings() async {
    await showDialog(
      context: context,
      builder: (context) => _ClassTimeSettingsDialog(
        configs: _timeConfigs,
        onSave: (sections) async {
          await _courseService.saveTimeConfigs(sections);
        },
      ),
    );
    await _loadData();
  }

  /// 手动管理课程
  Future<void> _manageCourses() async {
    final courses = await _courseService.getAllCourses();
    if (!mounted) return;
    await showDialog(
      context: context,
      builder: (context) => _CourseManageDialog(
        courses: courses,
        onAdd: (course) async {
          await _courseService.addCourse(course);
        },
        onUpdate: (course) async {
          await _courseService.updateCourse(course);
        },
        onDelete: (id) async {
          await _courseService.deleteCourse(id);
        },
      ),
    );
    await _loadData();
  }

  Future<void> _clearAllCourses() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('清空课表'),
        content: const Text('确定要清空所有课程吗？此操作不可恢复。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(
              foregroundColor: Colors.red,
            ),
            child: const Text('确定清空'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await _courseService.clearAllCourses();
      await _loadData();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('课表已清空')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    final isCurrentWeek = _semesterConfig != null &&
        _currentWeek == _semesterConfig!.getCurrentWeek();

    return Column(
      children: [
        // 考试倒计时区域
        if (_upcomingExams.isNotEmpty) _buildExamCountdown(theme),

        // 周次选择器和操作栏
        _buildHeader(theme, isCurrentWeek),

        // 任何宽度都直接展示完整一周网格，列宽随窗口自适应
        Expanded(
          child: _weeklySchedule == null
              ? const Center(child: Text('暂无课程数据'))
              : _buildScheduleGrid(theme,
                  highlightToday: isCurrentWeek,
                  compact: MediaQuery.sizeOf(context).width < 720),
        ),
      ],
    );
  }

  /// 构建考试倒计时区域（可折叠）
  Widget _buildExamCountdown(ThemeData theme) {
    // 只显示最近的3个考试
    final examsToShow = _upcomingExams.take(3).toList();
    final nearestExam = examsToShow.isNotEmpty ? examsToShow.first : null;
    final daysUntil = nearestExam?.getDaysUntilExam();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.amber.withValues(alpha: 0.10),
        border: Border(
          bottom: BorderSide(
            color: AppColors.amber.withValues(alpha: 0.2),
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 标题行（始终显示）
          GestureDetector(
            onTap: () =>
                setState(() => _isCountdownExpanded = !_isCountdownExpanded),
            behavior: HitTestBehavior.opaque,
            child: Row(
              children: [
                const Icon(Icons.alarm, size: 14, color: AppColors.amber),
                const SizedBox(width: 6),
                Text(
                  '考试倒计时',
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: AppColors.amber,
                  ),
                ),
                // 折叠时显示最近一场考试的简要信息
                if (!_isCountdownExpanded && nearestExam != null) ...[
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '${nearestExam.name} - ${daysUntil == 0 ? "今天" : (daysUntil! < 0 ? "已过" : "$daysUntil天")}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
                const Spacer(),
                // 折叠/展开按钮
                Icon(
                  _isCountdownExpanded ? Icons.expand_less : Icons.expand_more,
                  size: 18,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 4),
                TextButton.icon(
                  icon: const Icon(Icons.list, size: 14),
                  label: const Text('管理', style: TextStyle(fontSize: 12)),
                  onPressed: _showExamManagement,
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
              ],
            ),
          ),
          // 展开时显示详细卡片（带动画）
          AnimatedCrossFade(
            crossFadeState: _isCountdownExpanded
                ? CrossFadeState.showFirst
                : CrossFadeState.showSecond,
            duration: const Duration(milliseconds: 200),
            firstChild: Padding(
              padding: const EdgeInsets.only(top: 6),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: examsToShow
                      .map((exam) => _ExamCountdownCard(exam: exam))
                      .toList(),
                ),
              ),
            ),
            secondChild: const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }

  /// 显示考试管理对话框
  Future<void> _showExamManagement() async {
    await showDialog(
      context: context,
      builder: (context) => _ExamManagementDialog(
        exams: _upcomingExams,
        semester: _semesterConfig?.name ?? '2025-2026-1',
        onAdd: (exam) async {
          await _courseService.addExam(exam);
          await _loadData();
        },
        onUpdate: (exam) async {
          await _courseService.updateExam(exam);
          await _loadData();
        },
        onDelete: (id) async {
          await _courseService.deleteExam(id);
          await _loadData();
        },
      ),
    );
  }

  Widget _buildHeader(ThemeData theme, bool isCurrentWeek) {
    return Container(
      color: AppColors.paper.withValues(alpha: .50),
      padding: const EdgeInsets.fromLTRB(22, 25, 22, 15),
      child: Column(children: [
        Align(
          alignment: Alignment.centerLeft,
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('SCHEDULE / 每周节奏',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: AppColors.muted,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.6,
                )),
            const SizedBox(height: 10),
            Text('课程表', style: theme.textTheme.headlineMedium),
          ]),
        ),
        const SizedBox(height: 18),
        Row(children: [
          IconButton(
              onPressed: _currentWeek > 1 ? _previousWeek : null,
              icon: const Icon(Icons.chevron_left),
              tooltip: '上一周'),
          Text('第$_currentWeek周', style: theme.textTheme.titleMedium),
          IconButton(
              onPressed: _semesterConfig != null &&
                      _currentWeek < _semesterConfig!.totalWeeks
                  ? _nextWeek
                  : null,
              icon: const Icon(Icons.chevron_right),
              tooltip: '下一周'),
          const Spacer(),
          PopupMenuButton<String>(
            tooltip: '课表管理',
            onSelected: _handleScheduleMenu,
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'import', child: Text('导入课表')),
              const PopupMenuItem(value: 'courses', child: Text('管理课程')),
              const PopupMenuItem(value: 'exams', child: Text('管理考试')),
              const PopupMenuItem(value: 'times', child: Text('节次时间')),
              PopupMenuItem(
                  value: 'reminder',
                  child: Text(_remindEnabled ? '关闭课程提醒' : '开启课程提醒')),
              const PopupMenuDivider(),
              for (final semester in _semesters)
                PopupMenuItem(
                    value: 'semester:${semester.name}',
                    child: Text(semester.name == _semesterConfig?.name
                        ? '✓ ${semester.name}'
                        : semester.name)),
              const PopupMenuItem(
                  value: 'semester_settings', child: Text('学期设置')),
              const PopupMenuItem(value: 'semester_new', child: Text('新建学期')),
              const PopupMenuDivider(),
              const PopupMenuItem(value: 'clear', child: Text('清空课程')),
            ],
            child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 9),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.tune, size: 18, color: AppColors.muted),
                  const SizedBox(width: 5),
                  Text('课表管理',
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: AppColors.muted)),
                ])),
          ),
        ]),
        if (!isCurrentWeek)
          Row(children: [
            const Spacer(),
            TextButton(
                onPressed: _goToCurrentWeek, child: const Text('回到本周')),
          ]),
      ]),
    );
  }

  Future<void> _handleScheduleMenu(String value) async {
    switch (value) {
      case 'import':
        await _importSchedule();
        return;
      case 'courses':
        await _manageCourses();
        return;
      case 'exams':
        await _showExamManagement();
        return;
      case 'times':
        await _showTimeSettings();
        return;
      case 'reminder':
        await _toggleRemind(!_remindEnabled);
        return;
      case 'semester_settings':
        await _showSemesterSettings();
        return;
      case 'semester_new':
        await _showSemesterSettings(createNew: true);
        return;
      case 'clear':
        await _clearAllCourses();
        return;
      default:
        if (value.startsWith('semester:')) {
          final name = value.substring('semester:'.length);
          final target =
              _semesters.where((semester) => semester.name == name).firstOrNull;
          if (target != null && target.name != _semesterConfig?.name) {
            await _switchSemester(target);
          }
        }
    }
  }

  Widget _buildScheduleGrid(ThemeData theme,
      {bool highlightToday = false, bool compact = false}) {
    if (_weeklySchedule == null) {
      return const Center(child: Text('暂无课程数据'));
    }

    // 节次行来自统一配置（可在"节次"设置中修改）
    final timeSlots = _timeConfigs.isEmpty
        ? CourseService.defaultTimeConfigs()
        : _timeConfigs;

    final weekdays = ['周一', '周二', '周三', '周四', '周五', '周六', '周日'];
    final todayWeekday = DateTime.now().weekday; // 周一 = 1
    final todayColumnColor = AppColors.forest.withValues(alpha: .06);

    // 本周各天日期（学期 startDate 即第 1 周周一）
    final weekDates = <DateTime?>[
      for (var day = 1; day <= 7; day++)
        _semesterConfig == null
            ? null
            : _semesterConfig!.startDate
                .add(Duration(days: (_currentWeek - 1) * 7 + day - 1)),
    ];

    // 网格线颜色
    final gridLineColor = AppColors.ink.withValues(alpha: 0.11);
    // 窄屏压缩：时间列收窄，保证 7 列全部可见
    final timeColWidth = compact ? 46.0 : 64.0;

    return Container(
      // 压低白玻璃不透明度：夜间照片上不再是一整块大白板
      color: AppColors.paper.withValues(alpha: .50),
      padding: const EdgeInsets.fromLTRB(18, 8, 18, 18),
      child: Column(
        children: [
          // 表头
          Container(
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(color: gridLineColor, width: 1),
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: timeColWidth,
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  decoration: BoxDecoration(
                    border: Border(
                      right: BorderSide(color: gridLineColor, width: 1),
                    ),
                  ),
                  child: Center(
                    child: Text(
                      '时间',
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: theme.colorScheme.primary,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ),
                ...weekdays.asMap().entries.map((entry) {
                  final isLast = entry.key == weekdays.length - 1;
                  final isToday =
                      highlightToday && entry.key + 1 == todayWeekday;
                  final date = weekDates[entry.key];
                  return Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      decoration: BoxDecoration(
                        color: isToday ? todayColumnColor : null,
                        borderRadius: isToday ? BorderRadius.circular(8) : null,
                        border: isLast
                            ? null
                            : Border(
                                right:
                                    BorderSide(color: gridLineColor, width: 1),
                              ),
                      ),
                      child: Column(
                        children: [
                          Text(
                            isToday ? '今天' : entry.value,
                            style: theme.textTheme.bodySmall?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: isToday
                                  ? theme.colorScheme.primary
                                  : theme.colorScheme.onSurfaceVariant,
                              fontSize: compact ? 12 : 13,
                            ),
                          ),
                          if (date != null)
                            Text(
                              '${date.month}/${date.day}',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: isToday
                                    ? theme.colorScheme.primary
                                        .withValues(alpha: .75)
                                    : theme.colorScheme.onSurfaceVariant
                                        .withValues(alpha: .8),
                                fontSize: 10,
                              ),
                            ),
                        ],
                      ),
                    ),
                  );
                }),
              ],
            ),
          ),
          // 课程网格
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                children: timeSlots.asMap().entries.map((entry) {
                  final slotIndex = entry.key;
                  final slot = entry.value;
                  final isLastSlot = slotIndex == timeSlots.length - 1;
                  final coursesByDay = List.generate(7, (dayIndex) {
                    return (_weeklySchedule?[dayIndex + 1] ?? <Course>[])
                        .where((course) =>
                            course.startPeriod >= slot.firstPeriod &&
                            course.startPeriod <= slot.lastPeriod)
                        .toList();
                  });
                  final maxCourses = coursesByDay.fold<int>(
                    1,
                    (count, courses) =>
                        courses.length > count ? courses.length : count,
                  );
                  // 整行都没课的时段压缩行高，把空间还给有课的时段
                  final slotHasCourses =
                      coursesByDay.any((courses) => courses.isNotEmpty);

                  return Container(
                    height: slotHasCourses ? 116.0 * maxCourses : 52.0,
                    decoration: BoxDecoration(
                      border: Border(
                        bottom: isLastSlot
                            ? BorderSide.none
                            : BorderSide(color: gridLineColor, width: 1),
                      ),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // 时间列
                        Container(
                          width: timeColWidth,
                          padding: const EdgeInsets.symmetric(
                              vertical: 4, horizontal: 2),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.surfaceContainerHighest
                                .withValues(alpha: 0.3),
                            border: Border(
                              right: BorderSide(color: gridLineColor, width: 1),
                            ),
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              Text(
                                '${slot.periodLabel}节',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  fontWeight: FontWeight.bold,
                                  fontSize: compact ? 11 : 12,
                                ),
                              ),
                              Text(
                                slot.startLabel,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                  fontSize: compact ? 10 : 11,
                                ),
                              ),
                            ],
                          ),
                        ),
                        // 周一到周日的课程
                        ...weekdays.asMap().entries.map((weekdayEntry) {
                          final weekday = weekdayEntry.key + 1;
                          final isLastDay = weekday == 7;
                          // 课程归属其开始节次所在的节段
                          final dayCourses = coursesByDay[weekdayEntry.key];
                          final isToday =
                              highlightToday && weekday == todayWeekday;

                          return Expanded(
                            child: Container(
                              padding: const EdgeInsets.all(2),
                              decoration: BoxDecoration(
                                color: isToday ? todayColumnColor : null,
                                border: isLastDay
                                    ? null
                                    : Border(
                                        right: BorderSide(
                                            color: gridLineColor, width: 1),
                                      ),
                              ),
                              child: dayCourses.isEmpty
                                  ? const SizedBox()
                                  : Column(
                                      children: dayCourses
                                          .map((c) => Expanded(
                                              child: _CourseCard(
                                                  course: c,
                                                  compact: compact)))
                                          .toList(),
                                    ),
                            ),
                          );
                        }),
                      ],
                    ),
                  );
                }).toList(),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 课程卡片组件
class _CourseCard extends StatelessWidget {
  final Course course;

  /// 窄屏紧凑模式：字号缩小、信息省略更多，保证 7 列完整可见
  final bool compact;

  const _CourseCard({required this.course, this.compact = false});

  void _showCourseDetail(BuildContext context) {
    final theme = Theme.of(context);
    final color = Color(course.colorArgb);
    final weekdays = ['', '周一', '周二', '周三', '周四', '周五', '周六', '周日'];

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        titlePadding: EdgeInsets.zero,
        title: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.15),
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(28),
              topRight: Radius.circular(28),
            ),
            border: Border(
              bottom: BorderSide(color: color.withValues(alpha: 0.3), width: 2),
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 4,
                height: 32,
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  course.name,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: color.withValues(alpha: 0.9),
                  ),
                ),
              ),
            ],
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _DetailRow(
              icon: Icons.access_time,
              label: '上课时间',
              value:
                  '${weekdays[course.weekday]} 第${course.startPeriod}-${course.endPeriod}节',
            ),
            const SizedBox(height: 10),
            _DetailRow(
              icon: Icons.location_on,
              label: '上课地点',
              value: course.location.isNotEmpty ? course.location : '未指定',
            ),
            const SizedBox(height: 10),
            _DetailRow(
              icon: Icons.person,
              label: '授课教师',
              value: course.teacher.isNotEmpty ? course.teacher : '未指定',
            ),
            const SizedBox(height: 10),
            _DetailRow(
              icon: Icons.date_range,
              label: '上课周次',
              value: '第 ${course.weekRange} 周',
            ),
            if (course.notes != null && course.notes!.isNotEmpty) ...[
              const SizedBox(height: 10),
              _DetailRow(
                icon: Icons.notes,
                label: '备注',
                value: course.notes!,
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = Color(course.colorArgb);
    final weekdays = ['', '周一', '周二', '周三', '周四', '周五', '周六', '周日'];

    // 构建 Tooltip 内容
    final tooltipText = '${course.name}\n'
        '${weekdays[course.weekday]} 第${course.startPeriod}-${course.endPeriod}节\n'
        '${course.location.isNotEmpty ? course.location : "未指定地点"}\n'
        '${course.teacher.isNotEmpty ? course.teacher : "未指定教师"}';

    return Tooltip(
      message: tooltipText,
      waitDuration: const Duration(milliseconds: 300),
      preferBelow: false,
      child: GestureDetector(
        onTap: () => _showCourseDetail(context),
        child: Container(
          margin: const EdgeInsets.only(bottom: 3),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 9),
          decoration: BoxDecoration(
            color: Color.alphaBlend(
              color.withValues(alpha: .12),
              Colors.white.withValues(alpha: .72),
            ),
            borderRadius: BorderRadius.circular(11),
            border: Border(
              left: BorderSide(color: color.withValues(alpha: .82), width: 3),
              top: BorderSide(color: color.withValues(alpha: .18)),
              right: BorderSide(color: color.withValues(alpha: .18)),
              bottom: BorderSide(color: color.withValues(alpha: .18)),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                course.name,
                style: theme.textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  fontSize: compact ? 11 : 13,
                  color: AppColors.ink,
                  height: 1.25,
                ),
                maxLines: compact ? 3 : 2,
                overflow: TextOverflow.ellipsis,
              ),
              Text(
                  compact
                      ? '第${course.startPeriod}-${course.endPeriod}节'
                      : '第${course.startPeriod}-${course.endPeriod}节${course.location.isEmpty ? '' : ' · ${course.location}'}',
                  style: theme.textTheme.bodySmall?.copyWith(
                      fontSize: compact ? 10 : 11,
                      color: AppColors.muted,
                      height: 1.3),
                  maxLines: compact ? 1 : 2,
                  overflow: TextOverflow.ellipsis),
            ],
          ),
        ),
      ),
    );
  }
}

/// 详情行组件
class _DetailRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _DetailRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 20, color: theme.colorScheme.primary),
        const SizedBox(width: 12),
        SizedBox(
          width: 70,
          child: Text(
            label,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    );
  }
}

/// 导入预览对话框：展示解析结果与重复提示，确认后才入库
class _ImportPreviewDialog extends StatelessWidget {
  final List<Course> courses;
  final List<Course> existingCourses;
  final String semesterName;

  const _ImportPreviewDialog({
    required this.courses,
    required this.existingCourses,
    required this.semesterName,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final weekdays = ['', '周一', '周二', '周三', '周四', '周五', '周六', '周日'];
    final duplicateCount = courses
        .where((c) =>
            existingCourses.any((e) => CourseService.isDuplicateCourse(e, c)))
        .length;

    return AlertDialog(
      title: Text('导入预览（${courses.length} 门）'),
      content: SizedBox(
        width: 480,
        height: 420,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '将导入到学期：$semesterName',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            if (duplicateCount > 0) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.navySoft,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.info_outline,
                        color: AppColors.slate, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '检测到 $duplicateCount 门课程与现有课程重复'
                        '（同名同时间段），确认后将被跳过。',
                        style: theme.textTheme.bodySmall,
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 8),
            const Divider(height: 1),
            Expanded(
              child: ListView.builder(
                itemCount: courses.length,
                itemBuilder: (context, index) {
                  final course = courses[index];
                  final isDup = existingCourses
                      .any((e) => CourseService.isDuplicateCourse(e, course));
                  return ListTile(
                    dense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                    leading: Container(
                      width: 8,
                      height: 8,
                      margin: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color:
                            isDup ? AppColors.slate : Color(course.colorArgb),
                      ),
                    ),
                    title: Text(
                      course.name,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w500,
                        decoration: isDup ? TextDecoration.lineThrough : null,
                      ),
                    ),
                    subtitle: Text(
                      '${weekdays[course.weekday]} 第${course.startPeriod}-${course.endPeriod}节'
                      ' · ${course.weekRange}周'
                      '${course.location.isNotEmpty ? ' · ${course.location}' : ''}',
                      style: theme.textTheme.bodySmall,
                    ),
                    trailing: isDup
                        ? Text(
                            '重复',
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: AppColors.slate,
                            ),
                          )
                        : null,
                  );
                },
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: Text(duplicateCount > 0 ? '跳过重复并导入' : '确认导入'),
        ),
      ],
    );
  }
}

/// 节次时间设置对话框
class _ClassTimeSettingsDialog extends StatefulWidget {
  final List<ClassTimeConfig> configs;
  final Future<void> Function(List<ClassTimeConfig>) onSave;

  const _ClassTimeSettingsDialog({
    required this.configs,
    required this.onSave,
  });

  @override
  State<_ClassTimeSettingsDialog> createState() =>
      _ClassTimeSettingsDialogState();
}

class _ClassTimeSettingsDialogState extends State<_ClassTimeSettingsDialog> {
  late List<ClassTimeConfig> _sections;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    // 使用副本编辑，取消不落库
    _sections = widget.configs.map(_copy).toList();
  }

  static ClassTimeConfig _copy(ClassTimeConfig c) => ClassTimeConfig()
    ..id = c.id
    ..firstPeriod = c.firstPeriod
    ..lastPeriod = c.lastPeriod
    ..startMinutes = c.startMinutes
    ..endMinutes = c.endMinutes;

  void _addSection() {
    final lastPeriod = _sections.isEmpty
        ? 0
        : _sections.map((s) => s.lastPeriod).reduce((a, b) => a > b ? a : b);
    setState(() {
      _sections.add(ClassTimeConfig()
        ..id = _sections.length + 1
        ..firstPeriod = (lastPeriod + 1).clamp(1, 12)
        ..lastPeriod = (lastPeriod + 2).clamp(1, 12)
        ..startMinutes = 8 * 60
        ..endMinutes = 9 * 60 + 40);
    });
  }

  Future<void> _pickTime(int index, bool isStart) async {
    final initial = TimeOfDay(
      hour: (isStart
              ? _sections[index].startMinutes
              : _sections[index].endMinutes) ~/
          60,
      minute: (isStart
              ? _sections[index].startMinutes
              : _sections[index].endMinutes) %
          60,
    );
    final picked = await showTimePicker(
      context: context,
      initialTime: initial,
    );
    if (picked != null) {
      setState(() {
        final minutes = picked.hour * 60 + picked.minute;
        if (isStart) {
          _sections[index].startMinutes = minutes;
        } else {
          _sections[index].endMinutes = minutes;
        }
      });
    }
  }

  Future<void> _save() async {
    if (_sections.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('至少保留一个节次')),
      );
      return;
    }
    for (final s in _sections) {
      if (s.lastPeriod < s.firstPeriod) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('存在结束节次小于开始节次的配置')),
        );
        return;
      }
      if (s.endMinutes <= s.startMinutes) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('结束时间需晚于开始时间')),
        );
        return;
      }
    }
    setState(() => _saving = true);
    await widget.onSave(_sections);
    if (mounted) {
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final periodItems =
        List.generate(12, (i) => i + 1); // 节次选择范围 1-12，兼容超过 10 节的排课

    return AlertDialog(
      title: const Text('节次时间设置'),
      content: SizedBox(
        width: 500,
        height: 420,
        child: Column(
          children: [
            Text(
              '此处配置供课表显示与后续上课提醒共用',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: ListView.builder(
                itemCount: _sections.length,
                itemBuilder: (context, index) {
                  final section = _sections[index];
                  return Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                      child: Column(
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  '节段 ${index + 1}（第${section.periodLabel}节）',
                                  style: theme.textTheme.titleSmall,
                                ),
                              ),
                              IconButton(
                                icon:
                                    const Icon(Icons.delete_outline, size: 20),
                                color: theme.colorScheme.error,
                                tooltip: '删除节段',
                                onPressed: () =>
                                    setState(() => _sections.removeAt(index)),
                              ),
                            ],
                          ),
                          Row(
                            children: [
                              // 节次范围
                              _periodDropdown(
                                label: '开始节',
                                value: section.firstPeriod,
                                items: periodItems,
                                onChanged: (v) => setState(() => section
                                    .firstPeriod = v ?? section.firstPeriod),
                              ),
                              const SizedBox(width: 8),
                              _periodDropdown(
                                label: '结束节',
                                value: section.lastPeriod,
                                items: periodItems,
                                onChanged: (v) => setState(() => section
                                    .lastPeriod = v ?? section.lastPeriod),
                              ),
                              const Spacer(),
                              // 时间
                              TextButton(
                                onPressed: () => _pickTime(index, true),
                                child: Text(section.startLabel),
                              ),
                              const Text('-'),
                              TextButton(
                                onPressed: () => _pickTime(index, false),
                                child: Text(section.endLabel),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : _addSection,
          child: const Text('添加节段'),
        ),
        TextButton(
          onPressed: () => setState(() {
            _sections = CourseService.defaultTimeConfigs().map(_copy).toList();
          }),
          child: const Text('恢复默认'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: const Text('保存'),
        ),
      ],
    );
  }

  Widget _periodDropdown({
    required String label,
    required int value,
    required List<int> items,
    required ValueChanged<int?> onChanged,
  }) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant)),
        const SizedBox(width: 4),
        DropdownButton<int>(
          value: value,
          items: items
              .map((p) => DropdownMenuItem(value: p, child: Text('$p')))
              .toList(),
          onChanged: onChanged,
          isDense: true,
        ),
      ],
    );
  }
}

/// 课程管理对话框（手动增删改）
class _CourseManageDialog extends StatefulWidget {
  final List<Course> courses;
  final Future<void> Function(Course) onAdd;
  final Future<void> Function(Course) onUpdate;
  final Future<void> Function(int) onDelete;

  const _CourseManageDialog({
    required this.courses,
    required this.onAdd,
    required this.onUpdate,
    required this.onDelete,
  });

  @override
  State<_CourseManageDialog> createState() => _CourseManageDialogState();
}

class _CourseManageDialogState extends State<_CourseManageDialog> {
  late List<Course> _courses;

  @override
  void initState() {
    super.initState();
    _courses = List.from(widget.courses)
      ..sort((a, b) {
        if (a.weekday != b.weekday) return a.weekday.compareTo(b.weekday);
        return a.startPeriod.compareTo(b.startPeriod);
      });
  }

  Future<void> _addCourse() async {
    final course = await showDialog<Course>(
      context: context,
      builder: (context) => const _CourseEditDialog(),
    );
    if (course != null) {
      await widget.onAdd(course);
      setState(() => _courses.add(course));
    }
  }

  Future<void> _editCourse(Course course) async {
    final updated = await showDialog<Course>(
      context: context,
      builder: (context) => _CourseEditDialog(course: course),
    );
    if (updated != null) {
      await widget.onUpdate(updated);
      setState(() {
        final index = _courses.indexWhere((c) => c.id == updated.id);
        if (index >= 0) _courses[index] = updated;
      });
    }
  }

  Future<void> _deleteCourse(Course course) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除课程'),
        content: Text('确定要删除"${course.name}"吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await widget.onDelete(course.id);
      setState(() => _courses.removeWhere((c) => c.id == course.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final weekdays = ['', '周一', '周二', '周三', '周四', '周五', '周六', '周日'];

    return AlertDialog(
      title: Row(
        children: [
          const Icon(Icons.edit_calendar_outlined),
          const SizedBox(width: 12),
          const Text('课程管理'),
          const Spacer(),
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: _addCourse,
            tooltip: '添加课程',
          ),
        ],
      ),
      content: SizedBox(
        width: 500,
        height: 420,
        child: _courses.isEmpty
            ? Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.event_busy,
                      size: 64,
                      color: theme.colorScheme.onSurfaceVariant
                          .withValues(alpha: 0.3),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      '当前学期暂无课程',
                      style: theme.textTheme.bodyLarge?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextButton.icon(
                      icon: const Icon(Icons.add),
                      label: const Text('添加课程'),
                      onPressed: _addCourse,
                    ),
                  ],
                ),
              )
            : ListView.builder(
                itemCount: _courses.length,
                itemBuilder: (context, index) {
                  final course = _courses[index];
                  final color = Color(course.colorArgb);
                  return Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: ListTile(
                      leading: Container(
                        width: 6,
                        height: 40,
                        decoration: BoxDecoration(
                          color: color,
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ),
                      title: Text(
                        course.name,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      subtitle: Text(
                        '${weekdays[course.weekday]} 第${course.startPeriod}-${course.endPeriod}节 · ${course.weekRange}周'
                        '${course.location.isNotEmpty ? ' · ${course.location}' : ''}',
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.edit, size: 20),
                            onPressed: () => _editCourse(course),
                          ),
                          IconButton(
                            icon: Icon(Icons.delete,
                                size: 20, color: theme.colorScheme.error),
                            onPressed: () => _deleteCourse(course),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('关闭'),
        ),
      ],
    );
  }
}

/// 课程编辑对话框
class _CourseEditDialog extends StatefulWidget {
  final Course? course;

  const _CourseEditDialog({this.course});

  @override
  State<_CourseEditDialog> createState() => _CourseEditDialogState();
}

class _CourseEditDialogState extends State<_CourseEditDialog> {
  late TextEditingController _nameController;
  late TextEditingController _teacherController;
  late TextEditingController _locationController;
  late TextEditingController _weekRangeController;
  late TextEditingController _notesController;
  late int _weekday;
  late int _startPeriod;
  late int _endPeriod;

  @override
  void initState() {
    super.initState();
    final course = widget.course;
    _nameController = TextEditingController(text: course?.name ?? '');
    _teacherController = TextEditingController(text: course?.teacher ?? '');
    _locationController = TextEditingController(text: course?.location ?? '');
    _weekRangeController =
        TextEditingController(text: course?.weekRange ?? '1-16');
    _notesController = TextEditingController(text: course?.notes ?? '');
    _weekday = course?.weekday ?? DateTime.now().weekday;
    _startPeriod = course?.startPeriod ?? 1;
    _endPeriod = course?.endPeriod ?? 2;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _teacherController.dispose();
    _locationController.dispose();
    _weekRangeController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  void _save() {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请输入课程名称')),
      );
      return;
    }
    // 校验周次范围可解析
    final weeks = Course.parseWeekRange(_weekRangeController.text.trim());
    if (weeks.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('周次格式无效，示例：1-16 或 1-8,10-12')),
      );
      return;
    }
    if (_endPeriod < _startPeriod) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('结束节次不能小于开始节次')),
      );
      return;
    }

    final course = widget.course ?? Course();
    course.name = name;
    course.teacher = _teacherController.text.trim();
    course.location = _locationController.text.trim();
    course.weekday = _weekday;
    course.startPeriod = _startPeriod;
    course.endPeriod = _endPeriod;
    course.weekRange = _weekRangeController.text.trim();
    course.notes = _notesController.text.trim().isEmpty
        ? null
        : _notesController.text.trim();
    if (widget.course == null) {
      course.colorArgb = Course.getColorForName(name);
    }

    Navigator.pop(context, course);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final weekdayLabels = ['周一', '周二', '周三', '周四', '周五', '周六', '周日'];
    final periodItems = List.generate(12, (i) => i + 1);

    return AlertDialog(
      title: Text(widget.course == null ? '添加课程' : '编辑课程'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: _nameController,
                decoration: const InputDecoration(
                  labelText: '课程名称 *',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<int>(
                      initialValue: _weekday,
                      decoration: const InputDecoration(
                        labelText: '星期',
                        border: OutlineInputBorder(),
                      ),
                      items: List.generate(
                          7,
                          (i) => DropdownMenuItem(
                              value: i + 1, child: Text(weekdayLabels[i]))),
                      onChanged: (v) =>
                          setState(() => _weekday = v ?? _weekday),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: DropdownButtonFormField<int>(
                      initialValue: _startPeriod,
                      decoration: const InputDecoration(
                        labelText: '开始节次',
                        border: OutlineInputBorder(),
                      ),
                      items: periodItems
                          .map((p) =>
                              DropdownMenuItem(value: p, child: Text('$p')))
                          .toList(),
                      onChanged: (v) =>
                          setState(() => _startPeriod = v ?? _startPeriod),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: DropdownButtonFormField<int>(
                      initialValue: _endPeriod,
                      decoration: const InputDecoration(
                        labelText: '结束节次',
                        border: OutlineInputBorder(),
                      ),
                      items: periodItems
                          .map((p) =>
                              DropdownMenuItem(value: p, child: Text('$p')))
                          .toList(),
                      onChanged: (v) =>
                          setState(() => _endPeriod = v ?? _endPeriod),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _weekRangeController,
                decoration: const InputDecoration(
                  labelText: '上课周次 *',
                  hintText: '如 1-16 或 1-8,10-12',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _teacherController,
                      decoration: const InputDecoration(
                        labelText: '教师',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: _locationController,
                      decoration: const InputDecoration(
                        labelText: '地点',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _notesController,
                decoration: const InputDecoration(
                  labelText: '备注（可选）',
                  border: OutlineInputBorder(),
                ),
                maxLines: 2,
              ),
              if (widget.course == null) ...[
                const SizedBox(height: 12),
                Text(
                  '课程颜色按课程名自动分配',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: _save,
          child: Text(widget.course == null ? '添加' : '保存'),
        ),
      ],
    );
  }
}

/// 学期设置对话框
class _SemesterSettingsDialog extends StatefulWidget {
  final SemesterConfig? config;

  const _SemesterSettingsDialog({required this.config});

  @override
  State<_SemesterSettingsDialog> createState() =>
      _SemesterSettingsDialogState();
}

class _SemesterSettingsDialogState extends State<_SemesterSettingsDialog> {
  late TextEditingController _nameController;
  late DateTime _startDate;
  late int _totalWeeks;

  @override
  void initState() {
    super.initState();
    _nameController =
        TextEditingController(text: widget.config?.name ?? '2025-2026-1');
    _startDate = widget.config?.startDate ?? DateTime.now();
    _totalWeeks = widget.config?.totalWeeks ?? 20;
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _selectDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _startDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
    );

    if (picked != null) {
      // 找到该周的周一
      final weekday = picked.weekday;
      final monday = picked.subtract(Duration(days: weekday - 1));
      setState(() => _startDate = monday);
    }
  }

  void _save() {
    Navigator.pop(context, {
      'name': _nameController.text.trim(),
      'startDate': _startDate,
      'totalWeeks': _totalWeeks,
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AlertDialog(
      title: const Text('学期设置'),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 学期名称
            Text(
              '学期名称',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(
                hintText: '例如: 2025-2026-1',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),

            // 开学日期
            Text(
              '开学日期（第一周周一）',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            InkWell(
              onTap: _selectDate,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
                decoration: BoxDecoration(
                  border: Border.all(color: theme.colorScheme.outlineVariant),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.calendar_today, size: 20),
                    const SizedBox(width: 12),
                    Text(
                      '${_startDate.year}年${_startDate.month}月${_startDate.day}日 (周一)',
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // 总周数
            Text(
              '总周数',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.remove),
                  onPressed: _totalWeeks > 1
                      ? () => setState(() => _totalWeeks--)
                      : null,
                ),
                Expanded(
                  child: Center(
                    child: Text(
                      '$_totalWeeks 周',
                      style: theme.textTheme.titleLarge,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.add),
                  onPressed: () => setState(() => _totalWeeks++),
                ),
              ],
            ),

            const SizedBox(height: 16),

            // 计算结果
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color:
                    theme.colorScheme.primaryContainer.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.info_outline,
                          size: 16, color: theme.colorScheme.primary),
                      const SizedBox(width: 8),
                      Text(
                        '当前是第 ${_calculateCurrentWeek()} 周',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.primary,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '学期结束: ${_formatDate(_getEndDate())}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        TextButton(
          onPressed: _save,
          child: const Text('保存'),
        ),
      ],
    );
  }

  int _calculateCurrentWeek() {
    final now = DateTime.now();
    final daysDiff = now.difference(_startDate).inDays;
    int week = (daysDiff / 7).floor() + 1;
    if (week < 1) week = 1;
    if (week > _totalWeeks) week = _totalWeeks;
    return week;
  }

  DateTime _getEndDate() {
    return _startDate.add(Duration(days: _totalWeeks * 7 - 1));
  }

  String _formatDate(DateTime date) {
    return '${date.year}年${date.month}月${date.day}日';
  }
}

/// 考试倒计时卡片
class _ExamCountdownCard extends StatelessWidget {
  final Exam exam;

  const _ExamCountdownCard({required this.exam});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    const color = AppColors.amber;
    final days = exam.getDaysUntilExam();

    final urgencyColor = days < 0 ? AppColors.muted : AppColors.amber;

    return Container(
      margin: const EdgeInsets.only(right: 8, bottom: 4),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 倒计时数字
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: urgencyColor,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  days <= 0 ? (days == 0 ? '今天' : '已过') : '$days',
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                if (days > 0)
                  Text(
                    '天',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: Colors.white.withValues(alpha: 0.9),
                      fontSize: 10,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          // 考试信息
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                exam.name,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
              ),
              Text(
                '${exam.getFormattedDate()} ${exam.getFormattedTime()}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontSize: 10,
                ),
              ),
              if (exam.location.isNotEmpty)
                Text(
                  exam.location,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontSize: 10,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// 考试管理对话框
class _ExamManagementDialog extends StatefulWidget {
  final List<Exam> exams;
  final String semester;
  final Function(Exam) onAdd;
  final Function(Exam) onUpdate;
  final Function(int) onDelete;

  const _ExamManagementDialog({
    required this.exams,
    required this.semester,
    required this.onAdd,
    required this.onUpdate,
    required this.onDelete,
  });

  @override
  State<_ExamManagementDialog> createState() => _ExamManagementDialogState();
}

class _ExamManagementDialogState extends State<_ExamManagementDialog> {
  late List<Exam> _exams;

  @override
  void initState() {
    super.initState();
    _exams = List.from(widget.exams);
  }

  Future<void> _addExam() async {
    final result = await showDialog<Exam>(
      context: context,
      builder: (context) => _ExamEditDialog(
        semester: widget.semester,
      ),
    );

    if (result != null) {
      await widget.onAdd(result);
      setState(() {
        _exams.add(result);
        _exams.sort((a, b) => a.examDateTime.compareTo(b.examDateTime));
      });
    }
  }

  Future<void> _editExam(Exam exam) async {
    final result = await showDialog<Exam>(
      context: context,
      builder: (context) => _ExamEditDialog(
        exam: exam,
        semester: widget.semester,
      ),
    );

    if (result != null) {
      await widget.onUpdate(result);
      setState(() {
        final index = _exams.indexWhere((e) => e.id == result.id);
        if (index >= 0) {
          _exams[index] = result;
          _exams.sort((a, b) => a.examDateTime.compareTo(b.examDateTime));
        }
      });
    }
  }

  Future<void> _deleteExam(Exam exam) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除考试'),
        content: Text('确定要删除"${exam.name}"吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('删除'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await widget.onDelete(exam.id);
      setState(() {
        _exams.removeWhere((e) => e.id == exam.id);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AlertDialog(
      title: Row(
        children: [
          const Icon(Icons.event_note),
          const SizedBox(width: 12),
          const Text('考试管理'),
          const Spacer(),
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: _addExam,
            tooltip: '添加考试',
          ),
        ],
      ),
      content: SizedBox(
        width: 500,
        height: 400,
        child: _exams.isEmpty
            ? Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.event_available,
                      size: 64,
                      color: theme.colorScheme.onSurfaceVariant
                          .withValues(alpha: 0.3),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      '暂无考试安排',
                      style: theme.textTheme.bodyLarge?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextButton.icon(
                      icon: const Icon(Icons.add),
                      label: const Text('添加考试'),
                      onPressed: _addExam,
                    ),
                  ],
                ),
              )
            : ListView.builder(
                itemCount: _exams.length,
                itemBuilder: (context, index) {
                  final exam = _exams[index];
                  final color = Color(exam.colorArgb);
                  final days = exam.getDaysUntilExam();

                  return Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: ListTile(
                      leading: Container(
                        width: 50,
                        height: 50,
                        decoration: BoxDecoration(
                          color: days <= 0
                              ? theme.colorScheme.error
                              : days <= 3
                                  ? Colors.deepOrange
                                  : color,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              days <= 0 ? (days == 0 ? '今天' : '已过') : '$days',
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                            if (days > 0)
                              const Text(
                                '天',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 10,
                                ),
                              ),
                          ],
                        ),
                      ),
                      title: Text(
                        exam.name,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                              '${exam.getFormattedDate()} ${exam.getFormattedTime()}'),
                          if (exam.location.isNotEmpty)
                            Text(
                              exam.location,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                        ],
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.edit, size: 20),
                            onPressed: () => _editExam(exam),
                          ),
                          IconButton(
                            icon: Icon(Icons.delete,
                                size: 20, color: theme.colorScheme.error),
                            onPressed: () => _deleteExam(exam),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('关闭'),
        ),
      ],
    );
  }
}

/// 考试编辑对话框
class _ExamEditDialog extends StatefulWidget {
  final Exam? exam;
  final String semester;

  const _ExamEditDialog({
    this.exam,
    required this.semester,
  });

  @override
  State<_ExamEditDialog> createState() => _ExamEditDialogState();
}

class _ExamEditDialogState extends State<_ExamEditDialog> {
  late TextEditingController _nameController;
  late TextEditingController _locationController;
  late TextEditingController _notesController;
  late DateTime _selectedDate;
  late TimeOfDay _selectedTime;
  late int _durationMinutes;
  late int _selectedColorIndex;

  final List<int> _colors = [
    0xFFF44336, // 红
    0xFFE91E63, // 粉红
    0xFF9C27B0, // 紫色
    0xFF673AB7, // 深紫
    0xFF3F51B5, // 靛青
    0xFF2196F3, // 蓝色
    0xFF009688, // 蓝绿
    0xFF4CAF50, // 绿色
    0xFFFF9800, // 橙色
    0xFFFF5722, // 深橙
  ];

  @override
  void initState() {
    super.initState();
    final exam = widget.exam;
    _nameController = TextEditingController(text: exam?.name ?? '');
    _locationController = TextEditingController(text: exam?.location ?? '');
    _notesController = TextEditingController(text: exam?.notes ?? '');
    _selectedDate =
        exam?.examDateTime ?? DateTime.now().add(const Duration(days: 7));
    _selectedTime = exam != null
        ? TimeOfDay(
            hour: exam.examDateTime.hour, minute: exam.examDateTime.minute)
        : const TimeOfDay(hour: 9, minute: 0);
    _durationMinutes = exam?.durationMinutes ?? 120;
    _selectedColorIndex = exam != null
        ? _colors.indexOf(exam.colorArgb).clamp(0, _colors.length - 1)
        : 0;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _locationController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _selectDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime.now().subtract(const Duration(days: 30)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null) {
      setState(() => _selectedDate = picked);
    }
  }

  Future<void> _selectTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _selectedTime,
    );
    if (picked != null) {
      setState(() => _selectedTime = picked);
    }
  }

  void _save() {
    if (_nameController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请输入考试名称')),
      );
      return;
    }

    final examDateTime = DateTime(
      _selectedDate.year,
      _selectedDate.month,
      _selectedDate.day,
      _selectedTime.hour,
      _selectedTime.minute,
    );

    final exam = widget.exam ?? Exam();
    exam.name = _nameController.text.trim();
    exam.examDateTime = examDateTime;
    exam.durationMinutes = _durationMinutes;
    exam.location = _locationController.text.trim();
    exam.semester = widget.semester;
    exam.notes = _notesController.text.trim().isEmpty
        ? null
        : _notesController.text.trim();
    exam.colorArgb = _colors[_selectedColorIndex];

    Navigator.pop(context, exam);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isEditing = widget.exam != null;

    return AlertDialog(
      title: Text(isEditing ? '编辑考试' : '添加考试'),
      content: SizedBox(
        width: 400,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 考试名称
              TextField(
                controller: _nameController,
                decoration: const InputDecoration(
                  labelText: '考试名称 *',
                  hintText: '如：高等数学期末考试',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),

              // 考试日期
              Text(
                '考试日期',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 8),
              InkWell(
                onTap: _selectDate,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
                  decoration: BoxDecoration(
                    border: Border.all(color: theme.colorScheme.outlineVariant),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.calendar_today, size: 20),
                      const SizedBox(width: 12),
                      Text(
                          '${_selectedDate.year}年${_selectedDate.month}月${_selectedDate.day}日'),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // 考试时间
              Text(
                '考试时间',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: InkWell(
                      onTap: _selectTime,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 16),
                        decoration: BoxDecoration(
                          border: Border.all(
                              color: theme.colorScheme.outlineVariant),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.access_time, size: 20),
                            const SizedBox(width: 12),
                            Text(_selectedTime.format(context)),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  // 考试时长
                  SizedBox(
                    width: 120,
                    child: DropdownButtonFormField<int>(
                      value: _durationMinutes,
                      decoration: const InputDecoration(
                        labelText: '时长',
                        border: OutlineInputBorder(),
                        contentPadding:
                            EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      ),
                      items: const [
                        DropdownMenuItem(value: 60, child: Text('60分钟')),
                        DropdownMenuItem(value: 90, child: Text('90分钟')),
                        DropdownMenuItem(value: 120, child: Text('120分钟')),
                        DropdownMenuItem(value: 150, child: Text('150分钟')),
                        DropdownMenuItem(value: 180, child: Text('180分钟')),
                      ],
                      onChanged: (value) {
                        if (value != null) {
                          setState(() => _durationMinutes = value);
                        }
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // 考试地点
              TextField(
                controller: _locationController,
                decoration: const InputDecoration(
                  labelText: '考试地点',
                  hintText: '如：教学楼A101',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),

              // 备注
              TextField(
                controller: _notesController,
                decoration: const InputDecoration(
                  labelText: '备注',
                  hintText: '可选填',
                  border: OutlineInputBorder(),
                ),
                maxLines: 2,
              ),
              const SizedBox(height: 16),

              // 颜色选择
              Text(
                '标签颜色',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _colors.asMap().entries.map((entry) {
                  final index = entry.key;
                  final color = Color(entry.value);
                  final isSelected = index == _selectedColorIndex;
                  return GestureDetector(
                    onTap: () => setState(() => _selectedColorIndex = index),
                    child: Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: color,
                        borderRadius: BorderRadius.circular(16),
                        border: isSelected
                            ? Border.all(
                                color: theme.colorScheme.onSurface, width: 3)
                            : null,
                      ),
                      child: isSelected
                          ? const Icon(Icons.check,
                              color: Colors.white, size: 20)
                          : null,
                    ),
                  );
                }).toList(),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        TextButton(
          onPressed: _save,
          child: Text(isEditing ? '保存' : '添加'),
        ),
      ],
    );
  }
}
