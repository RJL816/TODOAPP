import 'package:isar/isar.dart';

part 'class_time_config.g.dart';

/// 节次时间配置（一大节 = 一行）
///
/// id 用作节次的显示序号（1,2,3...）。
/// 课表网格显示、当前课程判断与（阶段 2 的）课程提醒共用这一份配置，
/// 取代原先硬编码在 course_service 与 schedule_page 两处的时间表。
@Collection()
class ClassTimeConfig {
  Id id = Isar.autoIncrement;

  /// 该大节包含的起始节次（细粒度节次号，如 1）
  int firstPeriod = 1;

  /// 该大节包含的结束节次（如 2）
  int lastPeriod = 2;

  /// 开始时间（当天分钟数，如 480 = 08:00）
  int startMinutes = 480;

  /// 结束时间（当天分钟数，如 580 = 09:40）
  int endMinutes = 580;

  ClassTimeConfig();

  ClassTimeConfig.create({
    required this.id,
    required this.firstPeriod,
    required this.lastPeriod,
    required this.startMinutes,
    required this.endMinutes,
  });

  String get startLabel => formatMinutes(startMinutes);
  String get endLabel => formatMinutes(endMinutes);

  String get periodLabel =>
      firstPeriod == lastPeriod ? '$firstPeriod' : '$firstPeriod-$lastPeriod';

  String get timeLabel => '$startLabel-$endLabel';

  static String formatMinutes(int minutes) {
    final h = (minutes ~/ 60).toString().padLeft(2, '0');
    final m = (minutes % 60).toString().padLeft(2, '0');
    return '$h:$m';
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'firstPeriod': firstPeriod,
        'lastPeriod': lastPeriod,
        'startMinutes': startMinutes,
        'endMinutes': endMinutes,
      };

  factory ClassTimeConfig.fromJson(Map<String, dynamic> json) =>
      ClassTimeConfig()
        ..id = (json['id'] as int?) ?? Isar.autoIncrement
        ..firstPeriod = (json['firstPeriod'] as int?) ?? 1
        ..lastPeriod = (json['lastPeriod'] as int?) ?? 2
        ..startMinutes = (json['startMinutes'] as int?) ?? 480
        ..endMinutes = (json['endMinutes'] as int?) ?? 580;
}
