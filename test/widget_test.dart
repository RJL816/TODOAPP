import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:todo_app/services/gamification_service.dart';

/// 轻量组件测试（不依赖数据库初始化）。
/// 原冒烟测试直接 pump TodoHomePage，会在 Isar 未初始化时抛异常，已移除；
/// 服务层与数据层的真实测试见 isar_service_habit_test.dart / backup_service_test.dart。
void main() {
  testWidgets('StreakDisplayWidget 渲染打卡天数与火焰图标', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: Center(child: StreakDisplayWidget(streak: 3))),
      ),
    );
    expect(find.text('3天'), findsOneWidget);
    expect(find.byIcon(Icons.local_fire_department), findsOneWidget);
  });

  testWidgets('StreakDisplayWidget 零打卡时显示奖杯图标', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: Center(child: StreakDisplayWidget(streak: 0))),
      ),
    );
    expect(find.text('0天'), findsOneWidget);
    expect(find.byIcon(Icons.emoji_events_outlined), findsOneWidget);
  });
}
