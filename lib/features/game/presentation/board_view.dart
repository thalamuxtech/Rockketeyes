import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../application/round_controller.dart';
import '../domain/color_set.dart';
import '../domain/grid.dart';

/// Board geometry for a given viewport.
class BoardLayout {
  BoardLayout._(this.cellW, this.cellH, this.font, this.scrolls, this.cols, this.rows);

  static const double _minFont = 14;
  static const double _minFontFitAcross = 12;
  static const double _textPad = 16; // horizontal breathing room inside a cell
  static const double pad = 10;

  final double cellW;
  final double cellH;
  final double font;
  final bool scrolls;
  final int cols;
  final int rows;

  double get width => cellW * cols + pad * 2;
  double get height => cellH * rows + pad * 2;

  /// Small cells get a tighter, thinner ring so it never crowds the word.
  bool get dense => cellH < 48 || cellW < 90;
  double get ringInset => dense ? 2 : 3;
  double get ringStroke => dense ? 2 : 2.5;
  double get ringRadius => math.min(AppRadius.sm, (cellH - ringInset * 2) * 0.28);

  Rect rectOf(int index) {
    final r = index ~/ cols;
    final c = index % cols;
    return Rect.fromLTWH(pad + c * cellW, pad + r * cellH, cellW, cellH);
  }

  /// Highlight rectangle for a cell, snapped to whole pixels for crisp edges.
  Rect ringRectOf(int index) {
    final r = rectOf(index).deflate(ringInset);
    return Rect.fromLTRB(r.left.roundToDouble(), r.top.roundToDouble(), r.right.roundToDouble(),
        r.bottom.roundToDouble());
  }

  static final Map<String, double> _emCache = {};

  /// Width of the widest word per 1px of font size.
  static double _em(List<String> words) {
    final key = words.join(',');
    return _emCache.putIfAbsent(key, () {
      var widest = 0.0;
      for (final w in words) {
        final tp = TextPainter(
          text: TextSpan(text: w, style: AppText.boardWord(100, const Color(0xFFFFFFFF))),
          textDirection: TextDirection.ltr,
          maxLines: 1,
        )..layout();
        widest = math.max(widest, tp.width);
      }
      return math.max(widest, 1) / 100;
    });
  }

  factory BoardLayout.fit(Size box, GridSize size, List<String> words) {
    final em = _em(words);
    final w = box.width - pad * 2;
    final h = box.height - pad * 2;
    var cellW = w / size.cols;
    var cellH = math.max(0.0, math.min(h / size.rows, cellW * 0.62));
    var font = math.min(cellH * 0.42, (cellW - _textPad) / em);
    var scrolls = false;
    final fitAcross = (w / size.cols - _textPad) / em;
    if (font < _minFont && fitAcross >= _minFontFitAcross) {
      // Every column fits at a slightly smaller size: never scroll sideways,
      // only down, so no column is ever cut off.
      font = fitAcross;
      cellW = w / size.cols;
      cellH = math.max(font * 2.4, math.min(h / size.rows, cellW * 0.62));
      scrolls = cellH * size.rows > h + 0.5;
    } else if (font < _minFont) {
      // Too dense for the screen: keep text readable and scroll instead.
      scrolls = true;
      font = _minFont;
      cellW = math.max(cellW, font * em + _textPad + 8);
      cellH = math.max(font * 2.5, math.min(h / size.rows, cellW * 0.62));
    }
    font = math.min(font, 44);
    return BoardLayout._(cellW, cellH, font, scrolls, size.cols, size.rows);
  }
}

class BoardView extends StatefulWidget {
  const BoardView({super.key, required this.state, required this.darkInk});

  final RoundState state;
  final bool darkInk;

  @override
  State<BoardView> createState() => _BoardViewState();
}

class _BoardViewState extends State<BoardView> with TickerProviderStateMixin {
  final _v = ScrollController();
  final _h = ScrollController();
  late final AnimationController _breath =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1400));
  late final AnimationController _shake =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 420));
  BoardLayout? _layout;

  /// True when the highlight just wrapped to a new row: it should appear in
  /// place instead of sliding diagonally across the board.
  bool _rowJump = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (reduce) {
      _breath.stop();
    } else if (!_breath.isAnimating) {
      _breath.repeat(reverse: true);
    }
  }

  @override
  void didUpdateWidget(BoardView old) {
    super.didUpdateWidget(old);
    if (widget.state.mistake != null && old.state.mistake == null) {
      _shake.forward(from: 0);
    }
    if (widget.state.activeIndex != old.state.activeIndex) {
      final cols = widget.state.config.size.cols;
      _rowJump = widget.state.activeIndex ~/ cols != old.state.activeIndex ~/ cols;
      WidgetsBinding.instance.addPostFrameCallback((_) => _ensureVisible());
    }
  }

  void _ensureVisible() {
    final l = _layout;
    if (l == null || !l.scrolls || !mounted) return;
    final idx = math.min(widget.state.activeIndex, widget.state.cells.length - 1);
    if (idx < 0) return;
    final rect = l.rectOf(idx);
    // Only scroll when the active cell (plus a little look-ahead) leaves the
    // viewport, so the player keeps their place instead of the board jumping.
    void reveal(ScrollController c, double start, double end, double lookAhead) {
      if (!c.hasClients) return;
      final pos = c.position;
      final view = pos.viewportDimension;
      final offset = pos.pixels;
      double? target;
      if (start < offset + 4) {
        target = start - lookAhead * 0.5;
      } else if (end + lookAhead > offset + view) {
        target = start - view * 0.3;
      }
      if (target == null) return;
      c.animateTo(target.clamp(0.0, pos.maxScrollExtent), duration: AppMotion.short, curve: AppMotion.curve);
    }

    reveal(_v, rect.top - BoardLayout.pad, rect.bottom, l.cellH * 2);
    if (idx % l.cols == 0 && _h.hasClients) {
      _h.animateTo(0, duration: AppMotion.short, curve: AppMotion.curve);
    } else {
      reveal(_h, rect.left - BoardLayout.pad, rect.right, l.cellW * 1.5);
    }
  }

  @override
  void dispose() {
    _v.dispose();
    _h.dispose();
    _breath.dispose();
    _shake.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.state;
    return LayoutBuilder(builder: (context, box) {
      final words = [for (final c in s.config.colorSet.colors) c.word[0] + c.word.substring(1).toLowerCase()];
      final layout = _layout = BoardLayout.fit(box.biggest, s.config.size, words);
      final board = SizedBox(
        width: layout.width,
        height: layout.height,
        child: _boardStack(layout, s),
      );

      Widget content = layout.scrolls
          ? _EdgeFade(
              child: Scrollbar(
              controller: _v,
              child: SingleChildScrollView(
                controller: _v,
                child: SingleChildScrollView(
                  controller: _h,
                  scrollDirection: Axis.horizontal,
                  child: board,
                ),
              ),
            ))
          : Center(child: board);

      content = AnimatedBuilder(
        animation: _shake,
        builder: (context, child) {
          final t = _shake.value;
          final dx = math.sin(t * math.pi * 6) * 10 * (1 - t);
          return Transform.translate(offset: Offset(dx, 0), child: child);
        },
        child: content,
      );
      return content;
    });
  }

  Widget _boardStack(BoardLayout l, RoundState s) {
    final active = s.activeIndex < s.cells.length ? s.activeIndex : null;
    final playing = s.phase == RoundPhase.playing;
    final hidden = s.phase == RoundPhase.preparing ||
        s.phase == RoundPhase.arming ||
        s.phase == RoundPhase.paused ||
        (s.phase == RoundPhase.countdown && s.events.isEmpty);

    return Semantics(
      label: active == null
          ? 'Board complete'
          : 'Cell ${active + 1} of ${s.cells.length}. Say the ink color.',
      liveRegion: true,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: AppColors.board,
          borderRadius: BorderRadius.circular(AppRadius.lg),
          border: Border.all(color: AppColors.boardEdge, width: 1.5),
          boxShadow: const [
            BoxShadow(color: Color(0x66000000), blurRadius: 40, offset: Offset(0, 18)),
            BoxShadow(color: Color(0x227C5CFF), blurRadius: 60, spreadRadius: -10),
          ],
        ),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            // Active-row band.
            if (active != null && !hidden)
              AnimatedPositioned(
                duration: AppMotion.short,
                curve: AppMotion.curve,
                left: BoardLayout.pad / 2,
                right: BoardLayout.pad / 2,
                top: l.rectOf(active).top,
                height: l.cellH,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: const Color(0x0AFFFFFF),
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                  ),
                ),
              ),
            // Highlight ring: glides along a row, pops in on a new row.
            if (active != null && !hidden && s.mistake == null)
              AnimatedPositioned.fromRect(
                duration: _rowJump ? Duration.zero : const Duration(milliseconds: 170),
                curve: Curves.easeOutCubic,
                rect: l.ringRectOf(active),
                child: IgnorePointer(
                  child: TweenAnimationBuilder<double>(
                    key: ValueKey('row${active ~/ l.cols}'),
                    tween: Tween(begin: 0, end: 1),
                    duration: const Duration(milliseconds: 160),
                    curve: Curves.easeOutCubic,
                    builder: (context, t, child) => Opacity(
                      opacity: t,
                      child: Transform.scale(scale: 0.92 + 0.08 * t, child: child),
                    ),
                    child: AnimatedBuilder(
                      animation: _breath,
                      builder: (context, _) => _HighlightRing(
                        glow: playing ? _breath.value : 0.3,
                        radius: l.ringRadius,
                        stroke: l.ringStroke,
                        dense: l.dense,
                      ),
                    ),
                  ),
                ),
              ),
            Positioned.fill(
              child: AnimatedOpacity(
                opacity: hidden ? 0 : 1,
                duration: AppMotion.medium,
                child: RepaintBoundary(
                  child: CustomPaint(
                    painter: _WordsPainter(
                      cells: s.cells,
                      layout: l,
                      active: active,
                      answered: s.events.where((e) => e.correct).length,
                      mistake: s.mistake?.index,
                      dark: widget.darkInk,
                    ),
                  ),
                ),
              ),
            ),
            if (hidden) Positioned.fill(child: _HiddenBoardVeil(phase: s.phase)),
            // Correct burst on the cell just answered.
            if (s.lastCorrectIndex >= 0 && !hidden)
              Positioned.fromRect(
                key: ValueKey('burst${s.lastCorrectIndex}'),
                rect: l.ringRectOf(s.lastCorrectIndex),
                child: IgnorePointer(child: _Burst(color: AppColors.success, radius: l.ringRadius)),
              ),
            if (s.mistake != null)
              Positioned.fromRect(
                rect: l.ringRectOf(s.mistake!.index),
                child: IgnorePointer(child: _MistakeRing(radius: l.ringRadius, stroke: l.ringStroke + 0.5)),
              ),
          ],
        ),
      ),
    );
  }
}

class _HiddenBoardVeil extends StatelessWidget {
  const _HiddenBoardVeil({required this.phase});

  final RoundPhase phase;

  @override
  Widget build(BuildContext context) {
    final text = switch (phase) {
      RoundPhase.paused => 'Paused',
      RoundPhase.preparing => 'Preparing board…',
      RoundPhase.arming => 'Warming up the mic…',
      _ => '',
    };
    return Center(
      child: AnimatedSwitcher(
        duration: AppMotion.short,
        child: Text(text, key: ValueKey(text), style: AppText.label(15, color: AppColors.textMuted)),
      ),
    );
  }
}

class _HighlightRing extends StatelessWidget {
  const _HighlightRing({required this.glow, required this.radius, required this.stroke, required this.dense});

  final double glow;
  final double radius;
  final double stroke;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: AppColors.gold, width: stroke, strokeAlign: BorderSide.strokeAlignInside),
        color: AppColors.gold.withValues(alpha: 0.07),
        boxShadow: [
          BoxShadow(
            color: AppColors.gold.withValues(alpha: 0.35 + 0.35 * glow),
            blurRadius: dense ? 5 + 5 * glow : 10 + 12 * glow,
            blurStyle: BlurStyle.outer,
          ),
        ],
      ),
    );
  }
}

class _Burst extends StatelessWidget {
  const _Burst({required this.color, required this.radius});

  final Color color;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 420),
      curve: Curves.easeOutCubic,
      builder: (context, t, _) => Opacity(
        opacity: (1 - t).clamp(0, 1),
        child: Transform.scale(
          scale: 0.96 + 0.06 * t,
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(radius),
              border: Border.all(color: color, width: 2),
              boxShadow: [BoxShadow(color: color.withValues(alpha: 0.5), blurRadius: 16, blurStyle: BlurStyle.outer)],
            ),
          ),
        ),
      ),
    );
  }
}

class _MistakeRing extends StatelessWidget {
  const _MistakeRing({required this.radius, required this.stroke});

  final double radius;
  final double stroke;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 600),
      curve: Curves.elasticOut,
      builder: (context, t, _) => Transform.scale(
        scale: 0.85 + 0.15 * t,
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(radius),
            color: AppColors.error.withValues(alpha: 0.10),
            border: Border.all(color: AppColors.error, width: stroke, strokeAlign: BorderSide.strokeAlignInside),
            boxShadow: [
              BoxShadow(color: AppColors.error.withValues(alpha: 0.7), blurRadius: 18, blurStyle: BlurStyle.outer),
            ],
          ),
        ),
      ),
    );
  }
}

class _WordsPainter extends CustomPainter {
  _WordsPainter({
    required this.cells,
    required this.layout,
    required this.active,
    required this.answered,
    required this.mistake,
    required this.dark,
  });

  final List<Cell> cells;
  final BoardLayout layout;
  final int? active;
  final int answered;
  final int? mistake;
  final bool dark;

  static final Map<String, TextPainter> _cache = {};

  TextPainter _text(String word, Color color, double font) {
    final key = '$word|${color.toARGB32()}|${font.toStringAsFixed(1)}';
    return _cache.putIfAbsent(key, () {
      if (_cache.length > 600) _cache.clear();
      return TextPainter(
        text: TextSpan(text: word, style: AppText.boardWord(font, color)),
        textDirection: TextDirection.ltr,
        maxLines: 1,
      )..layout();
    });
  }

  @override
  void paint(Canvas canvas, Size size) {
    final checkPaint = Paint()
      ..color = AppColors.success
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round;
    for (final cell in cells) {
      final rect = layout.rectOf(cell.index);
      final done = cell.index < answered;
      final color = colorByKey(cell.ink).ink(darkBoard: dark);
      final word = _titleCase(colorByKey(cell.word).word);
      final alpha = done ? 0.22 : (cell.index == mistake ? 1.0 : 1.0);
      final tp = _text(word, color.withValues(alpha: alpha), layout.font);
      final maxW = rect.width - 12;
      final scale = tp.width > maxW ? maxW / tp.width : 1.0;
      canvas.save();
      canvas.translate(rect.center.dx, rect.center.dy);
      canvas.scale(scale);
      tp.paint(canvas, Offset(-tp.width / 2, -tp.height / 2));
      canvas.restore();

      final free = (rect.width - tp.width * scale) / 2;
      final checkSize = math.max(5.0, layout.font * 0.28);
      if (done && free >= checkSize * 1.6 + 6) {
        final s = checkSize;
        final o = Offset(rect.right - s - 5, rect.top + s + 4);
        final path = Path()
          ..moveTo(o.dx - s * 0.5, o.dy)
          ..lineTo(o.dx - s * 0.1, o.dy + s * 0.4)
          ..lineTo(o.dx + s * 0.6, o.dy - s * 0.4);
        canvas.drawPath(path, checkPaint);
      }
    }
  }

  static String _titleCase(String w) => w[0] + w.substring(1).toLowerCase();

  @override
  bool shouldRepaint(_WordsPainter old) =>
      old.cells != cells ||
      old.answered != answered ||
      old.active != active ||
      old.mistake != mistake ||
      old.dark != dark ||
      old.layout.cellW != layout.cellW ||
      old.layout.cellH != layout.cellH;
}

/// Soft fades on all edges hint that a dense board continues off-screen.
class _EdgeFade extends StatelessWidget {
  const _EdgeFade({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    const fade = [Colors.transparent, Colors.black, Colors.black, Colors.transparent];
    return ShaderMask(
      shaderCallback: (r) => const LinearGradient(colors: fade, stops: [0, 0.04, 0.96, 1])
          .createShader(r),
      blendMode: BlendMode.dstIn,
      child: ShaderMask(
        shaderCallback: (r) => const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: fade,
          stops: [0, 0.03, 0.97, 1],
        ).createShader(r),
        blendMode: BlendMode.dstIn,
        child: child,
      ),
    );
  }
}
