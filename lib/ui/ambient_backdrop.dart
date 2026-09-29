import 'dart:io';

import 'package:flutter/material.dart';

/// The photograph remains sharp. Only local content surfaces blur it.
class AmbientBackdrop extends StatelessWidget {
  const AmbientBackdrop({
    super.key,
    this.compact = false,
    this.sceneIndex = 0,
    this.customPath,
    this.customPortraitX = 0,
    this.shade = .10,
  });

  static const sceneAssets = [
    'assets/backgrounds/alpine_noon.png',
    'assets/backgrounds/alpine_dusk.png',
    'assets/backgrounds/alpine_night.png',
    'assets/backgrounds/alpine_dawn.png',
  ];
  static const sceneNames = ['山间午后', '山间晚霞', '山间夜色', '山间日出'];

  /// Four light states of the same study scene, using the device's local hour.
  static int sceneForHour(int hour) {
    if (hour >= 5 && hour < 9) return 3;
    if (hour >= 9 && hour < 17) return 0;
    if (hour >= 17 && hour < 20) return 1;
    return 2;
  }

  static int restoreSceneIndex(int selected,
      {required bool oldCatalog, required bool hasCustom}) {
    final migrated = oldCatalog && selected == 3
        ? (hasCustom ? sceneAssets.length : 0)
        : selected;
    if (migrated == sceneAssets.length && !hasCustom) return 0;
    return migrated.clamp(0, sceneAssets.length);
  }

  final bool compact;
  final int sceneIndex;
  final String? customPath;
  final double customPortraitX;
  final double shade;

  @override
  Widget build(BuildContext context) {
    final custom = sceneIndex == sceneAssets.length &&
        customPath != null &&
        File(customPath!).existsSync();
    final index = sceneIndex.clamp(0, sceneAssets.length - 1);
    final alignment = compact
        ? Alignment(custom ? customPortraitX.clamp(-1.0, 1.0) : -.10, 0)
        : Alignment.center;
    return Stack(fit: StackFit.expand, children: [
      AnimatedSwitcher(
        duration: Duration(milliseconds: compact ? 1200 : 1800),
        switchInCurve: Curves.easeInOutCubic,
        switchOutCurve: Curves.easeInOutCubic,
        child: SizedBox.expand(
          key: ValueKey(custom ? customPath : index),
          child: custom
              ? Image.file(File(customPath!),
                  fit: BoxFit.cover,
                  alignment: alignment,
                  filterQuality: FilterQuality.medium)
              : Image.asset(sceneAssets[index],
                  fit: BoxFit.cover,
                  alignment: alignment,
                  filterQuality: FilterQuality.medium),
        ),
      ),
      // The adjustment affects the image alone, never text or controls.
      ColoredBox(
        color: const Color(0xFF111B20).withValues(alpha: shade.clamp(0.0, .28)),
      ),
      // 环境光关系：远景天光偏冷（顶部轻压），室内灯光偏暖（底部回弹）。
      // 固定的极弱渐变，不随 shade 滑杆变化，保证照片始终清晰可感。
      const DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            stops: [0, .55, 1],
            colors: [
              Color(0x1A16222E),
              Color(0x00000000),
              Color(0x11302617),
            ],
          ),
        ),
      ),
    ]);
  }
}
