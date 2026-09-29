import 'package:flutter/foundation.dart';
import 'package:isar/isar.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/todo_item.dart';
import '../models/daily_completion.dart';
import '../models/course.dart';
import '../models/memo.dart';
import '../models/class_time_config.dart';
import '../models/pomodoro_session.dart';
import '../models/training.dart';
import '../models/diet_log.dart';
import '../models/expense.dart';

/// Isar 数据库服务类
class IsarService {
  static IsarService? _instance;
  static Isar? _isar;
  static SharedPreferences? _prefs;

  static const String _lastOpenedDateKey = 'last_opened_date';

  IsarService._();

  static IsarService get instance {
    _instance ??= IsarService._();
    return _instance!;
  }

  /// 初始化数据库
  Future<void> init() async {
    if (_isar != null) return;

    final dir = await getApplicationDocumentsDirectory();
    _prefs = await SharedPreferences.getInstance();

    _isar = await Isar.open(
      [
        TodoItemSchema,
        DailyCompletionSchema,
        CourseSchema,
        SemesterConfigSchema,
        ExamSchema,
        MemoSchema,
        TagSchema,
        ClassTimeConfigSchema,
        PomodoroSessionSchema,
        TrainingPlanSchema,
        PlanExerciseSchema,
        WorkoutLogSchema,
        WorkoutSetSchema,
        DietLogSchema,
        ExpenseSchema
      ],
      directory: dir.path,
      inspector: true, // 开发模式下启用 Isar Inspector
    );

    // 执行数据迁移（处理旧数据没有 taskType 字段的情况）
    await _migrateOldData();

    // 执行跨天重置逻辑
    await _checkAndResetForNewDay();
  }

  /// 数据迁移：为旧数据添加默认的 taskType
  Future<void> _migrateOldData() async {
    const String migrationKey = 'task_type_migration_v1';
    if (_prefs?.getBool(migrationKey) ?? false) return;

    await isar.writeTxn(() async {
      // 查找所有任务并更新 taskType
      final allTodos = await isar.todoItems.where().findAll();
      for (var todo in allTodos) {
        // 将所有任务的 taskType 设置为 oneTime（默认值）
        // 这样旧数据也能正常显示在统计中
        todo.taskType = TaskType.oneTime;
        await isar.todoItems.put(todo);
      }
    });

    await _prefs?.setBool(migrationKey, true);
  }

  Isar get isar {
    if (_isar == null) {
      throw Exception('Isar database not initialized. Call init() first.');
    }
    return _isar!;
  }

  /// 测试注入口：直接使用已打开的 Isar 实例（跳过路径与跨天重置逻辑）
  @visibleForTesting
  void initForTest(Isar isar) {
    _isar = isar;
    _prefs = null;
  }

  /// 跨天重置逻辑
  /// 检查上次打开日期，如果是新的一天则重置所有 Recurring 任务
  /// 注意：保留 completedAt 历史记录，不要清空！
  Future<void> _checkAndResetForNewDay() async {
    if (_prefs == null) return;

    final today = DateTime.now();
    final todayNormalized = DateTime(today.year, today.month, today.day);
    final todayString = todayNormalized.toIso8601String();

    final lastOpenedDate = _prefs!.getString(_lastOpenedDateKey);

    // 如果是新的一天（或是首次启动）
    if (lastOpenedDate == null || lastOpenedDate != todayString) {
      // 重置所有已完成的 Recurring 任务（每日习惯）
      await isar.writeTxn(() async {
        final recurringTodos = await isar.todoItems
            .filter()
            .taskTypeEqualTo(TaskType.recurring)
            .isCompletedEqualTo(true)
            .findAll();

        for (var todo in recurringTodos) {
          // 只重置 isCompleted 标记，保留 completedAt 历史记录
          // getTodosForDate 会根据 completedAt 的日期来判断是否在特定日期完成
          todo.isCompleted = false;
          // 不要清空 completedAt！保留历史完成记录用于统计连续打卡
          // todo.completedAt = null;  // ❌ 不要这样做！
          await isar.todoItems.put(todo);
        }
      });

      // 保存今天的日期
      await _prefs!.setString(_lastOpenedDateKey, todayString);
    }
  }

  // ==================== 基本 CRUD 操作 ====================

  /// 添加新任务
  Future<int> addTodo(TodoItem todo) async {
    return await isar.writeTxn(() async {
      final id = await isar.todoItems.put(todo);
      return id;
    });
  }

  /// 更新任务
  Future<void> updateTodo(TodoItem todo) async {
    await isar.writeTxn(() async {
      await isar.todoItems.put(todo);
    });
  }

  /// 删除任务
  Future<bool> deleteTodo(int id) async {
    return await isar.writeTxn(() async {
      return await isar.todoItems.delete(id);
    });
  }

  /// 切换任务完成状态
  /// [currentDate] 当前查看的日期，用于记录每日习惯的完成日期
  Future<void> toggleTodo(int id, DateTime currentDate) async {
    await isar.writeTxn(() async {
      final todo = await isar.todoItems.get(id);
      if (todo != null) {
        final normalizedDate =
            DateTime(currentDate.year, currentDate.month, currentDate.day);
        final today = DateTime.now();
        final todayNormalized = DateTime(today.year, today.month, today.day);

        if (todo.taskType.isRecurring) {
          // 每日习惯：只允许在今天切换状态，避免跨日期覆盖问题
          final isToday = normalizedDate.year == todayNormalized.year &&
              normalizedDate.month == todayNormalized.month &&
              normalizedDate.day == todayNormalized.day;

          if (!isToday) {
            // 不是今天，不允许切换每日习惯的完成状态
            return;
          }

          // 检查今天是否已经有完成记录
          // 使用 dateEqualTo 而不是 dateBetween，避免 DateTime 比较的精度问题
          final existingCompletion = await isar.dailyCompletions
              .filter()
              .todoIdEqualTo(id)
              .and()
              .dateEqualTo(todayNormalized)
              .findFirst();

          if (existingCompletion != null) {
            // 已完成 -> 取消完成（删除记录）
            await isar.dailyCompletions.delete(existingCompletion.id);
            todo.isCompleted = false;
          } else {
            // 未完成 -> 标记完成（创建记录）
            final completion = DailyCompletion.create(
              todoId: id,
              completionDate: todayNormalized,
            );
            await isar.dailyCompletions.put(completion);
            todo.isCompleted = true;
          }

          // 更新completedAt用于向后兼容
          todo.completedAt = todo.isCompleted
              ? todayNormalized.add(const Duration(hours: 12))
              : null;
        } else {
          // 一次性任务：直接切换
          todo.isCompleted = !todo.isCompleted;
          todo.completedAt = todo.isCompleted ? DateTime.now() : null;
        }

        await isar.todoItems.put(todo);
      }
    });
  }

  // ==================== 查询操作 ====================

  /// 获取指定日期的所有任务
  Future<List<TodoItem>> getTodosByDate(DateTime date) async {
    final normalizedDate = DateTime(date.year, date.month, date.day);
    final startOfDay = normalizedDate;
    final endOfDay = normalizedDate.add(const Duration(days: 1));

    return await isar.todoItems
        .filter()
        .createdDateBetween(startOfDay, endOfDay, includeLower: true)
        .sortByCreatedAt()
        .findAll();
  }

  /// 获取今天的任务（智能过滤）
  /// - Recurring 任务：显示所有（无论是否完成）
  /// - OneTime 任务：只显示未完成的
  Future<List<TodoItem>> getTodayTodos() async {
    final today = DateTime.now();
    return await getTodosForDate(today);
  }

  /// 获取指定日期的任务（包括每日习惯）
  /// - Recurring 任务：显示所有的每日习惯，但状态根据日期判断
  /// - OneTime 任务：只显示指定日期的
  Future<List<TodoItem>> getTodosForDate(DateTime date) async {
    final normalizedDate = DateTime(date.year, date.month, date.day);
    final startOfDay = normalizedDate;
    final endOfDay = normalizedDate.add(const Duration(days: 1));

    // 获取所有每日习惯（recurring 任务）
    // 习惯只在其创建日期（含）之后出现，避免"创建之前的日期"被算作未完成
    final recurringTasks = await isar.todoItems
        .filter()
        .taskTypeEqualTo(TaskType.recurring)
        .and()
        .createdDateLessThan(endOfDay)
        .sortByCreatedAt()
        .findAll();

    // 获取指定日期的所有完成记录
    // 使用 dateEqualTo 而不是 dateBetween，避免 DateTime 比较的精度问题
    final completions = await isar.dailyCompletions
        .filter()
        .dateEqualTo(normalizedDate)
        .findAll();

    // 构建完成记录的Map，方便查询
    final completionMap = <int, bool>{};
    for (var completion in completions) {
      completionMap[completion.todoId] = true;
    }

    // 处理每日习惯的完成状态：从DailyCompletion表查询
    final processedRecurring = recurringTasks.map((task) {
      // 检查是否有完成记录
      final isCompletedOnDate = completionMap[task.id] ?? false;

      // 创建副本，避免修改原对象
      return TodoItem()
        ..id = task.id
        ..title = task.title
        ..isCompleted = isCompletedOnDate // 根据完成记录设置状态
        ..createdDate = task.createdDate
        ..createdAt = task.createdAt
        ..completedAt = task.completedAt
        ..taskType = task.taskType
        ..category = task.category // 复制分类
        ..notes = task.notes // 复制备注
        ..sortOrder = task.sortOrder; // 复制排序
    }).toList();

    // 获取指定日期的一次性任务（包括已完成和未完成的）
    final oneTimeTasks = await isar.todoItems
        .filter()
        .taskTypeEqualTo(TaskType.oneTime)
        .and()
        .createdDateBetween(startOfDay, endOfDay,
            includeLower: true, includeUpper: false)
        .sortByCreatedAt()
        .findAll();

    // 合并并按创建时间排序
    final allTasks = [...processedRecurring, ...oneTimeTasks];
    allTasks.sort((a, b) => a.createdAt.compareTo(b.createdAt));

    return allTasks;
  }

  /// 获取指定日期范围内的所有任务
  Future<List<TodoItem>> getTodosBetween(DateTime start, DateTime end) async {
    final normalizedStart = DateTime(start.year, start.month, start.day);
    final normalizedEnd =
        DateTime(end.year, end.month, end.day).add(const Duration(days: 1));

    return await isar.todoItems
        .filter()
        .createdDateBetween(normalizedStart, normalizedEnd, includeLower: true)
        .sortByCreatedDate()
        .findAll();
  }

  /// 获取所有任务（按日期分组）
  Future<Map<DateTime, List<TodoItem>>> getAllTodosGroupedByDate() async {
    final todos = await isar.todoItems.where().sortByCreatedDate().findAll();

    final Map<DateTime, List<TodoItem>> grouped = {};
    for (var todo in todos) {
      final dateKey = DateTime(
          todo.createdDate.year, todo.createdDate.month, todo.createdDate.day);
      grouped.putIfAbsent(dateKey, () => []).add(todo);
    }
    return grouped;
  }

  // ==================== 统计操作 ====================

  /// 获取指定日期的完成率 (0.0 - 1.0)
  /// 统计所有任务（包括一次性任务和每日习惯）
  Future<double> getCompletionRate(DateTime date) async {
    final todos = await getTodosForDate(date); // 使用新的查询方法
    if (todos.isEmpty) return 0.0;

    // 统计所有任务的完成情况
    final completed = todos.where((t) => t.isCompleted).length;
    return completed / todos.length;
  }

  /// 获取日期范围内的完成率统计
  /// 返回: Map<日期字符串, 完成率>
  Future<Map<String, double>> getCompletionRatesInRange(
      DateTime start, DateTime end) async {
    final todos = await getTodosBetween(start, end);
    final Map<String, List<TodoItem>> grouped = {};

    for (var todo in todos) {
      final dateKey =
          '${todo.createdDate.year}-${todo.createdDate.month.toString().padLeft(2, '0')}-${todo.createdDate.day.toString().padLeft(2, '0')}';
      grouped.putIfAbsent(dateKey, () => []).add(todo);
    }

    final Map<String, double> rates = {};
    for (var entry in grouped.entries) {
      final completed = entry.value.where((t) => t.isCompleted).length;
      rates[entry.key] =
          entry.value.isEmpty ? 0.0 : completed / entry.value.length;
    }

    return rates;
  }

  /// 获取指定日期的统计数据
  Future<DateStatistics> getStatisticsForDate(DateTime date) async {
    final todos = await getTodosForDate(date); // 使用新的查询方法
    final completed = todos.where((t) => t.isCompleted).length;

    return DateStatistics(
      date: DateTime(date.year, date.month, date.day),
      total: todos.length,
      completed: completed,
      completionRate: todos.isEmpty ? 0.0 : completed / todos.length,
    );
  }

  /// 获取最近 N 天的统计数据
  Future<List<DateStatistics>> getRecentStatistics(int days) async {
    final today = DateTime.now();
    final List<DateStatistics> stats = [];

    for (int i = days - 1; i >= 0; i--) {
      final date = today.subtract(Duration(days: i));
      final stat = await getStatisticsForDate(date);
      stats.add(stat);
    }

    return stats;
  }

  /// 每日完成条数（热力图用）：一次性查出最近 [days] 天的打卡记录按日聚合，
  /// 避免逐日查询。返回的日期均为归一化（0 点）键。
  Future<Map<DateTime, int>> getDailyCompletionCounts({int days = 140}) async {
    final today = DateTime.now();
    final since = DateTime(today.year, today.month, today.day)
        .subtract(Duration(days: days - 1));
    final completions = await isar.dailyCompletions
        .filter()
        .dateGreaterThan(since.subtract(const Duration(days: 1)))
        .findAll();
    final counts = <DateTime, int>{};
    for (final completion in completions) {
      final day = DateTime(completion.date.year, completion.date.month,
          completion.date.day);
      counts[day] = (counts[day] ?? 0) + 1;
    }
    return counts;
  }

  /// 获取连续完成天数（streak）
  ///
  /// 口径（与 docs/UPGRADE_PLAN.md 1A.5 一致，配套单元测试）：
  /// - 有效任务日 =（按创建日期过滤后）当天任务数 > 0；全部完成计 1 天，存在未完成即中断
  /// - 无任务日：不计入、不中断
  /// - 今天未全部完成：不算中断（streak 以昨天为终点），全部完成则从今天计入
  /// - 回溯下界 = min(最早数据日期, 今天 − 366 天)，到达即停，避免无限回溯查询
  ///
  /// [asOf] 供测试注入"当前时间"，生产调用不传。
  Future<int> getCurrentStreak({DateTime? asOf}) async {
    final now = asOf ?? DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    final earliest = await _getEarliestTodoDate();
    final hardBound = today.subtract(const Duration(days: 366));
    final floor = (earliest != null && earliest.isAfter(hardBound))
        ? earliest
        : hardBound;

    int streak = 0;
    DateTime checkDate = today;

    // 从今天回溯到下界（含下界当天），下界之前不再回溯
    while (!checkDate.isBefore(floor)) {
      final todos = await getTodosForDate(checkDate);

      if (todos.isEmpty) {
        // 无任务日：不计入、不中断
        checkDate = checkDate.subtract(const Duration(days: 1));
        continue;
      }

      final allCompleted = todos.every((t) => t.isCompleted);
      final isToday = checkDate.year == today.year &&
          checkDate.month == today.month &&
          checkDate.day == today.day;

      if (allCompleted) {
        streak++;
      } else if (isToday) {
        // 今天未全部完成：不中断，继续回溯昨天
      } else {
        // 过去的有效任务日未全部完成 → 中断
        break;
      }

      checkDate = checkDate.subtract(const Duration(days: 1));
    }

    return streak;
  }

  /// 最早的任务创建日期（streak 回溯下界的数据部分）
  Future<DateTime?> _getEarliestTodoDate() async {
    final earliest =
        await isar.todoItems.where().sortByCreatedDate().findFirst();
    if (earliest == null) return null;
    final d = earliest.createdDate;
    return DateTime(d.year, d.month, d.day);
  }

  /// 清空所有数据（慎用）
  Future<void> clearAll() async {
    await isar.writeTxn(() async {
      await isar.clear();
    });
    await _prefs?.remove(_lastOpenedDateKey);
  }

  /// 导出所有任务为 JSON
  Future<String> exportToJson() async {
    final todos = await isar.todoItems.where().findAll();
    final jsonList = todos.map((t) => t.toJson()).toList();
    return jsonList.toString();
  }

  /// 关闭数据库
  Future<void> close() async {
    await _isar?.close();
    _isar = null;
  }

  /// 调试：打印数据库中的所有每日习惯和完成记录
  Future<Map<String, dynamic>> debugGetDatabaseInfo() async {
    // 1. 所有每日习惯
    final recurringTasks = await isar.todoItems
        .filter()
        .taskTypeEqualTo(TaskType.recurring)
        .findAll();

    // 2. 所有完成记录
    final allCompletions = await isar.dailyCompletions.where().findAll();

    return {
      'recurringCount': recurringTasks.length,
      'recurringTasks': recurringTasks
          .map((t) => {
                'id': t.id,
                'title': t.title,
                'isCompleted': t.isCompleted,
              })
          .toList(),
      'completionCount': allCompletions.length,
      'completions': allCompletions
          .map((c) => {
                'id': c.id,
                'todoId': c.todoId,
                'date':
                    '${c.date.year}-${c.date.month.toString().padLeft(2, '0')}-${c.date.day.toString().padLeft(2, '0')}',
              })
          .toList(),
    };
  }
}

/// 日期统计数据类
class DateStatistics {
  final DateTime date;
  final int total;
  final int completed;
  final double completionRate;

  DateStatistics({
    required this.date,
    required this.total,
    required this.completed,
    required this.completionRate,
  });

  String get dateString =>
      '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

  Map<String, dynamic> toJson() => {
        'date': dateString,
        'total': total,
        'completed': completed,
        'completionRate': completionRate,
      };
}
