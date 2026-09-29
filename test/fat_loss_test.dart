import 'package:flutter_test/flutter_test.dart';
import 'package:todo_app/services/fat_loss_service.dart';

/// 减脂计划目标计算（Mifflin-St Jeor）
void main() {
  test('男性标准档：BMR/TDEE/宏量在预期区间', () {
    // 25 岁 男 175cm 75kg 轻度活动(1.375) 缺口 500
    final t = FatLossService.computeTargets(const FatLossProfile(
      gender: 'm',
      age: 25,
      heightCm: 175,
      weightKg: 75,
      activityFactor: 1.375,
      deficit: 500,
    ));
    // BMR = 10*75 + 6.25*175 - 125 + 5 = 1723.75
    expect(t.bmr, closeTo(1723.75, 0.5));
    // TDEE = BMR * 1.375 ≈ 2370
    expect(t.tdee, closeTo(2370.2, 1));
    // 目标 = TDEE - 500
    expect(t.targetKcal, closeTo(t.tdee - 500, 1));
    // 蛋白 1.8 g/kg
    expect(t.proteinG, 135);
    // 脂肪 25% 热量
    expect(t.fatG, closeTo(t.targetKcal * 0.25 / 9, 1));
    // 碳水补余且非负
    expect(t.carbG, greaterThanOrEqualTo(0));
    expect(
        t.proteinG * 4 + t.fatG * 9 + t.carbG * 4,
        closeTo(t.targetKcal, 20));
  });

  test('女性小基数：目标热量不低于健康下限 1200', () {
    final t = FatLossService.computeTargets(const FatLossProfile(
      gender: 'f',
      age: 30,
      heightCm: 155,
      weightKg: 45,
      activityFactor: 1.2,
      deficit: 750, // 激进缺口会触底
    ));
    expect(t.targetKcal, greaterThanOrEqualTo(1200));
    // TDEE ≈ (450 + 968.75 - 150 - 161) * 1.2 ≈ 1329 → 减 750 后触底
    expect(t.targetKcal, 1200);
  });

  test('缺口不超过 TDEE 时目标等于 TDEE-缺口', () {
    final t = FatLossService.computeTargets(const FatLossProfile(
      gender: 'm',
      age: 22,
      heightCm: 180,
      weightKg: 85,
      activityFactor: 1.725,
      deficit: 300,
    ));
    expect(t.targetKcal, (t.tdee - 300).round());
  });
}
