import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:todo_app/models/training.dart';
import 'package:todo_app/services/workout_session_service.dart';
import 'package:todo_app/services/training_service.dart';
import 'package:todo_app/services/isar_service.dart';
import 'package:todo_app/services/course_service.dart';
import 'package:todo_app/pages/fitness_page.dart';
import 'package:todo_app/pages/plan_page.dart';
import 'isar_test_base.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  testWidgets(
      'weekly page renders just the real cycle day, including next week',
      (tester) async {
    await tester.runAsync(() async {
      final isar = await openTestIsar();
      IsarService.instance.initForTest(isar);
      await CourseService.instance.init(isar);
      await CourseService.instance.ensureActiveSemester();
      await CourseService.instance.getTimeConfigs();
      final now = DateTime.now();
      final start = DateTime(now.year, now.month, now.day)
          .subtract(Duration(days: now.weekday - 1));
      await TrainingService.instance
          .saveCycle(name: '十四日', startDate: start, days: [
        for (var i = 1; i <= 14; i++)
          TrainingCycleDay(name: '循环第$i天', isRestDay: false, exercises: [])
      ]);
    });
    await tester.runAsync(() async {
      await tester
          .pumpWidget(const MaterialApp(home: Scaffold(body: PlanPage())));
      await Future<void>.delayed(const Duration(milliseconds: 500));
    });
    final n = DateTime.now().weekday;
    for (var i = 0; i < 60 && find.text('循环第$n天').evaluate().isEmpty; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 100)));
      await tester.pump(const Duration(milliseconds: 20));
    }
    expect(tester.takeException(), isNull);
    expect(find.text('计划暂时无法加载。'), findsNothing);
    expect(find.text('循环第$n天'), findsOneWidget);
    expect(find.text('循环第${n + 7}天'), findsNothing);
    expect(find.text('训练计划'), findsOneWidget);
    await tester.runAsync(() async {
      await tester.tap(find.byTooltip('下一周'));
      await Future<void>.delayed(const Duration(milliseconds: 500));
    });
    for (var i = 0;
        i < 60 && find.text('循环第${n + 7}天').evaluate().isEmpty;
        i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 100)));
      await tester.pump(const Duration(milliseconds: 20));
    }
    expect(find.text('循环第${n + 7}天'), findsOneWidget);
    expect(find.text('循环第$n天'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('back keeps the workout and edited fields, discard is explicit',
      (tester) async {
    final service = WorkoutSessionService.instance;
    await service.clear();
    await service.begin(TrainingPlan.create(weekday: 1, name: '胸'), [
      PlanExercise.create(planId: 0, name: '卧推', plannedSets: 1)
        ..plannedReps = 12,
    ]);
    tester.view.physicalSize = const Size(320, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: Builder(
                builder: (context) => TextButton(
                    onPressed: () => openActiveWorkout(context),
                    child: const Text('恢复训练'))))));
    await tester.tap(find.text('恢复训练'));
    await tester.pumpAndSettle();
    final reps = find.widgetWithText(TextField, '12');
    await tester.enterText(reps, '9');
    await tester.tap(find.byTooltip('收起并保留训练'));
    await tester.pumpAndSettle();
    expect(service.active, true);
    expect(find.text('放弃这次训练？'), findsNothing);
    await tester.tap(find.text('恢复训练'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(TextField, '9'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.ensureVisible(find.text('放弃本次训练'));
    await tester.tap(find.text('放弃本次训练'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('放弃训练'));
    await tester.pumpAndSettle();
    expect(service.active, false);
    expect(find.text('恢复训练'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
}
