import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:todo_app/models/training.dart';
import 'package:todo_app/services/workout_session_service.dart';
import 'package:todo_app/services/training_service.dart';
import 'package:todo_app/services/isar_service.dart';
import 'isar_test_base.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
      'draft survives recreation, second start resumes, clear cannot resurrect',
      () async {
    final service = WorkoutSessionService.forTest();
    final restored = WorkoutSessionService.forTest();
    addTearDown(service.dispose);
    addTearDown(restored.dispose);
    await service.begin(TrainingPlan.create(weekday: 1, name: '胸'), [
      PlanExercise.create(planId: 0, name: '卧推', plannedSets: 3)
        ..plannedReps = 12,
    ]);
    final start = service.startedAt;
    service.updateForm('42', [
      {
        'name': '卧推',
        'sets': [
          {'reps': '10', 'weight': '60', 'duration': '', 'notes': '最后一组'},
        ]
      }
    ]);
    await service.flush();
    await restored.init();
    expect(restored.draft, service.draft);
    await restored.begin(null, []);
    expect(restored.title, '胸');
    expect(restored.startedAt, start);
    service.updateForm('43', []);
    final pendingWrite = service.flush();
    await service.clear();
    await pendingWrite;
    await restored.init();
    expect(restored.active, false);
    expect(
        (await SharedPreferences.getInstance())
            .getString(WorkoutSessionService.draftKey),
        isNull);
  });

  test('damaged nested draft does not crash session restoration', () async {
    SharedPreferences.setMockInitialValues({
      WorkoutSessionService.draftKey: jsonEncode({
        'start': 123,
        'title': '胸',
        'manual': false,
        'minutes': '',
        'exercises': [
          {
            'name': '卧推',
            'sets': [42]
          }
        ]
      })
    });
    final service = WorkoutSessionService.forTest();
    addTearDown(service.dispose);
    await service.init();
    expect(service.active, false);
  });

  test(
      'Android workout timer keeps stable start and stops only its own channel',
      () async {
    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(WorkoutSessionService.channel, (call) async {
      calls.add(call);
      return call.method == 'consumeOpen' ? true : true;
    });
    addTearDown(() => TestDefaultBinaryMessengerBinding
        .instance.defaultBinaryMessenger
        .setMockMethodCallHandler(WorkoutSessionService.channel, null));
    final service = WorkoutSessionService.forTest(android: true);
    addTearDown(service.dispose);
    await service.init();
    await service.begin(null, []);
    final start = service.startedAt!.millisecondsSinceEpoch;
    await service.setOverlayEnabled(true);
    expect(calls.last.method, 'sync');
    expect(calls.last.arguments['startEpochMs'], start);
    expect(calls.last.arguments['overlay'], true);
    var opens = 0;
    service.onOpenRequested = () => opens++;
    await service.consumeOpenRequest();
    expect(opens, 1);
    await service.clear();
    expect(calls.last.method, 'stop');
    await service.begin(null, [], manual: true);
    expect(calls.last.method, 'stop');
    await service.clear();
  });

  test(
      'eight-day chest/rest/back/rest/shoulder/rest/leg/rest never folds weekdays',
      () async {
    IsarService.instance.initForTest(await openTestIsar());
    final start = DateTime(2026, 10, 12);
    final names = ['胸', '休息', '背', '休息', '肩', '休息', '腿', '休息'];
    await TrainingService.instance
        .saveCycle(name: '八日循环', startDate: start, days: [
      for (var i = 0; i < 8; i++)
        TrainingCycleDay(name: names[i], isRestDay: i.isOdd, exercises: [])
    ]);
    for (var i = -1; i < 32; i++) {
      final plans = await TrainingService.instance
          .getPlansForDate(start.add(Duration(days: i)));
      if (i < 0 || i.isOdd) {
        expect(plans, isEmpty, reason: 'day $i');
      } else {
        expect(plans.map((p) => p.name).toList(), [names[i % 8]],
            reason: 'day $i');
      }
    }
  });

  test('retry after a saved session leaves one log and one set', () async {
    IsarService.instance.initForTest(await openTestIsar());
    final start = DateTime(2026, 10, 17, 10, 34);
    for (var i = 0; i < 2; i++) {
      await TrainingService.instance.saveWorkout(
          log: WorkoutLog.create(date: start, title: '胸', startedAt: start),
          sets: [WorkoutSet.create(workoutId: 0, exerciseName: '卧推', reps: 12)],
          deduplicateSession: true);
    }
    final logs = await TrainingService.instance.getWorkoutHistory();
    expect(logs, hasLength(1));
    expect(await TrainingService.instance.getSetsForWorkout(logs.single.id),
        hasLength(1));
  });
}
