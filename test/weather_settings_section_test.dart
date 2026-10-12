import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:todo_app/services/weather_background_service.dart';
import 'package:todo_app/ui/weather_settings_section.dart';

void main() {
  testWidgets('weather settings fit phone and allow manual city selection',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(320, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final service =
        WeatherBackgroundService.forTest(MockClient((request) async {
      final data = request.url.host.contains('geocoding')
          ? {
              'results': [
                {
                  'name': '北京',
                  'latitude': 39.9,
                  'longitude': 116.4,
                  'admin1': '北京市',
                  'country': '中国'
                }
              ],
            }
          : {
              'current': {'weather_code': 61, 'temperature_2m': 18.0}
            };
      return http.Response(jsonEncode(data), 200,
          headers: {'content-type': 'application/json; charset=utf-8'});
    }));
    addTearDown(service.dispose);
    await service.init();
    await service.selectPlace(const WeatherPlace('London', 51.5, -.1));
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: SingleChildScrollView(
      child: WeatherSettingsSection(service: service),
    ))));
    await tester.pumpAndSettle();
    expect(find.text('使用定位'), findsOneWidget);
    expect(find.text('选择城市'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('选择城市'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Beijing');
    await tester.tap(find.byTooltip('搜索城市'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('北京'));
    await tester.pumpAndSettle();
    expect(service.place!.name, '北京');
    expect(service.automaticLocation, isFalse);
    expect(tester.takeException(), isNull);
  });
}
