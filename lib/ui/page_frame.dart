import 'package:flutter/material.dart';

/// Keeps content readable on large monitors while filling the viewport height.
class PageFrame extends StatelessWidget {
  final Widget child;
  final double maxWidth;
  final bool ambient;

  const PageFrame({
    super.key,
    required this.child,
    this.maxWidth = 1180,
    this.ambient = false,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      left: false,
      right: false,
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth),
          child: SizedBox.expand(child: child),
        ),
      ),
    );
  }
}
