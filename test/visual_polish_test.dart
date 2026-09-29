import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:todo_app/pages/pomodoro_page.dart';
import 'package:todo_app/ui/app_theme.dart';
import 'package:todo_app/ui/ambient_backdrop.dart';
import 'package:todo_app/ui/glass_panel.dart';

void main() {
  for (final size in [
    const Size(390, 740),
    const Size(900, 540),
    const Size(1440, 900)
  ]) {
    testWidgets('focus controls stay reachable at $size', (tester) async {
      SharedPreferences.setMockInitialValues({});
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final font = FontLoader(AppTypography.sans)
        ..addFont(rootBundle.load('assets/fonts/MiSans-Regular-subset.ttf'))
        ..addFont(rootBundle.load('assets/fonts/MiSans-Medium-subset.ttf'))
        ..addFont(rootBundle.load('assets/fonts/MiSans-Semibold-subset.ttf'))
        ..addFont(rootBundle.load('assets/fonts/MiSans-Bold-subset.ttf'));
      await font.load();
      final icons = FontLoader('MaterialIcons')
        ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
      await icons.load();
      await tester.pumpWidget(MaterialApp(
        theme: buildAppTheme(),
        home: const RepaintBoundary(
            key: Key('preview'), child: Scaffold(body: PomodoroPage())),
      ));
      await tester.runAsync(() async {
        await precacheImage(
            const AssetImage('assets/backgrounds/daylight_study_final.png'),
            tester.element(find.byType(PomodoroPage)));
      });
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('开始专注'));
      await tester.pumpAndSettle();
      expect(find.text('开始专注').hitTestable(), findsOneWidget);
      expect(find.textContaining('今日待办 ·').hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
      if (const bool.fromEnvironment('SAVE_UI_PREVIEWS')) {
        await tester.runAsync(() async {
          final boundary = tester.renderObject<RenderRepaintBoundary>(
              find.byKey(const Key('preview')));
          final image = await boundary.toImage();
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          final output =
              File('build/ui-preview/focus-${size.width.toInt()}.png');
          await output.parent.create(recursive: true);
          await output.writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }
    });
  }

  for (final dark in [false, true]) {
    testWidgets('glass supports ${dark ? 'dark' : 'light'} and reduced effects',
        (tester) async {
      await tester.pumpWidget(MaterialApp(
        theme: dark ? ThemeData.dark() : buildAppTheme(),
        home: MediaQuery(
          data: const MediaQueryData(accessibleNavigation: true),
          child: Scaffold(
              body: Stack(children: [
            const Positioned.fill(child: AmbientBackdrop()),
            Center(
                child: GlassPanel(
                    child: Padding(
              padding: const EdgeInsets.all(24),
              child: TextButton(onPressed: () {}, child: const Text('开始专注')),
            ))),
          ])),
        ),
      ));
      await tester.pumpAndSettle();
      expect(find.text('开始专注').hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
