import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:todo_app/models/todo_item.dart';
import 'package:todo_app/pages/pomodoro_page.dart';
import 'package:todo_app/services/pomodoro_service.dart';
import 'package:todo_app/ui/app_theme.dart';

void main() {
  for (final width in [320.0, 390.0, 768.0, 960.0, 1440.0]) {
    testWidgets('focus room fits a $width px window', (tester) async {
      SharedPreferences.setMockInitialValues({});
      tester.view.physicalSize = Size(width, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(MaterialApp(
        theme: buildAppTheme(),
        home: Scaffold(
          body: PomodoroPage(onExit: () {}, onOpenTodo: () {}),
        ),
      ));
      await tester.pumpAndSettle();
      expect(find.textContaining('今日待办 ·'), findsOneWidget);
      expect(find.text('开始专注'), findsOneWidget);
      await tester.tap(find.textContaining('今日待办 ·'));
      await tester.pumpAndSettle();
      expect(find.text('今日待办'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('running timer keeps controls within a narrow window',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final service = PomodoroService.instance;
    service.runningPhase = PomodoroRunPhase.focus;
    service.targetEndTime = DateTime.now().add(const Duration(minutes: 25));
    addTearDown(() {
      service.runningPhase = null;
      service.targetEndTime = null;
    });
    tester.view.physicalSize = const Size(390, 760);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(MaterialApp(
      theme: buildAppTheme(),
      home: const Scaffold(body: PomodoroPage()),
    ));
    await tester.pumpAndSettle();
    expect(find.text('暂停'), findsOneWidget);
    expect(find.textContaining('今日待办 ·'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('immersive running timer fits a narrow window and can exit',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final service = PomodoroService.instance;
    service.runningPhase = PomodoroRunPhase.focus;
    service.targetEndTime = DateTime.now().add(const Duration(minutes: 40));
    addTearDown(() {
      service.runningPhase = null;
      service.targetEndTime = null;
    });
    tester.view.physicalSize = const Size(390, 760);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(MaterialApp(
      theme: buildAppTheme(),
      home: const Scaffold(body: PomodoroPage()),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('进入沉浸模式'));
    await tester.pumpAndSettle();
    expect(find.text('暂停'), findsOneWidget);
    expect(find.text('退出沉浸'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('退出沉浸'));
    await tester.pumpAndSettle();
    expect(find.textContaining('今日待办 ·'), findsOneWidget);
  });

  testWidgets('focus immersion does not change Windows fullscreen state',
      (tester) async {
    if (!Platform.isWindows) return;
    SharedPreferences.setMockInitialValues({});
    var nativeFullScreenCalls = 0;
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    const channel = MethodChannel('window_manager');
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'setFullScreen') nativeFullScreenCalls++;
      return null;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));

    await tester.pumpWidget(MaterialApp(
      theme: buildAppTheme(),
      home: const Scaffold(body: PomodoroPage()),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text('沉浸模式'));
    await tester.pumpAndSettle();
    expect(find.text('退出沉浸'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.textContaining('今日待办 ·'), findsNothing);
    expect(nativeFullScreenCalls, 0);
    await tester.tap(find.text('退出沉浸'));
    await tester.pumpAndSettle();
    expect(find.text('沉浸模式'), findsOneWidget);
    expect(nativeFullScreenCalls, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('focus immersion button follows the parent layout state',
      (tester) async {
    if (!Platform.isWindows) return;
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    var focusImmersive = false;
    var toggleCount = 0;
    await tester.pumpWidget(MaterialApp(
      theme: buildAppTheme(),
      home: StatefulBuilder(builder: (context, setParentState) {
        return Scaffold(
          body: PomodoroPage(
            focusImmersive: focusImmersive,
            onFocusImmersiveChanged: (value) async {
              setParentState(() => focusImmersive = value);
              toggleCount++;
            },
          ),
        );
      }),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text('沉浸模式'));
    await tester.pumpAndSettle();
    expect(focusImmersive, isTrue);
    expect(find.text('退出沉浸'), findsOneWidget);

    await tester.tap(find.text('退出沉浸'));
    await tester.pumpAndSettle();
    expect(focusImmersive, isFalse);
    expect(toggleCount, 2);
    expect(find.text('沉浸模式'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('glass todo panel shows tasks and handles completion',
      (tester) async {
    final todo = TodoItem.create(title: '阅读章节', date: DateTime.now());
    TodoItem? tapped;
    await tester.pumpWidget(MaterialApp(
      theme: buildAppTheme(),
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 320,
            child: FocusTodoBoard(
              todos: [todo],
              associatedTodoId: null,
              onToggle: (value) => tapped = value,
            ),
          ),
        ),
      ),
    ));
    expect(find.text('阅读章节'), findsOneWidget);
    expect(find.text('1 项待处理'), findsOneWidget);
    await tester.tap(find.text('阅读章节'));
    expect(tapped, same(todo));
    expect(tester.takeException(), isNull);
  });
}
