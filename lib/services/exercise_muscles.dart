/// A small, explicit exercise-to-muscle vocabulary for the interactive map.
/// The result is a training annotation, not a measure of physiological load.
enum MuscleGroup {
  chest('胸大肌'),
  frontDelts('三角肌前束'),
  middleDelts('三角肌中束'),
  rearDelts('三角肌后束'),
  biceps('肱二头肌'),
  triceps('肱三头肌'),
  forearms('前臂'),
  traps('斜方肌'),
  lats('背阔肌'),
  lowerBack('竖脊肌'),
  abs('腹直肌'),
  obliques('腹外斜肌'),
  glutes('臀大肌'),
  quads('股四头肌'),
  adductors('大腿内收肌'),
  hamstrings('腘绳肌'),
  calves('小腿后侧'),
  shins('胫骨前肌');

  const MuscleGroup(this.label);
  final String label;
}

class MuscleTarget {
  final MuscleGroup group;
  final bool primary;
  const MuscleTarget(this.group, {this.primary = false});
}

class ExerciseVolume {
  final String name;
  final int sets;
  const ExerciseVolume(this.name, this.sets);
}

String normalizeExerciseName(String name) =>
    name.toLowerCase().replaceAll(RegExp(r'\s+'), '');

/// Common names only. Unrecognized exercises remain unclassified until the
/// user assigns a main muscle in the fitness page.
List<MuscleTarget> targetsForExercise(String name, {MuscleGroup? override}) {
  if (override != null) return [MuscleTarget(override, primary: true)];
  final text = normalizeExerciseName(name);
  bool any(List<String> words) => words.any(text.contains);

  if (any(['面拉', '反向飞鸟', '俯身飞鸟', 'facepull', 'reversefly'])) {
    return const [
      MuscleTarget(MuscleGroup.rearDelts, primary: true),
      MuscleTarget(MuscleGroup.traps)
    ];
  }
  if (any(['腿弯举', 'legcurl'])) {
    return const [MuscleTarget(MuscleGroup.hamstrings, primary: true)];
  }
  if (any(['夹腿', '内收', 'adductor'])) {
    return const [MuscleTarget(MuscleGroup.adductors, primary: true)];
  }
  if (any(['勾脚', '胫骨前肌', 'tibialisraise'])) {
    return const [MuscleTarget(MuscleGroup.shins, primary: true)];
  }
  if (any(['侧平举', 'lateralraise'])) {
    return const [MuscleTarget(MuscleGroup.middleDelts, primary: true)];
  }

  if (any([
    '卧推',
    '胸推',
    '俯卧撑',
    '飞鸟',
    '夹胸',
    'benchpress',
    'pushup',
    'chestpress',
    'chestfly'
  ])) {
    return const [
      MuscleTarget(MuscleGroup.chest, primary: true),
      MuscleTarget(MuscleGroup.frontDelts),
      MuscleTarget(MuscleGroup.triceps),
    ];
  }
  if (any([
    '肩推',
    '推举',
    '前平举',
    'overheadpress',
    'shoulderpress',
  ])) {
    return const [
      MuscleTarget(MuscleGroup.frontDelts, primary: true),
      MuscleTarget(MuscleGroup.middleDelts),
      MuscleTarget(MuscleGroup.triceps),
    ];
  }
  if (any(['弯举', 'curl'])) {
    return const [
      MuscleTarget(MuscleGroup.biceps, primary: true),
      MuscleTarget(MuscleGroup.forearms)
    ];
  }
  if (any(['臂屈伸', '绳索下压', '三头', 'tricep', 'pushdown', 'skullcrusher'])) {
    return const [MuscleTarget(MuscleGroup.triceps, primary: true)];
  }
  if (any(['引体', '高位下拉', '下拉', 'pullup', 'pulldown', 'chinup'])) {
    return const [
      MuscleTarget(MuscleGroup.lats, primary: true),
      MuscleTarget(MuscleGroup.biceps),
      MuscleTarget(MuscleGroup.traps),
    ];
  }
  if (any(['划船', 'row'])) {
    return const [
      MuscleTarget(MuscleGroup.lats, primary: true),
      MuscleTarget(MuscleGroup.traps),
      MuscleTarget(MuscleGroup.biceps),
    ];
  }
  if (any(['硬拉', 'deadlift', '罗马尼亚'])) {
    return const [
      MuscleTarget(MuscleGroup.hamstrings, primary: true),
      MuscleTarget(MuscleGroup.glutes, primary: true),
      MuscleTarget(MuscleGroup.lowerBack),
    ];
  }
  if (any(['深蹲', '腿举', '箭步蹲', '弓步蹲', 'squat', 'legpress', 'lunge'])) {
    return const [
      MuscleTarget(MuscleGroup.quads, primary: true),
      MuscleTarget(MuscleGroup.glutes),
      MuscleTarget(MuscleGroup.hamstrings),
    ];
  }
  if (any(['臀桥', '臀推', 'hipthrust', 'glutebridge'])) {
    return const [
      MuscleTarget(MuscleGroup.glutes, primary: true),
      MuscleTarget(MuscleGroup.hamstrings)
    ];
  }
  if (any(['腿屈伸', 'legextension'])) {
    return const [MuscleTarget(MuscleGroup.quads, primary: true)];
  }
  if (any(['提踵', 'calfraise'])) {
    return const [MuscleTarget(MuscleGroup.calves, primary: true)];
  }
  if (any(['卷腹', '仰卧起坐', '平板支撑', 'crunch', 'situp', 'plank'])) {
    return const [
      MuscleTarget(MuscleGroup.abs, primary: true),
      MuscleTarget(MuscleGroup.obliques)
    ];
  }
  if (any(['俄罗斯转体', '侧平板', 'russiantwist', 'sideplank'])) {
    return const [MuscleTarget(MuscleGroup.obliques, primary: true)];
  }
  return const [];
}

Map<MuscleGroup, int> muscleScores(
  Iterable<ExerciseVolume> exercises, {
  Map<String, MuscleGroup> overrides = const {},
}) {
  final scores = <MuscleGroup, int>{};
  for (final exercise in exercises) {
    final targets = targetsForExercise(exercise.name,
        override: overrides[normalizeExerciseName(exercise.name)]);
    for (final target in targets) {
      scores.update(target.group,
          (value) => value + exercise.sets * (target.primary ? 2 : 1),
          ifAbsent: () => exercise.sets * (target.primary ? 2 : 1));
    }
  }
  return scores;
}
