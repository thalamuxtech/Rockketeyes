import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/theme/app_theme.dart';
import '../../core/widgets/avatar.dart';
import '../../core/widgets/glass.dart';
import '../../core/widgets/logo.dart';
import '../../core/widgets/nebula_background.dart';
import '../../services/audio_service.dart';
import '../../services/local_store.dart';
import '../../services/profile.dart';
import '../game/domain/color_set.dart';
import 'setup_sheet.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  @override
  void initState() {
    super.initState();
    AudioService.instance.setScene(MusicScene.menu);
  }

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(profileProvider).value;
    final history = LocalStore.instance.history();
    final best = LocalStore.instance.allBests().values.fold<int>(0, (a, b) => a > b ? a : b);
    final width = MediaQuery.sizeOf(context).width;
    final compact = width < 420;

    return Scaffold(
      body: NebulaBackground(
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: CustomScrollView(
                slivers: [
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
                      child: Column(
                        children: [
                          Row(
                            children: [
                              _ProfileChip(profile: profile),
                              const Spacer(),
                              GlassIconButton(
                                icon: LucideIcons.info,
                                tooltip: 'About',
                                onPressed: () => context.push('/about'),
                              ),
                              const SizedBox(width: AppSpace.sm),
                              GlassIconButton(
                                icon: LucideIcons.settings,
                                tooltip: 'Settings',
                                onPressed: () => context.push('/settings'),
                              ),
                            ],
                          ),
                          const Spacer(flex: 2),
                          RockketeyesLogo(size: compact ? 132 : 164),
                          const SizedBox(height: AppSpace.xl),
                          Wordmark(size: compact ? 44 : 54),
                          const SizedBox(height: AppSpace.sm),
                          const _Tagline(),
                          const Spacer(flex: 2),
                          GoldButton(
                            label: 'Play',
                            icon: LucideIcons.play,
                            height: 64,
                            onPressed: () => showSetupSheet(context).then((_) => setState(() {})),
                          ),
                          const SizedBox(height: AppSpace.md),
                          Row(
                            children: [
                              Expanded(
                                child: GlassButton(
                                  label: 'Global Legends',
                                  icon: LucideIcons.trophy,
                                  onPressed: () => context.push('/legends'),
                                ),
                              ),
                              const SizedBox(width: AppSpace.md),
                              Expanded(
                                child: GlassButton(
                                  label: 'How to play',
                                  icon: LucideIcons.circleHelp,
                                  onPressed: () => context.push('/onboarding?replay=1'),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: AppSpace.xl),
                          _StatsRow(best: best, games: history.length, lastScore: history.isEmpty ? null : history.first['score'] as int?),
                          const Spacer(),
                        ],
                      ),
                    ),
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

class _Tagline extends StatelessWidget {
  const _Tagline();

  @override
  Widget build(BuildContext context) {
    final red = colorByKey('red');
    final blue = colorByKey('blue');
    return Text.rich(
      TextSpan(children: [
        TextSpan(text: 'Say the ', style: AppText.body(17, color: AppColors.textMuted)),
        TextSpan(text: 'color', style: AppText.label(17, weight: FontWeight.w800, color: blue.inkDark)),
        TextSpan(text: ', not the ', style: AppText.body(17, color: AppColors.textMuted)),
        TextSpan(text: 'word', style: AppText.label(17, weight: FontWeight.w800, color: red.inkDark)),
        TextSpan(text: '.', style: AppText.body(17, color: AppColors.textMuted)),
      ]),
      textAlign: TextAlign.center,
    );
  }
}

class _ProfileChip extends StatelessWidget {
  const _ProfileChip({required this.profile});

  final Profile? profile;

  @override
  Widget build(BuildContext context) {
    final name = (profile?.nickname.isNotEmpty ?? false) ? profile!.nickname : 'Set up profile';
    return Semantics(
      button: true,
      label: 'Profile: $name',
      excludeSemantics: true,
      child: Material(
        color: AppColors.glassFill,
        shape: const StadiumBorder(side: BorderSide(color: AppColors.glassBorder)),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: () => context.push('/profile'),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(5, 5, 16, 5),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                PlayerAvatar(seed: profile?.avatarSeed ?? '', name: name, size: 38),
                const SizedBox(width: 10),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 160),
                  child: Text(name, overflow: TextOverflow.ellipsis, style: AppText.label(14)),
                ),
                if (profile != null && profile!.country.isNotEmpty) ...[
                  const SizedBox(width: 8),
                  CountryFlag(code: profile!.country, width: 18),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _StatsRow extends StatelessWidget {
  const _StatsRow({required this.best, required this.games, required this.lastScore});

  final int best;
  final int games;
  final int? lastScore;

  @override
  Widget build(BuildContext context) {
    Widget stat(String label, String value, IconData icon) => Expanded(
          child: Column(
            children: [
              Icon(icon, size: 18, color: AppColors.gold),
              const SizedBox(height: 6),
              Text(value, style: AppText.numeric(20)),
              Text(label, style: AppText.label(11, color: AppColors.textFaint)),
            ],
          ),
        );
    return GlassPanel(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
      child: Row(
        children: [
          stat('Best score', best == 0 ? '-' : '$best', LucideIcons.crown),
          stat('Rounds', '$games', LucideIcons.gamepad2),
          stat('Last', lastScore == null ? '-' : '$lastScore', LucideIcons.history),
        ],
      ),
    );
  }
}
