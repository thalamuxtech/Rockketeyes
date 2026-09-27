import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/theme/app_theme.dart';
import '../../core/widgets/glass.dart';
import '../../core/widgets/nebula_background.dart';
import '../../services/audio_service.dart';
import '../game/domain/color_set.dart';
import '../game/speech/color_recognizer.dart';
import '../game/speech/recognizer_factory.dart';

enum _MicState { idle, asking, listening, denied, unsupported }

/// Lets players try sound, voice and tap before their first round.
class DeviceCheckPanel extends StatefulWidget {
  const DeviceCheckPanel({super.key});

  @override
  State<DeviceCheckPanel> createState() => _DeviceCheckPanelState();
}

class _DeviceCheckPanelState extends State<DeviceCheckPanel> {
  static const _colors = ['red', 'blue', 'green', 'yellow', 'orange', 'purple'];

  ColorRecognizer? _rec;
  final List<StreamSubscription<Object?>> _subs = [];
  _MicState _mic = _MicState.idle;
  final Set<String> _heard = {};
  final Set<String> _tapped = {};
  String _last = '';
  double _level = 0;
  bool _soundPlayed = false;

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    _rec?.stop();
    _rec?.dispose();
    super.dispose();
  }

  Future<void> _startMic() async {
    AudioService.instance.unlock();
    setState(() => _mic = _MicState.asking);
    final rec = _rec ??= createRecognizer();
    final supported = await rec.isSupported();
    if (!mounted) return;
    if (!supported) {
      setState(() => _mic = rec.lastError == 'not-allowed' ? _MicState.denied : _MicState.unsupported);
      return;
    }
    _subs
      ..add(rec.tokens.listen((t) {
        if (t.loose) return;
        HapticFeedback.selectionClick();
        AudioService.instance.sfx(Sfx.correct, pitchStep: _heard.length);
        setState(() {
          _heard.add(t.color);
          _last = t.heard;
        });
      }))
      ..add(rec.transcripts.listen((t) {
        if (t.trim().isNotEmpty) setState(() => _last = t.trim());
      }))
      ..add(rec.levels.listen((v) => setState(() => _level = v)))
      ..add(rec.status.listen((s) {
        if (!mounted) return;
        if (s == RecognizerStatus.listening) setState(() => _mic = _MicState.listening);
        final err = rec.lastError;
        if (s == RecognizerStatus.error && (err == 'not-allowed' || err == 'service-not-allowed')) {
          setState(() => _mic = _MicState.denied);
        }
        if (s == RecognizerStatus.unsupported) setState(() => _mic = _MicState.unsupported);
      }));
    await rec.start(allowedColors: _colors.toSet());
    // Some engines never report "listening"; assume ready shortly after start.
    Future<void>.delayed(const Duration(seconds: 2), () {
      if (mounted && _mic == _MicState.asking) setState(() => _mic = _MicState.listening);
    });
  }

  Future<void> _stopMic() async {
    await _rec?.stop();
    if (mounted) setState(() => _mic = _MicState.idle);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _card(
          icon: LucideIcons.volume2,
          title: 'Sound',
          done: _soundPlayed,
          body: 'Play a short chime. If you hear nothing, turn up your media volume.',
          action: GlassButton(
            label: _soundPlayed ? 'Play again' : 'Play test sound',
            icon: LucideIcons.play,
            expand: false,
            height: 46,
            onPressed: () {
              AudioService.instance.testSound();
              setState(() => _soundPlayed = true);
            },
          ),
        ),
        const SizedBox(height: 12),
        _card(
          icon: LucideIcons.mic,
          title: 'Voice',
          done: _heard.length >= 2,
          body: 'Rockketeyes listens only during a round, to hear color words. Your audio is never '
              'recorded or stored. Allow the microphone, then say a few colors.',
          action: switch (_mic) {
            _MicState.idle => GoldButton(
                label: 'Test microphone',
                icon: LucideIcons.mic,
                expand: false,
                height: 46,
                onPressed: _startMic,
              ),
            _MicState.asking => Text('Waiting for microphone permission…',
                style: AppText.label(13, color: AppColors.textMuted)),
            _MicState.listening => Row(children: [
                _Orb(level: _level),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    _last.isEmpty ? 'Listening… say "red", "blue", "green"' : 'Heard "$_last"',
                    style: AppText.label(13),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                TextButton(onPressed: _stopMic, child: const Text('Stop')),
              ]),
            _MicState.denied => Text(
                'Microphone access is blocked. Allow it in your '
                '${kIsWeb ? 'browser address bar' : 'phone settings (Apps → Rockketeyes → Permissions)'}, '
                'then try again. You can always play with taps.',
                style: AppText.body(13, color: AppColors.error)),
            _MicState.unsupported => Text(
                'Voice isn\'t available on this ${kIsWeb ? 'browser. Try Chrome, Edge or Safari' : 'device'}. '
                'You can still play with taps.',
                style: AppText.body(13, color: AppColors.gold)),
          },
          footer: _chips(_heard, labelSuffix: 'heard'),
        ),
        const SizedBox(height: 12),
        _card(
          icon: LucideIcons.pointer,
          title: 'Tap',
          done: _tapped.length >= 2,
          body: 'No microphone? Tap the ink color instead. Try a couple.',
          footer: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final k in _colors)
                _ColorKey(
                  color: colorByKey(k),
                  lit: _tapped.contains(k),
                  onTap: () {
                    AudioService.instance.unlock();
                    AudioService.instance.sfx(Sfx.tap);
                    HapticFeedback.selectionClick();
                    setState(() => _tapped.add(k));
                  },
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _chips(Set<String> lit, {required String labelSuffix}) => Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final k in _colors)
            Semantics(
              label: '${_name(k)} ${lit.contains(k) ? labelSuffix : 'not yet'}',
              child: AnimatedContainer(
                duration: AppMotion.short,
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: lit.contains(k) ? colorByKey(k).inkDark.withValues(alpha: 0.22) : AppColors.board,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                      color: lit.contains(k) ? colorByKey(k).inkDark : AppColors.boardEdge, width: lit.contains(k) ? 1.5 : 1),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  if (lit.contains(k)) ...[
                    Icon(LucideIcons.check, size: 13, color: colorByKey(k).inkDark),
                    const SizedBox(width: 4),
                  ],
                  Text(_name(k), style: AppText.label(12, color: colorByKey(k).inkDark)),
                ]),
              ),
            ),
        ],
      );

  static String _name(String k) => k[0].toUpperCase() + k.substring(1);

  Widget _card({
    required IconData icon,
    required String title,
    required bool done,
    required String body,
    Widget? action,
    Widget? footer,
  }) {
    return GlassPanel(
      padding: const EdgeInsets.all(16),
      borderColor: done ? AppColors.success.withValues(alpha: 0.5) : AppColors.glassBorder,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(color: AppColors.gold.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(10)),
            child: Icon(icon, size: 17, color: AppColors.gold),
          ),
          const SizedBox(width: 10),
          Expanded(child: Text(title, style: AppText.heading(17))),
          AnimatedSwitcher(
            duration: AppMotion.short,
            child: done
                ? Row(key: const ValueKey('ok'), mainAxisSize: MainAxisSize.min, children: [
                    const Icon(LucideIcons.circleCheck, size: 18, color: AppColors.success),
                    const SizedBox(width: 4),
                    Text('Works', style: AppText.label(12, color: AppColors.success)),
                  ])
                : const SizedBox.shrink(),
          ),
        ]),
        const SizedBox(height: 8),
        Text(body, style: AppText.body(13, color: AppColors.textMuted)),
        if (action != null) ...[const SizedBox(height: 12), action],
        if (footer != null) ...[const SizedBox(height: 12), footer],
      ]),
    );
  }
}

class _Orb extends StatelessWidget {
  const _Orb({required this.level});

  final double level;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 36,
      height: 36,
      child: Stack(alignment: Alignment.center, children: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 90),
          width: 24 + 12 * level,
          height: 24 + 12 * level,
          decoration: BoxDecoration(shape: BoxShape.circle, color: AppColors.gold.withValues(alpha: 0.2 + 0.25 * level)),
        ),
        Container(
          width: 24,
          height: 24,
          decoration: const BoxDecoration(shape: BoxShape.circle, gradient: AppColors.goldGradient),
          child: const Icon(LucideIcons.mic, size: 13, color: Color(0xFF1A1206)),
        ),
      ]),
    );
  }
}

class _ColorKey extends StatelessWidget {
  const _ColorKey({required this.color, required this.lit, required this.onTap});

  final GameColor color;
  final bool lit;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final name = color.word[0] + color.word.substring(1).toLowerCase();
    return Semantics(
      button: true,
      label: 'Tap $name',
      excludeSemantics: true,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppRadius.sm),
          child: AnimatedContainer(
            duration: AppMotion.micro,
            width: 88,
            height: 44,
            decoration: BoxDecoration(
              color: color.inkDark.withValues(alpha: lit ? 0.32 : 0.14),
              borderRadius: BorderRadius.circular(AppRadius.sm),
              border: Border.all(color: color.inkDark.withValues(alpha: lit ? 1 : 0.6), width: lit ? 2 : 1.2),
            ),
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(lit ? LucideIcons.check : LucideIcons.circle, size: 13, color: color.inkDark),
              const SizedBox(width: 6),
              Text(name, style: AppText.label(13)),
            ]),
          ),
        ),
      ),
    );
  }
}

/// Standalone screen (Settings → Test sound and microphone).
class DeviceCheckScreen extends StatelessWidget {
  const DeviceCheckScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: NebulaBackground(
        intensity: 0.7,
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Row(children: [
                    GlassIconButton(
                      icon: LucideIcons.arrowLeft,
                      tooltip: 'Back',
                      onPressed: () => context.canPop() ? context.pop() : context.go('/settings'),
                    ),
                    const SizedBox(width: AppSpace.lg),
                    Expanded(child: Text('Check your setup', style: AppText.heading(26))),
                  ]),
                  const SizedBox(height: AppSpace.xl),
                  const DeviceCheckPanel(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
