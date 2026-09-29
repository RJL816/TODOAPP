import 'package:isar/isar.dart';

part 'daily_completion.g.dart';

/// 每日完成记录（用于记录每日习惯的历史完成情况）
@Collection()
class DailyCompletion {
  Id id = Isar.autoIncrement;

  /// 关联的 TodoItem ID
  @Index()
  late int todoId;

  /// 完成日期（只存年月日）
  @Index()
  late DateTime date;

  /// 创建时间戳
  late int timestamp;

  DailyCompletion();

  /// 创建新的完成记录
  DailyCompletion.create({
    required this.todoId,
    required DateTime completionDate,
  })  : date = DateTime(completionDate.year, completionDate.month, completionDate.day),
        timestamp = DateTime.now().millisecondsSinceEpoch;

  /// 转换为 JSON（用于备份导出）
  Map<String, dynamic> toJson() => {
        'id': id,
        'todoId': todoId,
        'date': date.toIso8601String(),
        'timestamp': timestamp,
      };

  /// 从 JSON 创建（用于备份恢复）
  factory DailyCompletion.fromJson(Map<String, dynamic> json) => DailyCompletion()
    ..id = (json['id'] as int?) ?? Isar.autoIncrement
    ..todoId = json['todoId'] as int
    ..date = DateTime.parse(json['date'] as String)
    ..timestamp = (json['timestamp'] as int?) ?? 0;
}
