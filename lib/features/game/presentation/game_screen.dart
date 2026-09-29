import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/env.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/glass.dart';
import '../../../core/widgets/toast.dart';
import '../../../core/widgets/nebula_background.dart';
import '../../../services/audio_service.dart';
import '../../../services/settings.dart';
import '../application/game_config.dart';
import '../application/round_controller.dart';
import '../domain/color_set.dart';
import '../speech/color_recognizer.dart';
import 'board_view.dart';
import '../../group/group_results_view.dart';
import 'results_view.dart';

class GameScreen extends ConsumerStatefulWidget {
  const GameScreen({super.key, required this.config, this.group});

  final GameConfig config;

  /// Set when playing a round of a group challenge.
  final GroupRun? group;

  @override
  ConsumerState<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends ConsumerState<GameScreen> {
  late final AppLifecycleListener _life;
  final FocusNode _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    AudioService.instance.setScene(MusicScene.play);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(roundProvider.notifier).start(widget.config, group: widget.group);
      _focus.requestFocus();
    });
    _life = AppLifecycleListener(
      onHide: () => ref.read(roundProvider.notifier).pause(),
    );
  }

  @override
  void dispose() {
    _life.dispose();
    _focus.dispose();
    AudioService.instance.setScene(MusicScene.menu);
    super.dispose();
  }

  Future<void> _leave() async {
    final c = ref.read(roundProvider.notifier);
    await c.quit();
    if (!mounted) return;
    if (widget.group != null) {
      Navigator.of(context).pop();
    } else {
      context.go('/');
    }
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent e) {
    if (e is! KeyDownEvent) return KeyEventResult.ignored;
    final c = ref.read(roundProvider.notifier);
    final s = ref.read(roundProvider);
    if (e.logicalKey == LogicalKeyboardKey.escape || e.logicalKey == LogicalKeyboardKey.space) {
      if (s.phase == RoundPhase.playing) {
        c.pause();
      } else if (s.phase == RoundPhase.paused) {
        c.resume();
      }
      return KeyEventResult.handled;
    }
    // Number keys 1..8 answer in tap mode.
    if (s.inputMode == InputMode.tap) {
      final digit = int.tryParse(e.character ?? '');
      final keys = s.config.colorSet.keys;
      if (digit != null && digit >= 1 && digit <= keys.length) {
        c.answer(keys[digit - 1]);
        return KeyEventResult.handled;
      }
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(roundProvider);
    final c = ref.read(roundProvider.notifier);
    final settings = ref.watch(settingsProvider);

    ref.listen(roundProvider.select((s) => s.notice), (_, notice) {
      if (notice == null) return;
      showToast(context, notice, icon: Icons.info_outline_rounded);
      c.clearNotice();
    });

    final showSim = Env.devTools && settings.showSimulator && s.inputMode == InputMode.voice;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _leave();
      },
      child: Focus(
        focusNode: _focus,
        autofocus: true,
        onKeyEvent: _onKey,
        child: Scaffold(
          body: NebulaBackground(
            intensity: 0.55,
            calm: true,
            animate: s.phase != RoundPhase.playing,
            child: SafeArea(
              child: Stack(
                children: [
                  Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 1100),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                        child: Column(
                          children: [
                            _Hud(state: s, controller: c, onBack: _leave),
                            const SizedBox(height: AppSpace.md),
                            _Instruction(state: s),
                            const SizedBox(height: AppSpace.md),
                            Expanded(child: BoardView(state: s, darkInk: true)),
                            const SizedBox(height: AppSpace.md),
                            if (s.inputMode == InputMode.tap)
                              _TapPad(state: s, onTap: c.answer)
                            else
                              _MicPanel(state: s, level: c.micLevel),
                            if (showSim) ...[
                              const SizedBox(height: AppSpace.sm),
                              _Simulator(state: s, onSay: (k) => c.answer(k, heard: k)),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                  if (s.phase == RoundPhase.countdown) _CountdownOverlay(value: s.countdown),
                  if (s.phase == RoundPhase.paused) _PausedOverlay(onResume: c.resume, onQuit: _leave),
                  if (s.phase == RoundPhase.ending) _EndingBanner(state: s),
                  if (s.phase == RoundPhase.results && s.group != null)
                    GroupResultsView(state: s, onBack: _leave)
                  else if (s.phase == RoundPhase.results)
                    ResultsView(
                      state: s,
                      onPlayAgain: () => c.start(s.config),
                      onHome: _leave,
                      onLegends: () async {
                        await c.quit();
                        if (context.mounted) context.go('/legends?board=${s.config.boardId}');
                      },
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Hud extends StatelessWidget {
  const _Hud({required this.state, required this.controller, required this.onBack});

  final RoundState state;
  final RoundController controller;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final total = state.cells.length;
    final done = state.events.where((e) => e.correct).length;
    return GlassPanel(
      blur: kGameBlur,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      radius: AppRadius.md + 4,
      child: Row(
        children: [
          GlassIconButton(icon: LucideIcons.arrowLeft, tooltip: 'Leave game', onPressed: onBack),
          const SizedBox(width: AppSpace.md),
          Expanded(
            child: Row(
              children: [
                _HudStat(
                  label: 'TIME',
                  child: _TimerText(controller: controller, running: state.phase == RoundPhase.playing),
                ),
                _divider(),
                _HudStat(
                  label: 'CLEARED',
                  child: Text('$done / $total', style: AppText.numeric(20)),
                ),
                _divider(),
                _HudStat(
                  label: 'STREAK',
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(LucideIcons.flame,
                          size: 18, color: done >= 5 ? AppColors.gold : AppColors.textFaint),
                      const SizedBox(width: 4),
                      AnimatedSwitcher(
                        duration: AppMotion.micro,
                        transitionBuilder: (c, a) => ScaleTransition(scale: a, child: c),
                        child: Text('$done', key: ValueKey(done), style: AppText.numeric(20)),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          _RankBadge(state: state),
          const SizedBox(width: AppSpace.sm),
          GlassIconButton(
            icon: state.phase == RoundPhase.paused ? LucideIcons.play : LucideIcons.pause,
            tooltip: state.phase == RoundPhase.paused ? 'Resume' : 'Pause',
            onPressed: state.phase == RoundPhase.playing
                ? controller.pause
                : state.phase == RoundPhase.paused
                    ? controller.resume
                    : null,
          ),
        ],
      ),
    );
  }

  Widget _divider() => Container(
        width: 1,
        height: 30,
        margin: const EdgeInsets.symmetric(horizontal: AppSpace.md),
        color: AppColors.glassBorder,
      );
}

class _RankBadge extends StatelessWidget {
  const _RankBadge({required this.state});

  final RoundState state;

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.sizeOf(context).width < 520) return const SizedBox.shrink();
    if (state.group != null) {
      return Pill(label: 'GROUP · ${state.group!.code}', color: AppColors.violet, icon: LucideIcons.users);
    }
    return state.ranked
        ? const Pill(label: 'RANKED', icon: LucideIcons.trophy)
        : const Pill(label: 'PRACTICE', color: AppColors.textMuted, icon: LucideIcons.dumbbell);
  }
}

class _HudStat extends StatelessWidget {
  const _HudStat({required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Flexible(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(label, style: AppText.label(10, color: AppColors.textFaint).copyWith(letterSpacing: 1.4)),
          ),
          const SizedBox(height: 2),
          FittedBox(fit: BoxFit.scaleDown, child: child),
        ],
      ),
    );
  }
}

class _TimerText extends StatefulWidget {
  const _TimerText({required this.controller, required this.running});

  final RoundController controller;
  final bool running;

  @override
  State<_TimerText> createState() => _TimerTextState();
}

class _TimerTextState extends State<_TimerText> with SingleTickerProviderStateMixin {
  late final Ticker _ticker = createTicker((_) => setState(() {}));

  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didUpdateWidget(_TimerText old) {
    super.didUpdateWidget(old);
    _sync();
  }

  void _sync() {
    if (widget.running && !_ticker.isActive) _ticker.start();
    if (!widget.running && _ticker.isActive) _ticker.stop();
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Text(formatClock(widget.controller.elapsedMs), style: AppText.numeric(20));
  }
}

String formatClock(int ms) {
  final m = ms ~/ 60000;
  final s = (ms % 60000) ~/ 1000;
  final t = (ms % 1000) ~/ 100;
  return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}.$t';
}

class _Instruction extends StatelessWidget {
  const _Instruction({required this.state});

  final RoundState state;

  @override
  Widget build(BuildContext context) {
    final hint = state.idleHint;
    return AnimatedSwitcher(
      duration: AppMotion.short,
      child: Text.rich(
        key: ValueKey(hint),
        TextSpan(children: [
          TextSpan(text: hint ? 'Say the ' : 'Say the ', style: AppText.label(15, color: AppColors.textMuted)),
          TextSpan(text: 'INK COLOR', style: AppText.label(15, weight: FontWeight.w800, color: AppColors.gold)),
          TextSpan(
            text: hint ? ' of the glowing word, not the word itself' : ', not the word',
            style: AppText.label(15, color: AppColors.textMuted),
          ),
        ]),
        textAlign: TextAlign.center,
      ),
    );
  }
}

class _MicPanel extends StatelessWidget {
  const _MicPanel({required this.state, required this.level});

  final RoundState state;
  final ValueNotifier<double> level;

  @override
  Widget build(BuildContext context) {
    final listening = state.micStatus == RecognizerStatus.listening ||
        state.phase == RoundPhase.playing;
    final err = state.micStatus == RecognizerStatus.error && state.micError != null &&
        state.micError != 'no-speech' && state.micError != 'aborted';
    final status = switch (state.phase) {
      RoundPhase.preparing => 'Preparing…',
      RoundPhase.arming => 'Allow microphone access to play',
      RoundPhase.countdown => 'Get ready…',
      RoundPhase.playing => err ? 'Mic issue: ${state.micError}' : 'Listening',
      RoundPhase.paused => 'Paused',
      _ => 'Stopped',
    };
    return GlassPanel(
      blur: kGameBlur,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      radius: AppRadius.md + 4,
      child: Row(
        children: [
          ValueListenableBuilder<double>(
            valueListenable: level,
            builder: (context, v, _) => _MicOrb(level: listening ? v : 0, active: state.phase == RoundPhase.playing),
          ),
          const SizedBox(width: AppSpace.md),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(status, style: AppText.label(14, color: err ? AppColors.error : AppColors.text)),
                const SizedBox(height: 2),
                Text('Speak clearly, one color at a time',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.body(12, color: AppColors.textFaint)),
              ],
            ),
          ),
          if (state.heard.isNotEmpty)
            AnimatedSwitcher(
              duration: AppMotion.micro,
              child: Container(
                key: ValueKey(state.heard + state.events.length.toString()),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                decoration: BoxDecoration(
                  color: AppColors.glassFillStrong,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: AppColors.glassBorder),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(LucideIcons.audioLines, size: 14, color: AppColors.textMuted),
                    const SizedBox(width: 6),
                    Text('"${state.heard}"', style: AppText.label(13)),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _MicOrb extends StatelessWidget {
  const _MicOrb({required this.level, required this.active});

  final double level;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 48,
      height: 48,
      child: Stack(
        alignment: Alignment.center,
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 90),
            width: 34 + 14 * level,
            height: 34 + 14 * level,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: (active ? AppColors.gold : AppColors.textFaint).withValues(alpha: 0.18 + 0.2 * level),
            ),
          ),
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: active ? AppColors.goldGradient : null,
              color: active ? null : AppColors.glassFillStrong,
            ),
            child: Icon(LucideIcons.mic,
                size: 18, color: active ? const Color(0xFF1A1206) : AppColors.textMuted),
          ),
        ],
      ),
    );
  }
}

class _TapPad extends StatelessWidget {
  const _TapPad({required this.state, required this.onTap});

  final RoundState state;
  final void Function(String) onTap;

  @override
  Widget build(BuildContext context) {
    final colors = state.config.colorSet.colors;
    final enabled = state.phase == RoundPhase.playing;
    return GlassPanel(
      blur: kGameBlur,
      padding: const EdgeInsets.all(10),
      radius: AppRadius.md + 4,
      child: Wrap(
        alignment: WrapAlignment.center,
        spacing: 8,
        runSpacing: 8,
        children: [
          for (var i = 0; i < colors.length; i++)
            _ColorKey(
              color: colors[i],
              hotkey: '${i + 1}',
              onTap: enabled ? () => onTap(colors[i].key) : null,
            ),
        ],
      ),
    );
  }
}

class _ColorKey extends StatelessWidget {
  const _ColorKey({required this.color, required this.hotkey, required this.onTap});

  final GameColor color;
  final String hotkey;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final ink = color.inkDark;
    final name = color.word[0] + color.word.substring(1).toLowerCase();
    return Semantics(
      button: true,
      label: name,
      excludeSemantics: true,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppRadius.sm),
          child: Container(
            width: 92,
            height: 52,
            decoration: BoxDecoration(
              color: ink.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(AppRadius.sm),
              border: Border.all(color: ink.withValues(alpha: 0.7), width: 1.5),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(width: 14, height: 14, decoration: BoxDecoration(color: ink, shape: BoxShape.circle)),
                const SizedBox(width: 8),
                Text(name, style: AppText.label(13)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Dev-only: feeds the same pipeline as the microphone.
class _Simulator extends StatelessWidget {
  const _Simulator({required this.state, required this.onSay});

  final RoundState state;
  final void Function(String) onSay;

  @override
  Widget build(BuildContext context) {
    final keys = state.config.colorSet.keys;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0x14FF9F1C),
        borderRadius: BorderRadius.circular(AppRadius.sm),
        border: Border.all(color: const Color(0x55FF9F1C)),
      ),
      child: Row(
        children: [
          Text('VOICE SIM', style: AppText.label(10, color: const Color(0xFFFF9F1C)).copyWith(letterSpacing: 1.2)),
          const SizedBox(width: 8),
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final k in keys)
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: ActionChip(
                        label: Text(k, style: AppText.label(12, color: colorByKey(k).inkDark)),
                        backgroundColor: AppColors.bgDeep,
                        side: BorderSide(color: colorByKey(k).inkDark.withValues(alpha: 0.5)),
                        onPressed: () => onSay(k),
                      ),
                    ),
                  if (state.activeCell != null)
                    ActionChip(
                      avatar: const Icon(LucideIcons.wandSparkles, size: 14, color: AppColors.gold),
                      label: Text('correct', style: AppText.label(12, color: AppColors.gold)),
                      backgroundColor: AppColors.bgDeep,
                      onPressed: () => onSay(state.activeCell!.ink),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CountdownOverlay extends StatelessWidget {
  const _CountdownOverlay({required this.value});

  final int value;

  @override
  Widget build(BuildContext context) {
    final label = value == 0 ? 'GO!' : '$value';
    return Positioned.fill(
      child: IgnorePointer(
        child: ColoredBox(
          color: const Color(0x66050410),
          child: Center(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 380),
              switchInCurve: Curves.easeOutBack,
              transitionBuilder: (child, a) => FadeTransition(
                opacity: a,
                child: ScaleTransition(scale: Tween(begin: 1.9, end: 1.0).animate(a), child: child),
              ),
              child: Container(
                key: ValueKey(label),
                width: 200,
                height: 200,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(colors: [
                    AppColors.gold.withValues(alpha: 0.30),
                    AppColors.gold.withValues(alpha: 0.0),
                  ]),
                ),
                child: ShaderMask(
                  shaderCallback: (b) => AppColors.goldGradient.createShader(b),
                  child: Text(label,
                      semanticsLabel: value == 0 ? 'Go' : 'Starting in $value',
                      style: AppText.display(value == 0 ? 76 : 110, color: Colors.white)),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PausedOverlay extends StatelessWidget {
  const _PausedOverlay({required this.onResume, required this.onQuit});

  final VoidCallback onResume;
  final VoidCallback onQuit;

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: ColoredBox(
        color: const Color(0xB3050410),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 360),
            child: GlassPanel(
              padding: const EdgeInsets.all(AppSpace.xl),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(LucideIcons.pause, color: AppColors.gold, size: 36),
                  const SizedBox(height: AppSpace.md),
                  Text('Paused', style: AppText.heading(24)),
                  const SizedBox(height: AppSpace.sm),
                  Text('The board is hidden and the timer is stopped.',
                      textAlign: TextAlign.center, style: AppText.body(14, color: AppColors.textMuted)),
                  const SizedBox(height: AppSpace.xl),
                  GoldButton(label: 'Resume', icon: LucideIcons.play, onPressed: onResume),
                  const SizedBox(height: AppSpace.md),
                  GlassButton(label: 'Quit to menu', icon: LucideIcons.house, onPressed: onQuit),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _EndingBanner extends StatelessWidget {
  const _EndingBanner({required this.state});

  final RoundState state;

  @override
  Widget build(BuildContext context) {
    final m = state.mistake;
    final cleared = m == null;
    final cell = m == null ? null : state.cells[m.index];
    final ink = cell == null ? null : colorByKey(cell.ink);
    final said = m == null ? null : colorByKey(m.said);
    final title = cleared
        ? 'Board cleared!'
        : m.kind == MistakeKind.word
            ? 'You read the word!'
            : 'Wrong color!';
    final color = cleared ? AppColors.gold : AppColors.error;

    return Positioned.fill(
      child: IgnorePointer(
        child: Center(
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: 1),
            duration: const Duration(milliseconds: 520),
            curve: Curves.easeOutBack,
            builder: (context, t, child) => Opacity(
              opacity: t.clamp(0, 1),
              child: Transform.scale(scale: 0.7 + 0.3 * t, child: child),
            ),
            child: GlassPanel(
              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 22),
              fill: color.withValues(alpha: 0.16),
              borderColor: color.withValues(alpha: 0.6),
              glow: color.withValues(alpha: 0.45),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(cleared ? LucideIcons.trophy : LucideIcons.circleX, color: color, size: 40),
                  const SizedBox(height: AppSpace.sm),
                  Text(title, style: AppText.heading(28, color: color)),
                  if (!cleared) ...[
                    const SizedBox(height: AppSpace.sm),
                    Text.rich(
                      TextSpan(children: [
                        TextSpan(text: 'The ink was ', style: AppText.body(15, color: AppColors.textMuted)),
                        TextSpan(text: _t(ink!.word), style: AppText.label(15, color: ink.inkDark)),
                        TextSpan(text: '. You said ', style: AppText.body(15, color: AppColors.textMuted)),
                        TextSpan(text: _t(said!.word), style: AppText.label(15, color: said.inkDark)),
                      ]),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  static String _t(String w) => w[0] + w.substring(1).toLowerCase();
}
