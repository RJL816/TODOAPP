import 'package:flutter_test/flutter_test.dart';
import 'package:todo_app/services/exercise_muscles.dart';

void main() {
  test('specific exercise names map before broad name fragments', () {
    expect(targetsForExercise('反向飞鸟').first.group, MuscleGroup.rearDelts);
    expect(targetsForExercise('腿弯举').first.group, MuscleGroup.hamstrings);
    expect(targetsForExercise('卧推').first.group, MuscleGroup.chest);
  });

  test('planned sets produce a restrained primary and secondary intensity', () {
    final scores = muscleScores(const [ExerciseVolume('卧推', 4)]);
    expect(scores[MuscleGroup.chest], 8);
    expect(scores[MuscleGroup.frontDelts], 4);
    expect(scores[MuscleGroup.triceps], 4);
  });

  test('unknown movement stays unclassified until the user assigns it', () {
    expect(targetsForExercise('我的特殊动作'), isEmpty);
    final scores = muscleScores(const [ExerciseVolume('我的特殊动作', 3)],
        overrides: {normalizeExerciseName('我的特殊动作'): MuscleGroup.lats});
    expect(scores[MuscleGroup.lats], 6);
    expect(scores.length, 1);
  });
}
