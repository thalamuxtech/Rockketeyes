import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/theme/app_theme.dart';
import '../../core/widgets/glass.dart';
import '../../core/widgets/logo.dart';
import '../../core/widgets/nebula_background.dart';
import '../../services/settings.dart';
import '../game/domain/color_set.dart';

class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key, this.replay = false});

  final bool replay;

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final _page = PageController();
  int _index = 0;

  static const _pages = 3;

  Future<void> _finish() async {
    final s = ref.read(settingsProvider);
    if (!s.onboarded) await ref.read(settingsProvider.notifier).update(s.copyWith(onboarded: true));
    if (!mounted) return;
    if (widget.replay && context.canPop()) {
      context.pop();
    } else {
      context.go(widget.replay ? '/' : '/profile?welcome=1');
    }
  }

  @override
  void dispose() {
    _page.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: NebulaBackground(
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        onPressed: _finish,
                        child: Text('Skip', style: AppText.label(14, color: AppColors.textMuted)),
                      ),
                    ),
                    Expanded(
                      child: PageView(
                        controller: _page,
                        onPageChanged: (i) => setState(() => _index = i),
                        children: const [
                          _Page(
                            visual: _StroopDemo(),
                            title: 'Read the ink,\nnot the word',
                            body: 'Every word is printed in a different color. Your brain wants to read it, but '
                                'your job is to name the color of the ink.',
                          ),
                          _Page(
                            visual: _MicDemo(),
                            title: 'Just say it.\nWe\'re listening.',
                            body: 'After the 3-2-1 countdown the mic stays open. Say each ink color out loud and '
                                'the glow jumps to the next word.',
                          ),
                          _Page(
                            visual: RockketeyesLogo(size: 150),
                            title: 'One mistake\nends the run',
                            body: 'Name a wrong color, or read the word, and the round is over. '
                                'Clear the board fast to climb the Global Legends.',
                          ),
                        ],
                      ),
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        for (var i = 0; i < _pages; i++)
                          AnimatedContainer(
                            duration: AppMotion.short,
                            margin: const EdgeInsets.symmetric(horizontal: 4),
                            width: i == _index ? 26 : 8,
                            height: 8,
                            decoration: BoxDecoration(
                              color: i == _index ? AppColors.gold : AppColors.glassBorder,
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: AppSpace.xl),
                    GoldButton(
                      label: _index == _pages - 1 ? (widget.replay ? 'Got it' : 'Let\'s go') : 'Next',
                      icon: _index == _pages - 1 ? LucideIcons.rocket : LucideIcons.arrowRight,
                      onPressed: () {
                        if (_index == _pages - 1) {
                          _finish();
                        } else {
                          _page.nextPage(duration: AppMotion.medium, curve: AppMotion.curve);
                        }
                      },
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

class _Page extends StatelessWidget {
  const _Page({required this.visual, required this.title, required this.body});

  final Widget visual;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Column(
        children: [
          const SizedBox(height: AppSpace.xl),
          SizedBox(height: 220, child: Center(child: visual)),
          const SizedBox(height: AppSpace.xxl),
          Text(title, textAlign: TextAlign.center, style: AppText.display(34)),
          const SizedBox(height: AppSpace.lg),
          Text(body, textAlign: TextAlign.center, style: AppText.body(16, color: AppColors.textMuted)),
        ],
      ),
    );
  }
}

/// Animated mini board: highlight walks across three Stroop words.
class _StroopDemo extends StatefulWidget {
  const _StroopDemo();

  @override
  State<_StroopDemo> createState() => _StroopDemoState();
}

class _StroopDemoState extends State<_StroopDemo> {
  static const _cells = [('yellow', 'green'), ('blue', 'red'), ('orange', 'blue')];
  int _active = 0;
  Timer? _t;

  @override
  void initState() {
    super.initState();
    _t = Timer.periodic(const Duration(milliseconds: 1300), (_) {
      if (mounted) setState(() => _active = (_active + 1) % _cells.length);
    });
  }

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final (word, ink) = _cells[_active];
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.board,
            borderRadius: BorderRadius.circular(AppRadius.md),
            border: Border.all(color: AppColors.boardEdge),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var i = 0; i < _cells.length; i++)
                AnimatedContainer(
                  duration: AppMotion.short,
                  width: 96,
                  height: 58,
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                    border: Border.all(color: i == _active ? AppColors.gold : Colors.transparent, width: 2.5),
                    color: i == _active ? AppColors.gold.withValues(alpha: 0.08) : Colors.transparent,
                  ),
                  child: Text(
                    _t2(colorByKey(_cells[i].$1).word),
                    style: AppText.boardWord(21, colorByKey(_cells[i].$2).inkDark),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        AnimatedSwitcher(
          duration: AppMotion.short,
          layoutBuilder: (current, previous) => current ?? const SizedBox(),
          child: Text.rich(
            key: ValueKey(_active),
            TextSpan(children: [
              TextSpan(text: 'Say  ', style: AppText.body(16, color: AppColors.textMuted)),
              TextSpan(text: '"${_t2(colorByKey(ink).word)}"', style: AppText.heading(20, color: colorByKey(ink).inkDark)),
              TextSpan(text: '   not "${_t2(colorByKey(word).word)}"', style: AppText.body(14, color: AppColors.textFaint)),
            ]),
          ),
        ),
      ],
    );
  }

  static String _t2(String w) => w[0] + w.substring(1).toLowerCase();
}

class _MicDemo extends StatefulWidget {
  const _MicDemo();

  @override
  State<_MicDemo> createState() => _MicDemoState();
}

class _MicDemoState extends State<_MicDemo> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1600))..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) => Stack(
        alignment: Alignment.center,
        children: [
          for (var k = 0; k < 3; k++)
            Builder(builder: (context) {
              final t = (_c.value + k / 3) % 1.0;
              return Container(
                width: 90 + 110 * t,
                height: 90 + 110 * t,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: AppColors.gold.withValues(alpha: (1 - t) * 0.6), width: 2),
                ),
              );
            }),
          Container(
            width: 90,
            height: 90,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: AppColors.goldGradient,
              boxShadow: [BoxShadow(color: AppColors.gold.withValues(alpha: 0.5), blurRadius: 30)],
            ),
            child: const Icon(LucideIcons.mic, size: 40, color: Color(0xFF1A1206)),
          ),
        ],
      ),
    );
  }
}
