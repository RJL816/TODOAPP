import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:todo_app/ui/food_estimation_panel.dart';
import 'package:todo_app/services/food_estimation_service.dart';
import 'package:todo_app/pages/training_cycle_dialog.dart';
import 'package:todo_app/pages/diet_page.dart';
import 'package:todo_app/services/isar_service.dart';
import 'package:todo_app/services/fat_loss_service.dart';
import 'isar_test_base.dart';
import 'package:todo_app/services/training_service.dart';
import 'package:todo_app/models/training.dart';

void main() {
  testWidgets('body profile and daily energy comparison fit a 320px phone',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.runAsync(() async {
      IsarService.instance.initForTest(await openTestIsar());
      await FatLossService.instance.saveProfile(const FatLossProfile(
          gender: 'm',
          age: 25,
          heightCm: 175,
          weightKg: 70,
          activityFactor: 1.2,
          deficit: 300));
    });
    tester.view.physicalSize = const Size(320, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester
        .pumpWidget(const MaterialApp(home: Scaffold(body: DietPage())));
    for (var i = 0;
        i < 30 && find.textContaining('全天预计消耗').evaluate().isEmpty;
        i++) {
      await tester.runAsync(
          () async => Future<void>.delayed(const Duration(milliseconds: 100)));
      await tester.pump(const Duration(milliseconds: 20));
    }
    expect(find.textContaining('全天预计消耗'), findsOneWidget);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.textContaining('全天预计消耗'));
    expect(find.textContaining('摄入尚未完整记录'), findsOneWidget);
    expect(tester.takeException(), isNull);
    final log = WorkoutLog.create(
        date: DateTime.now(), title: '手动训练', startedAt: DateTime.now())
      ..estimatedMinutes = 20;
    await tester
        .runAsync(() => TrainingService.instance.saveWorkout(log: log, sets: [
              WorkoutSet.create(
                  workoutId: 0,
                  exerciseName: '深蹲',
                  reps: 12,
                  weightGrams: 60000)
            ]));
    final changed = find.textContaining('已完成训练净消耗约 ${log.estimatedCalories}');
    for (var i = 0; i < 30 && changed.evaluate().isEmpty; i++) {
      await tester.runAsync(
          () async => Future<void>.delayed(const Duration(milliseconds: 100)));
      await tester.pump(const Duration(milliseconds: 20));
    }
    expect(changed, findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('offline food estimate fits phone and waits for explicit tap',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(320, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final food = TextEditingController(text: '米饭 150g');
    addTearDown(food.dispose);
    FoodEstimate? result;
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: SingleChildScrollView(
                child: FoodEstimationPanel(
                    foodController: food,
                    onEstimate: (value) => result = value,
                    onBusy: (_) {})))));
    expect(result, isNull);
    await tester.tap(find.text('按名称估算'));
    await tester.pumpAndSettle();
    expect(result?.calories, 174);
    expect(find.textContaining('离线常见食物参考'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('training cycle exposes set count, reps and kg on narrow screen',
      (tester) async {
    tester.view.physicalSize = const Size(320, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: Builder(
                builder: (context) => TextButton(
                    onPressed: () => showDialog(
                        context: context,
                        builder: (_) => const TrainingCycleDialog()),
                    child: const Text('打开'))))));
    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('添加动作').first);
    await tester.tap(find.text('添加动作').first);
    await tester.pumpAndSettle();
    expect(find.text('每组次数（可选）'), findsOneWidget);
    expect(find.text('重量 kg（可选）'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  });
}
