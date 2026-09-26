import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/theme/app_theme.dart';
import '../../core/widgets/glass.dart';
import '../../core/widgets/logo.dart';
import '../../core/widgets/nebula_background.dart';
import '../game/domain/color_set.dart';

const _developerUrl = 'https://ismailukman.github.io/';

class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  Future<void> _openDeveloper() async {
    await launchUrl(Uri.parse(_developerUrl), mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width > 720;
    return Scaffold(
      body: NebulaBackground(
        intensity: 0.8,
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 820),
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 40),
                children: [
                  Row(children: [
                    GlassIconButton(
                      icon: LucideIcons.arrowLeft,
                      tooltip: 'Back',
                      onPressed: () => context.canPop() ? context.pop() : context.go('/'),
                    ),
                    const SizedBox(width: AppSpace.lg),
                    Text('About', style: AppText.heading(26)),
                  ]),
                  const SizedBox(height: AppSpace.xxl),

                  // Hero
                  const Center(child: RockketeyesLogo(size: 112)),
                  const SizedBox(height: AppSpace.lg),
                  const Center(child: Wordmark(size: 40)),
                  const SizedBox(height: AppSpace.sm),
                  Text(
                    'A modern take on the Stroop test: one of the most studied tasks in cognitive science.',
                    textAlign: TextAlign.center,
                    style: AppText.body(16, color: AppColors.textMuted),
                  ),
                  const SizedBox(height: AppSpace.xxl),

                  _Section(
                    icon: LucideIcons.brain,
                    title: 'What is the Stroop effect?',
                    children: [
                      _para(
                        'In 1935 the psychologist John Ridley Stroop showed that people are slower and make more '
                        'mistakes when they name the ink color of a word that spells a different color. Reading is '
                        'so automatic for adults that the word pops into mind first, and the brain has to actively '
                        'hold it back to report the color instead.',
                      ),
                      const SizedBox(height: AppSpace.md),
                      const _StroopExample(),
                      const SizedBox(height: AppSpace.md),
                      _para(
                        'That moment of conflict is exactly what Rockketeyes trains. Every word on the board is a '
                        'small tug-of-war between what you read and what you see.',
                      ),
                    ],
                  ),

                  _Section(
                    icon: LucideIcons.sparkles,
                    title: 'Why it matters for your mind',
                    children: [
                      _BenefitGrid(wide: wide, items: const [
                        _Benefit(LucideIcons.crosshair, 'Selective attention',
                            'Focusing on the one feature that matters (the ink) while ignoring a strong distraction (the word).'),
                        _Benefit(LucideIcons.shieldHalf, 'Inhibitory control',
                            'Stopping an automatic response before it happens. This is a core executive function used in self-control and decision making.'),
                        _Benefit(LucideIcons.zap, 'Processing speed',
                            'How quickly you can take in information and respond. The timer and speed score make this visible.'),
                        _Benefit(LucideIcons.shuffle, 'Cognitive flexibility',
                            'Switching smoothly between competing rules as the colors and words change on every cell.'),
                        _Benefit(LucideIcons.hourglass, 'Sustained focus',
                            'Larger boards ask you to keep your concentration steady for longer without a single slip.'),
                        _Benefit(LucideIcons.activity, 'Tracking your progress',
                            'Your personal bests and reaction-time chart show how your speed and consistency change over time.'),
                      ]),
                    ],
                  ),

                  _Section(
                    icon: LucideIcons.eye,
                    title: 'Your eyes and visual attention',
                    children: [
                      _bullet('Visual scanning: moving your gaze smoothly from word to word, row by row, as on a page of text.'),
                      _bullet('Color discrimination: telling similar hues apart quickly and accurately.'),
                      _bullet('Eye and voice coordination: linking what you see to what you say, many times a minute.'),
                      _bullet('Visual search load: bigger boards (up to 16 by 16) increase how much your eyes must process at once.'),
                      const SizedBox(height: AppSpace.sm),
                      _para(
                        'Screen time is still screen time. Follow the 20-20-20 habit: every 20 minutes, look at '
                        'something about 20 feet (6 metres) away for 20 seconds, and blink often.',
                        muted: true,
                      ),
                    ],
                  ),

                  _Section(
                    icon: LucideIcons.microscope,
                    title: 'Trusted by researchers and clinicians',
                    children: [
                      _para(
                        'Versions of the Stroop task are used worldwide in psychology and neuropsychology to study '
                        'attention and executive function. They appear in research on healthy ageing, attention '
                        'difficulties, fatigue, stress and recovery. Rockketeyes brings the same principle into a '
                        'fast, voice-controlled game you can play anywhere.',
                      ),
                    ],
                  ),

                  _Section(
                    icon: LucideIcons.lightbulb,
                    title: 'Getting the most out of it',
                    children: [
                      _bullet('Play short, regular sessions rather than one long one.'),
                      _bullet('Start on 3 by 4 or 4 by 4 on Easy, then grow the board as you get consistent.'),
                      _bullet('Aim for accuracy first. Speed follows once the pattern feels natural.'),
                      _bullet('Play in a quiet room, or use headphones, so the microphone hears you clearly.'),
                    ],
                  ),

                  const SizedBox(height: AppSpace.sm),
                  GlassPanel(
                    fill: const Color(0x14FF9F1C),
                    borderColor: const Color(0x55FF9F1C),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(LucideIcons.info, size: 18, color: Color(0xFFFF9F1C)),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'Rockketeyes is a game for entertainment and everyday brain training. It is not a medical '
                            'device and does not diagnose, treat or measure any health condition. If you have concerns '
                            'about your vision or memory, please speak to a qualified professional.',
                            style: AppText.body(13, color: AppColors.textMuted),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppSpace.xl),

                  // Developer
                  GlassPanel(
                    padding: const EdgeInsets.all(AppSpace.xl),
                    glow: AppColors.gold.withValues(alpha: 0.18),
                    borderColor: AppColors.gold.withValues(alpha: 0.4),
                    child: Column(
                      children: [
                        Text('DEVELOPED BY',
                            style: AppText.label(11, color: AppColors.textFaint).copyWith(letterSpacing: 2)),
                        const SizedBox(height: AppSpace.sm),
                        ShaderMask(
                          shaderCallback: (b) => AppColors.goldGradient.createShader(b),
                          child: Text('Lukman Enegi Ismaila, PhD',
                              textAlign: TextAlign.center, style: AppText.heading(24, color: Colors.white)),
                        ),
                        const SizedBox(height: AppSpace.lg),
                        GoldButton(
                          label: 'Visit ismailukman.github.io',
                          icon: LucideIcons.externalLink,
                          expand: false,
                          height: 52,
                          onPressed: _openDeveloper,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppSpace.xl),
                  Center(
                    child: Text('Rockketeyes · Version 1.0.0',
                        style: AppText.label(12, color: AppColors.textFaint)),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  static Widget _para(String text, {bool muted = false}) => Text(
        text,
        style: AppText.body(15, color: muted ? AppColors.textFaint : AppColors.textMuted),
      );

  static Widget _bullet(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 6,
              height: 6,
              margin: const EdgeInsets.only(top: 9, right: 12),
              decoration: const BoxDecoration(color: AppColors.gold, shape: BoxShape.circle),
            ),
            Expanded(child: Text(text, style: AppText.body(15, color: AppColors.textMuted))),
          ],
        ),
      );
}

class _Section extends StatelessWidget {
  const _Section({required this.icon, required this.title, required this.children});

  final IconData icon;
  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpace.lg),
      child: GlassPanel(
        padding: const EdgeInsets.all(AppSpace.xl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: AppColors.gold.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, size: 18, color: AppColors.gold),
              ),
              const SizedBox(width: 12),
              Expanded(child: Text(title, style: AppText.heading(19))),
            ]),
            const SizedBox(height: AppSpace.lg),
            ...children,
          ],
        ),
      ),
    );
  }
}

class _Benefit {
  const _Benefit(this.icon, this.title, this.body);

  final IconData icon;
  final String title;
  final String body;
}

class _BenefitGrid extends StatelessWidget {
  const _BenefitGrid({required this.items, required this.wide});

  final List<_Benefit> items;
  final bool wide;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, box) {
      final cols = wide ? 2 : 1;
      final w = (box.maxWidth - (cols - 1) * 12) / cols;
      return Wrap(
        spacing: 12,
        runSpacing: 12,
        children: [
          for (final b in items)
            SizedBox(
              width: w,
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppColors.glassFill,
                  borderRadius: BorderRadius.circular(AppRadius.sm + 2),
                  border: Border.all(color: AppColors.glassBorder),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(b.icon, size: 20, color: AppColors.violet),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(b.title, style: AppText.label(15)),
                          const SizedBox(height: 4),
                          Text(b.body, style: AppText.body(13, color: AppColors.textMuted)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      );
    });
  }
}

/// Congruent vs. incongruent example, drawn with the game's own ink colors.
class _StroopExample extends StatelessWidget {
  const _StroopExample();

  @override
  Widget build(BuildContext context) {
    Widget tile(String word, String ink, String caption, Color captionColor) => Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
            decoration: BoxDecoration(
              color: AppColors.board,
              borderRadius: BorderRadius.circular(AppRadius.sm + 2),
              border: Border.all(color: AppColors.boardEdge),
            ),
            child: Column(
              children: [
                Text(word, style: AppText.boardWord(28, colorByKey(ink).inkDark)),
                const SizedBox(height: 8),
                Text(caption, textAlign: TextAlign.center, style: AppText.label(12, color: captionColor)),
              ],
            ),
          ),
        );
    return Row(
      children: [
        tile('Blue', 'blue', 'Easy: word and ink agree', AppColors.success),
        const SizedBox(width: 12),
        tile('Blue', 'orange', 'Hard: say "Orange"', AppColors.gold),
      ],
    );
  }
}
