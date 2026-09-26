import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// The Rockketeyes mark: an iris of the game's ink colors around a gold
/// pupil, with a comet orbiting like a rocket.
///
/// Geometry and timing mirror `tool/brand/logo.mjs`, which generates the app
/// icons and the web loading splash, so the mark is identical everywhere.
class RockketeyesLogo extends StatefulWidget {
  const RockketeyesLogo({super.key, this.size = 120, this.animate = true});

  final double size;
  final bool animate;

  @override
  State<RockketeyesLogo> createState() => _RockketeyesLogoState();
}

class _RockketeyesLogoState extends State<RockketeyesLogo> with SingleTickerProviderStateMixin {
  // One 24 s cycle = one iris turn = ten comet orbits / pupil breaths.
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(seconds: 24));

  @override
  void initState() {
    super.initState();
    if (widget.animate) _c.repeat();
  }

  @override
  void didUpdateWidget(RockketeyesLogo old) {
    super.didUpdateWidget(old);
    if (widget.animate && !_c.isAnimating) _c.repeat();
    if (!widget.animate && _c.isAnimating) _c.stop();
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
            builder: (context, _) => CustomPaint(painter: LogoPainter(_c.value)),
          ),
        ),
      ),
    );
  }
}

/// Paints the mark on a 512-unit design grid scaled to the canvas.
class LogoPainter extends CustomPainter {
  LogoPainter(this.t);

  /// Position in the 24 s master cycle, 0..1.
  final double t;

  static const _inks = [
    Color(0xFFFF4D5E), Color(0xFFFF9F1C), Color(0xFFFFD93D), Color(0xFF2EE59D),
    Color(0xFF4D8DFF), Color(0xFFB57BFF), Color(0xFFFF6FCF), Color(0xFFF5F5F7),
  ];

  // Shared with tool/brand/logo.mjs.
  static const _orbitR = 214.0, _orbitW = 3.0;
  static const _irisR = 152.0, _irisW = 46.0, _gapDeg = 6.0;
  static const _lensR = 126.0, _pupilR = 66.0;
  static const _cometDeg = -38.0, _cometTailDeg = 78.0, _cometR = 11.0;

  static double _rad(double d) => d * math.pi / 180;

  /// CSS `cubic-bezier(.45,.05,.55,.95)` approximated by an ease-in-out sine.
  static double _ease(double x) => -(math.cos(math.pi * x) - 1) / 2;

  @override
  void paint(Canvas canvas, Size size) {
    final k = size.width / 512;
    canvas.save();
    canvas.scale(k);
    const c = Offset(256, 256);

    final spin = t * 2 * math.pi;
    final sub = (t * 10) % 1.0; // 2.4 s sub-cycle
    final orbit = _ease(sub) * 2 * math.pi;
    final breath = 1 + 0.06 * math.sin(sub * math.pi);
    final glow = 0.55 + 0.45 * math.sin(sub * math.pi);

    // Halo.
    canvas.drawCircle(
      c,
      236,
      Paint()
        ..shader = RadialGradient(
          colors: [
            const Color(0xFF7C5CFF).withValues(alpha: 0.38 * glow),
            const Color(0xFF7C5CFF).withValues(alpha: 0),
          ],
          stops: const [0.55, 1],
        ).createShader(Rect.fromCircle(center: c, radius: 236)),
    );

    // Orbit track.
    canvas.drawCircle(
      c,
      _orbitR,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = _orbitW
        ..color = Colors.white.withValues(alpha: 0.10),
    );

    // Iris underlay keeps the gaps between segments dark and crisp.
    canvas.drawCircle(
      c,
      _irisR,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = _irisW + 4
        ..color = const Color(0xFF0C0A1A),
    );

    // Iris segments (rotating).
    canvas.save();
    canvas.translate(c.dx, c.dy);
    canvas.rotate(spin);
    canvas.translate(-c.dx, -c.dy);
    final irisRect = Rect.fromCircle(center: c, radius: _irisR);
    const seg = 360 / 8;
    for (var i = 0; i < _inks.length; i++) {
      canvas.drawArc(
        irisRect,
        _rad(-90 + i * seg + _gapDeg / 2),
        _rad(seg - _gapDeg),
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = _irisW
          ..strokeCap = StrokeCap.butt
          ..color = _inks[i],
      );
    }
    // Depth shading across the ring.
    const outer = _irisR + _irisW / 2;
    canvas.drawCircle(
      c,
      _irisR,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = _irisW
        ..shader = RadialGradient(
          colors: [
            Colors.black.withValues(alpha: 0.42),
            Colors.black.withValues(alpha: 0),
            Colors.white.withValues(alpha: 0.10),
            Colors.black.withValues(alpha: 0.30),
          ],
          stops: const [(_irisR - _irisW / 2) / outer, (_irisR - 6) / outer, 0.9, 1],
        ).createShader(Rect.fromCircle(center: c, radius: outer)),
    );
    canvas.restore();

    // Lens.
    final lensRect = Rect.fromCircle(center: c, radius: _lensR);
    canvas.drawCircle(
      c,
      _lensR,
      Paint()
        ..shader = const RadialGradient(
          center: Alignment(-0.16, -0.28),
          radius: 0.7,
          colors: [Color(0xFF241D45), Color(0xFF0C0A1A), Color(0xFF07060F)],
          stops: [0, 0.7, 1],
        ).createShader(lensRect),
    );
    canvas.drawCircle(
      c,
      _lensR - 0.75,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = Colors.white.withValues(alpha: 0.14),
    );

    // Pupil (breathing).
    canvas.save();
    canvas.translate(c.dx, c.dy);
    canvas.scale(breath);
    canvas.translate(-c.dx, -c.dy);
    canvas.drawCircle(c, _pupilR + 14, Paint()..color = AppColors.gold.withValues(alpha: 0.16));
    canvas.drawCircle(
      c,
      _pupilR,
      Paint()
        ..shader = const RadialGradient(
          center: Alignment(-0.24, -0.32),
          radius: 0.72,
          colors: [AppColors.goldSoft, AppColors.gold, AppColors.goldDeep],
          stops: [0, 0.5, 1],
        ).createShader(Rect.fromCircle(center: c, radius: _pupilR)),
    );
    canvas.save();
    canvas.translate(c.dx - 22, c.dy - 25);
    canvas.rotate(_rad(-30));
    canvas.drawOval(
      Rect.fromCenter(center: Offset.zero, width: 34, height: 26),
      Paint()..color = Colors.white.withValues(alpha: 0.92),
    );
    canvas.restore();
    canvas.drawCircle(c + const Offset(20, 22), 5, Paint()..color = Colors.white.withValues(alpha: 0.45));
    canvas.restore();

    // Comet (orbiting).
    canvas.save();
    canvas.translate(c.dx, c.dy);
    canvas.rotate(orbit);
    canvas.translate(-c.dx, -c.dy);
    Offset at(double deg) => c + Offset(math.cos(_rad(deg)), math.sin(_rad(deg))) * _orbitR;
    final head = at(_cometDeg);
    final tail = at(_cometDeg - _cometTailDeg);
    canvas.drawArc(
      Rect.fromCircle(center: c, radius: _orbitR),
      _rad(_cometDeg - _cometTailDeg),
      _rad(_cometTailDeg),
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 7
        ..strokeCap = StrokeCap.round
        ..shader = LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: [
            AppColors.gold.withValues(alpha: 0),
            AppColors.gold.withValues(alpha: 0.85),
            const Color(0xFFFFF6DD),
          ],
          stops: const [0, 0.75, 1],
        ).createShader(Rect.fromPoints(tail, head)),
    );
    canvas.drawCircle(
      head,
      _cometR * 2.2,
      Paint()
        ..shader = RadialGradient(
          colors: [Colors.white, const Color(0xFFFFF1C9), AppColors.gold.withValues(alpha: 0)],
          stops: const [0, 0.45, 1],
        ).createShader(Rect.fromCircle(center: head, radius: _cometR * 2.2)),
    );
    canvas.drawCircle(head, _cometR * 0.62, Paint()..color = Colors.white);
    canvas.restore();

    canvas.restore();
  }

  @override
  bool shouldRepaint(LogoPainter old) => old.t != t;
}

/// "Rockketeyes" wordmark with the same gradient as the web splash.
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
