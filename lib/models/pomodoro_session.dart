import 'package:isar/isar.dart';

part 'pomodoro_session.g.dart';

/// 番茄钟阶段类型
enum PomodoroPhaseType {
  focus, // 专注
  shortBreak, // 短休息
  longBreak; // 长休息

  String get displayName {
    switch (this) {
      case PomodoroPhaseType.focus:
        return '专注';
      case PomodoroPhaseType.shortBreak:
        return '短休息';
      case PomodoroPhaseType.longBreak:
        return '长休息';
    }
  }
}

/// 一次番茄钟会话记录
///
/// 统计口径：只有 `completed == true` 且类型为 focus 的会话计入专注时长与番茄数；
/// 被放弃的会话保留记录（completed == false）但**不计入**统计。
@Collection()
class PomodoroSession {
  Id id = Isar.autoIncrement;

  /// 关联的待办 ID（可选）
  int? todoId;

  /// 开始时的主题快照，也用于独立创建的专注事项。
  String? taskTitle;

  /// 实际开始时间
  @Index()
  late DateTime startedAt;

  /// 结束时间
  late DateTime endedAt;

  /// 实际时长（秒）
  late int durationSeconds;

  /// 阶段类型
  @Enumerated(EnumType.name)
  late PomodoroPhaseType type;

  /// 是否完整跑完（未放弃）
  late bool completed;

  PomodoroSession();

  PomodoroSession.create({
    required this.startedAt,
    required this.endedAt,
    required this.durationSeconds,
    required this.type,
    this.completed = true,
    this.todoId,
    this.taskTitle,
  });

  /// 转换为 JSON（用于备份导出）
  Map<String, dynamic> toJson() => {
        'id': id,
        'todoId': todoId,
        'taskTitle': taskTitle,
        'startedAt': startedAt.toIso8601String(),
        'endedAt': endedAt.toIso8601String(),
        'durationSeconds': durationSeconds,
        'type': type.name,
        'completed': completed,
      };

  /// 从 JSON 创建（用于备份恢复）
  factory PomodoroSession.fromJson(Map<String, dynamic> json) =>
      PomodoroSession()
        ..id = (json['id'] as int?) ?? Isar.autoIncrement
        ..todoId = json['todoId'] as int?
        ..taskTitle = json['taskTitle'] as String?
        ..startedAt = DateTime.parse(json['startedAt'] as String)
        ..endedAt = DateTime.parse(json['endedAt'] as String)
        ..durationSeconds = (json['durationSeconds'] as int?) ?? 0
        ..type = PomodoroPhaseType.values.firstWhere(
          (t) => t.name == json['type'],
          orElse: () => PomodoroPhaseType.focus,
        )
        ..completed = (json['completed'] as bool?) ?? false;
}
