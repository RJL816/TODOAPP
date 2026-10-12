import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../models/weather_scene.dart';

@immutable
class WeatherPlace {
  const WeatherPlace(this.name, this.latitude, this.longitude,
      {this.region = ''});
  final String name;
  final double latitude;
  final double longitude;
  final String region;
  String get key => '$latitude,$longitude';
  String get label => region.isEmpty ? name : '$name · $region';
  Map<String, dynamic> toJson() => {
        'name': name,
        'latitude': latitude,
        'longitude': longitude,
        'region': region,
      };
  factory WeatherPlace.fromJson(Map<String, dynamic> data) {
    final lat = (data['latitude'] as num).toDouble();
    final lon = (data['longitude'] as num).toDouble();
    if (!lat.isFinite || !lon.isFinite || lat.abs() > 90 || lon.abs() > 180) {
      throw const FormatException('Invalid location');
    }
    return WeatherPlace(data['name'] as String, lat, lon,
        region: data['region'] as String? ?? '');
  }
}

@immutable
class WeatherSnapshot {
  const WeatherSnapshot(
      this.place, this.code, this.temperature, this.fetchedAt);
  final WeatherPlace place;
  final int code;
  final double temperature;
  final DateTime fetchedAt;
  Map<String, dynamic> toJson() => {
        'place': place.toJson(),
        'code': code,
        'temperature': temperature,
        'fetchedAt': fetchedAt.toIso8601String(),
      };
  factory WeatherSnapshot.fromJson(Map<String, dynamic> data) =>
      WeatherSnapshot(
          WeatherPlace.fromJson(data['place'] as Map<String, dynamic>),
          data['code'] as int,
          (data['temperature'] as num).toDouble(),
          DateTime.parse(data['fetchedAt'] as String));
}

/// 天气仅在用户启用后更新；定位为前台单次获取，缓存坐标只保留城市级精度。
class WeatherBackgroundService extends ChangeNotifier {
  WeatherBackgroundService._()
      : _client = http.Client(),
        _clock = DateTime.now,
        _locate = _deviceLocation;
  @visibleForTesting
  WeatherBackgroundService.forTest(
    this._client, {
    DateTime Function()? clock,
    Future<WeatherPlace> Function(bool)? locate,
  })  : _clock = clock ?? DateTime.now,
        _locate = locate ?? _deviceLocation;
  static final instance = WeatherBackgroundService._();
  final http.Client _client;
  final DateTime Function() _clock;
  final Future<WeatherPlace> Function(bool) _locate;
  bool enabled = false;
  bool automaticLocation = true;
  bool busy = false;
  WeatherPlace? place;
  WeatherSnapshot? snapshot;
  String? error;
  bool _initialized = false;
  bool _pendingRefresh = false;
  bool _disposed = false;
  int _generation = 0;
  DateTime? _lastAttempt;

  AmbientWeather get mood {
    final data = snapshot;
    if (!enabled ||
        data == null ||
        data.place.key != place?.key ||
        _clock().difference(data.fetchedAt) > const Duration(hours: 3)) {
      return AmbientWeather.clear;
    }
    return weatherSceneForCode(data.code);
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;
    final prefs = await SharedPreferences.getInstance();
    enabled = prefs.getBool('weather_background_enabled') ?? false;
    automaticLocation =
        prefs.getBool('weather_background_auto_location') ?? true;
    try {
      final raw = prefs.getString('weather_background_place');
      if (raw != null) place = WeatherPlace.fromJson(jsonDecode(raw));
      final cache = prefs.getString('weather_background_cache');
      if (cache != null) snapshot = WeatherSnapshot.fromJson(jsonDecode(cache));
    } catch (_) {
      snapshot = null;
    }
    _notify();
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('weather_background_enabled', enabled);
    await prefs.setBool('weather_background_auto_location', automaticLocation);
    if (place != null) {
      await prefs.setString(
          'weather_background_place', jsonEncode(place!.toJson()));
    }
  }

  Future<void> setEnabled(bool value) async {
    enabled = value;
    _generation++;
    _lastAttempt = null;
    error = null;
    await _save();
    _notify();
    if (value) await refresh(force: true);
  }

  Future<void> selectPlace(WeatherPlace selected) async {
    place = selected;
    automaticLocation = false;
    enabled = true;
    _generation++;
    _lastAttempt = null;
    error = null;
    await _save();
    _notify();
    await refresh(force: true);
  }

  Future<void> useDeviceLocation() async {
    if (busy) return;
    busy = true;
    error = null;
    final generation = _generation;
    _notify();
    try {
      final selected = await _locate(true);
      if (_disposed || generation != _generation) return;
      place = selected;
      automaticLocation = true;
      enabled = true;
      _generation++;
      _lastAttempt = null;
      await _save();
    } catch (e) {
      error = _friendlyError(e);
    } finally {
      busy = false;
      _notify();
    }
    if (error == null) await refresh(force: true, reuseLocation: true);
  }

  Future<List<WeatherPlace>> searchCities(String query) async {
    final name = query.trim();
    if (name.isEmpty) return [];
    final response = await _client
        .get(Uri.https('geocoding-api.open-meteo.com', '/v1/search',
            {'name': name, 'count': '8', 'language': 'zh', 'format': 'json'}))
        .timeout(const Duration(seconds: 15));
    if (response.statusCode != 200) throw Exception('城市搜索暂时不可用，请稍后重试');
    final data =
        jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
    return (data['results'] as List? ?? []).map((raw) {
      final item = raw as Map<String, dynamic>;
      return WeatherPlace.fromJson({
        ...item,
        'region':
            [item['admin1'], item['country']].whereType<String>().join(' · '),
      });
    }).toList();
  }

  Future<void> refresh({bool force = false, bool reuseLocation = false}) async {
    if (!enabled || _disposed) return;
    if (busy) {
      if (force) _pendingRefresh = true;
      return;
    }
    final now = _clock();
    if (!force &&
        _lastAttempt != null &&
        now.difference(_lastAttempt!) >= Duration.zero &&
        now.difference(_lastAttempt!) < const Duration(minutes: 30)) {
      return;
    }
    if (!force &&
        snapshot != null &&
        snapshot!.place.key == place?.key &&
        now.difference(snapshot!.fetchedAt) >= Duration.zero &&
        now.difference(snapshot!.fetchedAt) < const Duration(minutes: 30)) {
      return;
    }
    _lastAttempt = now;
    final generation = _generation;
    busy = true;
    error = null;
    _notify();
    try {
      final selected =
          automaticLocation && !reuseLocation ? await _locate(false) : place;
      if (selected == null) throw Exception('请先选择城市或使用定位');
      if (generation != _generation || !enabled || _disposed) return;
      final response = await _client
          .get(Uri.https('api.open-meteo.com', '/v1/forecast', {
            'latitude': selected.latitude.toString(),
            'longitude': selected.longitude.toString(),
            'current': 'temperature_2m,weather_code',
            'timezone': 'auto',
          }))
          .timeout(const Duration(seconds: 15));
      if (response.statusCode != 200) throw Exception('天气暂时不可用，请稍后重试');
      final data =
          jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
      final current = data['current'] as Map<String, dynamic>;
      final temp = (current['temperature_2m'] as num).toDouble();
      if (!temp.isFinite) throw const FormatException('Invalid temperature');
      final updated = WeatherSnapshot(
          selected, (current['weather_code'] as num).toInt(), temp, _clock());
      if (generation != _generation || !enabled || _disposed) return;
      place = selected;
      snapshot = updated;
      await _save();
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
          'weather_background_cache', jsonEncode(updated.toJson()));
    } catch (e) {
      if (generation == _generation) error = _friendlyError(e);
    } finally {
      busy = false;
      _notify();
      if (_pendingRefresh && !_disposed) {
        _pendingRefresh = false;
        unawaited(refresh(force: true));
      }
    }
  }

  static Future<WeatherPlace> _deviceLocation(bool askPermission) async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      throw Exception('系统定位未开启，可以开启定位或手动选择城市');
    }
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied && askPermission) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      throw Exception('尚未授予定位权限，可使用定位按钮授权或手动选择城市');
    }
    final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.low, timeLimit: Duration(seconds: 20)));
    return WeatherPlace(
        '当前位置',
        double.parse(position.latitude.toStringAsFixed(2)),
        double.parse(position.longitude.toStringAsFixed(2)));
  }

  static String _friendlyError(Object error) {
    if (error is TimeoutException) return '获取位置或天气超时，可重试或手动选择城市';
    if (error is FormatException || error is TypeError) {
      return '天气数据暂时不可用，请稍后重试';
    }
    final text = error.toString().replaceFirst('Exception: ', '');
    return text.contains('PlatformException') || text.contains('MissingPlugin')
        ? '当前设备定位不可用，请手动选择城市'
        : text;
  }

  @override
  void dispose() {
    _disposed = true;
    _client.close();
    super.dispose();
  }
}
