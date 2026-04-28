import 'dart:io';

import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'services/isar_service.dart';
import 'services/gamification_service.dart';
import 'services/autostart_service.dart';
import 'services/course_service.dart';
import 'services/widget_service.dart';
import 'services/memo_service.dart';
import 'models/todo_item.dart';
import 'pages/statistics_page.dart';
import 'pages/schedule_page.dart';
import 'pages/memo_page.dart';

// Intent 类定义
class AddTodoIntent extends Intent {
  const AddTodoIntent();
}

class ToggleTodoIntent extends Intent {
  const ToggleTodoIntent();
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // 只在 Windows 平台初始化窗口管理器
  if (Platform.isWindows) {
    await windowManager.ensureInitialized();

    const windowOptions = WindowOptions(
      size: Size(500, 650),
      center: true,
      backgroundColor: Colors.transparent,
      skipTaskbar: false,
      titleBarStyle: TitleBarStyle.hidden,
    );

    await windowManager.waitUntilReadyToShow(windowOptions, () async {
      await windowManager.setAsFrameless();
      await windowManager.show();
      await windowManager.focus();
    });
  }

  // 初始化中文日期格式
  await initializeDateFormatting('zh_CN');

  // 初始化数据库
  await IsarService.instance.init();

  // 初始化课程服务
  await CourseService.instance.init(IsarService.instance.isar);

  // 初始化备忘录服务
  MemoService.instance.init(IsarService.instance.isar);

  // 初始化游戏化服务
  await GamificationService.instance.init();

  // 初始化开机自启动服务（内部已有平台判断）
  await AutoStartService.instance.init();

  // 初始化桌面小部件服务（Android）
  await WidgetService.instance.initialize();
  // 同步考试数据到小部件
  if (Platform.isAndroid) {
    final exams = await CourseService.instance.getAllExams();
    await WidgetService.instance.syncExams(exams);
  }

  runApp(const TodoApp());
}

class TodoApp extends StatelessWidget {
  const TodoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '待办事项',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.green),
        useMaterial3: true,
      ),
      home: const TodoHomePage(),
    );
  }
}

class TodoHomePage extends StatefulWidget {
  const TodoHomePage({super.key});

  @override
  State<TodoHomePage> createState() => _TodoHomePageState();
}

class _TodoHomePageState extends State<TodoHomePage>
    with WindowListener {
  final IsarService _db = IsarService.instance;
  int _currentIndex = 0; // 底部导航栏当前索引
  List<TodoItem> _todos = [];
  final TextEditingController _controller = TextEditingController();
  DateTime _selectedDate = DateTime.now();
  bool _isLoading = true;

  // 任务类型选择：默认为一次性任务
  TaskType _selectedTaskType = TaskType.oneTime;

  // 任务分类选择：默认为生活
  TaskCategory _selectedCategory = TaskCategory.life;

  // 任务分类筛选：null表示显示全部
  TaskCategory? _selectedCategoryFilter;

  // 游戏化相关状态
  int _currentStreak = 0;
  bool _shouldPlayConfetti = false;

  // 开机自启动状态
  bool _autoStartEnabled = false;

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    _loadTodos();
    _loadStreak();
    _loadAutoStartState();
  }

  // 加载开机自启动状态
  Future<void> _loadAutoStartState() async {
    if (Platform.isWindows) {
      final enabled = await AutoStartService.instance.isAutoStartEnabled();
      if (mounted) {
        setState(() => _autoStartEnabled = enabled);
      }
    }
  }

  // 切换开机自启动
  Future<void> _toggleAutoStart(bool value) async {
    if (Platform.isWindows) {
      final success = await AutoStartService.instance.setAutoStart(value);
      if (mounted && success) {
        setState(() => _autoStartEnabled = value);
      }
    }
  }

  // 显示设置对话框
  void _showSettingsDialog() {
    showDialog(
      context: context,
      builder: (context) => _SettingsDialog(
        autoStartEnabled: _autoStartEnabled,
        onAutoStartChanged: _toggleAutoStart,
      ),
    );
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    _controller.dispose();
    super.dispose();
  }

  @override
  void onWindowClose() {
    windowManager.destroy();
  }

  Future<void> _loadTodos() async {
    setState(() => _isLoading = true);
    // 获取选中日期的任务（包括每日习惯）
    final todos = await _db.getTodosForDate(_selectedDate);
    setState(() {
      _todos = todos;
      _isLoading = false;
    });
  }

  Future<void> _addTodo(String text) async {
    if (text.trim().isEmpty) return;
    final todo = TodoItem.create(
      title: text.trim(),
      date: _selectedDate,  // 使用选中的日期
      taskType: _selectedTaskType,
      category: _selectedCategory,  // 使用选中的分类
    );
    await _db.addTodo(todo);
    _controller.clear();
    _loadTodos();
  }

  Future<void> _toggleTodo(int id) async {
    await _db.toggleTodo(id, _selectedDate);  // 传入当前查看的日期

    // 播放音效
    GamificationService.instance.playCheckSound();

    await _loadTodos();
    await _loadStreak();

    // 检查是否所有任务都完成了
    if (_todos.isNotEmpty && _todos.every((todo) => todo.isCompleted)) {
      // 播放庆祝动画
      setState(() => _shouldPlayConfetti = true);
      GamificationService.instance.playAllCompleteSound();

      // 延迟重置动画状态
      Future.delayed(const Duration(seconds: 3), () {
        if (mounted) {
          setState(() => _shouldPlayConfetti = false);
        }
      });
    }
  }

  // 加载连续打卡天数
  Future<void> _loadStreak() async {
    final streak = await _db.getCurrentStreak();
    if (mounted) {
      setState(() => _currentStreak = streak);
    }
  }

  Future<void> _deleteTodo(int id) async {
    await _db.deleteTodo(id);
    _loadTodos();
  }

  Future<void> _changeDate(DateTime newDate) async {
    setState(() => _selectedDate = newDate);
    _loadTodos();
  }

  int get _completedCount => _todos.where((todo) => todo.isCompleted).length;

  // 根据筛选条件过滤任务
  List<TodoItem> get _filteredTodos {
    if (_selectedCategoryFilter == null) {
      return _todos;
    }
    return _todos.where((todo) => todo.category == _selectedCategoryFilter).toList();
  }

  String get _formattedDate {
    final weekday = ['周一', '周二', '周三', '周四', '周五', '周六', '周日']
        [_selectedDate.weekday - 1];
    return '${_selectedDate.month}月${_selectedDate.day}日 $weekday';
  }

  bool get _isToday {
    final now = DateTime.now();
    return _selectedDate.year == now.year &&
        _selectedDate.month == now.month &&
        _selectedDate.day == now.day;
  }

  void _startDragging() {
    windowManager.startDragging();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final screenWidth = MediaQuery.of(context).size.width;
    final isNarrowScreen = screenWidth < 600; // 窄屏判断

    return ConfettiCelebrationWidget(
      play: _shouldPlayConfetti,
      child: RepaintBoundary(
        child: Scaffold(
          body: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  theme.colorScheme.primary.withOpacity(0.1),
                  theme.colorScheme.secondary.withOpacity(0.1),
                ],
              ),
            ),
            child: Column(
              children: [
                // Custom Title Bar (with streak display)
                _buildTitleBarWithStreak(theme),

                // 今日进度条（只在今日任务tab显示）
                if (_currentIndex == 0 && _isToday)
                  _buildTodayProgress(theme),

                // Page Content - 使用IndexedStack保持页面状态
                Expanded(
                  child: IndexedStack(
                    index: _currentIndex,
                    children: [
                      _buildTodoListPage(theme),
                      const StatisticsPage(),
                      const SchedulePage(),
                      const MemoPage(),
                    ],
                  ),
                ),
              ],
            ),
          ),
          // 底部导航栏
          bottomNavigationBar: BottomNavigationBar(
            currentIndex: _currentIndex,
            onTap: (index) {
              setState(() => _currentIndex = index);
              // 切换到今日任务页面时刷新数据
              if (index == 0) {
                _loadTodos();
                _loadStreak();
                _loadAutoStartState();
              }
            },
            selectedItemColor: theme.colorScheme.primary,
            unselectedItemColor: theme.colorScheme.onSurfaceVariant,
            backgroundColor: theme.colorScheme.surface,
            elevation: 8,
            type: BottomNavigationBarType.fixed,
            selectedFontSize: 12,
            unselectedFontSize: 11,
            items: const [
              BottomNavigationBarItem(
                icon: Icon(Icons.task_alt),
                label: '今日任务',
              ),
              BottomNavigationBarItem(
                icon: Icon(Icons.bar_chart),
                label: '历史统计',
              ),
              BottomNavigationBarItem(
                icon: Icon(Icons.calendar_today),
                label: '课程表',
              ),
              BottomNavigationBarItem(
                icon: Icon(Icons.edit_note_rounded),
                label: '备忘录',
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 带连续打卡显示的标题栏
  Widget _buildTitleBarWithStreak(ThemeData theme) {
    return GestureDetector(
      onTapDown: Platform.isWindows ? (_) => _startDragging() : null,
      behavior: HitTestBehavior.translucent,
      child: Container(
        height: 50,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          border: Border(
            bottom: BorderSide(
              color: theme.colorScheme.outlineVariant.withOpacity(0.3),
            ),
          ),
        ),
        child: Row(
          children: [
            Icon(
              Icons.check_circle_outline,
              color: theme.colorScheme.primary,
              size: 20,
            ),
            const SizedBox(width: 8),
            Text(
              '待办事项',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const Spacer(),
            // 连续打卡天数显示
            StreakDisplayWidget(streak: _currentStreak),
            const SizedBox(width: 12),
            // 设置按钮
            _WindowButton(
              icon: Icons.settings_outlined,
              onPressed: _showSettingsDialog,
            ),
            // Windows 平台才显示窗口控制按钮
            if (Platform.isWindows) ...[
              const SizedBox(width: 4),
              Row(
                children: [
                  _WindowButton(
                    icon: Icons.minimize,
                    onPressed: () async {
                      final isMinimized = await windowManager.isMinimized();
                      if (isMinimized) {
                        await windowManager.restore();
                      } else {
                        await windowManager.minimize();
                      }
                    },
                  ),
                  _WindowButton(
                    icon: Icons.close,
                    onPressed: () async {
                      await windowManager.close();
                    },
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildTodoListPage(ThemeData theme) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    final screenWidth = MediaQuery.of(context).size.width;
    final isNarrowScreen = screenWidth < 600;
    final sidebarWidth = isNarrowScreen ? 100.0 : 140.0;
    final sidePadding = isNarrowScreen ? 8.0 : 16.0;
    final iconSize = isNarrowScreen ? 24.0 : 32.0;
    final cardPadding = isNarrowScreen ? 8.0 : 12.0;

    return Row(
      children: [
        // Left Sidebar - 响应式宽度
        Container(
          width: sidebarWidth,
          padding: EdgeInsets.all(sidePadding),
          decoration: BoxDecoration(
            color: theme.colorScheme.surface.withOpacity(0.5),
            border: Border(
              right: BorderSide(
                color: theme.colorScheme.outlineVariant.withOpacity(0.3),
              ),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.today_outlined,
                color: theme.colorScheme.primary,
                size: iconSize,
              ),
              SizedBox(height: isNarrowScreen ? 8 : 16),
              Text(
                _formattedDate,
                style: (isNarrowScreen 
                  ? theme.textTheme.bodySmall 
                  : theme.textTheme.bodyMedium)?.copyWith(
                  fontWeight: FontWeight.w500,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              if (!_isToday && !isNarrowScreen) ...[
                const SizedBox(height: 8),
                TextButton.icon(
                  onPressed: () => _changeDate(DateTime.now()),
                  icon: const Icon(Icons.today, size: 16),
                  label: const Text('回到今天'),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
              ],
              if (!_isToday && isNarrowScreen) ...[
                const SizedBox(height: 4),
                IconButton(
                  onPressed: () => _changeDate(DateTime.now()),
                  icon: const Icon(Icons.today, size: 20),
                  tooltip: '回到今天',
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ],
              SizedBox(height: isNarrowScreen ? 12 : 24),
              Container(
                padding: EdgeInsets.all(cardPadding),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primaryContainer.withOpacity(0.3),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isNarrowScreen ? '进度' : '完成进度',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        fontSize: isNarrowScreen ? 10 : null,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '$_completedCount/${_todos.length}',
                      style: (isNarrowScreen
                        ? theme.textTheme.titleMedium
                        : theme.textTheme.headlineSmall)?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                    if (_todos.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: _completedCount / _todos.length,
                          backgroundColor:
                              theme.colorScheme.surfaceContainerHighest,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            theme.colorScheme.primary,
                          ),
                          minHeight: 4,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const Spacer(),
              // 日期选择按钮
              IconButton.outlined(
                onPressed: () => _selectDate(context),
                icon: Icon(
                  Icons.calendar_month,
                  size: isNarrowScreen ? 18 : 24,
                ),
                tooltip: '选择日期',
                style: IconButton.styleFrom(
                  padding: EdgeInsets.all(isNarrowScreen ? 8 : 12),
                  side: BorderSide(
                    color: theme.colorScheme.outlineVariant.withOpacity(0.3),
                  ),
                ),
              ),
            ],
          ),
        ),

        // Right Main Area - Todo List
        Expanded(
          child: Column(
            children: [
              // 分类筛选按钮 - 可横向滚动
              Container(
                padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surface.withOpacity(0.5),
                  border: Border(
                    bottom: BorderSide(
                      color: theme.colorScheme.outlineVariant.withOpacity(0.3),
                    ),
                  ),
                ),
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(left: 4),
                        child: Text(
                          '筛选:',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      _FilterChip(
                        label: '全部',
                        isSelected: _selectedCategoryFilter == null,
                        onTap: () {
                          setState(() {
                            _selectedCategoryFilter = null;
                          });
                        },
                      ),
                      ...TaskCategory.values.map((category) {
                        return _FilterChip(
                          label: category.displayName,
                          isSelected: _selectedCategoryFilter == category,
                          onTap: () {
                            setState(() {
                              _selectedCategoryFilter = category;
                            });
                          },
                        );
                      }),
                      const SizedBox(width: 8), // 右侧留白便于查看最后一项
                    ],
                  ),
                ),
              ),
              Expanded(
                child: _filteredTodos.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.task_alt_outlined,
                              size: 64,
                              color: theme.colorScheme.outlineVariant,
                            ),
                            const SizedBox(height: 16),
                            Text(
                              _selectedCategoryFilter == null ? '还没有任务' : '该分类没有任务',
                              style: theme.textTheme.bodyLarge?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              '在下方添加新任务',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: _filteredTodos.length,
                        itemBuilder: (context, index) {
                          final todo = _filteredTodos[index];
                          return _TodoListItem(
                            todo: todo,
                            selectedDate: _selectedDate,
                            onToggle: () => _toggleTodo(todo.id),
                            onDelete: () => _deleteTodo(todo.id),
                          );
                        },
                      ),
              ),

              // Input Area
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surface,
                  border: Border(
                    top: BorderSide(
                      color: theme.colorScheme.outlineVariant.withOpacity(0.3),
                    ),
                  ),
                ),
                child: Column(
                  children: [
                    // 任务类型选择
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          Text(
                            '类型:',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(width: 8),
                          _TaskTypeButton(
                            type: TaskType.oneTime,
                            isSelected: _selectedTaskType == TaskType.oneTime,
                            onTap: () {
                              setState(() {
                                _selectedTaskType = TaskType.oneTime;
                              });
                            },
                          ),
                          const SizedBox(width: 8),
                          _TaskTypeButton(
                            type: TaskType.recurring,
                            isSelected: _selectedTaskType == TaskType.recurring,
                            onTap: () {
                              setState(() {
                                _selectedTaskType = TaskType.recurring;
                              });
                            },
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                    // 任务分类选择 - 可横向滚动
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          Text(
                            '分类:',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(width: 8),
                          ...TaskCategory.values.map((category) {
                            return Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: _CategoryButton(
                                category: category,
                                isSelected: _selectedCategory == category,
                                onTap: () {
                                  setState(() {
                                    _selectedCategory = category;
                                  });
                                },
                              ),
                            );
                          }),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                    // 输入框和添加按钮
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _controller,
                            decoration: InputDecoration(
                              hintText: _selectedTaskType == TaskType.recurring
                                  ? '添加每日习惯...'
                                  : '添加新任务...',
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide.none,
                              ),
                              filled: true,
                              fillColor: theme.colorScheme.surfaceContainerHighest
                                  .withOpacity(0.5),
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 12,
                              ),
                            ),
                            onSubmitted: _addTodo,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Material(
                          color: _selectedTaskType == TaskType.recurring
                              ? Colors.orange
                              : theme.colorScheme.primary,
                          borderRadius: BorderRadius.circular(12),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(12),
                            onTap: () => _addTodo(_controller.text),
                            child: Container(
                              padding: const EdgeInsets.all(12),
                              child: Icon(
                                Icons.add,
                                color: theme.colorScheme.onPrimary,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// 今日进度展示
  Widget _buildTodayProgress(ThemeData theme) {
    final total = _todos.length;
    final completed = _completedCount;
    final progress = total > 0 ? completed / total : 0.0;
    final percentage = (progress * 100).toInt();

    // 按分类统计
    final Map<TaskCategory, Map<String, int>> categoryStats = {};
    for (var category in TaskCategory.values) {
      final categoryTodos = _todos.where((t) => t.category == category).toList();
      final categoryCompleted = categoryTodos.where((t) => t.isCompleted).length;
      categoryStats[category] = {
        'total': categoryTodos.length,
        'completed': categoryCompleted,
      };
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(
          bottom: BorderSide(
            color: theme.colorScheme.outlineVariant.withOpacity(0.3),
          ),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Row(
              children: [
                Text(
                  '$completed/$total',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: theme.colorScheme.primary,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: progress,
                      minHeight: 4,
                      backgroundColor: theme.colorScheme.surfaceVariant,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        theme.colorScheme.primary,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '$percentage%',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.primary,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _selectDate(BuildContext context) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),  // 允许选择未来一年内的日期
    );
    if (picked != null) {
      _changeDate(picked);
    }
  }
}

class _WindowButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onPressed;

  const _WindowButton({
    required this.icon,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onPressed,
      customBorder: const CircleBorder(),
      child: Container(
        width: 32,
        height: 32,
        alignment: Alignment.center,
        child: Icon(
          icon,
          size: 18,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

// 任务类型选择按钮
class _TaskTypeButton extends StatelessWidget {
  final TaskType type;
  final bool isSelected;
  final VoidCallback onTap;

  const _TaskTypeButton({
    required this.type,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected
              ? (type == TaskType.recurring
                  ? Colors.orange.withOpacity(0.1)
                  : theme.colorScheme.primaryContainer.withOpacity(0.5))
              : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected
                ? (type == TaskType.recurring
                    ? Colors.orange
                    : theme.colorScheme.primary)
                : theme.colorScheme.outlineVariant.withOpacity(0.3),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              type == TaskType.recurring ? Icons.repeat : Icons.task_alt,
              size: 16,
              color: isSelected
                  ? (type == TaskType.recurring
                      ? Colors.orange
                      : theme.colorScheme.primary)
                  : theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 6),
            Text(
              type == TaskType.recurring ? '每日习惯' : '一次性',
              style: theme.textTheme.bodySmall?.copyWith(
                color: isSelected
                    ? (type == TaskType.recurring
                        ? Colors.orange
                        : theme.colorScheme.primary)
                    : theme.colorScheme.onSurfaceVariant,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TodoListItem extends StatelessWidget {
  final TodoItem todo;
  final DateTime selectedDate;
  final VoidCallback onToggle;
  final VoidCallback onDelete;

  const _TodoListItem({
    required this.todo,
    required this.selectedDate,
    required this.onToggle,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    // 判断是否是今天
    final today = DateTime.now();
    final isToday = selectedDate.year == today.year &&
        selectedDate.month == today.month &&
        selectedDate.day == today.day;
    
    // 每日习惯在非今天的日期禁用复选框
    final isCheckboxEnabled = !todo.taskType.isRecurring || isToday;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: todo.taskType.isRecurring
            ? Colors.orange.withOpacity(0.05)
            : theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: todo.taskType.isRecurring
              ? Colors.orange.withOpacity(0.3)
              : theme.colorScheme.outlineVariant.withOpacity(0.3),
        ),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        leading: Checkbox(
          value: todo.isCompleted,
          onChanged: isCheckboxEnabled ? (_) => onToggle() : null,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(6),
          ),
        ),
        title: Row(
          children: [
            // 分类标签
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: _getCategoryColor(todo.category).withOpacity(0.1),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                todo.category.displayName,
                style: TextStyle(
                  fontSize: 11,
                  color: _getCategoryColor(todo.category),
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            const SizedBox(width: 8),
            // 每日习惯显示循环图标
            if (todo.taskType.isRecurring) ...[
              const Icon(
                Icons.repeat,
                size: 16,
                color: Colors.orange,
              ),
              const SizedBox(width: 6),
            ],
            Expanded(
              child: Text(
                todo.title,
                style: theme.textTheme.bodyMedium?.copyWith(
                  decoration: todo.isCompleted ? TextDecoration.lineThrough : null,
                  color: todo.isCompleted
                      ? theme.colorScheme.onSurfaceVariant.withOpacity(0.6)
                      : theme.colorScheme.onSurface,
                ),
              ),
            ),
          ],
        ),
        trailing: IconButton(
          icon: Icon(
            Icons.delete_outline,
            color: theme.colorScheme.error,
          ),
          onPressed: onDelete,
          tooltip: '删除',
        ),
      ),
    );
  }

  Color _getCategoryColor(TaskCategory category) {
    switch (category) {
      case TaskCategory.work:
        return Colors.blue;
      case TaskCategory.life:
        return Colors.green;
      case TaskCategory.study:
        return Colors.purple;
      case TaskCategory.health:
        return Colors.red;
    }
  }
}

// 设置对话框
class _SettingsDialog extends StatefulWidget {
  final bool autoStartEnabled;
  final Function(bool) onAutoStartChanged;

  const _SettingsDialog({
    required this.autoStartEnabled,
    required this.onAutoStartChanged,
  });

  @override
  State<_SettingsDialog> createState() => _SettingsDialogState();
}

class _SettingsDialogState extends State<_SettingsDialog> {
  late bool _autoStartEnabled;

  @override
  void initState() {
    super.initState();
    _autoStartEnabled = widget.autoStartEnabled;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AlertDialog(
      title: Row(
        children: [
          Icon(Icons.settings, color: theme.colorScheme.primary),
          const SizedBox(width: 12),
          const Text('设置'),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '开机自启动',
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '启用后，应用将在 Windows 启动时自动运行',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 16),
          SwitchListTile(
            value: _autoStartEnabled,
            onChanged: (value) {
              setState(() => _autoStartEnabled = value);
              widget.onAutoStartChanged(value);
            },
            title: Text(
              _autoStartEnabled ? '已启用开机自启动' : '未启用开机自启动',
              style: theme.textTheme.bodyMedium,
            ),
            subtitle: Text(
              _autoStartEnabled ? '应用将随系统启动' : '需要手动启动应用',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            contentPadding: EdgeInsets.zero,
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('关闭'),
        ),
      ],
    );
  }
}

// 筛选按钮
class _FilterChip extends StatelessWidget {
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _FilterChip({
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        margin: const EdgeInsets.only(right: 8),
        decoration: BoxDecoration(
          color: isSelected ? theme.colorScheme.primary : Colors.transparent,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? theme.colorScheme.primary : theme.colorScheme.outlineVariant.withOpacity(0.5),
          ),
        ),
        child: Text(
          label,
          style: theme.textTheme.bodySmall?.copyWith(
            color: isSelected ? theme.colorScheme.onPrimary : theme.colorScheme.onSurfaceVariant,
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
          ),
        ),
      ),
    );
  }
}

// 分类选择按钮
class _CategoryButton extends StatelessWidget {
  final TaskCategory category;
  final bool isSelected;
  final VoidCallback onTap;

  const _CategoryButton({
    required this.category,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = _getCategoryColor(category);

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? color.withOpacity(0.15) : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected ? color : theme.colorScheme.outlineVariant.withOpacity(0.3),
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              category.displayName,
              style: theme.textTheme.bodySmall?.copyWith(
                color: isSelected ? color : theme.colorScheme.onSurfaceVariant,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Color _getCategoryColor(TaskCategory category) {
    switch (category) {
      case TaskCategory.work:
        return Colors.blue;
      case TaskCategory.life:
        return Colors.green;
      case TaskCategory.study:
        return Colors.purple;
      case TaskCategory.health:
        return Colors.red;
    }
  }
}
