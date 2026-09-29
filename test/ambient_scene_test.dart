import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:todo_app/ui/ambient_backdrop.dart';
import 'package:todo_app/ui/ambient_palette.dart';
import 'package:todo_app/ui/ambient_reading_theme.dart';

void main() {
  testWidgets('selected font color reaches record reading theme',
      (tester) async {
    const selected = Color(0xFFBFE3FF);
    await tester.pumpWidget(MaterialApp(
      home: AmbientPaletteScope(
        palette: AmbientPalette.daylight
            .withFontColor(selected, selected.withValues(alpha: .85)),
        enabled: true,
        foregroundOverride: selected,
        child: const AmbientReadingTheme(
          enabled: true,
          child: Scaffold(body: Text('记录标题')),
        ),
      ),
    ));
    final textContext = tester.element(find.text('记录标题'));
    expect(Theme.of(textContext).textTheme.bodyMedium?.color, selected);
  });

  test('workspace follows four time-of-day states', () {
    expect(AmbientBackdrop.sceneForHour(4), 2);
    expect(AmbientBackdrop.sceneForHour(5), 3);
    expect(AmbientBackdrop.sceneForHour(8), 3);
    expect(AmbientBackdrop.sceneForHour(9), 0);
    expect(AmbientBackdrop.sceneForHour(16), 0);
    expect(AmbientBackdrop.sceneForHour(17), 1);
    expect(AmbientBackdrop.sceneForHour(19), 1);
    expect(AmbientBackdrop.sceneForHour(20), 2);
    expect(AmbientBackdrop.sceneForHour(23), 2);
    expect(AmbientBackdrop.sceneForHour(0), 2);
  });

  test('old personal background keeps its selection after catalog expansion',
      () {
    expect(
        AmbientBackdrop.restoreSceneIndex(3, oldCatalog: true, hasCustom: true),
        AmbientBackdrop.sceneAssets.length);
    expect(
        AmbientBackdrop.restoreSceneIndex(3,
            oldCatalog: true, hasCustom: false),
        0);
    expect(
        AmbientBackdrop.restoreSceneIndex(3,
            oldCatalog: false, hasCustom: false),
        3);
  });
}
