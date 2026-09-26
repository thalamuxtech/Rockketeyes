import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/glass.dart';
import '../../../core/widgets/google_connect.dart';
import '../application/round_controller.dart';
import '../domain/color_set.dart';
import 'game_screen.dart' show formatClock;

class ResultsView extends StatelessWidget {
  const ResultsView({
    super.key,
    required this.state,
    required this.onPlayAgain,
    required this.onHome,
    required this.onLegends,
  });

  final RoundState state;
  final VoidCallback onPlayAgain;
  final VoidCallback onHome;
  final VoidCallback onLegends;

  @override
  Widget build(BuildContext context) {
    final b = state.breakdown!;
    final score = state.server?.score ?? b.score;
    final avg = b.correct == 0 ? 0 : (state.events.where((e) => e.correct).last.tMs / b.correct).round();
    final wide = MediaQuery.sizeOf(context).width > 760;

    return Positioned.fill(
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 1),
        duration: AppMotion.medium,
        curve: AppMotion.curve,
        builder: (context, t, child) => ColoredBox(
          color: Color.fromRGBO(5, 4, 16, 0.78 * t),
          child: Opacity(
            opacity: t,
            child: Transform.translate(offset: Offset(0, 40 * (1 - t)), child: child),
          ),
        ),
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 640),
              child: GlassPanel(
                padding: const EdgeInsets.all(AppSpace.xl),
                radius: AppRadius.lg,
                fill: const Color(0xCC141026),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _Header(state: state),
                    const SizedBox(height: AppSpace.lg),
                    _ScoreCountUp(score: score),
                    const SizedBox(height: AppSpace.sm),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      alignment: WrapAlignment.center,
                      children: [
                        if (state.localBest || (state.server?.personalBest ?? false))
                          const Pill(label: 'NEW PERSONAL BEST', icon: LucideIcons.sparkles),
                        Pill(
                          label: '${state.config.size.label} · ${state.config.difficulty.name.toUpperCase()}',
                          color: AppColors.violet,
                          icon: LucideIcons.grid3x3,
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpace.xl),
                    _Bento(
                      wide: wide,
                      tiles: [
                        _Tile(
                          icon: LucideIcons.circleCheck,
                          label: 'Cleared',
                          value: '${b.correct}/${b.cells}',
                          extra: _ProgressRing(value: b.completion),
                        ),
                        _Tile(icon: LucideIcons.timer, label: 'Time', value: formatClock(b.elapsedMs)),
                        _Tile(icon: LucideIcons.zap, label: 'Avg / word', value: b.correct == 0 ? '-' : '$avg ms'),
                        _Tile(icon: LucideIcons.gauge, label: 'Speed', value: '×${b.speedFactor.toStringAsFixed(2)}'),
                      ],
                    ),
                    const SizedBox(height: AppSpace.lg),
                    _RankStrip(state: state),
                    if (state.events.length >= 3) ...[
                      const SizedBox(height: AppSpace.lg),
                      _ReactionChart(state: state),
                    ],
                    const SizedBox(height: AppSpace.xl),
                    GoldButton(label: 'Play again', icon: LucideIcons.rotateCcw, onPressed: onPlayAgain),
                    const SizedBox(height: AppSpace.md),
                    Row(
                      children: [
                        Expanded(child: GlassButton(label: 'Legends', icon: LucideIcons.trophy, onPressed: onLegends)),
                        const SizedBox(width: AppSpace.md),
                        GlassIconButton(
                          icon: LucideIcons.share2,
                          tooltip: 'Share score',
                          onPressed: () => SharePlus.instance.share(ShareParams(
                            text: 'I scored $score on Rockketeyes (${state.config.size.label}, '
                                '${b.correct}/${b.cells} cleared). Say the color, not the word. Can you beat me?',
                          )),
                        ),
                        const SizedBox(width: AppSpace.md),
                        GlassIconButton(icon: LucideIcons.house, tooltip: 'Home', onPressed: onHome),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.state});

  final RoundState state;

  @override
  Widget build(BuildContext context) {
    final m = state.mistake;
    if (m == null) {
      return Column(children: [
        const Icon(LucideIcons.trophy, color: AppColors.gold, size: 34),
        const SizedBox(height: 6),
        Text('Board cleared!', style: AppText.heading(26)),
      ]);
    }
    final cell = state.cells[m.index];
    final ink = colorByKey(cell.ink);
    final said = colorByKey(m.said);
    String t(String w) => w[0] + w.substring(1).toLowerCase();
    return Column(children: [
      Text(m.kind == MistakeKind.word ? 'You read the word' : 'Wrong color', style: AppText.heading(26)),
      const SizedBox(height: 6),
      Text.rich(
        TextSpan(children: [
          TextSpan(text: 'Word ${m.index + 1}: "${t(colorByKey(cell.word).word)}" was written in ',
              style: AppText.body(14, color: AppColors.textMuted)),
          TextSpan(text: t(ink.word), style: AppText.label(14, color: ink.inkDark)),
          TextSpan(text: ' ink. You said ', style: AppText.body(14, color: AppColors.textMuted)),
          TextSpan(text: t(said.word), style: AppText.label(14, color: said.inkDark)),
          TextSpan(text: '.', style: AppText.body(14, color: AppColors.textMuted)),
        ]),
        textAlign: TextAlign.center,
      ),
    ]);
  }
}

class _ScoreCountUp extends StatelessWidget {
  const _ScoreCountUp({required this.score});

  final int score;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: score.toDouble()),
      duration: const Duration(milliseconds: 1100),
      curve: Curves.easeOutCubic,
      builder: (context, v, _) => Column(
        children: [
          Text('SCORE', style: AppText.label(11, color: AppColors.textFaint).copyWith(letterSpacing: 2)),
          ShaderMask(
            shaderCallback: (b) => AppColors.goldGradient.createShader(b),
            child: Text(
              _fmt(v.round()),
              semanticsLabel: 'Score $score',
              style: AppText.display(64, color: Colors.white)
                  .copyWith(fontFeatures: const [FontFeature.tabularFigures()]),
            ),
          ),
        ],
      ),
    );
  }

  static String _fmt(int n) {
    final s = n.toString();
    final b = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) b.write(',');
      b.write(s[i]);
    }
    return b.toString();
  }
}

class _Tile {
  const _Tile({required this.icon, required this.label, required this.value, this.extra});

  final IconData icon;
  final String label;
  final String value;
  final Widget? extra;
}

class _Bento extends StatelessWidget {
  const _Bento({required this.tiles, required this.wide});

  final List<_Tile> tiles;
  final bool wide;

  @override
  Widget build(BuildContext context) {
    final cols = wide ? 4 : 2;
    return LayoutBuilder(builder: (context, box) {
      final w = (box.maxWidth - (cols - 1) * 10) / cols;
      return Wrap(
        spacing: 10,
        runSpacing: 10,
        children: [
          for (final t in tiles)
            SizedBox(
              width: w,
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppColors.glassFill,
                  borderRadius: BorderRadius.circular(AppRadius.sm + 4),
                  border: Border.all(color: AppColors.glassBorder),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(children: [
                            Icon(t.icon, size: 14, color: AppColors.textMuted),
                            const SizedBox(width: 6),
                            Flexible(child: Text(t.label, style: AppText.label(12, color: AppColors.textMuted))),
                          ]),
                          const SizedBox(height: 6),
                          FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerLeft,
                            child: Text(t.value, style: AppText.numeric(20)),
                          ),
                        ],
                      ),
                    ),
                    ?t.extra,
                  ],
                ),
              ),
            ),
        ],
      );
    });
  }
}

class _ProgressRing extends StatelessWidget {
  const _ProgressRing({required this.value});

  final double value;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: value),
      duration: const Duration(milliseconds: 900),
      curve: Curves.easeOutCubic,
      builder: (context, v, _) => SizedBox(
        width: 34,
        height: 34,
        child: CircularProgressIndicator(
          value: v,
          strokeWidth: 4,
          backgroundColor: AppColors.glassFillStrong,
          color: v >= 1 ? AppColors.gold : AppColors.success,
          strokeCap: StrokeCap.round,
        ),
      ),
    );
  }
}

class _RankStrip extends StatelessWidget {
  const _RankStrip({required this.state});

  final RoundState state;

  @override
  Widget build(BuildContext context) {
    Widget child;
    switch (state.submit) {
      case SubmitStatus.submitting:
      case SubmitStatus.none:
        child = Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          const SizedBox(
              width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.gold)),
          const SizedBox(width: 10),
          Text('Saving to Global Legends…', style: AppText.label(14, color: AppColors.textMuted)),
        ]);
      case SubmitStatus.offline:
        child = _note(LucideIcons.dumbbell,
            state.config.rankable ? 'Practice round, saved on this device.' : 'Custom boards are practice only. Saved on this device.');
      case SubmitStatus.failed:
        child = _note(LucideIcons.cloudOff, 'Couldn\'t reach Global Legends. Your record is saved on this device.');
      case SubmitStatus.done:
        final r = state.server!;
        if (r.ranked && !r.legendsEligible) {
          child = const GoogleConnectCard(compact: true);
        } else if (!r.ranked) {
          child = _note(LucideIcons.dumbbell, 'Practice board, not ranked.');
        } else if (r.review) {
          child = _note(LucideIcons.shieldAlert, 'Score submitted for review before it appears on the board.');
        } else {
          child = Row(
            children: [
              Expanded(child: _RankTile(label: 'Today', rank: r.rankDay)),
              const SizedBox(width: 10),
              Expanded(child: _RankTile(label: 'This week', rank: r.rankWeek)),
              const SizedBox(width: 10),
              Expanded(child: _RankTile(label: 'All-time', rank: r.rankAll)),
            ],
          );
        }
    }
    return AnimatedSwitcher(duration: AppMotion.short, child: KeyedSubtree(key: ValueKey(state.submit), child: child));
  }

  Widget _note(IconData icon, String text) => Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 16, color: AppColors.textMuted),
          const SizedBox(width: 8),
          Flexible(child: Text(text, textAlign: TextAlign.center, style: AppText.label(13, color: AppColors.textMuted))),
        ],
      );
}

class _RankTile extends StatelessWidget {
  const _RankTile({required this.label, required this.rank});

  final String label;
  final int? rank;

  @override
  Widget build(BuildContext context) {
    final top = rank != null && rank! <= 3;
    final color = switch (rank) { 1 => AppColors.gold, 2 => AppColors.silver, 3 => AppColors.bronze, _ => AppColors.text };
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        color: top ? color.withValues(alpha: 0.12) : AppColors.glassFill,
        borderRadius: BorderRadius.circular(AppRadius.sm + 4),
        border: Border.all(color: top ? color.withValues(alpha: 0.6) : AppColors.glassBorder),
      ),
      child: Column(children: [
        Text(label, style: AppText.label(11, color: AppColors.textMuted)),
        const SizedBox(height: 4),
        Text(rank == null ? '-' : '#$rank', style: AppText.numeric(22, color: color)),
      ]),
    );
  }
}

class _ReactionChart extends StatelessWidget {
  const _ReactionChart({required this.state});

  final RoundState state;

  @override
  Widget build(BuildContext context) {
    final ev = state.events;
    final spots = <FlSpot>[];
    var prev = 0;
    var maxY = 0.0;
    for (var i = 0; i < ev.length; i++) {
      final d = (ev[i].tMs - prev).toDouble();
      prev = ev[i].tMs;
      spots.add(FlSpot(i + 1.0, d));
      maxY = math.max(maxY, d);
    }
    final wrong = ev.isNotEmpty && !ev.last.correct;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Time per word (ms)', style: AppText.label(12, color: AppColors.textMuted)),
        const SizedBox(height: 8),
        SizedBox(
          height: 120,
          child: LineChart(
            LineChartData(
              minY: 0,
              maxY: (maxY * 1.15).clamp(500, 20000),
              gridData: FlGridData(
                show: true,
                drawVerticalLine: false,
                getDrawingHorizontalLine: (_) => const FlLine(color: AppColors.glassBorder, strokeWidth: 1),
              ),
              borderData: FlBorderData(show: false),
              titlesData: FlTitlesData(
                topTitles: const AxisTitles(),
                rightTitles: const AxisTitles(),
                bottomTitles: const AxisTitles(),
                leftTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 40,
                    interval: 500,
                    getTitlesWidget: (v, meta) => v == meta.max && v % 500 != 0
                        ? const SizedBox.shrink()
                        : Text('${v.round()}', style: AppText.label(11, color: AppColors.textFaint)),
                  ),
                ),
              ),
              lineTouchData: const LineTouchData(enabled: true),
              lineBarsData: [
                LineChartBarData(
                  spots: spots,
                  isCurved: true,
                  preventCurveOverShooting: true,
                  color: AppColors.gold,
                  barWidth: 2.5,
                  belowBarData: BarAreaData(
                    show: true,
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [AppColors.gold.withValues(alpha: 0.25), AppColors.gold.withValues(alpha: 0)],
                    ),
                  ),
                  dotData: FlDotData(
                    show: true,
                    checkToShowDot: (s, _) => wrong && s.x == spots.length,
                    getDotPainter: (_, _, _, _) =>
                        FlDotCirclePainter(radius: 5, color: AppColors.error, strokeColor: Colors.white, strokeWidth: 1.5),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
