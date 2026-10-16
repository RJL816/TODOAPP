import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/testing.dart';
import 'package:http/http.dart' as http;
import 'package:todo_app/models/memo.dart';
import 'package:todo_app/models/todo_item.dart';
import 'package:todo_app/models/training.dart';
import 'package:todo_app/services/ai_service.dart';
import 'package:todo_app/services/isar_service.dart';
import 'package:todo_app/services/training_service.dart';
import 'package:todo_app/services/fat_loss_service.dart';
import 'isar_test_base.dart';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    IsarService.instance.initForTest(await openTestIsar());
  });
  test(
      'unfinished deadline carries across dates, overdue remains, ordinary task stays on its date',
      () async {
    final db = IsarService.instance.isar;
    final date = DateTime(2026, 10, 10);
    await db.writeTxn(() async => db.todoItems.putAll([
          TodoItem.create(
              title: 'DDL',
              date: date,
              deadline: date.add(const Duration(days: 2))),
          TodoItem.create(title: '普通一次性', date: date),
        ]));
    for (final day in [11, 12, 13]) {
      final todos =
          await IsarService.instance.getTodosForDate(DateTime(2026, 10, day));
      expect(todos.map((t) => t.title), ['DDL']);
    }
    expect(await IsarService.instance.getTodosForDate(DateTime(2026, 10, 9)),
        isEmpty);
  });
  test(
      'completed deadline is visible through completion day, historical status remains correct',
      () async {
    final date = DateTime(2026, 10, 10);
    final todo = TodoItem.create(
        title: '提交', date: date, deadline: DateTime(2026, 10, 12))
      ..isCompleted = true
      ..completedAt = DateTime(2026, 10, 13, 12);
    await IsarService.instance.isar
        .writeTxn(() async => IsarService.instance.isar.todoItems.put(todo));
    expect(
        (await IsarService.instance.getTodosForDate(DateTime(2026, 10, 11)))
            .single
            .isCompleted,
        isFalse);
    expect(
        (await IsarService.instance.getTodosForDate(DateTime(2026, 10, 13)))
            .single
            .isCompleted,
        isTrue);
    expect(await IsarService.instance.getTodosForDate(DateTime(2026, 10, 14)),
        isEmpty);
  });
  test(
      'memo consent defaults off; only bounded live memo content reaches context',
      () async {
    expect(AiConfig.fromJson({}).scopeMemos, isFalse);
    final db = IsarService.instance.isar;
    final memo = Memo.create(title: '出行清单', content: '需要带充电器');
    final deleted = Memo.create(title: '删除秘密', content: '不应上传')
      ..isDeleted = true;
    await db.writeTxn(() async => db.memos.putAll([memo, deleted]));
    final client = MockClient((_) async => http.Response('{}', 200));
    addTearDown(client.close);
    final service = AiService.forTest(client);
    const off = AiConfig(
        scopeTodos: false,
        scopeCourses: false,
        scopeFocus: false,
        scopeTraining: false,
        scopeDiet: false,
        scopeFatLoss: false);
    expect(await service.buildTodayContext(off), isNot(contains('充电器')));
    final text =
        await service.buildTodayContext(off.copyWith(scopeMemos: true));
    expect(text, contains('需要带充电器'));
    expect(text, isNot(contains('删除秘密')));
    final roundTrip = AiConfig.fromJson(
        off.copyWith(scopeMemos: true, visionModel: 'vision').toJson());
    expect(roundTrip.scopeMemos, isTrue);
    expect(roundTrip.visionModel, 'vision');
  });
  test(
      'completed training saves calorie and weight snapshot; incomplete and other dates excluded',
      () async {
    const profile = FatLossProfile(
        gender: 'm',
        age: 25,
        heightCm: 175,
        weightKg: 70,
        activityFactor: 1.2,
        deficit: 300);
    await FatLossService.instance.saveProfile(profile);
    final date = DateTime(2026, 10, 16);
    final log = WorkoutLog.create(date: date, title: '训练', startedAt: date)
      ..estimatedMinutes = 20;
    final service = TrainingService.instance;
    await service.saveWorkout(log: log, sets: [
      WorkoutSet.create(
          workoutId: 0, exerciseName: '深蹲', reps: 12, weightGrams: 60000)
    ]);
    final saved = (await service.getCompletedForDate(date)).single;
    expect(saved.estimatedCalories, greaterThan(0));
    expect(saved.calorieWeightKg, 70);
    expect(saved.endedAt, isNull); // 手动补记不伪造实际开始结束区间。
    expect(WorkoutLog.fromJson(saved.toJson()).estimatedCalories,
        saved.estimatedCalories);
    final old = Map<String, dynamic>.from(saved.toJson())
      ..remove('estimatedCalories')
      ..remove('calorieWeightKg')
      ..remove('estimatedMinutes');
    expect(WorkoutLog.fromJson(old).estimatedCalories, isNull);
    await service.saveWorkout(
        log: WorkoutLog.create(
            date: date, title: '未完成', startedAt: date, completed: false),
        sets: []);
    expect(await service.getCompletedForDate(date), hasLength(1));
    expect(await service.getCompletedForDate(date.add(const Duration(days: 1))),
        isEmpty);
  });
}
