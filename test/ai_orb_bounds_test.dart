import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:todo_app/services/ai_service.dart';
import 'package:todo_app/ui/ai_assistant.dart';

void main() {
  testWidgets('saved and dragged orb stays above narrow-screen navigation',
      (tester) async {
    tester.view.physicalSize = const Size(390, 740);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues({
      'ai_orb_position_x': 18.0,
      'ai_orb_position_y': 0.0,
    });

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        extendBody: true,
        body: Stack(children: [
          AiFloatingOrb(
            config: const AiConfig(),
            service: AiService.instance,
            minBottom: 84,
          ),
        ]),
        bottomNavigationBar: const SizedBox(height: 72),
      ),
    ));
    await tester.pumpAndSettle();

    final orb = find.byKey(const Key('ai-floating-orb-target'));
    expect(tester.getBottomLeft(orb).dy, lessThanOrEqualTo(656));

    final initialTop = tester.getTopLeft(orb).dy;
    await tester.drag(orb, const Offset(0, -24));
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(orb).dy, lessThan(initialTop));

    await tester.drag(orb, const Offset(0, 450));
    await tester.pumpAndSettle();
    expect(tester.getBottomLeft(orb).dy, lessThanOrEqualTo(656));
    expect(tester.takeException(), isNull);
  });
}
