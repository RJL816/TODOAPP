import 'package:flutter/material.dart';

/// Quiet Academic / Digital Journal.
/// 暖白纸面 + 深墨蓝文字 + 琥珀色只承担"正在发生 / 专注 / 连续"语义。
abstract final class AppColors {
  // 纸面
  static const canvas = Color(0xFFF2F0EA); // 无照片时的暖纸底色
  static const paper = Color(0xFFF8FAF8); // 主表面
  static const paperSoft = Color(0xFFEAEDEB); // 次级表面

  // 墨
  static const ink = Color(0xFF172A3A); // 主文字（非纯黑）
  static const muted = Color(0xFF344A5A); // 照片背景上的辅助文字保持清晰

  // 结构色
  static const navy = Color(0xFF293F50); // 链接 / 选中 / 图形
  static const navySoft = Color(0xFFE5ECEE);
  static const forest = navy; // 既有组件沿用这一主色令牌
  static const forestSoft = navySoft;

  // 语义琥珀：只用于 正在发生 / 当前 / Focus / Streak
  static const amber = Color(0xFFD89523);
  static const amberSoft = Color(0xFFF8EEDC);

  // 线
  static const line = Color(0xFFB9C5C7); // 发丝线

  // 低饱和功能色（语义辅助，不做彩虹）
  static const clay = amber;
  static const olive = Color(0xFF7E8590);
  static const slate = Color(0xFF687D91);
  static const moss = Color(0xFF6E7F6A); // 训练 / 生活记录

  // 环境玻璃（Ambient Glass）：照片背景上的悬浮层
  static const glassNight = Color(0xFF1C2833); // 深墨蓝玻璃面（冷，天光侧）
  static const warmCream = Color(0xFFF2E4C9); // 室内暖光（暖白奶油色）
  static const warmAmber = Color(0xFFE4A93E); // 暖琥珀（按钮高光 / 火焰 / 强调）
  static const warmInk = Color(0xFF2A2114); // 暖面上的深字（非纯黑）
  static const actionFill = Color(0xFFDCE6E5); // 安静的雾蓝灰主操作
  static const actionFillDeep = Color(0xFFC8D5D5);
  static const actionInk = Color(0xFF1B303C);
}

abstract final class AppTypography {
  /// MiSans（小米×汉仪，免费商用）。assets/fonts 内为按项目字符集
  /// 子集化的 4 个静态字重（见 assets/fonts/README-MiSans.md 与
  /// scripts/subset_misans.py）；生僻字运行时回退系统字体。
  static const sans = 'MiSans';
  static const serif = 'NotoSerifSC';
}

/// Consistent sans typography for the workspace; numerals remain tabular.
abstract final class AppType {
  /// Page headings and prominent numbers.
  static TextStyle display({
    double size = 34,
    FontWeight weight = FontWeight.w600,
    Color color = AppColors.ink,
    double letterSpacing = 0,
    double? height,
  }) {
    return TextStyle(
      fontFamily: AppTypography.sans,
      fontSize: size,
      fontWeight: weight,
      color: color,
      letterSpacing: letterSpacing,
      height: height ?? 1.25,
    );
  }

  /// 小型大写栏目词（极少量使用，每 3 个区块至多 1 个）
  static TextStyle overline({Color color = AppColors.muted}) {
    return TextStyle(
      fontFamily: AppTypography.sans,
      fontSize: 11,
      fontWeight: FontWeight.w600,
      letterSpacing: 1.2,
      color: color,
    );
  }

  /// 杂志式标题（衬线，只用于固定文案：问候语等。
  /// NotoSerifSC-Headings 是子集字体，不含任意汉字与 ASCII 标点，
  /// 用户输入内容（任务标题等）必须继续使用 sans。）
  static TextStyle editorial({
    double size = 42,
    FontWeight weight = FontWeight.w600,
    Color color = AppColors.ink,
    double letterSpacing = .5,
    double? height,
  }) {
    return TextStyle(
      fontFamily: AppTypography.serif,
      fontSize: size,
      fontWeight: weight,
      color: color,
      letterSpacing: letterSpacing,
      height: height ?? 1.18,
    );
  }

  /// 计时 / 金额等大数字的等宽数字特性
  static const List<FontFeature> tabular = [FontFeature.tabularFigures()];
}

ThemeData buildAppTheme() {
  final scheme = ColorScheme.fromSeed(seedColor: AppColors.forest).copyWith(
    primary: AppColors.forest,
    onPrimary: Colors.white,
    primaryContainer: AppColors.forestSoft,
    onPrimaryContainer: AppColors.ink,
    surface: AppColors.paper,
    onSurface: AppColors.ink,
    onSurfaceVariant: AppColors.muted,
    outline: AppColors.muted,
    outlineVariant: AppColors.line,
    surfaceContainerHighest: AppColors.paperSoft,
  );
  final baseText = ThemeData.light().textTheme.apply(
        fontFamily: AppTypography.sans,
        bodyColor: AppColors.ink,
        displayColor: AppColors.ink,
      );
  return ThemeData(
    useMaterial3: true,
    fontFamily: AppTypography.sans,
    colorScheme: scheme,
    scaffoldBackgroundColor: AppColors.canvas,
    canvasColor: AppColors.canvas,
    dividerColor: AppColors.line,
    textTheme: baseText.copyWith(
      headlineMedium: baseText.headlineMedium?.copyWith(
        fontSize: 28,
        fontWeight: FontWeight.w600,
        letterSpacing: 0,
        color: AppColors.ink,
      ),
      titleLarge: baseText.titleLarge?.copyWith(
        fontSize: 22,
        fontWeight: FontWeight.w600,
        letterSpacing: 0,
        color: AppColors.ink,
      ),
      titleMedium: baseText.titleMedium?.copyWith(
        fontSize: 16,
        fontWeight: FontWeight.w600,
        color: AppColors.ink,
      ),
      titleSmall: baseText.titleSmall?.copyWith(
        fontSize: 15,
        fontWeight: FontWeight.w600,
        color: AppColors.ink,
      ),
      bodyLarge: baseText.bodyLarge
          ?.copyWith(fontSize: 16, height: 1.6, fontWeight: FontWeight.w500),
      bodyMedium: baseText.bodyMedium
          ?.copyWith(fontSize: 15, height: 1.55, fontWeight: FontWeight.w500),
      bodySmall: baseText.bodySmall
          ?.copyWith(fontSize: 13, height: 1.45, fontWeight: FontWeight.w500),
      labelSmall: baseText.labelSmall
          ?.copyWith(fontSize: 12, fontWeight: FontWeight.w500),
    ),
    cardTheme: CardThemeData(
      color: AppColors.paper.withValues(alpha: .80),
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Colors.white.withValues(alpha: .62)),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.paper.withValues(alpha: .47),
      hintStyle: const TextStyle(
        color: AppColors.muted,
        fontWeight: FontWeight.w500,
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: Colors.white.withValues(alpha: .70)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: AppColors.forest, width: 1.5),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
        side: BorderSide(color: Colors.white.withValues(alpha: .72)),
        backgroundColor: Colors.white.withValues(alpha: .30),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    ),
    popupMenuTheme: PopupMenuThemeData(
      // color 不固定：跟随 colorScheme.surface（环境模式深底浅字/纸面模式浅底深字）
      surfaceTintColor: Colors.transparent,
      elevation: 8,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Colors.white.withValues(alpha: .35)),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: AppColors.paper,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
    ),
    timePickerTheme: TimePickerThemeData(
      backgroundColor: AppColors.paper,
    ),
    datePickerTheme: DatePickerThemeData(
      backgroundColor: AppColors.paper,
    ),
    bottomNavigationBarTheme: const BottomNavigationBarThemeData(
      selectedItemColor: AppColors.forest,
      unselectedItemColor: AppColors.muted,
      backgroundColor: AppColors.paper,
      elevation: 0,
      type: BottomNavigationBarType.fixed,
      selectedLabelStyle: TextStyle(fontWeight: FontWeight.w600),
    ),
  );
}
