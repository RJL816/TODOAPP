import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:todo_app/models/memo.dart';
import 'package:todo_app/pages/memo_page.dart';
import 'package:todo_app/services/memo_service.dart';
import 'package:todo_app/ui/app_theme.dart';
import 'package:todo_app/ui/ambient_backdrop.dart';
import 'package:todo_app/ui/ambient_reading_theme.dart';
import 'package:todo_app/ui/live_markdown_editor.dart';
import 'isar_test_base.dart';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final isar = await openTestIsar();
    MemoService.instance.init(isar);
    await MemoService.instance.addMemo(Memo.create(
        title: '阅读笔记',
        content: '## 今天的想法\n\n把读到的内容，用自己的话记下来。\n\n留一点时间，整理问题和下一步。'));
    await MemoService.instance
        .addMemo(Memo.create(title: '本周安排', content: '整理资料，完成阅读。'));
  });

  for (final width in [320.0, 390.0, 800.0, 1220.0]) {
    for (final dark in [false, true]) {
      testWidgets('memo workspace $width dark=$dark', (tester) async {
        tester.view.physicalSize = Size(width, 800);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await (FontLoader(AppTypography.sans)
              ..addFont(rootBundle.load('assets/fonts/MiSans-Regular-subset.ttf'))
              ..addFont(rootBundle.load('assets/fonts/MiSans-Medium-subset.ttf'))
              ..addFont(
                  rootBundle.load('assets/fonts/MiSans-Semibold-subset.ttf'))
              ..addFont(rootBundle.load('assets/fonts/MiSans-Bold-subset.ttf')))
            .load();
        await (FontLoader('MaterialIcons')
              ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf')))
            .load();
        await tester.runAsync(() async {
          await tester.pumpWidget(MaterialApp(
              theme: buildAppTheme(),
              home: RepaintBoundary(
                key: const Key('memo-preview'),
                child: Scaffold(
                    body: Stack(children: [
                  Positioned.fill(
                      child: AmbientBackdrop(sceneIndex: dark ? 1 : 0)),
                  AmbientReadingTheme(enabled: dark, child: const MemoPage()),
                ])),
              )));
          await Future<void>.delayed(const Duration(milliseconds: 250));
          await precacheImage(
              AssetImage(AmbientBackdrop.sceneAssets[dark ? 1 : 0]),
              tester.element(find.byType(MemoPage)));
        });
        await tester.pumpAndSettle();
        await tester.tap(find.text('阅读笔记').first);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.byType(TextField), findsWidgets);
        if (width >= 780) {
          expect(find.byKey(const Key('memo-workspace')), findsOneWidget);
          await tester.tap(find.byTooltip('收起列表'));
          await tester.pumpAndSettle();
          expect(find.byTooltip('显示列表'), findsOneWidget);
          await tester.tap(find.byTooltip('显示列表'));
          await tester.pumpAndSettle();
        }
        expect(find.text('今天的想法'), findsOneWidget);
        await tester.tap(width < 780 ? find.byTooltip('源码') : find.text('源码'));
        await tester.pumpAndSettle();
        expect(find.text('## 今天的想法\n\n把读到的内容，用自己的话记下来。\n\n留一点时间，整理问题和下一步。'),
            findsOneWidget);
        await tester
            .tap(width < 780 ? find.byTooltip('实时预览') : find.text('实时预览'));
        await tester.pumpAndSettle();
        expect(find.text('今天的想法'), findsOneWidget);
        expect(tester.takeException(), isNull);
        if (const bool.fromEnvironment('SAVE_UI_PREVIEWS')) {
          await tester.runAsync(() async {
            final boundary = tester.renderObject<RenderRepaintBoundary>(
                find.byKey(const Key('memo-preview')));
            final image = await boundary.toImage();
            final bytes =
                await image.toByteData(format: ui.ImageByteFormat.png);
            final output = File(
                'build/ui-preview/memo-${width.toInt()}-${dark ? 'dark' : 'light'}.png');
            await output.parent.create(recursive: true);
            await output.writeAsBytes(bytes!.buffer.asUint8List());
            image.dispose();
          });
        }
        await tester.pumpWidget(const SizedBox());
      });
    }
  }

  testWidgets('switching notes immediately saves the edited block',
      (tester) async {
    tester.view.physicalSize = const Size(900, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.runAsync(() async {
      await tester.pumpWidget(MaterialApp(
        theme: buildAppTheme(),
        home: const Scaffold(body: MemoPage()),
      ));
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    await tester.pumpAndSettle();
    await tester.tap(find.text('阅读笔记').first);
    await tester.pumpAndSettle();
    expect(find.text('今天的想法'), findsOneWidget);
    await tester.tap(find.byKey(const Key('markdown-preview-block-0')));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const Key('markdown-active-block')), '## 修改后的标题');
    await tester.pump();
    expect(
        tester
            .widget<LiveMarkdownEditor>(find.byType(LiveMarkdownEditor))
            .controller
            .text,
        startsWith('## 修改后的标题\n\n'));
    await tester.runAsync(() async {
      await tester.tap(find.text('本周安排').first);
      await Future<void>.delayed(const Duration(seconds: 1));
    });
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<LiveMarkdownEditor>(find.byType(LiveMarkdownEditor))
            .controller
            .text,
        '整理资料，完成阅读。');
    await tester.runAsync(() async {
      final notes = await MemoService.instance.getAllMemos();
      final edited = notes.firstWhere((note) => note.title == '阅读笔记');
      expect(edited.content, startsWith('## 修改后的标题\n\n'));
    });
  });
}
