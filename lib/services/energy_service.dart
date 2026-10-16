import 'dart:math' as math;
import '../models/training.dart';
import 'fat_loss_service.dart';

class TrainingEnergy {
  const TrainingEnergy(this.calories, this.minutes, this.inferredDuration);
  final int calories;
  final double minutes;
  final bool inferredDuration;
}

/// MET 分类参考 2024 Adult Compendium；组数、节奏和负重只能粗估强度。
/// 返回净运动消耗（扣除 1 MET 静息部分），避免与基础日常消耗重复。
class EnergyService {
  static TrainingEnergy? estimateTraining({
    required double weightKg,
    required List<WorkoutSet> sets,
    double? durationMinutes,
  }) {
    if (!weightKg.isFinite || weightKg < 30 || weightKg > 300) return null;
    var activeSeconds = 0.0;
    var weightedNetSeconds = 0.0;
    var validSets = 0;
    for (final set in sets) {
      if (set.exerciseName.trim().isEmpty || (set.weightGrams ?? 0) < 0)
        continue;
      final seconds = (set.durationSeconds ?? 0) > 0
          ? set.durationSeconds!.toDouble()
          : (set.reps ?? 0) > 0
              ? set.reps! * 3.0
              : 0.0;
      if (seconds <= 0 || seconds > 36000) continue;
      var met = 3.5;
      final name = set.exerciseName.toLowerCase();
      if (RegExp(r'跑步|慢跑|running|jog').hasMatch(name)) {
        met = 8;
      } else if (RegExp(r'骑行|单车|cycling|bike').hasMatch(name)) {
        met = 6.8;
      } else if (RegExp(r'步行|快走|walk').hasMatch(name)) {
        met = 3.8;
      } else if (RegExp(r'深蹲|硬拉|卧推|squat|deadlift|bench').hasMatch(name) &&
          (set.weightGrams ?? 0) / 1000 >= weightKg * .75) {
        met = 6;
      }
      activeSeconds += seconds;
      weightedNetSeconds += (met - 1) * seconds;
      validSets++;
    }
    if (validSets == 0) return null;
    final inferred = durationMinutes == null;
    final totalSeconds = durationMinutes != null &&
            durationMinutes.isFinite &&
            durationMinutes > 0
        ? durationMinutes.clamp(0, 600) * 60
        : activeSeconds + math.max(0, validSets - 1) * 60;
    final scale =
        activeSeconds > totalSeconds ? totalSeconds / activeSeconds : 1.0;
    final restSeconds = math.max(0, totalSeconds - activeSeconds);
    final calories = (3.5 *
            weightKg /
            200 *
            (weightedNetSeconds * scale + .5 * restSeconds) /
            60)
        .round();
    return TrainingEnergy(calories, totalSeconds / 60, inferred);
  }

  static double baseline(FatLossProfile profile) =>
      FatLossService.computeTargets(profile).tdee;

  static String advice(
      {required int intake,
      required int missingEntries,
      required double expenditure,
      required bool isToday}) {
    if (missingEntries > 0) return '还有 $missingEntries 条饮食未填写热量，先补全记录再比较。';
    if (intake == 0) return '尚未记录摄入，不能将未记录视为没有进食。';
    if (isToday) return '这是全天预计消耗与目前已记录摄入的比较；今天尚未结束，不据此建议少吃或追加训练。';
    final delta = intake - expenditure;
    if (delta.abs() <= 200) return '记录摄入与估计消耗较接近。结合连续多天记录和体重趋势观察。';
    if (delta > 0) return '记录摄入高于估计消耗。先核对份量与漏记，保持规律饮食和训练，不必因单日记录补偿运动。';
    return '记录摄入低于估计消耗。先确认是否漏记；若长期缺口较大或感觉不适，应调整饮食并寻求专业建议。';
  }
}
