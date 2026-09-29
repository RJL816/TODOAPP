import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:todo_app/services/exercise_muscles.dart';
import 'package:todo_app/ui/muscle_map.dart';

void main() {
  testWidgets('front and back regions are selectable', (tester) async {
    MuscleGroup? selected;
    BodyView view = BodyView.front;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 180,
            height: 350,
            child: StatefulBuilder(
                builder: (context, update) => MuscleMap(
                      view: view,
                      scores: const {MuscleGroup.chest: 8, MuscleGroup.lats: 6},
                      selected: selected,
                      onSelect: (group) => update(() => selected = group),
                    )),
          ),
        ),
      ),
    ));
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 500));
    });
    await tester.pumpAndSettle();
    final topLeft = tester.getTopLeft(find.byType(MuscleMap));
    await tester.tapAt(topLeft + const Offset(70, 77));
    await tester.pump();
    expect(selected, MuscleGroup.chest);

    view = BodyView.back;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 180,
            height: 350,
            child: MuscleMap(
              view: view,
              scores: const {MuscleGroup.lats: 6},
              selected: selected,
              onSelect: (group) => selected = group,
            ),
          ),
        ),
      ),
    ));
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 500));
    });
    await tester.pumpAndSettle();
    await tester.tapAt(topLeft + const Offset(75, 108));
    expect(selected, MuscleGroup.lats);
  });
}
