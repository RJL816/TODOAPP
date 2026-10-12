import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:todo_app/models/weather_scene.dart';
import 'package:todo_app/services/weather_background_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  const city = WeatherPlace('北京', 39.9, 116.4);
  http.Response forecast(int code) => http.Response(
      jsonEncode({
        'current': {'weather_code': code, 'temperature_2m': 18.0},
      }),
      200);

  test('WMO rain and snow codes select the appropriate background', () {
    for (final code in [51, 61, 65, 80, 95, 99]) {
      expect(weatherSceneForCode(code), AmbientWeather.rain);
    }
    for (final code in [71, 73, 75, 77, 85, 86]) {
      expect(weatherSceneForCode(code), AmbientWeather.snow);
    }
    for (final code in [0, 1, 3, 45, 48]) {
      expect(weatherSceneForCode(code), AmbientWeather.clear);
    }
  });

  test('disabled weather makes no network or location requests', () async {
    var calls = 0;
    final service = WeatherBackgroundService.forTest(MockClient((_) async {
      calls++;
      return forecast(61);
    }), locate: (_) async {
      calls++;
      return city;
    });
    addTearDown(service.dispose);
    await service.init();
    await service.refresh(force: true);
    expect(calls, 0);
  });

  test('manual city fetches weather without requesting location', () async {
    var locations = 0;
    final service =
        WeatherBackgroundService.forTest(MockClient((request) async {
      expect(request.url.queryParameters['current'],
          'temperature_2m,weather_code');
      expect(request.url.queryParameters['latitude'], '39.9');
      return forecast(71);
    }), locate: (_) async {
      locations++;
      return city;
    });
    addTearDown(service.dispose);
    await service.init();
    await service.selectPlace(city);
    expect(service.mood, AmbientWeather.snow);
    expect(service.automaticLocation, isFalse);
    expect(locations, 0);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('weather_background_enabled'), isTrue);
    expect(prefs.getString('weather_background_cache'), isNotNull);
  });

  test('explicit location asks once, periodic refresh does not ask permission',
      () async {
    var now = DateTime(2026, 10, 12, 12);
    final permissions = <bool>[];
    var calls = 0;
    final service = WeatherBackgroundService.forTest(
        MockClient((_) async {
          calls++;
          return forecast(61);
        }),
        clock: () => now,
        locate: (ask) async {
          permissions.add(ask);
          return city;
        });
    addTearDown(service.dispose);
    await service.init();
    await service.useDeviceLocation();
    await service.refresh();
    expect(permissions, [true]);
    expect(calls, 1);
    now = now.add(const Duration(minutes: 31));
    await service.refresh();
    expect(permissions, [true, false]);
    expect(calls, 2);
  });

  test(
      'network failure retains recent weather, stale cache returns to dry scene',
      () async {
    var now = DateTime(2026, 10, 12, 12);
    var fail = false;
    final service = WeatherBackgroundService.forTest(
        MockClient((_) async => fail ? http.Response('', 503) : forecast(61)),
        clock: () => now);
    addTearDown(service.dispose);
    await service.init();
    await service.selectPlace(city);
    fail = true;
    now = now.add(const Duration(minutes: 31));
    await service.refresh();
    expect(service.error, isNotNull);
    expect(service.mood, AmbientWeather.rain);
    now = now.add(const Duration(hours: 3));
    expect(service.mood, AmbientWeather.clear);
  });

  test('disabling during a fetch prevents late response from restoring weather',
      () async {
    final gate = Completer<http.Response>();
    final service =
        WeatherBackgroundService.forTest(MockClient((_) => gate.future));
    addTearDown(service.dispose);
    await service.init();
    final pending = service.selectPlace(city);
    await Future<void>.delayed(Duration.zero);
    await service.setEnabled(false);
    gate.complete(forecast(71));
    await pending;
    expect(service.enabled, isFalse);
    expect(service.snapshot, isNull);
    expect(service.mood, AmbientWeather.clear);
  });

  test('denied device location retains the manual city and its weather',
      () async {
    final service = WeatherBackgroundService.forTest(
        MockClient((_) async => forecast(61)),
        locate: (_) async => throw Exception('定位权限未开启'));
    addTearDown(service.dispose);
    await service.init();
    await service.selectPlace(city);
    await service.useDeviceLocation();
    expect(service.place, city);
    expect(service.automaticLocation, isFalse);
    expect(service.error, contains('定位权限'));
    expect(service.mood, AmbientWeather.rain);
  });
}
