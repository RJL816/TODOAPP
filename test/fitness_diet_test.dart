import 'package:flutter_test/flutter_test.dart';
import 'package:isar/isar.dart';

import 'package:todo_app/models/diet_log.dart';
import 'package:todo_app/models/todo_item.dart';
import 'package:todo_app/models/training.dart';
import 'package:todo_app/services/diet_service.dart';
import 'package:todo_app/services/isar_service.dart';
import 'package:todo_app/services/training_service.dart';

import 'isar_test_base.dart';

/// 健身与饮食服务的单元测试。
void main() {
  setUpAll(() async {
    await initIsarCoreForTests();
  });

  setUp(() async {
    final isar = await openTestIsar();
    IsarService.instance.initForTest(isar);
  });

  group('TrainingService 周计划', () {
    test('按星期查询只返回启用计划', () async {
      final svc = TrainingService.instance;
      final isar = IsarService.instance.isar;
      await isar.writeTxn(() async {
        await isar.trainingPlans
            .put(TrainingPlan.create(weekday: 1, name: '胸'));
        await isar.trainingPlans.put(
            TrainingPlan.create(weekday: 1, name: '停用项', isEnabled: false));
        await isar.trainingPlans
            .put(TrainingPlan.create(weekday: 2, name: '背'));
      });

      final monday = await svc.getPlansForWeekday(1);
      expect(monday.length, 1);
      expect(monday.first.name, '胸');
    });

    test('保存计划整体替换其动作列表', () async {
      final svc = TrainingService.instance;
      final plan = TrainingPlan.create(weekday: 3, name: '腿');
      plan.id = await svc.savePlan(plan, [
        PlanExercise.create(planId: 0, name: '深蹲', plannedSets: 4),
        PlanExercise.create(planId: 0, name: '硬拉', plannedSets: 3),
      ]);
      expect((await svc.getExercisesForPlan(plan.id)).length, 2);

      await svc.savePlan(plan, [
        PlanExercise.create(planId: plan.id, name: '弓步', plannedSets: 3),
      ]);
      final after = await svc.getExercisesForPlan(plan.id);
      expect(after.length, 1);
      expect(after.first.name, '弓步');
    });

    test('删除计划级联删除其动作', () async {
      final svc = TrainingService.instance;
      final plan = TrainingPlan.create(weekday: 5, name: '跑');
      plan.id = await svc.savePlan(plan, [
        PlanExercise.create(planId: 0, name: '慢跑', plannedSets: 1),
      ]);
      await svc.deletePlan(plan.id);
      final isar = IsarService.instance.isar;
      expect(await isar.trainingPlans.count(), 0);
      expect(await isar.planExercises.count(), 0);
    });
  });

  group('训练循环', () {
    test('旧每周计划迁移保留动作和 ID', () async {
      final svc = TrainingService.instance;
      final legacy = TrainingPlan.create(weekday: 3, name: '腿');
      final id = await svc.savePlan(legacy, [
        PlanExercise.create(planId: 0, name: '深蹲', plannedSets: 4),
      ]);
      await svc.migrateWeeklyPlans();
      final migrated = (await svc.getAllPlans()).single;
      expect(migrated.id, id);
      expect(migrated.cycleLength, 7);
      expect(migrated.cycleDay, 3);
      expect((await svc.getExercisesForPlan(id)).single.name, '深蹲');
    });

    test('从起始日按周期轮转，休息日不出现训练', () async {
      final svc = TrainingService.instance;
      final start = DateTime(2026, 9, 25);
      final groupId = await svc.saveCycle(name: '推拉休', startDate: start, days: [
        TrainingCycleDay(name: '推', isRestDay: false, exercises: [
          PlanExercise.create(planId: 0, name: '卧推', plannedSets: 4)
        ]),
        const TrainingCycleDay(name: '休息日', isRestDay: true, exercises: []),
        TrainingCycleDay(name: '拉', isRestDay: false, exercises: [
          PlanExercise.create(planId: 0, name: '划船', plannedSets: 3)
        ]),
      ]);
      expect(groupId, greaterThan(0));
      expect((await svc.getPlansForDate(start)).single.name, '推');
      expect(await svc.getPlansForDate(start.add(const Duration(days: 1))),
          isEmpty);
      expect(
          (await svc.getPlansForDate(start.add(const Duration(days: 2))))
              .single
              .name,
          '拉');
      expect(
          (await svc.getPlansForDate(start.add(const Duration(days: 3))))
              .single
              .name,
          '推');
      final reminders = TrainingService.trainingOccurrences(
          plans: await svc.getAllPlans(),
          now: DateTime(2026, 9, 25, 8),
          remindMinutes: 17 * 60,
          windowDays: 4);
      expect(reminders.length, 3);
    });
  });

  group('训练提醒排程', () {
    test('滚动 30 天窗口内匹配星期，只保留未来时刻', () {
      // 2026-09-24 是周四；计划周五 17:00
      final now = DateTime(2026, 9, 24, 12, 0);
      final plan = TrainingPlan.create(weekday: 5, name: '上肢');
      plan.id = 3;

      final occurrences = TrainingService.trainingOccurrences(
        plans: [plan],
        now: now,
        remindMinutes: 17 * 60,
      );
      // 30 天内共 4 个周五：9/25、10/2、10/9、10/16、10/23 —— 5 个
      expect(occurrences.length, 5);
      expect(occurrences.first.fireAt, DateTime(2026, 9, 25, 17, 0));
      expect(occurrences.last.fireAt, DateTime(2026, 10, 23, 17, 0));
      // ID 稳定且互不相同
      expect(occurrences.map((o) => o.id).toSet().length, 5);
    });

    test('当日提醒时刻已过则跳过当天', () {
      final now = DateTime(2026, 9, 25, 18, 0); // 周五 18:00
      final plan = TrainingPlan.create(weekday: 5, name: '上肢');
      plan.id = 1;
      final occurrences = TrainingService.trainingOccurrences(
        plans: [plan],
        now: now,
        remindMinutes: 17 * 60,
      );
      expect(occurrences.first.fireAt, DateTime(2026, 10, 2, 17, 0));
    });

    test('停用的计划不排程', () {
      final now = DateTime(2026, 9, 24, 12, 0);
      final plan = TrainingPlan.create(weekday: 5, name: '停', isEnabled: false);
      plan.id = 1;
      expect(
        TrainingService.trainingOccurrences(
            plans: [plan], now: now, remindMinutes: 600),
        isEmpty,
      );
    });
  });

  group('训练打卡与统计', () {
    test('保存训练日志与组记录，组归属正确', () async {
      final svc = TrainingService.instance;
      final log = WorkoutLog.create(
        date: DateTime(2026, 9, 24),
        title: '胸+三头',
        startedAt: DateTime(2026, 9, 24, 18, 0),
      );
      final id = await svc.saveWorkout(log: log, sets: [
        WorkoutSet.create(
            workoutId: 0,
            exerciseName: '卧推',
            setIndex: 1,
            reps: 12,
            weightGrams: 60000),
        WorkoutSet.create(
            workoutId: 0,
            exerciseName: '卧推',
            setIndex: 2,
            reps: 10,
            weightGrams: 62500),
        WorkoutSet.create(
            workoutId: 0, exerciseName: '绳索下压', setIndex: 1, reps: 15),
      ]);

      final sets = await svc.getSetsForWorkout(id);
      expect(sets.length, 3);
      expect(sets.every((s) => s.workoutId == id), isTrue);
      // 重量以克存储避免浮点误差，展示层换算
      expect(sets[1].weightGrams, 62500);
    });

    test('本周训练次数只计 completed 且限当周', () async {
      final svc = TrainingService.instance;
      final now = DateTime(2026, 9, 24); // 周四
      Future<void> put(DateTime date, {bool completed = true}) async {
        await svc.saveWorkout(
          log: WorkoutLog.create(
            date: date,
            title: 't',
            startedAt: date,
            completed: completed,
          ),
          sets: const [],
        );
      }

      await put(DateTime(2026, 9, 21)); // 本周一 ✓
      await put(DateTime(2026, 9, 24)); // 本周四 ✓
      await put(DateTime(2026, 9, 24), completed: false); // 中断 ✗
      await put(DateTime(2026, 9, 19)); // 上周六 ✗

      expect(await svc.workoutCountThisWeek(now), 2);
    });
  });

  group('训练计划关联待办', () {
    test('添加为当天的健康类一次性待办', () async {
      final svc = TrainingService.instance;
      final plan = TrainingPlan.create(weekday: 4, name: '全身');
      plan.id = 9;
      final id = await svc.addPlanAsTodoForDate(plan, DateTime(2026, 9, 24));
      expect(id, isNotNull);

      final todo = await IsarService.instance.isar.todoItems.get(id!);
      expect(todo, isNotNull);
      expect(todo!.title, '训练：全身');
      expect(todo.category, TaskCategory.health);
      expect(todo.taskType, TaskType.oneTime);
      expect(todo.createdDate, DateTime(2026, 9, 24));
    });
  });

  group('DietService 按日记录与汇总', () {
    test('按日期隔离，餐次正确', () async {
      final svc = DietService.instance;
      await svc.addLog(DietLog.create(
        date: DateTime(2026, 9, 24),
        mealType: MealType.breakfast,
        food: '鸡蛋 x2',
        calories: 150,
        proteinGrams: 12,
      ));
      await svc.addLog(DietLog.create(
        date: DateTime(2026, 9, 24),
        mealType: MealType.lunch,
        food: '牛肉面',
      ));
      await svc.addLog(DietLog.create(
        date: DateTime(2026, 9, 25),
        mealType: MealType.dinner,
        food: '明天的',
      ));

      final today = await svc.getLogsForDate(DateTime(2026, 9, 24));
      expect(today.length, 2);
      expect(today.first.mealType, MealType.breakfast);

      final tomorrow = await svc.getLogsForDate(DateTime(2026, 9, 25));
      expect(tomorrow.length, 1);
    });

    test('日汇总只对填写的营养字段求和', () async {
      final svc = DietService.instance;
      await svc.addLog(DietLog.create(
        date: DateTime(2026, 9, 24),
        mealType: MealType.breakfast,
        food: '鸡蛋 x2',
        calories: 150,
        proteinGrams: 12,
      ));
      await svc.addLog(DietLog.create(
        date: DateTime(2026, 9, 24),
        mealType: MealType.snack,
        food: '香蕉',
        calories: 90,
        carbsGrams: 23,
      ));
      // 无营养数据的记录
      await svc.addLog(DietLog.create(
        date: DateTime(2026, 9, 24),
        mealType: MealType.dinner,
        food: '外卖',
      ));

      final summary = await svc.getSummaryForDate(DateTime(2026, 9, 24));
      expect(summary.count, 3);
      expect(summary.hasCalorieData, isTrue);
      expect(summary.calories, 240);
      expect(summary.proteinGrams, 12);
      expect(summary.carbsGrams, 23);
      expect(summary.fatGrams, 0);
    });

    test('删除与更新', () async {
      final svc = DietService.instance;
      final log = DietLog.create(
          date: DateTime(2026, 9, 24), mealType: MealType.lunch, food: '沙拉');
      log.id = await svc.addLog(log);

      log.food = '鸡胸沙拉';
      await svc.updateLog(log);
      expect(
          (await svc.getLogsForDate(DateTime(2026, 9, 24))).first.food, '鸡胸沙拉');

      await svc.deleteLog(log.id);
      expect(await svc.getLogsForDate(DateTime(2026, 9, 24)), isEmpty);
    });

    test('复制昨天一餐只复制所选餐次并保留营养字段', () async {
      final svc = DietService.instance;
      await svc.addLog(DietLog.create(
          date: DateTime(2026, 9, 24),
          mealType: MealType.breakfast,
          food: '牛奶',
          calories: 120,
          proteinGrams: 8));
      await svc.addLog(DietLog.create(
          date: DateTime(2026, 9, 24), mealType: MealType.lunch, food: '米饭'));
      final copied =
          await svc.copyPreviousMeal(DateTime(2026, 9, 25), MealType.breakfast);
      expect(copied, 1);
      final today = await svc.getLogsForDate(DateTime(2026, 9, 25));
      expect(today.single.food, '牛奶');
      expect(today.single.calories, 120);
      expect(today.single.proteinGrams, 8);
      expect(today.single.mealType, MealType.breakfast);
    });
  });

  group('模型序列化（备份链路）', () {
    test('新集合 JSON 往返无损', () {
      final plan = TrainingPlan.create(weekday: 2, name: '推')
        ..id = 7
        ..notes = '备注';
      final restoredPlan = TrainingPlan.fromJson(plan.toJson());
      expect(restoredPlan.id, 7);
      expect(restoredPlan.name, '推');
      expect(restoredPlan.weekday, 2);
      expect(restoredPlan.notes, '备注');

      final set = WorkoutSet.create(
          workoutId: 3,
          exerciseName: '深蹲',
          setIndex: 2,
          reps: 8,
          weightGrams: 80500,
          durationSeconds: null);
      set.id = 11;
      final restoredSet = WorkoutSet.fromJson(set.toJson());
      expect(restoredSet.weightGrams, 80500);
      expect(restoredSet.reps, 8);
      expect(restoredSet.displaySummary.contains('80.5 kg'), isTrue);

      final diet = DietLog.create(
          date: DateTime(2026, 9, 24),
          mealType: MealType.dinner,
          food: '鱼',
          calories: 300);
      diet.id = 5;
      final restoredDiet = DietLog.fromJson(diet.toJson());
      expect(restoredDiet.mealType, MealType.dinner);
      expect(restoredDiet.calories, 300);
    });
  });
}
