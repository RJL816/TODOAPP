import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:todo_app/pages/expense_page.dart';
import 'package:todo_app/pages/more_page.dart';
import 'package:todo_app/pages/record_hub_page.dart';
import 'package:todo_app/pages/training_cycle_dialog.dart';
import 'package:todo_app/ui/app_theme.dart';
import 'package:todo_app/ui/ambient_reading_theme.dart';
import 'package:todo_app/ui/page_frame.dart';

void main() {
  for (final width in [320.0, 390.0, 768.0]) {
    testWidgets('record hub fits $width px and opens summary', (tester) async {
      tester.view.physicalSize = Size(width, 740);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var summaryOpened = false;
      await tester.pumpWidget(MaterialApp(
        theme: buildAppTheme(),
        home: Scaffold(
          body: RecordHubPage(
            darkBackground: true,
            onOpenMemo: () {},
            onOpenFitness: () {},
            onOpenDiet: () {},
            onOpenExpense: () {},
            onOpenSummary: () => summaryOpened = true,
          ),
        ),
      ));
      await tester.ensureVisible(find.text('生活总结'));
      await tester.tap(find.text('生活总结'));
      await tester.pump();
      expect(summaryOpened, isTrue);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('training cycle form stays readable on a phone', (tester) async {
    tester.view.physicalSize = const Size(390, 740);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
      theme: buildAppTheme(),
      home: const Scaffold(
        body: AmbientReadingTheme(
          enabled: true,
          child: TrainingCycleDialog(),
        ),
      ),
    ));
    await tester.pump();
    expect(find.text('创建训练循环'), findsOneWidget);
    expect(find.text('保存循环'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  for (final (width, expected) in [
    (390.0, 390.0),
    (960.0, 960.0),
    (1440.0, 1180.0),
  ]) {
    testWidgets('page content is centered without a sheet at $width px',
        (tester) async {
      tester.view.physicalSize = Size(width, 740);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(MaterialApp(
        theme: buildAppTheme(),
        home: const Scaffold(
          body: PageFrame(
            child: ColoredBox(key: Key('page-body'), color: Colors.white),
          ),
        ),
      ));
      expect(tester.getSize(find.byKey(const Key('page-body'))).width,
          closeTo(expected, 0.1));
      expect(tester.takeException(), isNull);
    });
  }

  for (final width in [320.0, 390.0, 768.0, 1440.0]) {
    testWidgets('More page fits a $width px window and opens modules',
        (tester) async {
      tester.view.physicalSize = Size(width, 740);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      var opened = '';
      await tester.pumpWidget(MaterialApp(
        theme: buildAppTheme(),
        home: Scaffold(
            body: MorePage(
          onOpenMemo: () => opened = 'memo',
          onOpenPomodoro: () => opened = 'pomodoro',
          onOpenFitness: () => opened = 'fitness',
          onOpenDiet: () => opened = 'diet',
          onOpenExpense: () => opened = 'expense',
        )),
      ));
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(find.text('消费记录'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('消费记录'));
      await tester.pump();
      expect(opened, 'expense');
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('More page also fits enlarged text on a narrow window',
      (tester) async {
    tester.view.physicalSize = const Size(390, 740);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
      theme: buildAppTheme(),
      home: MediaQuery(
        data: const MediaQueryData(textScaler: TextScaler.linear(1.5)),
        child: Scaffold(
            body: MorePage(
          onOpenMemo: () {},
          onOpenPomodoro: () {},
          onOpenFitness: () {},
          onOpenDiet: () {},
          onOpenExpense: () {},
        )),
      ),
    ));
    await tester.ensureVisible(find.text('消费记录'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  for (final width in [390.0, 1180.0]) {
    testWidgets('Expense page layout fits a $width px window', (tester) async {
      tester.view.physicalSize = Size(width, 740);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(MaterialApp(
        theme: buildAppTheme(),
        home: const Scaffold(body: ExpensePage()),
      ));
      await tester.pumpAndSettle();
      expect(find.text('记一笔'), findsOneWidget);
      expect(find.textContaining('先记下一笔'), findsOneWidget);
      expect(find.text('分类去向'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }
}
