/// Skeleton loader con efecto shimmer para Fernecito Locales.
library;

import 'package:flutter/material.dart';
import '../core/constants.dart';
import '../core/tema_app_locales.dart';

Color get _skeletonBase =>
    TemaAppLocales.instancia.esOscuro
        ? ColoresLocales.superficieElevada
        : ColoresLocales.grisClaroFondo;

Color get _skeletonHighlight => Colors.white.withValues(
      alpha: TemaAppLocales.instancia.esOscuro ? 0.06 : 0.35,
    );

class ShimmerSkeleton extends StatefulWidget {
  const ShimmerSkeleton({super.key, required this.child});

  final Widget child;

  @override
  State<ShimmerSkeleton> createState() => _ShimmerSkeletonState();
}

class _ShimmerSkeletonState extends State<ShimmerSkeleton>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat();
    _animation = Tween<double>(begin: -2, end: 2).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        final t = (_animation.value + 1) / 2;
        return ShaderMask(
          blendMode: BlendMode.srcATop,
          shaderCallback: (bounds) {
            return LinearGradient(
              begin: Alignment(t - 0.4, 0),
              end: Alignment(t + 0.4, 0),
              colors: [
                _skeletonBase,
                _skeletonHighlight,
                _skeletonBase,
              ],
              stops: const [0.0, 0.5, 1.0],
            ).createShader(bounds);
          },
          child: child,
        );
      },
      child: widget.child,
    );
  }
}

Widget ShimmerBox({
  double? width,
  double? height,
  double borderRadius = 12,
}) {
  return ShimmerSkeleton(
    child: Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: _skeletonBase,
        borderRadius: BorderRadius.circular(borderRadius),
      ),
    ),
  );
}

Widget ShimmerLine({
  double? width,
  double height = 14,
  double borderRadius = 6,
}) {
  return ShimmerSkeleton(
    child: Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: _skeletonBase,
        borderRadius: BorderRadius.circular(borderRadius),
      ),
    ),
  );
}
