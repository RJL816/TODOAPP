import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:isar/isar.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:todo_app/main.dart';
import 'package:todo_app/pages/focus_insights_page.dart';
import 'package:todo_app/pages/more_page.dart';
import 'package:todo_app/models/daily_completion.dart';
import 'package:todo_app/models/diet_log.dart';
import 'package:todo_app/models/expense.dart';
import 'package:todo_app/models/pomodoro_session.dart';
import 'package:todo_app/models/todo_item.dart';
import 'package:todo_app/models/training.dart';
import 'package:todo_app/services/course_service.dart';
import 'package:todo_app/services/isar_service.dart';
import 'package:todo_app/services/memo_service.dart';
import 'package:todo_app/services/pomodoro_service.dart';
import 'package:todo_app/ui/app_theme.dart';
import 'package:todo_app/ui/glass_panel.dart';
import 'package:todo_app/ui/frosted_form_dialog.dart';

import 'isar_test_base.dart';

/// 首页视觉预览：注入示例数据后把 TodoHomePage 渲染为 PNG。
/// 运行：flutter test test/home_visual_preview_test.dart
///      --dart-define=SAVE_UI_PREVIEWS=true
/// 产物：build/ui-preview/home-*.png

void _mockNativeChannels() {
  // 原生通道兜底：窗口 / 自启动查询在测试 VM 中没有插件实现
  Future<Object?>? handler(MethodCall call) async {
    switch (call.method) {
      case 'startDragging':
        _windowDragCalls++;
        return null;
      case 'isMaximized':
      case 'isFullScreen':
      case 'isMinimized':
      case 'isVisible':
      case 'isEnabled':
        return false;
      case 'getSize':
        return <double>[1440, 900];
      case 'getPosition':
        return <double>[0, 0];
      default:
        return null;
    }
  }

  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(const MethodChannel('window_manager'), handler);
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
          const MethodChannel('com.todo.app/autostart'), handler);
}

Isar? _sharedDb;
int _windowDragCalls = 0;

void main() {
  Future<void> pumpHome(
    WidgetTester tester, {
    required Map<String, Object> prefs,
    required Size size,
    required String fileName,
    String? navigateTo,
  }) async {
    SharedPreferences.setMockInitialValues(prefs);
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    _mockNativeChannels();

    debugPrint('home-preview: channels mocked');
    // Isar 原生库使用 RawReceivePort 回调，必须跑在真实事件循环（runAsync）里，
    // 否则会与 testWidgets 的 FakeAsync 死锁；因此也不做 close 清理
    //（close 同样是原生异步调用，且 Isar 3 不允许同 isolate 打开第二个实例，
    // 四个用例复用同一实例，每例开始前清空）。
    final isar = (await tester.runAsync<Isar>(() async {
      await initIsarCoreForTests();
      if (_sharedDb == null || !_sharedDb!.isOpen) {
        final dir =
            await Directory.systemTemp.createTemp('todoapp_home_preview');
        _sharedDb = await Isar.open(appSchemas, directory: dir.path);
      } else {
        await _sharedDb!.writeTxn(() async => _sharedDb!.clear());
      }
      final db = _sharedDb!;
      IsarService.instance.initForTest(db);
      await CourseService.instance.init(db);
      MemoService.instance.init(db);
      await PomodoroService.instance.init();
      return db;
    }))!;
    debugPrint('home-preview: isar + services ready');

    // ---- 示例数据 ----
    await tester.runAsync(() async {
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final todos = <TodoItem>[
        TodoItem.create(
            title: '整理文献综述的第三章初稿', date: today, category: TaskCategory.study)
          ..deadline = DateTime(now.year, now.month, now.day, 18, 0),
        TodoItem.create(
            title: '每日阅读 30 页',
            date: today,
            taskType: TaskType.recurring,
            category: TaskCategory.life),
        TodoItem.create(
            title: '回导师邮件：确认开题时间', date: today, category: TaskCategory.work),
        TodoItem.create(
            title: '晚上跑步 5 公里', date: today, category: TaskCategory.health),
        TodoItem.create(
            title: '背 50 个单词',
            date: today,
            taskType: TaskType.recurring,
            category: TaskCategory.study),
      ];
      final ids = await isar.writeTxn(() async {
        return await isar.todoItems.putAll(todos);
      });
      // 两个习惯在今天完成（习惯状态存 DailyCompletion 表）
      final done1 = todos[1]
        ..isCompleted = true
        ..completedAt = DateTime(now.year, now.month, now.day, 8, 20);
      final done2 = todos[4]
        ..isCompleted = true
        ..completedAt = DateTime(now.year, now.month, now.day, 7, 45);
      await isar.writeTxn(() async {
        await isar.todoItems.putAll([done1, done2]);
        await isar.dailyCompletions.putAll([
          DailyCompletion()
            ..todoId = ids[1]
            ..date = today
            ..timestamp = DateTime(now.year, now.month, now.day, 8, 20)
                .millisecondsSinceEpoch,
          DailyCompletion()
            ..todoId = ids[4]
            ..date = today
            ..timestamp = DateTime(now.year, now.month, now.day, 7, 45)
                .millisecondsSinceEpoch,
        ]);
        await isar.pomodoroSessions.put(PomodoroSession.create(
          startedAt: DateTime(now.year, now.month, now.day, 9, 30),
          endedAt: DateTime(now.year, now.month, now.day, 10, 10),
          durationSeconds: 40 * 60,
          type: PomodoroPhaseType.focus,
          taskTitle: '文献综述',
        ));
        await isar.workoutLogs.put(WorkoutLog.create(
          date: today,
          title: '晨跑 · 自由训练',
          startedAt: DateTime(now.year, now.month, now.day, 7, 15),
          endedAt: DateTime(now.year, now.month, now.day, 7, 50),
        ));
        await isar.dietLogs.putAll([
          DietLog.create(
              date: today, mealType: MealType.breakfast, food: '豆浆 + 全麦面包'),
          DietLog.create(
              date: today,
              mealType: MealType.lunch,
              food: '番茄牛肉饭',
              calories: 620),
        ]);
        await isar.expenses.put(Expense.create(
          date: now,
          amountCents: 1280,
          category: '餐饮',
          paymentMethod: '微信支付',
          counterparty: '第二食堂',
          product: '午餐',
        ));
      });
    });

    debugPrint('home-preview: data seeded');

    // ---- 字体与背景图 ----
    for (final family in [AppTypography.sans, AppTypography.serif]) {
      final assets = family == AppTypography.sans
          ? const [
              'assets/fonts/MiSans-Regular-subset.ttf',
              'assets/fonts/MiSans-Medium-subset.ttf',
              'assets/fonts/MiSans-Semibold-subset.ttf',
              'assets/fonts/MiSans-Bold-subset.ttf',
            ]
          : const ['assets/fonts/NotoSerifSC-Headings.ttf'];
      final font = FontLoader(family);
      for (final asset in assets) {
        font.addFont(rootBundle.load(asset));
      }
      await font.load();
    }
    final icons = FontLoader('MaterialIcons')
      ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await icons.load();
    debugPrint('home-preview: fonts loaded');

    await tester.pumpWidget(MaterialApp(
      title: '学习桌',
      theme: buildAppTheme(),
      home: const RepaintBoundary(key: Key('preview'), child: TodoHomePage()),
    ));
    debugPrint('home-preview: pumped widget');
    // initState 发起的 Isar 异步查询在真实事件循环上完成，
    // 需要"真实延时 + pump"交替冲刷，让 setState 结果重绘出来
    for (var i = 0; i < 20; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 150)));
      await tester.pump(const Duration(milliseconds: 50));
    }
    debugPrint('home-preview: async loads flushed');
    await tester.runAsync(() async {
      for (final asset in [
        'assets/backgrounds/alpine_noon.png',
        'assets/backgrounds/alpine_dawn.png',
        'assets/backgrounds/alpine_dusk.png',
        'assets/backgrounds/alpine_night.png',
      ]) {
        await precacheImage(
            AssetImage(asset), tester.element(find.byType(TodoHomePage)));
      }
    });
    debugPrint('home-preview: images precached');
    if (navigateTo != null) {
      // 优先点底部导航项的文本：首页分类 chip 可能与导航标签同名（如"生活"）
      final navText = find.descendant(
          of: find.byType(BottomNavigationBar), matching: find.text(navigateTo));
      await tester.tap(navText.evaluate().isNotEmpty
          ? navText.first
          : find.text(navigateTo).hitTestable().first);
      await tester.pump();
    }
    // 有界 pump：某些常驻页面可能持续排帧，pumpAndSettle 会挂起
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    debugPrint('home-preview: frames settled, capturing');

    if (const bool.fromEnvironment('SAVE_UI_PREVIEWS')) {
      await tester.runAsync(() async {
        final boundary = tester.renderObject<RenderRepaintBoundary>(
            find.byKey(const Key('preview')));
        final image = await boundary.toImage();
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        final output = File('build/ui-preview/$fileName');
        await output.parent.create(recursive: true);
        await output.writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
      });
    }
  }

  testWidgets('home preview · daylight desktop', (tester) async {
    await pumpHome(tester,
        prefs: {
          'show_ambient_background': true,
          'ambient_scene_index': 0,
          'ambient_scene_auto': false,
          'ambient_shade': 0.10,
        },
        size: const Size(1440, 900),
        fileName: 'home-daylight-1440.png');
    expect(find.text('开始专注'), findsOneWidget);
    final hero = tester.getRect(find
        .ancestor(
          of: find.text('接下来做'),
          matching: find.byType(GlassPanel),
        )
        .first);
    final tasks = tester.getRect(find
        .ancestor(
          of: find.text('待处理'),
          matching: find.byType(GlassPanel),
        )
        .first);
    expect((hero.left - tasks.left).abs(), lessThan(1));
    expect((hero.right - tasks.right).abs(), lessThan(1));

    await tester.tap(find.byTooltip('设置').first);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.ensureVisible(find.text('玻璃通透度'));
    await tester.drag(find.byType(Slider).at(1), const Offset(90, 0));
    await tester.pump();
    expect(GlassTuning.clarity.value, greaterThan(.55));
    final savedClarity = await tester.runAsync(() async =>
        (await SharedPreferences.getInstance()).getDouble('glass_clarity'));
    expect(savedClarity, closeTo(GlassTuning.clarity.value, .001));

    Navigator.of(tester.element(find.text('玻璃通透度'))).pop();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('专注').hitTestable().first);
    await tester.pump();
    await tester.tap(find.byTooltip('今日专注统计'));
    for (var i = 0; i < 12; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 100)));
      await tester.pump(const Duration(milliseconds: 60));
    }
    expect(find.byType(FocusInsightsPage), findsOneWidget);
    _windowDragCalls = 0;
    await tester.drag(find.text('专注时间'), const Offset(90, 0));
    await tester.pump();
    expect(_windowDragCalls, greaterThan(0));
    if (const bool.fromEnvironment('SAVE_UI_PREVIEWS')) {
      await tester.runAsync(() async {
        final image =
            await captureImage(tester.element(find.byType(FocusInsightsPage)));
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        final output =
            File('build/ui-preview/focus-insights-daylight-1440.png');
        await output.parent.create(recursive: true);
        await output.writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
      });
    }
    tester.view.physicalSize = const Size(390, 844);
    await tester.pump(const Duration(milliseconds: 300));
    expect(tester.getTopLeft(find.text('时间，花在了哪里')).dy,
        greaterThan(kToolbarHeight));
    expect(tester.takeException(), isNull);
  });

  testWidgets('compact desktop sidebar keeps all routes accessible',
      (tester) async {
    await pumpHome(tester,
        prefs: {
          'show_ambient_background': true,
          'ambient_scene_index': 1,
          'ambient_scene_auto': false,
        },
        size: const Size(1080, 760),
        fileName: 'home-compact-sidebar-1080.png');
    expect(find.byTooltip('展开侧栏'), findsOneWidget);
    await tester.tap(find.byTooltip('展开侧栏'));
    await tester.pump();
    expect(find.text('核心视图'), findsOneWidget);
    expect(find.text('回顾与数据'), findsOneWidget);
    expect(find.text('月度总结'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('home preview · night desktop', (tester) async {
    await pumpHome(tester,
        prefs: {
          'show_ambient_background': true,
          'ambient_scene_index': 2,
          'ambient_scene_auto': false,
          'ambient_shade': 0.10,
        },
        size: const Size(1440, 900),
        fileName: 'home-night-1440.png');
    expect(find.text('开始专注'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('home preview · dawn desktop', (tester) async {
    await pumpHome(tester,
        prefs: {
          'show_ambient_background': true,
          'ambient_scene_index': 3,
          'ambient_scene_auto': false,
          'ambient_scene_catalog_version': 1,
          'ambient_shade': 0.10,
          'glass_clarity': 1.0,
        },
        size: const Size(1440, 900),
        fileName: 'home-dawn-1440.png');
    expect(find.text('开始专注'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('home preview · dusk mobile', (tester) async {
    await pumpHome(tester,
        prefs: {
          'show_ambient_background': true,
          'ambient_scene_index': 1,
          'ambient_scene_auto': false,
          'ambient_shade': 0.10,
        },
        size: const Size(390, 740),
        fileName: 'home-mobile-390.png');
    expect(find.text('开始专注'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('最近'), 280,
        scrollable: find.byType(Scrollable).first);
    await tester.drag(find.byType(ListView).first, const Offset(0, -320));
    for (var i = 0;
        i < 40 && find.text('正在整理最近的记录…').evaluate().isNotEmpty;
        i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 100)));
      await tester.pump(const Duration(milliseconds: 50));
      // DEBUG-TEMP: 逐帧扫描溢出
      tester.allElements
          .where((e) => e.renderObject is RenderFlex)
          .forEach((e) {
        final ro = e.renderObject as RenderFlex;
        final cw = ro.constraints;
        if (cw.maxWidth.isFinite && ro.size.width > cw.maxWidth + 1) {
          // ignore: avoid_print
          print('DEBUG-FLEX-FRAME$i: w=${ro.size.width} max=${cw.maxWidth} '
              'widget=' + e.widget.toStringShort());
        }
      });
    }
    await tester.scrollUntilVisible(find.textContaining('消费 · 第二食堂'), 100,
        scrollable: find.byType(Scrollable).first);
    expect(find.textContaining('消费 · 第二食堂'), findsOneWidget);
    await tester.scrollUntilVisible(find.textContaining('早餐 · 豆浆'), 100,
        scrollable: find.byType(Scrollable).first);
    expect(find.textContaining('早餐 · 豆浆'), findsOneWidget);
    // DEBUG-TEMP: 扫描所有溢出的 RenderFlex 并打印创建者链
    final ex = tester.takeException();
    if (ex != null) {
      // ignore: avoid_print
      print('DEBUG-OVERFLOW: ' + ex.toString());
      tester.allElements
          .where((e) => e.renderObject is RenderFlex)
          .forEach((e) {
        final ro = e.renderObject as RenderFlex;
        final cw = ro.constraints;
        if (cw.maxWidth.isFinite && ro.size.width > cw.maxWidth + 1) {
          // ignore: avoid_print
          print('DEBUG-OVERFLOW-FLEX: size=${ro.size} max=${cw.maxWidth} '
              'widget=' + e.widget.toStringShort() + ' @' + e.toString());
        }
        if (cw.maxHeight.isFinite && ro.size.height > cw.maxHeight + 1) {
          // ignore: avoid_print
          print('DEBUG-OVERFLOW-H: size.h=${ro.size.height} max.h=${cw.maxHeight} '
              'widget=' + e.widget.toStringShort());
        }
      });
    }
  });

  testWidgets('home preview · paper desktop', (tester) async {
    await pumpHome(tester,
        prefs: {'show_ambient_background': false},
        size: const Size(1440, 900),
        fileName: 'home-paper-1440.png');
    expect(find.text('开始专注'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('record preview · daylight desktop', (tester) async {
    await pumpHome(tester,
        prefs: {
          'show_ambient_background': true,
          'ambient_scene_index': 0,
          'ambient_scene_auto': false,
          'ambient_shade': 0.10,
        },
        size: const Size(1440, 900),
        navigateTo: '生活',
        fileName: 'record-daylight-1440.png');
    expect(find.text('记下来'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('mobile records open a readable glass form', (tester) async {
    tester.view.padding = const FakeViewPadding(top: 32, bottom: 20);
    tester.view.viewPadding = const FakeViewPadding(top: 32, bottom: 20);
    addTearDown(tester.view.resetPadding);
    addTearDown(tester.view.resetViewPadding);
    await pumpHome(tester,
        prefs: {
          'show_ambient_background': true,
          'ambient_scene_index': 0,
          'ambient_scene_auto': false,
        },
        size: const Size(390, 844),
        navigateTo: '生活',
        fileName: 'record-mobile-390.png');
    expect(
        tester.getTopLeft(find.text('学习桌').first).dy, greaterThanOrEqualTo(32));
    expect(find.text('备忘录'), findsWidgets);
    expect(find.text('番茄钟'), findsNothing);
    await tester.tap(find.text('饮食').hitTestable().first);
    for (var i = 0; i < 10; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 100)));
      await tester.pump(const Duration(milliseconds: 50));
    }
    await tester.tap(find.text('记录一餐'));
    await tester.pump(const Duration(milliseconds: 300));
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.byType(FrostedFormDialog), findsOneWidget);
    expect(find.text('添加饮食记录'), findsOneWidget);
    if (const bool.fromEnvironment('SAVE_UI_PREVIEWS')) {
      await tester.runAsync(() async {
        final image =
            await captureImage(tester.element(find.byType(FrostedFormDialog)));
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        final output = File('build/ui-preview/diet-dialog-mobile-390.png');
        await output.parent.create(recursive: true);
        await output.writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
      });
    }
    await tester.tap(find.text('取消'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('生活').hitTestable().first);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('消费记录').hitTestable().first);
    for (var i = 0; i < 8; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 100)));
      await tester.pump(const Duration(milliseconds: 50));
    }
    await tester.tap(find.text('记一笔').hitTestable().first);
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(FrostedFormDialog), findsOneWidget);
    expect(find.text('金额（元）'), findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('生活').hitTestable().first);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('生活总结').hitTestable().first);
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(MorePage), findsOneWidget);
    expect(find.text('工具'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('focus preview · daylight desktop', (tester) async {
    await pumpHome(tester,
        prefs: {
          'show_ambient_background': true,
          'ambient_scene_index': 0,
          'ambient_scene_auto': false,
          'ambient_shade': 0.10,
        },
        size: const Size(1440, 900),
        navigateTo: '专注',
        fileName: 'focus-daylight-1440.png');
    expect(find.text('开始专注'), findsWidgets);
    expect(tester.takeException(), isNull);
  });
}
