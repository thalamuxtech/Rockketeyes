import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../features/game/domain/color_set.dart';
import '../theme/app_theme.dart';

/// The Rockketeyes mark: an iris of game colors around a gold pupil, slowly
/// rotating, with a comet-trail highlight.
class RockketeyesLogo extends StatefulWidget {
  const RockketeyesLogo({super.key, this.size = 120, this.animate = true});

  final double size;
  final bool animate;

  @override
  State<RockketeyesLogo> createState() => _RockketeyesLogoState();
}

class _RockketeyesLogoState extends State<RockketeyesLogo> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(seconds: 24));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (widget.animate && !reduce) {
      _c.repeat();
    } else {
      _c.stop();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Rockketeyes logo',
      image: true,
      child: RepaintBoundary(
        child: SizedBox.square(
          dimension: widget.size,
          child: AnimatedBuilder(
            animation: _c,
            builder: (context, _) => CustomPaint(painter: _LogoPainter(_c.value)),
          ),
        ),
      ),
    );
  }
}

class _LogoPainter extends CustomPainter {
  _LogoPainter(this.t);

  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.width / 2;

    // Outer glow.
    canvas.drawCircle(
      c,
      r * 0.92,
      Paint()
        ..color = AppColors.violet.withValues(alpha: 0.28)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, r * 0.22),
    );

    // Iris segments.
    final colors = kAllColors.map((e) => e.inkDark).toList();
    final seg = 2 * math.pi / colors.length;
    final rot = t * 2 * math.pi;
    final ring = Rect.fromCircle(center: c, radius: r * 0.74);
    for (var i = 0; i < colors.length; i++) {
      canvas.drawArc(
        ring,
        rot + i * seg + 0.06,
        seg - 0.12,
        false,
        Paint()
          ..color = colors[i]
          ..style = PaintingStyle.stroke
          ..strokeWidth = r * 0.2
          ..strokeCap = StrokeCap.round,
      );
    }

    // Inner dark disc.
    canvas.drawCircle(c, r * 0.54, Paint()..color = AppColors.bgDeep);
    canvas.drawCircle(
      c,
      r * 0.54,
      Paint()
        ..color = AppColors.glassBorder
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2,
    );

    // Gold pupil with gradient.
    final pupil = Rect.fromCircle(center: c, radius: r * 0.3);
    canvas.drawCircle(
      c,
      r * 0.3,
      Paint()..shader = const RadialGradient(
        colors: [AppColors.goldSoft, AppColors.gold, AppColors.goldDeep],
        stops: [0, 0.55, 1],
        center: Alignment(-0.3, -0.35),
      ).createShader(pupil),
    );

    // Rocket-trail glint orbiting the pupil.
    final a = -rot * 2.2;
    final glint = c + Offset(math.cos(a), math.sin(a)) * r * 0.42;
    canvas.drawCircle(
      glint,
      r * 0.05,
      Paint()
        ..color = Colors.white
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, r * 0.03),
    );
    canvas.drawArc(
      Rect.fromCircle(center: c, radius: r * 0.42),
      a - 0.9,
      0.9,
      false,
      Paint()
        ..shader = SweepGradient(
          startAngle: a - 0.9,
          endAngle: a,
          colors: [Colors.white.withValues(alpha: 0), Colors.white.withValues(alpha: 0.7)],
          transform: GradientRotation(0),
        ).createShader(Rect.fromCircle(center: c, radius: r * 0.42))
        ..style = PaintingStyle.stroke
        ..strokeWidth = r * 0.03
        ..strokeCap = StrokeCap.round,
    );

    // Specular highlight.
    canvas.drawCircle(
      c + Offset(-r * 0.1, -r * 0.11),
      r * 0.07,
      Paint()..color = Colors.white.withValues(alpha: 0.85),
    );
  }

  @override
  bool shouldRepaint(_LogoPainter old) => old.t != t;
}

/// "Rockketeyes" wordmark with a gold gradient.
class Wordmark extends StatelessWidget {
  const Wordmark({super.key, this.size = 40});

  final double size;

  @override
  Widget build(BuildContext context) {
    return ShaderMask(
      shaderCallback: (b) => const LinearGradient(
        colors: [AppColors.text, AppColors.goldSoft, AppColors.gold],
        stops: [0.0, 0.55, 1.0],
      ).createShader(b),
      child: Text('Rockketeyes', style: AppText.display(size, color: Colors.white)),
    );
  }
}
