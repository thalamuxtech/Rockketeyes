import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../env.dart';
import '../theme/app_theme.dart';

/// Animated galaxy backdrop driven by `shaders/nebula.frag`: spiral galaxy,
/// parallax starfield, shooting stars, comets and nebula gas.
///
/// Falls back to a static gradient while the shader loads, if it fails to
/// compile, or when the platform asks for reduced motion.
class NebulaBackground extends StatefulWidget {
  const NebulaBackground({
    super.key,
    this.intensity = 1.0,
    this.animate = true,
    this.calm = false,
    this.child,
  });

  final double intensity;

  /// False draws one still frame (used while playing to keep the game smooth).
  final bool animate;

  /// Quiet starfield only: no warp jumps, places, meteors or comets.
  final bool calm;
  final Widget? child;

  static Future<ui.FragmentProgram?>? _loading;

  /// Seconds added to the animation clock (tests jump to specific scenes).
  static double timeOffset = 0;

  /// Set when a device can't draw the shader fast enough (e.g. a browser
  /// without GPU acceleration); every backdrop then uses the gradient.
  static bool _tooSlow = false;
  static double? _jump;

  /// Jump every backdrop to animation second [t] (previews and tests).
  static void jumpTo(double t) => _jump = t;

  static Future<ui.FragmentProgram?> _load() => _loading ??= Env.lightBackground
      ? Future<ui.FragmentProgram?>.value(null)
      : ui.FragmentProgram.fromAsset('shaders/nebula.frag')
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
      if (!mounted || program == null || NebulaBackground._tooSlow) return;
      setState(() => _shader = program.fragmentShader());
      _probeSpeed();
    });
  }

  /// Times the first frames with the shader; falls back if they're too slow.
  void _probeSpeed() {
    if (_probed) return;
    _probed = true;
    final sw = Stopwatch()..start();
    var frames = 0;
    void onFrame(Duration _) {
      frames++;
      if (!mounted) return;
      if (frames < 4) {
        WidgetsBinding.instance.addPostFrameCallback(onFrame);
        WidgetsBinding.instance.scheduleFrame();
        return;
      }
      final avgMs = sw.elapsedMilliseconds / frames;
      if (avgMs > 90) {
        NebulaBackground._tooSlow = true;
        setState(() => _shader = null);
      }
    }
    WidgetsBinding.instance.addPostFrameCallback(onFrame);
  }

  static bool _probed = false;

  void _onTick(Duration elapsed) {
    // ~30 fps keeps shooting stars fluid while keeping GPU cost modest
    // (test builds tick slowly so several browsers can run side by side).
    final frame = Env.e2e
        ? const Duration(milliseconds: 250)
        : const Duration(milliseconds: 33);
    if (elapsed - _lastFrame < frame) return;
    _lastFrame = elapsed;
    final secs = elapsed.inMilliseconds / 1000.0;
    final jump = NebulaBackground._jump;
    if (jump != null) {
      NebulaBackground.timeOffset = jump - secs;
      NebulaBackground._jump = null;
    }
    _time.value = secs + NebulaBackground.timeOffset;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduce =
        !widget.animate ||
        (MediaQuery.maybeDisableAnimationsOf(context) ?? false);
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
              painter: _NebulaPainter(
                shader,
                _time,
                widget.intensity,
                widget.calm ? 1.0 : 0.0,
              ),
            ),
          ),
        ?widget.child,
      ],
    );
  }
}

class _NebulaPainter extends CustomPainter {
  _NebulaPainter(this.shader, this.time, this.intensity, this.calm)
    : super(repaint: time);

  final ui.FragmentShader shader;
  final ValueNotifier<double> time;
  final double intensity;
  final double calm;

  @override
  void paint(Canvas canvas, Size size) {
    shader
      ..setFloat(0, size.width)
      ..setFloat(1, size.height)
      ..setFloat(2, time.value)
      ..setFloat(3, intensity)
      ..setFloat(4, calm);
    canvas.drawRect(Offset.zero & size, Paint()..shader = shader);
  }

  @override
  bool shouldRepaint(_NebulaPainter old) =>
      old.shader != shader || old.intensity != intensity || old.calm != calm;
}
