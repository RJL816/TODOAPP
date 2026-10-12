import 'package:flutter/material.dart';

/// Android 的拉伸滤镜会隔离背景采样，令玻璃在边缘拉动时变色。
/// 对所有页面和弹层使用位置回弹，保留滚动反馈及用户的玻璃设置。
class GlassScrollBehavior extends MaterialScrollBehavior {
  const GlassScrollBehavior();

  @override
  ScrollPhysics getScrollPhysics(BuildContext context) =>
      getPlatform(context) == TargetPlatform.android
          ? const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics())
          : super.getScrollPhysics(context);

  @override
  Widget buildOverscrollIndicator(
          BuildContext context, Widget child, ScrollableDetails details) =>
      getPlatform(context) == TargetPlatform.android
          ? child
          : super.buildOverscrollIndicator(context, child, details);
}
