/// 背景只表达晴、雨、雪；云雾仍保留原有时段照片。
enum AmbientWeather { clear, rain, snow }

AmbientWeather weatherSceneForCode(int code) {
  if ({71, 73, 75, 77, 85, 86}.contains(code)) {
    return AmbientWeather.snow;
  }
  if ({51, 53, 55, 56, 57, 61, 63, 65, 66, 67, 80, 81, 82, 95, 96, 97, 99}
      .contains(code)) {
    return AmbientWeather.rain;
  }
  return AmbientWeather.clear;
}
