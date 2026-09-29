import 'package:flutter/foundation.dart';
import 'package:isar/isar.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/todo_item.dart';
import '../models/training.dart';
import 'isar_service.dart';
import 'reminder_calc.dart';
import 'reminder_service.dart';

class TrainingCycleDay {
  final String name;
  final bool isRestDay;
  final List<PlanExercise> exercises;

  const TrainingCycleDay(
      {required this.name, required this.isRestDay, required this.exercises});
}

/// 健身服务：按起始日期循环的计划、训练记录与提醒。
class TrainingService {
  static TrainingService? _instance;
  static TrainingService get instance => _instance ??= TrainingService._();
  TrainingService._();

  static const String remindEnabledKey = 'training_remind_enabled';
  static const String remindTimeKey = 'training_remind_minutes';
  static const int defaultRemindMinutes = 17 * 60; // 默认 17:00

  /// 注册训练提醒排程（供 ReminderService 全量重排时调用）
  Future<void> init() async {
    await migrateWeeklyPlans();
    try {
      ReminderService.instance.addExtraOccurrencesProvider(
          () => collectOccurrences(DateTime.now()));
      ReminderService.instance.requestReschedule();
    } catch (_) {}
  }

  // ==================== 循环计划 ====================

  static int? cycleDayForDate(TrainingPlan plan, DateTime date) {
    final start = plan.cycleStartDate;
    final length = plan.cycleLength;
    if (start == null || length == null || length < 1) return null;
    final day = DateTime(date.year, date.month, date.day);
    final first = DateTime(start.year, start.month, start.day);
    final elapsed = day.difference(first).inDays;
    if (elapsed < 0) return null;
    return elapsed % length + 1;
  }

  /// 旧版每周安排转为从本周一开始的七日循环，动作与历史关联 ID 保留。
  Future<void> migrateWeeklyPlans() async {
    final isar = IsarService.instance.isar;
    final plans = await isar.trainingPlans.where().findAll();
    final legacy = plans.where((p) => p.cycleStartDate == null).toList();
    if (legacy.isEmpty) return;
    final now = DateTime.now();
    final monday = DateTime(now.year, now.month, now.day)
        .subtract(Duration(days: now.weekday - 1));
    final groupId = legacy.map((p) => p.id).reduce((a, b) => a < b ? a : b);
    legacy.sort((a, b) => a.id.compareTo(b.id));
    final usedWeekdays = <int>{};
    await isar.writeTxn(() async {
      for (final plan in legacy) {
        final duplicateDay = !usedWeekdays.add(plan.weekday);
        plan.cycleGroupId = duplicateDay ? plan.id : groupId;
        plan.cycleStartDate = monday;
        plan.cycleLength = 7;
        plan.cycleDay = plan.weekday;
        plan.cycleName = duplicateDay ? plan.name : '原每周计划';
        await isar.trainingPlans.put(plan);
      }
    });
  }

  Future<List<TrainingPlan>> getPlansForDate(DateTime date) async {
    final plans = await getAllPlans();
    return plans
        .where((plan) =>
            plan.isEnabled &&
            !plan.isRestDay &&
            (plan.cycleStartDate == null
                ? plan.weekday == date.weekday
                : cycleDayForDate(plan, date) == plan.cycleDay))
        .toList();
  }

  Future<int> saveCycle({
    int? groupId,
    required String name,
    required DateTime startDate,
    required List<TrainingCycleDay> days,
  }) async {
    if (days.isEmpty || days.length > 14) {
      throw ArgumentError('循环天数必须为 1 到 14 天');
    }
    final isar = IsarService.instance.isar;
    final old = groupId == null
        ? <TrainingPlan>[]
        : (await isar.trainingPlans.where().findAll())
            .where((p) => p.cycleGroupId == groupId)
            .toList();
    final byDay = {for (final p in old) p.cycleDay: p};
    final start = DateTime(startDate.year, startDate.month, startDate.day);
    final id = await isar.writeTxn(() async {
      var resolvedGroup = groupId;
      for (var i = 0; i < days.length; i++) {
        final draft = days[i];
        final plan = byDay[i + 1] ?? TrainingPlan();
        plan.weekday = start.add(Duration(days: i)).weekday;
        plan.name = draft.isRestDay ? '休息日' : draft.name.trim();
        plan.isEnabled = true;
        plan.isRestDay = draft.isRestDay;
        plan.cycleStartDate = start;
        plan.cycleLength = days.length;
        plan.cycleDay = i + 1;
        plan.cycleName = name.trim();
        plan.cycleGroupId = resolvedGroup;
        final planId = await isar.trainingPlans.put(plan);
        resolvedGroup ??= planId;
        if (plan.cycleGroupId != resolvedGroup) {
          plan.cycleGroupId = resolvedGroup;
          await isar.trainingPlans.put(plan);
        }
        await isar.planExercises.filter().planIdEqualTo(planId).deleteAll();
        for (final exercise in draft.exercises) {
          exercise.planId = planId;
          exercise.id = Isar.autoIncrement;
        }
        await isar.planExercises.putAll(draft.exercises);
      }
      for (final plan in old.where((p) => (p.cycleDay ?? 0) > days.length)) {
        await isar.trainingPlans.delete(plan.id);
        await isar.planExercises.filter().planIdEqualTo(plan.id).deleteAll();
      }
      return resolvedGroup!;
    });
    ReminderService.instance.requestReschedule();
    return id;
  }

  Future<void> deleteCycle(int groupId) async {
    final isar = IsarService.instance.isar;
    final plans = (await isar.trainingPlans.where().findAll())
        .where((p) => p.cycleGroupId == groupId)
        .toList();
    await isar.writeTxn(() async {
      for (final plan in plans) {
        await isar.trainingPlans.delete(plan.id);
        await isar.planExercises.filter().planIdEqualTo(plan.id).deleteAll();
      }
    });
    ReminderService.instance.requestReschedule();
  }

  Future<List<TrainingPlan>> getAllPlans() async {
    final isar = IsarService.instance.isar;
    final plans = await isar.trainingPlans.where().findAll();
    plans.sort((a, b) {
      if ((a.cycleGroupId ?? a.id) != (b.cycleGroupId ?? b.id)) {
        return (a.cycleGroupId ?? a.id).compareTo(b.cycleGroupId ?? b.id);
      }
      if ((a.cycleDay ?? a.weekday) != (b.cycleDay ?? b.weekday)) {
        return (a.cycleDay ?? a.weekday).compareTo(b.cycleDay ?? b.weekday);
      }
      return a.id.compareTo(b.id);
    });
    return plans;
  }

  /// 指定星期几的启用计划
  Future<List<TrainingPlan>> getPlansForWeekday(int weekday) async {
    final isar = IsarService.instance.isar;
    return await isar.trainingPlans
        .filter()
        .weekdayEqualTo(weekday)
        .and()
        .isEnabledEqualTo(true)
        .findAll();
  }

  Future<List<PlanExercise>> getExercisesForPlan(int planId) async {
    final isar = IsarService.instance.isar;
    final list =
        await isar.planExercises.filter().planIdEqualTo(planId).findAll();
    list.sort((a, b) => a.id.compareTo(b.id));
    return list;
  }

  /// 保存计划及其动作（整体替换动作列表）
  Future<int> savePlan(TrainingPlan plan, List<PlanExercise> exercises) async {
    final isar = IsarService.instance.isar;
    final planId = await isar.writeTxn(() async {
      final id = await isar.trainingPlans.put(plan);
      // 替换该计划的动作
      await isar.planExercises.filter().planIdEqualTo(id).deleteAll();
      for (final e in exercises) {
        e.planId = id;
      }
      await isar.planExercises.putAll(exercises);
      return id;
    });
    ReminderService.instance.requestReschedule();
    return planId;
  }

  Future<void> deletePlan(int planId) async {
    final isar = IsarService.instance.isar;
    await isar.writeTxn(() async {
      await isar.trainingPlans.delete(planId);
      await isar.planExercises.filter().planIdEqualTo(planId).deleteAll();
    });
    ReminderService.instance.requestReschedule();
  }

  // ==================== 训练打卡与历史 ====================

  /// 保存一次训练（日志 + 全部组记录）
  Future<int> saveWorkout({
    required WorkoutLog log,
    required List<WorkoutSet> sets,
  }) async {
    final isar = IsarService.instance.isar;
    final workoutId = await isar.writeTxn(() async {
      final id = await isar.workoutLogs.put(log);
      for (final s in sets) {
        s.workoutId = id;
      }
      await isar.workoutSets.putAll(sets);
      return id;
    });
    return workoutId;
  }

  Future<void> deleteWorkout(int workoutId) async {
    final isar = IsarService.instance.isar;
    await isar.writeTxn(() async {
      await isar.workoutLogs.delete(workoutId);
      await isar.workoutSets.filter().workoutIdEqualTo(workoutId).deleteAll();
    });
  }

  /// 训练历史（按日期倒序）
  Future<List<WorkoutLog>> getWorkoutHistory({int limit = 50}) async {
    final isar = IsarService.instance.isar;
    return await isar.workoutLogs
        .where()
        .sortByStartedAtDesc()
        .limit(limit)
        .findAll();
  }

  Future<List<WorkoutSet>> getSetsForWorkout(int workoutId) async {
    final isar = IsarService.instance.isar;
    final list =
        await isar.workoutSets.filter().workoutIdEqualTo(workoutId).findAll();
    list.sort((a, b) {
      if (a.exerciseName != b.exerciseName) {
        return a.exerciseName.compareTo(b.exerciseName);
      }
      return a.setIndex.compareTo(b.setIndex);
    });
    return list;
  }

  /// 本周（周一至今）完成的训练次数（统计页独立指标口径：completed 记录）
  Future<int> workoutCountThisWeek(DateTime now) async {
    final isar = IsarService.instance.isar;
    final monday = DateTime(now.year, now.month, now.day)
        .subtract(Duration(days: now.weekday - 1));
    final end = monday.add(const Duration(days: 7));
    return await isar.workoutLogs
        .filter()
        .dateBetween(monday, end, includeLower: true, includeUpper: false)
        .and()
        .completedEqualTo(true)
        .count();
  }

  // ==================== 关联待办 ====================

  /// 把某天的训练计划添加为当天的健康类待办（训练计划关联待办的入口）
  Future<int?> addPlanAsTodoForDate(TrainingPlan plan, DateTime date) async {
    try {
      final todo = TodoItem.create(
        title: '训练：${plan.name}',
        date: date,
        taskType: TaskType.oneTime,
        category: TaskCategory.health,
      );
      return await IsarService.instance.addTodo(todo);
    } catch (e) {
      debugPrint('训练计划转待办失败: $e');
      return null;
    }
  }

  // ==================== 训练提醒排程 ====================

  /// 训练提醒排程计算（纯函数，便于测试）：
  /// 未来 30 天内每个启用计划的训练日，在设定时刻提醒。
  /// 计划是长期周循环，30 天滚动窗口由启动/变更/周期重排持续覆盖。
  static List<ReminderOccurrence> trainingOccurrences({
    required List<TrainingPlan> plans,
    required DateTime now,
    required int remindMinutes,
    int windowDays = 30,
  }) {
    final result = <ReminderOccurrence>[];
    final today = DateTime(now.year, now.month, now.day);

    for (final plan in plans) {
      if (!plan.isEnabled || plan.isRestDay) continue;
      for (int i = 0; i < windowDays; i++) {
        final date = today.add(Duration(days: i));
        if (plan.cycleStartDate == null
            ? date.weekday != plan.weekday
            : cycleDayForDate(plan, date) != plan.cycleDay) {
          continue;
        }
        final fireAt = DateTime(date.year, date.month, date.day,
            remindMinutes ~/ 60, remindMinutes % 60);
        if (!fireAt.isAfter(now)) continue;
        // 稳定 ID：计划 × 日期（自 2020-01-01 起的天数取模，避免溢出 int32）
        final dayIndex = date.difference(DateTime(2020, 1, 1)).inDays % 900;
        result.add(ReminderOccurrence(
          id: 5000000 + plan.id * 1000 + dayIndex,
          fireAt: fireAt,
          title: '训练提醒：${plan.name}',
          body: '今天有训练安排'
              '${plan.notes != null && plan.notes!.isNotEmpty ? ' · ${plan.notes}' : ''}',
          payload: '{"type":"training","id":${plan.id}}',
          target: ReminderTarget.course,
          channel: ReminderChannels.schedule,
        ));
      }
    }
    result.sort((a, b) => a.fireAt.compareTo(b.fireAt));
    return result;
  }

  /// 异步收集训练提醒（供 ReminderService 全量重排时调用）
  Future<List<ReminderOccurrence>> collectOccurrences(DateTime now) async {
    final prefs = await SharedPreferences.getInstance();
    final enabled = prefs.getBool(remindEnabledKey) ?? true;
    if (!enabled) return const [];
    final remindMinutes = prefs.getInt(remindTimeKey) ?? defaultRemindMinutes;
    final plans = await _enabledPlans();
    return trainingOccurrences(
        plans: plans, now: now, remindMinutes: remindMinutes);
  }

  Future<List<TrainingPlan>> _enabledPlans() async {
    final isar = IsarService.instance.isar;
    return await isar.trainingPlans.filter().isEnabledEqualTo(true).findAll();
  }
}
