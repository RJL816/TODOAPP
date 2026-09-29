import 'package:flutter_test/flutter_test.dart';
import 'package:isar/isar.dart';

import 'package:todo_app/models/daily_completion.dart';
import 'package:todo_app/models/todo_item.dart';
import 'package:todo_app/services/isar_service.dart';

import 'isar_test_base.dart';

/// 习惯（每日重复任务）按创建日期过滤 + 连续打卡（streak）口径的单元测试。
/// 口径定义见 docs/UPGRADE_PLAN.md 1A.5。
void main() {
  late Isar isar;
  late IsarService db;

  setUpAll(() async {
    await initIsarCoreForTests();
  });

  setUp(() async {
    isar = await openTestIsar();
    db = IsarService.instance;
    db.initForTest(isar);
  });

  final now = DateTime.now();
  DateTime d(int daysAgo) => DateTime(now.year, now.month, now.day)
      .subtract(Duration(days: daysAgo));

  Future<int> seedOneTime({
    required DateTime date,
    required bool completed,
    String title = '一次性任务',
  }) async {
    final todo = TodoItem.create(title: title, date: date)
      ..isCompleted = completed;
    if (completed) {
      todo.completedAt = DateTime.now();
    }
    return await isar.writeTxn(() async => await isar.todoItems.put(todo));
  }

  Future<int> seedHabit({required DateTime createdOn, String title = '习惯'}) async {
    final todo = TodoItem.create(
      title: title,
      date: createdOn,
      taskType: TaskType.recurring,
    );
    return await isar.writeTxn(() async => await isar.todoItems.put(todo));
  }

  Future<void> completeOn(int todoId, DateTime date) async {
    await isar.writeTxn(() async {
      await isar.dailyCompletions.put(
          DailyCompletion.create(todoId: todoId, completionDate: date));
    });
  }

  group('getTodosForDate 习惯按创建日期过滤', () {
    test('今天创建的习惯不出现在昨天', () async {
      await seedHabit(createdOn: d(0));
      expect((await db.getTodosForDate(d(1))).length, 0);
      expect((await db.getTodosForDate(d(0))).length, 1);
    });

    test('3 天前创建的习惯从创建日起可见，更早日期不可见', () async {
      await seedHabit(createdOn: d(3));
      expect((await db.getTodosForDate(d(4))).length, 0);
      expect((await db.getTodosForDate(d(3))).length, 1);
      expect((await db.getTodosForDate(d(0))).length, 1);
    });

    test('一次性任务只出现在其所属日期', () async {
      await seedOneTime(date: d(1), completed: false);
      expect((await db.getTodosForDate(d(1))).length, 1);
      expect((await db.getTodosForDate(d(0))).length, 0);
      expect((await db.getTodosForDate(d(2))).length, 0);
    });

    test('习惯的完成状态按对应日期的完成记录读取', () async {
      final id = await seedHabit(createdOn: d(2));
      await completeOn(id, d(1));
      final onD1 = await db.getTodosForDate(d(1));
      final onD0 = await db.getTodosForDate(d(0));
      expect(onD1.first.isCompleted, isTrue);
      expect(onD0.first.isCompleted, isFalse);
    });
  });

  group('toggleTodo 每日习惯只在今天可切换', () {
    test('对过去日期切换习惯无任何效果', () async {
      final id = await seedHabit(createdOn: d(5));
      await db.toggleTodo(id, d(1));
      final completions =
          await isar.dailyCompletions.where().findAll();
      expect(completions, isEmpty);
      final todo = await isar.todoItems.get(id);
      expect(todo!.isCompleted, isFalse);
    });

    test('今天切换习惯会写入完成记录，再切换则撤销', () async {
      final id = await seedHabit(createdOn: d(0));
      await db.toggleTodo(id, d(0));
      expect(
          (await isar.dailyCompletions.where().findAll()).length, 1);
      final shown = await db.getTodosForDate(d(0));
      expect(shown.first.isCompleted, isTrue);

      await db.toggleTodo(id, d(0));
      expect(
          (await isar.dailyCompletions.where().findAll()).length, 0);
    });
  });

  group('getCurrentStreak 口径', () {
    test('无任何数据返回 0', () async {
      expect(await db.getCurrentStreak(asOf: now), 0);
    });

    test('连续 3 个有效任务日全部完成 → streak = 3', () async {
      await seedOneTime(date: d(2), completed: true);
      await seedOneTime(date: d(1), completed: true);
      await seedOneTime(date: d(0), completed: true);
      expect(await db.getCurrentStreak(asOf: now), 3);
    });

    test('今天未全部完成不中断（以昨天为终点）', () async {
      await seedOneTime(date: d(2), completed: true);
      await seedOneTime(date: d(1), completed: true);
      await seedOneTime(date: d(0), completed: false);
      expect(await db.getCurrentStreak(asOf: now), 2);
    });

    test('无任务日不计入、不中断', () async {
      await seedOneTime(date: d(5), completed: true);
      // d(4) 无任务
      await seedOneTime(date: d(3), completed: true);
      await seedOneTime(date: d(2), completed: true);
      await seedOneTime(date: d(1), completed: true);
      await seedOneTime(date: d(0), completed: true);
      expect(await db.getCurrentStreak(asOf: now), 5);
    });

    test('过去的有效任务日未全部完成 → 中断', () async {
      await seedOneTime(date: d(2), completed: false);
      await seedOneTime(date: d(1), completed: true);
      await seedOneTime(date: d(0), completed: true);
      expect(await db.getCurrentStreak(asOf: now), 2);
    });

    test('习惯创建之前的日期不参与统计（核心回归用例）', () async {
      // 3 天前有一个已完成的任务；今天创建新习惯并完成今天。
      // 修复前：习惯会出现在 d(3) 且记为未完成 → streak 被截断为 1。
      await seedOneTime(date: d(3), completed: true);
      final habitId = await seedHabit(createdOn: d(0));
      await completeOn(habitId, d(0));
      // d(2)、d(1) 无任务不计入不中断 → streak = 今天 + d(3) = 2
      expect(await db.getCurrentStreak(asOf: now), 2);
    });

    test('习惯只完成一部分的天算中断', () async {
      await seedOneTime(date: d(1), completed: true);
      await seedHabit(createdOn: d(2)); // 习惯在 d(1)、d(0) 都可见但未完成
      // d(0)（今天）未全部完成不计入不中断；d(1) 一次性已完成但习惯未完成
      // → 过去的有效任务日未全部完成 → 中断 → streak = 0
      expect(await db.getCurrentStreak(asOf: now), 0);
    });
  });
}
