import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:todo_app/ui/glass_panel.dart';

void main() {
  for (final size in [const Size(800, 1280), const Size(1280, 800)]) {
    testWidgets(
        'tablet $size keeps glass adjustable with accessible navigation',
        (tester) async {
      final previous = GlassTuning.clarity.value;
      addTearDown(() => GlassTuning.clarity.value = previous);
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      GlassTuning.clarity.value = .1;
      await tester.pumpWidget(MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(size: size, accessibleNavigation: true),
          child: const Center(
              child: GlassPanel(
            level: GlassSurfaceLevel.dark,
            child: SizedBox(width: 300, height: 200),
          )),
        ),
      ));
      List<Color> tintColors() => tester
          .widgetList<DecoratedBox>(
            find.descendant(
                of: find.byType(BackdropFilter),
                matching: find.byType(DecoratedBox)),
          )
          .map((box) => (box.decoration as BoxDecoration).gradient)
          .whereType<LinearGradient>()
          .first
          .colors;
      final frosted = tintColors().first.a;
      GlassTuning.clarity.value = .9;
      await tester.pump();
      expect(tintColors().first.a, lessThan(frosted));
      expect(tester.widget<BackdropFilter>(find.byType(BackdropFilter)).enabled,
          isTrue);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('explicit high contrast keeps reading surface opaque',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(highContrast: true),
        child: GlassPanel(child: SizedBox(width: 300, height: 200)),
      ),
    ));
    expect(tester.widget<BackdropFilter>(find.byType(BackdropFilter)).enabled,
        isFalse);
    final backgrounds = tester.widgetList<DecoratedBox>(find.descendant(
      of: find.byType(BackdropFilter),
      matching: find.byType(DecoratedBox),
    ));
    final gradient = backgrounds
        .map((box) => (box.decoration as BoxDecoration).gradient)
        .whereType<LinearGradient>()
        .first;
    expect(gradient.colors.every((color) => color.a == 1), isTrue);
  });
}
