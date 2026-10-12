import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:todo_app/models/weather_scene.dart';
import 'package:todo_app/ui/ambient_backdrop.dart';

void main() {
  test(
      'rain and snow cover all four daylight phases without changing custom index',
      () {
    expect(AmbientBackdrop.sceneAssets.length, 4);
    for (final weather in AmbientWeather.values) {
      final assets = [
        for (var i = 0; i < 4; i++) AmbientBackdrop.sceneAsset(i, weather)
      ];
      expect(assets.toSet().length, 4);
      for (final asset in assets) {
        expect(File(asset).existsSync(), isTrue, reason: asset);
      }
    }
    expect(AmbientBackdrop.sceneAsset(1, AmbientWeather.rain),
        endsWith('rain_dusk.png'));
    expect(AmbientBackdrop.sceneAsset(2, AmbientWeather.snow),
        endsWith('snow_night.png'));
  });
}
