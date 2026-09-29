import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:muscle_mapper/muscle_mapper.dart' as atlas;

import '../services/exercise_muscles.dart';
import 'app_theme.dart';

enum BodyView { front, back }

/// The detailed anatomy asset and hit regions come from muscle_mapper.
/// This adapter keeps the app's exercise vocabulary independent of the asset.
class MuscleMap extends StatelessWidget {
  const MuscleMap({
    super.key,
    required this.view,
    required this.scores,
    required this.selected,
    required this.onSelect,
  });

  final BodyView view;
  final Map<MuscleGroup, int> scores;
  final MuscleGroup? selected;
  final ValueChanged<MuscleGroup> onSelect;

  @override
  Widget build(BuildContext context) {
    final active = <atlas.Muscle>{};
    final intensities = <atlas.Muscle, double>{};
    final colours = <atlas.Muscle, Color>{};
    final maxScore = scores.values.fold<int>(0, math.max);

    for (final entry in scores.entries) {
      final intensity = maxScore == 0
          ? .0
          : (.35 + .40 * entry.value / maxScore).clamp(.0, 1.0);
      for (final muscle in _partsFor(entry.key)) {
        active.add(muscle);
        intensities[muscle] = intensity;
        colours[muscle] = AppColors.amber;
      }
    }
    if (selected != null) {
      for (final muscle in _partsFor(selected!)) {
        active.add(muscle);
        intensities[muscle] = .78;
        colours[muscle] = const Color(0xFFC8862E);
      }
    }

    return AspectRatio(
      aspectRatio: 587 / 1137,
      child: atlas.MuscleMapper(
        gender: atlas.AnatomyGender.male,
        view: view == BodyView.front
            ? atlas.AnatomyView.front
            : atlas.AnatomyView.back,
        assetProvider: const atlas.DefaultAnatomyProvider(
            style: atlas.AnatomyStyle.advanced),
        activeMuscles: active,
        muscleIntensities: intensities,
        muscleColors: colours,
        highlightColor: AppColors.amber,
        loadingWidget: const SizedBox.shrink(),
        onError: (error) => debugPrint('肌群图谱加载失败: $error'),
        onMuscleTapped: (part) {
          final group = _groupFor(part);
          if (group != null) onSelect(group);
        },
      ),
    );
  }
}

Set<atlas.Muscle> _partsFor(MuscleGroup group) => switch (group) {
      MuscleGroup.chest => {
          atlas.Muscle.upperPectoralis,
          atlas.Muscle.midLowerPectoralis,
        },
      MuscleGroup.frontDelts => {atlas.Muscle.anteriorDeltoid},
      MuscleGroup.middleDelts => {atlas.Muscle.lateralDeltoid},
      MuscleGroup.rearDelts => {atlas.Muscle.posteriorDeltoid},
      MuscleGroup.biceps => {
          atlas.Muscle.longHeadBicep,
          atlas.Muscle.shortHeadBicep,
        },
      MuscleGroup.triceps => {
          atlas.Muscle.longHeadTriceps,
          atlas.Muscle.lateralHeadTriceps,
          atlas.Muscle.medialHeadTriceps,
        },
      MuscleGroup.forearms => {
          atlas.Muscle.wristFlexors,
          atlas.Muscle.wristExtensors,
        },
      MuscleGroup.traps => {
          atlas.Muscle.upperTrapezius,
          atlas.Muscle.trapsMiddle,
          atlas.Muscle.lowerTrapezius,
        },
      MuscleGroup.lats => {atlas.Muscle.lats},
      MuscleGroup.lowerBack => {atlas.Muscle.lowerBack},
      MuscleGroup.abs => {
          atlas.Muscle.upperAbdominals,
          atlas.Muscle.lowerAbdominals,
        },
      MuscleGroup.obliques => {atlas.Muscle.obliques},
      MuscleGroup.glutes => {
          atlas.Muscle.gluteusMaximus,
          atlas.Muscle.gluteusMedius,
        },
      MuscleGroup.quads => {
          atlas.Muscle.outerQuadricep,
          atlas.Muscle.rectusFemoris,
          atlas.Muscle.innerQuadricep,
        },
      MuscleGroup.hamstrings => {
          atlas.Muscle.lateralHamstrings,
          atlas.Muscle.medialHamstrings,
        },
      MuscleGroup.calves => {
          atlas.Muscle.gastrocnemius,
          atlas.Muscle.soleus,
        },
      MuscleGroup.adductors => {
          atlas.Muscle.groin,
          atlas.Muscle.innerThigh,
        },
      MuscleGroup.shins => {atlas.Muscle.tibialis},
    };

MuscleGroup? _groupFor(atlas.Muscle part) {
  for (final group in MuscleGroup.values) {
    if (_partsFor(group).contains(part)) return group;
  }
  return null;
}
