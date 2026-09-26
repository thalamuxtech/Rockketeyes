import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/env.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/glass.dart';
import '../../core/widgets/nebula_background.dart';
import '../../services/audio_service.dart';
import '../../services/settings.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(settingsProvider);
    final c = ref.read(settingsProvider.notifier);

    Widget section(String title, List<Widget> children) => Padding(
          padding: const EdgeInsets.only(bottom: AppSpace.lg),
          child: GlassPanel(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title.toUpperCase(),
                    style: AppText.label(11, color: AppColors.textFaint).copyWith(letterSpacing: 1.5)),
                const SizedBox(height: 6),
                ...children,
              ],
            ),
          ),
        );

    Widget slider(String label, IconData icon, double value, ValueChanged<double> onChanged) => Row(
          children: [
            Icon(icon, size: 18, color: AppColors.textMuted),
            const SizedBox(width: 12),
            SizedBox(width: 72, child: Text(label, style: AppText.label(14))),
            Expanded(child: Slider(value: value, onChanged: onChanged)),
            SizedBox(width: 40, child: Text('${(value * 100).round()}', textAlign: TextAlign.right, style: AppText.numeric(14))),
          ],
        );

    Widget toggle(String label, String sub, IconData icon, bool value, ValueChanged<bool> onChanged) =>
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          secondary: Icon(icon, size: 18, color: AppColors.textMuted),
          title: Text(label, style: AppText.label(14)),
          subtitle: Text(sub, style: AppText.body(12, color: AppColors.textFaint)),
          value: value,
          onChanged: onChanged,
        );

    return Scaffold(
      body: NebulaBackground(
        intensity: 0.8,
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
                      onPressed: () => context.canPop() ? context.pop() : context.go('/'),
                    ),
                    const SizedBox(width: AppSpace.lg),
                    Text('Settings', style: AppText.heading(26)),
                  ]),
                  const SizedBox(height: AppSpace.xl),
                  section('Sound', [
                    slider('Music', LucideIcons.music, s.musicVolume, (v) => c.update(s.copyWith(musicVolume: v))),
                    slider('Effects', LucideIcons.volume2, s.sfxVolume, (v) => c.update(s.copyWith(sfxVolume: v))),
                    const SizedBox(height: 8),
                    Text('Music while the mic listens', style: AppText.label(13, color: AppColors.textMuted)),
                    const SizedBox(height: 8),
                    Segmented<PlayMusicLevel>(
                      values: PlayMusicLevel.values,
                      selected: s.playMusic,
                      labelOf: (l) => switch (l) {
                        PlayMusicLevel.off => 'Off',
                        PlayMusicLevel.low => 'Low',
                        PlayMusicLevel.normal => 'Full',
                      },
                      onChanged: (l) => c.update(s.copyWith(playMusic: l)),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Text('Low keeps the mic from hearing the music through your speakers.',
                          style: AppText.body(12, color: AppColors.textFaint)),
                    ),
                  ]),
                  section('Play', [
                    toggle('Colorblind-safe colors', 'Blue, orange, yellow, white and pink only', LucideIcons.eye,
                        s.colorblind, (v) => c.update(s.copyWith(colorblind: v))),
                    toggle('Haptics', 'Vibrate on answers', LucideIcons.vibrate, s.haptics,
                        (v) => c.update(s.copyWith(haptics: v))),
                    const SizedBox(height: 10),
                  ]),
                  if (Env.devTools)
                    section('Developer', [
                      toggle('Voice simulator', 'Color buttons that feed the voice pipeline', LucideIcons.wrench,
                          s.showSimulator, (v) => c.update(s.copyWith(showSimulator: v))),
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(LucideIcons.server, size: 18, color: AppColors.textMuted),
                        title: Text('API', style: AppText.label(14)),
                        subtitle: Text(Env.apiBase, style: AppText.body(12, color: AppColors.textFaint)),
                      ),
                    ]),
                  section('About', [
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(LucideIcons.info, size: 18, color: AppColors.textMuted),
                      title: Text('About Rockketeyes', style: AppText.label(14)),
                      subtitle: Text('The science of the Stroop test, and who made it',
                          style: AppText.body(12, color: AppColors.textFaint)),
                      onTap: () => context.push('/about'),
                    ),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(LucideIcons.circleHelp, size: 18, color: AppColors.textMuted),
                      title: Text('How to play', style: AppText.label(14)),
                      onTap: () => context.push('/onboarding?replay=1'),
                    ),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(LucideIcons.fileText, size: 18, color: AppColors.textMuted),
                      title: Text('Credits & licenses', style: AppText.label(14)),
                      onTap: () => showLicensePage(context: context, applicationName: 'Rockketeyes'),
                    ),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(LucideIcons.lock, size: 18, color: AppColors.textMuted),
                      title: Text('Privacy', style: AppText.label(14)),
                      subtitle: Text(
                          'Voice is processed by your device or browser speech service and never stored by Rockketeyes.',
                          style: AppText.body(12, color: AppColors.textFaint)),
                    ),
                  ]),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
