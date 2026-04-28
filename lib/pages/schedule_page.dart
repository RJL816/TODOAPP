import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import '../services/course_service.dart';
import '../services/course_import_service.dart';
import '../models/course.dart';

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
  List<Exam> _upcomingExams = [];
  bool _isLoading = true;
  bool _isCountdownExpanded = true; // 控制倒计时区域是否展开

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);

    try {
      _semesterConfig = await _courseService.getOrCreateCurrentSemester();
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
    }

    setState(() => _isLoading = false);
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
    final semester = await _courseService.getCurrentSemester();
    if (semester != null) {
      setState(() => _currentWeek = semester.getCurrentWeek());
      _loadScheduleForWeek(_currentWeek);
    }
  }

  Future<void> _loadScheduleForWeek(int week) async {
    _weeklySchedule = await _courseService.getWeeklySchedule(week);
    setState(() {});
  }

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
                  Text('正在导入课表...'),
                ],
              ),
            ),
          ),
        ),
      );

      try {
        // 导入课程
        final courses = await CourseImportService.instance.importFromExcel(filePath);

        if (courses.isEmpty) {
          if (!mounted) return;
          Navigator.pop(context); // 关闭加载对话框
          _showErrorDialog('未能解析到任何课程，请确认文件格式正确');
          return;
        }

        // 获取学期信息
        final semester = await _courseService.getOrCreateCurrentSemester();

        // 保存到数据库
        await _courseService.importCourses(courses, semester.name);

        if (!mounted) return;
        Navigator.pop(context); // 关闭加载对话框

        // 刷新数据
        await _loadData();

        // 显示成功消息
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('成功导入 ${courses.length} 门课程'),
            backgroundColor: Colors.green,
            action: SnackBarAction(
              label: '查看',
              textColor: Colors.white,
              onPressed: () {
                // 已经在课表页面，不需要跳转
              },
            ),
          ),
        );
      } catch (e) {
        if (!mounted) return;
        Navigator.pop(context); // 关闭加载对话框
        _showErrorDialog('导入失败: $e');
      }
    }
  }

  /// 显示 .xls 格式提示对话框
  void _showXlsFormatDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.info_outline, color: Colors.orange),
            SizedBox(width: 12),
            Text('文件格式不兼容'),
          ],
        ),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('当前仅支持 .xlsx 格式的课表文件。'),
            SizedBox(height: 12),
            Text('请将 .xls 文件转换为 .xlsx 格式：'),
            SizedBox(height: 8),
            Text('1. 用 Excel 或 WPS 打开 .xls 文件'),
            Text('2. 点击 "文件" -> "另存为"'),
            Text('3. 文件类型选择 "Excel 工作簿 (*.xlsx)"'),
            Text('4. 保存后重新选择该文件导入'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('知道了'),
          ),
        ],
      ),
    );
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

  Future<void> _showSemesterSettings() async {
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => _SemesterSettingsDialog(config: _semesterConfig),
    );

    if (result != null && _semesterConfig != null) {
      // 更新学期配置
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
      await _loadData();
    }
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
        if (_upcomingExams.isNotEmpty)
          _buildExamCountdown(theme),

        // 周次选择器和操作栏
        _buildHeader(theme, isCurrentWeek),

        // 课程表网格
        Expanded(
          child: _weeklySchedule == null
              ? const Center(child: Text('暂无课程数据'))
              : _buildScheduleGrid(theme),
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
        color: theme.colorScheme.errorContainer.withOpacity(0.3),
        border: Border(
          bottom: BorderSide(
            color: theme.colorScheme.error.withOpacity(0.2),
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 标题行（始终显示）
          GestureDetector(
            onTap: () => setState(() => _isCountdownExpanded = !_isCountdownExpanded),
            behavior: HitTestBehavior.opaque,
            child: Row(
              children: [
                Icon(Icons.alarm, size: 14, color: theme.colorScheme.error),
                const SizedBox(width: 6),
                Text(
                  '考试倒计时',
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: theme.colorScheme.error,
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
                  children: examsToShow.map((exam) => _ExamCountdownCard(exam: exam)).toList(),
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
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(
          bottom: BorderSide(
            color: theme.colorScheme.outlineVariant.withOpacity(0.3),
          ),
        ),
      ),
      child: Column(
        children: [
          // 第一行：周次选择和当前周标识
          Row(
            children: [
              IconButton(
                icon: const Icon(Icons.chevron_left, size: 20),
                onPressed: _currentWeek > 1 ? _previousWeek : null,
                tooltip: '上一周',
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(
                  color: isCurrentWeek
                      ? theme.colorScheme.primary
                      : theme.colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (isCurrentWeek)
                      const Icon(Icons.today, size: 14, color: Colors.white),
                    if (isCurrentWeek) const SizedBox(width: 4),
                    Text(
                      '第$_currentWeek周',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: isCurrentWeek
                            ? Colors.white
                            : theme.colorScheme.onPrimaryContainer,
                        fontSize: 13,
                      ),
                    ),
                    if (_semesterConfig != null && _currentWeek > _semesterConfig!.totalWeeks)
                      const Text(' (已结束)',
                          style: TextStyle(fontSize: 10, color: Colors.red)),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.chevron_right, size: 20),
                onPressed: _semesterConfig != null &&
                        _currentWeek < _semesterConfig!.totalWeeks
                    ? _nextWeek
                    : null,
                tooltip: '下一周',
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              ),
              const Spacer(),
              if (!isCurrentWeek)
                TextButton.icon(
                  icon: const Icon(Icons.today, size: 14),
                  label: const Text('返回本周', style: TextStyle(fontSize: 11)),
                  onPressed: _goToCurrentWeek,
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
            ],
          ),
          // 第二行：操作按钮
          const SizedBox(height: 4),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _buildHeaderButton(
                  icon: Icons.upload_file,
                  label: '导入',
                  onPressed: _importSchedule,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 8),
                _buildHeaderButton(
                  icon: Icons.event_note,
                  label: '考试',
                  onPressed: _showExamManagement,
                  color: Colors.deepOrange,
                ),
                const SizedBox(width: 8),
                _buildHeaderButton(
                  icon: Icons.settings,
                  label: '学期',
                  onPressed: _showSemesterSettings,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 8),
                _buildHeaderButton(
                  icon: Icons.delete_outline,
                  label: '清空',
                  onPressed: _clearAllCourses,
                  color: theme.colorScheme.error,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeaderButton({
    required IconData icon,
    required String label,
    required VoidCallback onPressed,
    required Color color,
  }) {
    return TextButton.icon(
      icon: Icon(icon, size: 14),
      label: Text(label, style: const TextStyle(fontSize: 11)),
      onPressed: onPressed,
      style: TextButton.styleFrom(
        foregroundColor: color,
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
    );
  }

  Widget _buildScheduleGrid(ThemeData theme) {
    if (_weeklySchedule == null) {
      return const Center(child: Text('暂无课程数据'));
    }

    // 时间段配置
    final timeSlots = [
      {'period': '1-2', 'time': '08:00-09:40'},
      {'period': '3-4', 'time': '10:00-11:40'},
      {'period': '5-6', 'time': '14:30-16:10'},
      {'period': '7-8', 'time': '16:30-18:10'},
      {'period': '9-10', 'time': '19:30-21:10'},
    ];

    final weekdays = ['一', '二', '三', '四', '五', '六', '日'];
    
    // 网格线颜色
    final gridLineColor = theme.colorScheme.outlineVariant.withOpacity(0.3);

    return Container(
      padding: const EdgeInsets.all(8),
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
                  width: 50,
                  padding: const EdgeInsets.symmetric(vertical: 4),
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
                        fontSize: 10,
                      ),
                    ),
                  ),
                ),
                ...weekdays.asMap().entries.map((entry) {
                  final isLast = entry.key == weekdays.length - 1;
                  return Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      decoration: BoxDecoration(
                        border: isLast ? null : Border(
                          right: BorderSide(color: gridLineColor, width: 1),
                        ),
                      ),
                      child: Center(
                        child: Text(
                          entry.value,
                          style: theme.textTheme.bodySmall?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: theme.colorScheme.onSurfaceVariant,
                            fontSize: 11,
                          ),
                        ),
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
                  final startPeriod = slotIndex * 2 + 1;
                  final isLastSlot = slotIndex == timeSlots.length - 1;

                  return Container(
                    constraints: const BoxConstraints(minHeight: 70),
                    decoration: BoxDecoration(
                      border: Border(
                        bottom: isLastSlot ? BorderSide.none : BorderSide(color: gridLineColor, width: 1),
                      ),
                    ),
                    child: IntrinsicHeight(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // 时间列
                          Container(
                            width: 50,
                            padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
                            decoration: BoxDecoration(
                              color: theme.colorScheme.surfaceContainerHighest.withOpacity(0.3),
                              border: Border(
                                right: BorderSide(color: gridLineColor, width: 1),
                              ),
                            ),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                Text(
                                  '${slot['period']}节',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 10,
                                  ),
                                ),
                                Text(
                                  (slot['time'] as String).split('-')[0],
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: theme.colorScheme.onSurfaceVariant,
                                    fontSize: 9,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          // 周一到周日的课程
                          ...weekdays.asMap().entries.map((weekdayEntry) {
                            final weekday = weekdayEntry.key + 1;
                            final isLastDay = weekday == 7;
                            final dayCourses = _weeklySchedule![weekday]!
                                .where((c) => c.startPeriod == startPeriod)
                                .toList();

                            return Expanded(
                              child: Container(
                                padding: const EdgeInsets.all(2),
                                decoration: BoxDecoration(
                                  border: isLastDay ? null : Border(
                                    right: BorderSide(color: gridLineColor, width: 1),
                                  ),
                                ),
                                child: dayCourses.isEmpty
                                    ? const SizedBox()
                                    : Column(
                                        children: dayCourses
                                            .map((c) => _CourseCard(course: c))
                                            .toList(),
                                      ),
                              ),
                            );
                          }),
                        ],
                      ),
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

  const _CourseCard({required this.course});

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
            color: color.withOpacity(0.15),
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(28),
              topRight: Radius.circular(28),
            ),
            border: Border(
              bottom: BorderSide(color: color.withOpacity(0.3), width: 2),
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
                    color: color.withOpacity(0.9),
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
              value: '${weekdays[course.weekday]} 第${course.startPeriod}-${course.endPeriod}节',
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
          margin: const EdgeInsets.only(bottom: 2),
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
          decoration: BoxDecoration(
            color: color.withOpacity(0.85),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(
              color: color,
              width: 1,
            ),
            boxShadow: [
              BoxShadow(
                color: color.withOpacity(0.3),
                blurRadius: 2,
                offset: const Offset(0, 1),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                course.name,
                style: theme.textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  fontSize: 9,
                  color: Colors.white,
                  height: 1.2,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              if (course.location.isNotEmpty)
                Text(
                  course.location,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontSize: 8,
                    color: Colors.white.withOpacity(0.9),
                    height: 1.2,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
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
    _nameController = TextEditingController(text: widget.config?.name ?? '2025-2026-1');
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
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
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
                color: theme.colorScheme.primaryContainer.withOpacity(0.3),
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
    final color = Color(exam.colorArgb);
    final days = exam.getDaysUntilExam();
    
    // 根据剩余天数选择紧急程度颜色
    Color urgencyColor;
    if (days <= 0) {
      urgencyColor = theme.colorScheme.error;
    } else if (days <= 3) {
      urgencyColor = Colors.deepOrange;
    } else if (days <= 7) {
      urgencyColor = Colors.orange;
    } else {
      urgencyColor = theme.colorScheme.primary;
    }

    return Container(
      margin: const EdgeInsets.only(right: 8, bottom: 4),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.4)),
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
                      color: Colors.white.withOpacity(0.9),
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
                      color: theme.colorScheme.onSurfaceVariant.withOpacity(0.3),
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
                          Text('${exam.getFormattedDate()} ${exam.getFormattedTime()}'),
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
                            icon: Icon(Icons.delete, size: 20, color: theme.colorScheme.error),
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
    _selectedDate = exam?.examDateTime ?? DateTime.now().add(const Duration(days: 7));
    _selectedTime = exam != null
        ? TimeOfDay(hour: exam.examDateTime.hour, minute: exam.examDateTime.minute)
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
    exam.notes = _notesController.text.trim().isEmpty ? null : _notesController.text.trim();
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
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
                  decoration: BoxDecoration(
                    border: Border.all(color: theme.colorScheme.outlineVariant),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.calendar_today, size: 20),
                      const SizedBox(width: 12),
                      Text('${_selectedDate.year}年${_selectedDate.month}月${_selectedDate.day}日'),
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
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
                        decoration: BoxDecoration(
                          border: Border.all(color: theme.colorScheme.outlineVariant),
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
                        contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
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
                            ? Border.all(color: theme.colorScheme.onSurface, width: 3)
                            : null,
                      ),
                      child: isSelected
                          ? const Icon(Icons.check, color: Colors.white, size: 20)
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
