import 'package:isar/isar.dart';

part 'diet_log.g.dart';

/// 餐次
enum MealType {
  breakfast, // 早餐
  lunch, // 午餐
  dinner, // 晚餐
  snack; // 加餐

  String get displayName {
    switch (this) {
      case MealType.breakfast:
        return '早餐';
      case MealType.lunch:
        return '午餐';
      case MealType.dinner:
        return '晚餐';
      case MealType.snack:
        return '加餐';
    }
  }
}

/// 一条饮食记录（营养字段全部可选——只做记录与回顾，不生成目标）
@Collection()
class DietLog {
  Id id = Isar.autoIncrement;

  /// 日期（只存年月日）
  @Index()
  late DateTime date;

  /// 餐次
  @Enumerated(EnumType.name)
  late MealType mealType;

  /// 食物描述
  late String food;

  /// 备注
  String? notes;

  /// 热量（千卡，可选）
  int? calories;

  /// 蛋白质（克，可选）
  int? proteinGrams;

  /// 碳水（克，可选）
  int? carbsGrams;

  /// 脂肪（克，可选）
  int? fatGrams;

  /// 记录时间
  late DateTime createdAt;

  DietLog();

  DietLog.create({
    required this.date,
    required this.mealType,
    required this.food,
    this.notes,
    this.calories,
    this.proteinGrams,
    this.carbsGrams,
    this.fatGrams,
  }) : createdAt = DateTime.now();

  Map<String, dynamic> toJson() => {
        'id': id,
        'date': date.toIso8601String(),
        'mealType': mealType.name,
        'food': food,
        'notes': notes,
        'calories': calories,
        'proteinGrams': proteinGrams,
        'carbsGrams': carbsGrams,
        'fatGrams': fatGrams,
        'createdAt': createdAt.toIso8601String(),
      };

  factory DietLog.fromJson(Map<String, dynamic> json) => DietLog()
    ..id = (json['id'] as int?) ?? Isar.autoIncrement
    ..date = DateTime.parse(json['date'] as String)
    ..mealType = MealType.values.firstWhere(
      (m) => m.name == json['mealType'],
      orElse: () => MealType.snack,
    )
    ..food = (json['food'] as String?) ?? ''
    ..notes = json['notes'] as String?
    ..calories = json['calories'] as int?
    ..proteinGrams = json['proteinGrams'] as int?
    ..carbsGrams = json['carbsGrams'] as int?
    ..fatGrams = json['fatGrams'] as int?
    ..createdAt = json['createdAt'] != null
        ? DateTime.parse(json['createdAt'] as String)
        : DateTime.now();
}
