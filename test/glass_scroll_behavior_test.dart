import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:todo_app/ui/glass_panel.dart';
import 'package:todo_app/ui/glass_scroll_behavior.dart';

void main() {
  bool usesBounce(ScrollPhysics? physics) {
    while (physics != null) {
      if (physics is BouncingScrollPhysics) return true;
      physics = physics.parent;
    }
    return false;
  }
  testWidgets('Android routes and dialogs bounce without stretch filters',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData(platform: TargetPlatform.android),
      scrollBehavior: const GlassScrollBehavior(),
      home: Builder(
          builder: (context) => Scaffold(
                body: ListView(children: [
                  const GlassPanel(child: SizedBox(height: 1000)),
                  TextButton(
                      onPressed: () => showDialog<void>(
                          context: context,
                          builder: (_) => const Dialog(
                                  child: SingleChildScrollView(
                                child:
                                    GlassPanel(child: SizedBox(height: 1000)),
                              ))),
                      child: const Text('打开弹层')),
                ]),
              )),
    ));
    expect(find.byType(StretchingOverscrollIndicator), findsNothing);
    final scrollable =
        tester.state<ScrollableState>(find.byType(Scrollable).first);
    expect(usesBounce(scrollable.position.physics), isTrue);
    final filter =
        tester.widget<BackdropFilter>(find.byType(BackdropFilter).first).filter;
    final gesture = await tester.startGesture(const Offset(150, 150));
    await gesture.moveBy(const Offset(0, 160));
    await tester.pump(const Duration(milliseconds: 100));
    expect(scrollable.position.pixels, lessThan(0));
    expect(find.byType(StretchingOverscrollIndicator), findsNothing);
    expect(
        tester.widget<BackdropFilter>(find.byType(BackdropFilter).first).filter,
        filter);
    await gesture.up();
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('打开弹层'), 300);
    await tester.tap(find.text('打开弹层'));
    await tester.pumpAndSettle();
    final dialogScrollable = tester.state<ScrollableState>(find
        .descendant(of: find.byType(Dialog), matching: find.byType(Scrollable))
        .first);
    expect(usesBounce(dialogScrollable.position.physics), isTrue);
    expect(find.byType(StretchingOverscrollIndicator), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Windows retains its standard scrolling physics', (tester) async {
    late BuildContext context;
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData(platform: TargetPlatform.windows),
      home: Builder(builder: (value) {
        context = value;
        return const SizedBox();
      }),
    ));
    expect(const GlassScrollBehavior().getScrollPhysics(context),
        isA<ClampingScrollPhysics>());
  });
}
