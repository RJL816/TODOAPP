import 'package:isar/isar.dart';

part 'training.g.dart';

/// 训练计划（按星期安排）
@Collection()
class TrainingPlan {
  Id id = Isar.autoIncrement;

  /// 星期几（1=周一 … 7=周日）
  @Index()
  late int weekday;

  /// 计划名称，如 "胸+三头"、"晨跑"
  late String name;

  /// 备注
  String? notes;

  /// 是否启用（临时停用不影响历史）
  late bool isEnabled;

  /// 循环计划：同一组的每一天共用 groupId、起点和长度。
  int? cycleGroupId;
  DateTime? cycleStartDate;
  int? cycleLength;
  int? cycleDay;
  String? cycleName;
  bool isRestDay = false;

  TrainingPlan();

  TrainingPlan.create({
    required this.weekday,
    required this.name,
    this.notes,
    this.isEnabled = true,
  });

  String get weekdayLabel => _weekdayLabel(weekday);

  static String _weekdayLabel(int weekday) {
    const labels = ['', '周一', '周二', '周三', '周四', '周五', '周六', '周日'];
    return weekday >= 1 && weekday <= 7 ? labels[weekday] : '未知';
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'weekday': weekday,
        'name': name,
        'notes': notes,
        'isEnabled': isEnabled,
        'cycleGroupId': cycleGroupId,
        'cycleStartDate': cycleStartDate?.toIso8601String(),
        'cycleLength': cycleLength,
        'cycleDay': cycleDay,
        'cycleName': cycleName,
        'isRestDay': isRestDay,
      };

  factory TrainingPlan.fromJson(Map<String, dynamic> json) => TrainingPlan()
    ..id = (json['id'] as int?) ?? Isar.autoIncrement
    ..weekday = (json['weekday'] as int?) ?? 1
    ..name = (json['name'] as String?) ?? '未命名'
    ..notes = json['notes'] as String?
    ..isEnabled = (json['isEnabled'] as bool?) ?? true
    ..cycleGroupId = json['cycleGroupId'] as int?
    ..cycleStartDate = json['cycleStartDate'] == null
        ? null
        : DateTime.parse(json['cycleStartDate'] as String)
    ..cycleLength = json['cycleLength'] as int?
    ..cycleDay = json['cycleDay'] as int?
    ..cycleName = json['cycleName'] as String?
    ..isRestDay = (json['isRestDay'] as bool?) ?? false;
}

/// 计划中的动作
@Collection()
class PlanExercise {
  Id id = Isar.autoIncrement;

  /// 所属计划 ID
  @Index()
  late int planId;

  /// 动作名称，如 "卧推"
  late String name;

  /// 计划组数
  int plannedSets = 3;

  /// 备注（目标重量等）
  String? notes;

  PlanExercise();

  PlanExercise.create({
    required this.planId,
    required this.name,
    this.plannedSets = 3,
    this.notes,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'planId': planId,
        'name': name,
        'plannedSets': plannedSets,
        'notes': notes,
      };

  factory PlanExercise.fromJson(Map<String, dynamic> json) => PlanExercise()
    ..id = (json['id'] as int?) ?? Isar.autoIncrement
    ..planId = (json['planId'] as int?) ?? 0
    ..name = (json['name'] as String?) ?? ''
    ..plannedSets = (json['plannedSets'] as int?) ?? 3
    ..notes = json['notes'] as String?;
}

/// 一次训练打卡
@Collection()
class WorkoutLog {
  Id id = Isar.autoIncrement;

  /// 训练日期（只存年月日）
  @Index()
  late DateTime date;

  /// 关联的计划（自由训练为空）
  @Index()
  int? planId;

  /// 训练标题
  late String title;

  /// 开始时间
  late DateTime startedAt;

  /// 实际结束时间；旧训练记录为空，不推算时长。
  DateTime? endedAt;

  /// 是否完整完成
  late bool completed;

  WorkoutLog();

  WorkoutLog.create({
    required this.date,
    required this.title,
    required this.startedAt,
    this.endedAt,
    this.planId,
    this.completed = true,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'date': date.toIso8601String(),
        'planId': planId,
        'title': title,
        'startedAt': startedAt.toIso8601String(),
        'endedAt': endedAt?.toIso8601String(),
        'completed': completed,
      };

  factory WorkoutLog.fromJson(Map<String, dynamic> json) => WorkoutLog()
    ..id = (json['id'] as int?) ?? Isar.autoIncrement
    ..date = DateTime.parse(json['date'] as String)
    ..planId = json['planId'] as int?
    ..title = (json['title'] as String?) ?? '训练'
    ..startedAt = json['startedAt'] != null
        ? DateTime.parse(json['startedAt'] as String)
        : DateTime.now()
    ..endedAt = json['endedAt'] == null
        ? null
        : DateTime.parse(json['endedAt'] as String)
    ..completed = (json['completed'] as bool?) ?? true;
}

/// 单组记录（次数/重量/时长全部可选，按需记录）
@Collection()
class WorkoutSet {
  Id id = Isar.autoIncrement;

  /// 所属训练
  @Index()
  late int workoutId;

  /// 动作名称
  late String exerciseName;

  /// 第几组
  int setIndex = 1;

  /// 次数（可选）
  int? reps;

  /// 重量（克，整数避免浮点误差；显示时换算 kg）
  int? weightGrams;

  /// 时长秒（跑步等有氧，可选）
  int? durationSeconds;

  /// 备注
  String? notes;

  WorkoutSet();

  WorkoutSet.create({
    required this.workoutId,
    required this.exerciseName,
    this.setIndex = 1,
    this.reps,
    this.weightGrams,
    this.durationSeconds,
    this.notes,
  });

  /// 展示用描述
  String get displaySummary {
    final parts = <String>[];
    if (reps != null) parts.add('$reps 次');
    if (weightGrams != null) {
      final kg = weightGrams! / 1000;
      parts.add(kg == kg.roundToDouble() ? '${kg.toInt()} kg' : '$kg kg');
    }
    if (durationSeconds != null) {
      final m = durationSeconds! ~/ 60;
      final s = durationSeconds! % 60;
      parts.add('$m 分 ${s.toString().padLeft(2, '0')} 秒');
    }
    if (notes != null && notes!.isNotEmpty) parts.add(notes!);
    return parts.isEmpty ? '已记录' : parts.join(' · ');
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'workoutId': workoutId,
        'exerciseName': exerciseName,
        'setIndex': setIndex,
        'reps': reps,
        'weightGrams': weightGrams,
        'durationSeconds': durationSeconds,
        'notes': notes,
      };

  factory WorkoutSet.fromJson(Map<String, dynamic> json) => WorkoutSet()
    ..id = (json['id'] as int?) ?? Isar.autoIncrement
    ..workoutId = (json['workoutId'] as int?) ?? 0
    ..exerciseName = (json['exerciseName'] as String?) ?? ''
    ..setIndex = (json['setIndex'] as int?) ?? 1
    ..reps = json['reps'] as int?
    ..weightGrams = json['weightGrams'] as int?
    ..durationSeconds = json['durationSeconds'] as int?
    ..notes = json['notes'] as String?;
}
