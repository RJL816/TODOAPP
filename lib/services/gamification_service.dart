import 'dart:math';
import 'package:flutter/material.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:confetti/confetti.dart';

/// 游戏化服务 - 处理音效、动画等游戏化元素
class GamificationService {
  static GamificationService? _instance;
  static GamificationService get instance {
    _instance ??= GamificationService._();
    return _instance!;
  }

  GamificationService._();

  // 音频播放器：懒加载，未播放过音效前不占用原生资源
  AudioPlayer? _audioPlayer;
  AudioPlayer get _player => _audioPlayer ??= AudioPlayer();

  // Confetti 控制器列表（支持多个实例）
  final List<ConfettiController> _confettiControllers = [];

  /// 初始化服务
  Future<void> init() async {
    // 预加载音效
    await _preloadSounds();
  }

  /// 预加载音效文件
  Future<void> _preloadSounds() async {
    // 注意：这里使用内置音效，无需外部文件
    // 如果需要自定义音效，可以将音频文件放在 assets/audio/ 目录
    // 然后使用: await _audioPlayer.setAsset('assets/audio/check.mp3');
  }

  /// 播放任务完成音效（清脆的"叮"声）
  Future<void> playCheckSound() async {
    try {
      // 使用系统提示音作为替代
      // 在 Windows 上会播放系统默认的提示音
      await _player.play(AssetSource('sounds/check.wav'));
    } catch (e) {
      // 如果音频文件不存在，静默失败
      debugPrint('Audio play failed: $e');
    }
  }

  /// 播放所有任务完成音效（更欢快的音效）
  Future<void> playAllCompleteSound() async {
    try {
      await _player.play(AssetSource('sounds/celebration.wav'));
    } catch (e) {
      debugPrint('Audio play failed: $e');
    }
  }

  /// 创建 Confetti 控制器
  ConfettiController createConfettiController() {
    final controller = ConfettiController(
      duration: const Duration(seconds: 2),
    );
    _confettiControllers.add(controller);
    return controller;
  }

  /// 播放撒花动画
  void playConfetti(ConfettiController controller) {
    controller.play();
  }

  /// 停止所有 Confetti 动画
  void stopAllConfetti() {
    for (final controller in _confettiControllers) {
      controller.stop();
    }
  }

  /// 释放资源
  void dispose() {
    _audioPlayer?.dispose();
    _audioPlayer = null;
    for (final controller in _confettiControllers) {
      controller.dispose();
    }
    _confettiControllers.clear();
  }
}

/// 连续打卡天数显示组件（顶栏右侧的暖光玻璃胶囊）
class StreakDisplayWidget extends StatelessWidget {
  final int streak;

  const StreakDisplayWidget({
    super.key,
    required this.streak,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final lit = streak > 0;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        gradient: lit
            ? const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color(0x4DF6E3BE),
                  Color(0x24E4A93E),
                ],
              )
            : null,
        color: lit ? null : Colors.white.withValues(alpha: .10),
        border: Border.all(
          color: lit
              ? const Color(0x59FFFFFF)
              : Colors.white.withValues(alpha: .22),
        ),
        boxShadow: lit
            ? [
                BoxShadow(
                  color: const Color(0xFFE4A93E).withValues(alpha: .30),
                  blurRadius: 16,
                  offset: const Offset(0, 3),
                ),
              ]
            : null,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 火焰图标（有连续天数时点亮暖琥珀）
          if (lit)
            const Icon(
              Icons.local_fire_department,
              color: Color(0xFFF3B04E),
              size: 17,
            )
          else
            const Icon(
              Icons.emoji_events_outlined,
              color: Colors.white,
              size: 17,
            ),
          const SizedBox(width: 7),
          // 文本显示
          Text(
            '$streak天',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 13,
              letterSpacing: .3,
            ),
          ),
        ],
      ),
    );
  }
}

/// Confetti 撒花动画组件
class ConfettiCelebrationWidget extends StatefulWidget {
  final Widget child;
  final bool play;

  const ConfettiCelebrationWidget({
    super.key,
    required this.child,
    this.play = false,
  });

  @override
  State<ConfettiCelebrationWidget> createState() =>
      _ConfettiCelebrationWidgetState();
}

class _ConfettiCelebrationWidgetState extends State<ConfettiCelebrationWidget> {
  late ConfettiController _confettiController;

  @override
  void initState() {
    super.initState();
    _confettiController =
        GamificationService.instance.createConfettiController();
  }

  @override
  void didUpdateWidget(ConfettiCelebrationWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.play && !oldWidget.play) {
      GamificationService.instance.playConfetti(_confettiController);
    }
  }

  @override
  void dispose() {
    _confettiController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        widget.child,
        // 从中心向四周散开的彩带
        Align(
          alignment: Alignment.topCenter,
          child: ConfettiWidget(
            confettiController: _confettiController,
            blastDirection: pi / 2, // 向下
            blastDirectionality: BlastDirectionality.explosive,
            particleDrag: 0.05,
            emissionFrequency: 0.05,
            numberOfParticles: 50,
            gravity: 0.1,
            shouldLoop: false,
            colors: const [
              Colors.green,
              Colors.blue,
              Colors.pink,
              Colors.orange,
              Colors.purple,
            ],
          ),
        ),
        // 从左侧散开
        Align(
          alignment: Alignment.centerLeft,
          child: ConfettiWidget(
            confettiController: _confettiController,
            blastDirection: 0, // 向右
            blastDirectionality: BlastDirectionality.directional,
            particleDrag: 0.05,
            emissionFrequency: 0.05,
            numberOfParticles: 30,
            gravity: 0.05,
            shouldLoop: false,
            colors: const [
              Colors.yellow,
              Colors.red,
              Colors.cyan,
            ],
          ),
        ),
        // 从右侧散开
        Align(
          alignment: Alignment.centerRight,
          child: ConfettiWidget(
            confettiController: _confettiController,
            blastDirection: pi, // 向左
            blastDirectionality: BlastDirectionality.directional,
            particleDrag: 0.05,
            emissionFrequency: 0.05,
            numberOfParticles: 30,
            gravity: 0.05,
            shouldLoop: false,
            colors: const [
              Colors.lime,
              Colors.indigo,
              Colors.teal,
            ],
          ),
        ),
      ],
    );
  }
}
