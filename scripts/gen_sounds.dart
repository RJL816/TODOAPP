// 生成应用音效资源（16-bit PCM 单声道 WAV），运行：dart run scripts/gen_sounds.dart
import 'dart:io';
import 'dart:math';

const sampleRate = 44100;

void main() {
  writeWav('assets/sounds/check.wav', [
    ...tone(880, 0.15, 0.45),
  ]);
  // 完成音：上行三连音
  writeWav('assets/sounds/celebration.wav', [
    ...tone(523.25, 0.16, 0.4),
    ...tone(659.25, 0.16, 0.4),
    ...tone(783.99, 0.28, 0.45),
  ]);
}

/// 单音：快速起音 + 指数衰减的正弦波
List<int> tone(double freq, double seconds, double volume) {
  final n = (seconds * sampleRate).floor();
  return List<int>.generate(n, (i) {
    final t = i / sampleRate;
    final attack = i < 220 ? i / 220 : 1.0;
    final envelope = attack * exp(-5 * t);
    final v = sin(2 * pi * freq * t) * envelope * volume;
    return (v * 32767).round().clamp(-32768, 32767);
  });
}

void writeWav(String path, List<int> samples) {
  final bytes = <int>[];
  void str(String s) => bytes.addAll(s.codeUnits);
  void u32(int v) =>
      bytes.addAll([v & 255, (v >> 8) & 255, (v >> 16) & 255, (v >> 24) & 255]);
  void u16(int v) => bytes.addAll([v & 255, (v >> 8) & 255]);

  final dataLen = samples.length * 2;
  str('RIFF');
  u32(36 + dataLen);
  str('WAVE');
  str('fmt ');
  u32(16); // PCM chunk size
  u16(1); // PCM
  u16(1); // mono
  u32(sampleRate);
  u32(sampleRate * 2); // byte rate
  u16(2); // block align
  u16(16); // bits per sample
  str('data');
  u32(dataLen);
  for (final s in samples) {
    u16(s & 0xffff);
  }

  File(path).writeAsBytesSync(bytes);
  print('wrote $path (${samples.length} samples, ${(samples.length / sampleRate).toStringAsFixed(2)}s)');
}
