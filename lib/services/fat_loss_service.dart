import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

/// 减脂计划：用户身体档案 + 每日目标计算。
/// 计算基于通行做法：Mifflin-St Jeor 公式估 BMR，× 活动系数得 TDEE，
/// 再按选择的力度扣出热量缺口；蛋白质按体重给量、脂肪按热量占比、碳水补余。
/// 仅供记录参考，不构成医疗建议。
class FatLossProfile {
  final String gender; // 'm' | 'f'
  final int age;
  final double heightCm;
  final double weightKg;
  final double activityFactor; // 1.2 / 1.375 / 1.55 / 1.725
  final int deficit; // 每日热量缺口（大卡）

  const FatLossProfile({
    required this.gender,
    required this.age,
    required this.heightCm,
    required this.weightKg,
    required this.activityFactor,
    required this.deficit,
  });

  Map<String, dynamic> toJson() => {
        'gender': gender,
        'age': age,
        'heightCm': heightCm,
        'weightKg': weightKg,
        'activityFactor': activityFactor,
        'deficit': deficit,
      };

  factory FatLossProfile.fromJson(Map<String, dynamic> json) =>
      FatLossProfile(
        gender: json['gender'] as String? ?? 'm',
        age: json['age'] as int? ?? 25,
        heightCm: (json['heightCm'] as num?)?.toDouble() ?? 170,
        weightKg: (json['weightKg'] as num?)?.toDouble() ?? 65,
        activityFactor: (json['activityFactor'] as num?)?.toDouble() ?? 1.375,
        deficit: json['deficit'] as int? ?? 500,
      );
}

class FatLossTargets {
  final double bmr;
  final double tdee;
  final int targetKcal;
  final int proteinG;
  final int fatG;
  final int carbG;

  const FatLossTargets({
    required this.bmr,
    required this.tdee,
    required this.targetKcal,
    required this.proteinG,
    required this.fatG,
    required this.carbG,
  });
}

class FatLossService {
  static FatLossService? _instance;
  static FatLossService get instance {
    _instance ??= FatLossService._();
    return _instance!;
  }

  FatLossService._();

  static const String _profileKey = 'fat_loss_profile';

  /// 计算每日目标（纯函数）。
  /// 蛋白质 1.8 g/kg（减脂期保肌肉）；脂肪占总热量 25%；碳水补余；
  /// 目标热量设有下限（女 1200 / 男 1500），避免激进缺口伤身。
  static FatLossTargets computeTargets(FatLossProfile profile) {
    final genderOffset = profile.gender == 'f' ? -161 : 5;
    final bmr = 10 * profile.weightKg +
        6.25 * profile.heightCm -
        5 * profile.age +
        genderOffset;
    final tdee = bmr * profile.activityFactor;
    final floor = profile.gender == 'f' ? 1200.0 : 1500.0;
    final target = (tdee - profile.deficit).clamp(floor, tdee);
    final proteinG = (1.8 * profile.weightKg).round();
    final fatG = (target * 0.25 / 9).round();
    final carbG =
        ((target - proteinG * 4 - fatG * 9) / 4).round().clamp(0, 9999);
    return FatLossTargets(
      bmr: bmr,
      tdee: tdee,
      targetKcal: target.round(),
      proteinG: proteinG,
      fatG: fatG,
      carbG: carbG,
    );
  }

  Future<FatLossProfile?> loadProfile() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_profileKey);
      if (raw == null || raw.isEmpty) return null;
      return FatLossProfile.fromJson(
          jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  Future<void> saveProfile(FatLossProfile profile) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_profileKey, jsonEncode(profile.toJson()));
  }
}
