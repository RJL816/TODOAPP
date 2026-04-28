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

  // 音频播放器
  final AudioPlayer _audioPlayer = AudioPlayer();

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
      await _audioPlayer.play(AssetSource('sounds/check.mp3'));
    } catch (e) {
      // 如果音频文件不存在，静默失败
      debugPrint('Audio play failed: $e');
    }
  }

  /// 播放所有任务完成音效（更欢快的音效）
  Future<void> playAllCompleteSound() async {
    try {
      await _audioPlayer.play(AssetSource('sounds/celebration.mp3'));
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
    _audioPlayer.dispose();
    for (final controller in _confettiControllers) {
      controller.dispose();
    }
    _confettiControllers.clear();
  }
}

/// 连续打卡天数显示组件
class StreakDisplayWidget extends StatelessWidget {
  final int streak;

  const StreakDisplayWidget({
    super.key,
    required this.streak,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: streak > 0
              ? [Colors.orange[400]!, Colors.orange[600]!]
              : [Colors.grey[400]!, Colors.grey[500]!],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: (streak > 0 ? Colors.orange : Colors.grey).withOpacity(0.3),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 火焰图标（有连续天数时显示动画效果）
          if (streak > 0)
            const Icon(
              Icons.local_fire_department,
              color: Colors.white,
              size: 18,
            )
          else
            const Icon(
              Icons.emoji_events_outlined,
              color: Colors.white70,
              size: 18,
            ),
          const SizedBox(width: 8),
          // 文本显示
          Text(
            '$streak天',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 13,
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
  State<ConfettiCelebrationWidget> createState() => _ConfettiCelebrationWidgetState();
}

class _ConfettiCelebrationWidgetState extends State<ConfettiCelebrationWidget> {
  late ConfettiController _confettiController;

  @override
  void initState() {
    super.initState();
    _confettiController = GamificationService.instance.createConfettiController();
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
