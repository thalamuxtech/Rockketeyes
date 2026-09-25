import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../theme/app_theme.dart';

/// Animated cosmic backdrop driven by `shaders/nebula.frag`.
///
/// Falls back to a static gradient while the shader loads, if it fails to
/// compile, or when the platform asks for reduced motion.
class NebulaBackground extends StatefulWidget {
  const NebulaBackground({super.key, this.intensity = 1.0, this.child});

  final double intensity;
  final Widget? child;

  static Future<ui.FragmentProgram?>? _loading;

  static Future<ui.FragmentProgram?> _load() => _loading ??= ui.FragmentProgram
          .fromAsset('shaders/nebula.frag')
          .then<ui.FragmentProgram?>((p) => p)
          .catchError((Object _) => null);

  @override
  State<NebulaBackground> createState() => _NebulaBackgroundState();
}

class _NebulaBackgroundState extends State<NebulaBackground>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  final ValueNotifier<double> _time = ValueNotifier(0);
  ui.FragmentShader? _shader;
  Duration _lastFrame = Duration.zero;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick);
    NebulaBackground._load().then((program) {
      if (!mounted || program == null) return;
      setState(() => _shader = program.fragmentShader());
    });
  }

  void _onTick(Duration elapsed) {
    // ~20 fps is plenty for a slow nebula and keeps GPU cost low.
    if (elapsed - _lastFrame < const Duration(milliseconds: 50)) return;
    _lastFrame = elapsed;
    _time.value = elapsed.inMilliseconds / 1000.0;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (reduce && _ticker.isActive) {
      _ticker.stop();
    } else if (!reduce && !_ticker.isActive) {
      _ticker.start();
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    _time.dispose();
    _shader?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final shader = _shader;
    return Stack(
      fit: StackFit.expand,
      children: [
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [AppColors.bgDeep, AppColors.bgIndigo],
            ),
          ),
        ),
        if (shader != null)
          RepaintBoundary(
            child: CustomPaint(
              painter: _NebulaPainter(shader, _time, widget.intensity),
            ),
          ),
        ?widget.child,
      ],
    );
  }
}

class _NebulaPainter extends CustomPainter {
  _NebulaPainter(this.shader, this.time, this.intensity) : super(repaint: time);

  final ui.FragmentShader shader;
  final ValueNotifier<double> time;
  final double intensity;

  @override
  void paint(Canvas canvas, Size size) {
    shader
      ..setFloat(0, size.width)
      ..setFloat(1, size.height)
      ..setFloat(2, time.value)
      ..setFloat(3, intensity);
    canvas.drawRect(Offset.zero & size, Paint()..shader = shader);
  }

  @override
  bool shouldRepaint(_NebulaPainter old) =>
      old.shader != shader || old.intensity != intensity;
}
