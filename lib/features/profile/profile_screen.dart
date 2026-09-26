import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/theme/app_theme.dart';
import '../../core/widgets/avatar.dart';
import '../../core/widgets/glass.dart';
import '../../core/widgets/toast.dart';
import '../../core/widgets/nebula_background.dart';
import '../../services/api_client.dart';
import '../../services/local_store.dart';
import '../../services/profile.dart';
import 'countries.dart';

class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key, this.welcome = false});

  final bool welcome;

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  final _name = TextEditingController();
  String _seed = '';
  String _country = '';
  bool _loaded = false;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _hydrate(Profile p) {
    if (_loaded) return;
    _loaded = true;
    _name.text = p.nickname;
    _seed = p.avatarSeed;
    _country = p.country;
  }

  Future<void> _save() async {
    final name = _name.text.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (name.length < 3 || name.length > 16 || !RegExp(r'^[A-Za-z0-9_ ]+$').hasMatch(name)) {
      setState(() => _error = '3 to 16 letters, numbers, spaces or _');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref.read(profileProvider.notifier).save(nickname: name, avatarSeed: _seed, country: _country);
      if (!mounted) return;
      showToast(context, 'Profile saved');
      if (widget.welcome) context.go('/');
    } on ApiException catch (e) {
      setState(() => _error = switch (e.code) {
            'nickname_taken' => 'That name is taken. Try another.',
            'profane' => 'Please pick a friendlier name.',
            'invalid_nickname' => '3 to 16 letters, numbers, spaces or _',
            _ => e.isNetwork ? 'Can\'t reach the server. Try again when online.' : 'Couldn\'t save (${e.code}).',
          });
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _pickCountry() async {
    final code = await showDialog<String>(context: context, builder: (_) => const _CountryDialog());
    if (code != null) setState(() => _country = code);
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(profileProvider);
    final profile = async.value;
    if (profile != null) _hydrate(profile);
    final bests = LocalStore.instance.allBests().entries.toList()..sort((a, b) => b.value.compareTo(a.value));

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
                  Row(
                    children: [
                      GlassIconButton(
                        icon: LucideIcons.arrowLeft,
                        tooltip: 'Back',
                        onPressed: () => context.canPop() ? context.pop() : context.go('/'),
                      ),
                      const SizedBox(width: AppSpace.lg),
                      Text(widget.welcome ? 'Choose your pilot' : 'Profile', style: AppText.heading(26)),
                    ],
                  ),
                  const SizedBox(height: AppSpace.xl),
                  if (profile == null)
                    const Center(child: CircularProgressIndicator(color: AppColors.gold))
                  else ...[
                    GlassPanel(
                      padding: const EdgeInsets.all(AppSpace.xl),
                      child: Column(
                        children: [
                          Stack(
                            clipBehavior: Clip.none,
                            children: [
                              PlayerAvatar(seed: _seed, name: _name.text, size: 104, ring: AppColors.gold),
                              Positioned(
                                right: -6,
                                bottom: -6,
                                child: GlassIconButton(
                                  icon: LucideIcons.dices,
                                  tooltip: 'New avatar',
                                  size: 44,
                                  onPressed: () => setState(
                                      () => _seed = '${profile.uid}-${math.Random().nextInt(1 << 30)}'),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: AppSpace.xl),
                          TextField(
                            controller: _name,
                            maxLength: 16,
                            textInputAction: TextInputAction.done,
                            onSubmitted: (_) => _save(),
                            onChanged: (_) => setState(() {}),
                            style: AppText.label(17),
                            decoration: InputDecoration(
                              labelText: 'Nickname',
                              hintText: 'e.g. NeonFalcon',
                              errorText: _error,
                              prefixIcon: const Icon(LucideIcons.user, size: 18),
                            ),
                          ),
                          const SizedBox(height: AppSpace.sm),
                          Material(
                            color: AppColors.glassFill,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(AppRadius.sm),
                              side: const BorderSide(color: AppColors.glassBorder),
                            ),
                            child: ListTile(
                              onTap: _pickCountry,
                              leading: _country.isEmpty
                                  ? const Icon(LucideIcons.globe, color: AppColors.textMuted)
                                  : CountryFlag(code: _country, width: 28),
                              title: Text(_country.isEmpty ? 'Choose your country' : (kCountries[_country] ?? _country),
                                  style: AppText.label(15)),
                              subtitle: Text('Shown on the leaderboard', style: AppText.body(12, color: AppColors.textFaint)),
                              trailing: const Icon(LucideIcons.chevronRight, color: AppColors.textMuted),
                            ),
                          ),
                          const SizedBox(height: AppSpace.xl),
                          GoldButton(label: 'Save profile', icon: LucideIcons.check, busy: _saving, onPressed: _save),
                          if (widget.welcome) ...[
                            const SizedBox(height: AppSpace.md),
                            TextButton(
                              onPressed: () => context.go('/'),
                              child: Text('Maybe later', style: AppText.label(14, color: AppColors.textMuted)),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: AppSpace.lg),
                    if (!profile.linked)
                      GlassPanel(
                        child: Row(
                          children: [
                            const Icon(LucideIcons.shieldCheck, color: AppColors.gold),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('Secure your legend', style: AppText.label(15)),
                                  Text('Link Google to keep your scores on every device.',
                                      style: AppText.body(12, color: AppColors.textMuted)),
                                ],
                              ),
                            ),
                            GlassButton(
                              label: 'Link',
                              expand: false,
                              height: 44,
                              onPressed: () async {
                                try {
                                  await ref.read(profileProvider.notifier).linkGoogle();
                                } catch (e) {
                                  if (context.mounted) {
                                    showToast(context, 'Linking failed: $e', icon: Icons.error_outline_rounded);
                                  }
                                }
                              },
                            ),
                          ],
                        ),
                      ),
                    const SizedBox(height: AppSpace.lg),
                    GlassPanel(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Personal bests', style: AppText.heading(18)),
                          const SizedBox(height: AppSpace.md),
                          if (bests.isEmpty)
                            Text('Play a round to set your first record.',
                                style: AppText.body(14, color: AppColors.textMuted))
                          else
                            for (final b in bests.take(8))
                              Padding(
                                padding: const EdgeInsets.symmetric(vertical: 6),
                                child: Row(
                                  children: [
                                    Icon(b.key.endsWith('.tap') ? LucideIcons.pointer : LucideIcons.mic,
                                        size: 16, color: AppColors.textMuted),
                                    const SizedBox(width: 10),
                                    Expanded(child: Text(_boardLabel(b.key), style: AppText.label(14))),
                                    Text('${b.value}', style: AppText.numeric(16, color: AppColors.gold)),
                                  ],
                                ),
                              ),
                        ],
                      ),
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

  static String _boardLabel(String id) {
    final p = id.split('.');
    if (p.length != 3) return id;
    final size = p[0].replaceAll('x', '×');
    return '$size · ${p[1][0].toUpperCase()}${p[1].substring(1)}';
  }
}

class _CountryDialog extends StatefulWidget {
  const _CountryDialog();

  @override
  State<_CountryDialog> createState() => _CountryDialogState();
}

class _CountryDialogState extends State<_CountryDialog> {
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final items = kCountries.entries
        .where((e) => _q.isEmpty || e.value.toLowerCase().contains(_q) || e.key.toLowerCase() == _q)
        .toList();
    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420, maxHeight: 560),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              TextField(
                autofocus: true,
                decoration: const InputDecoration(hintText: 'Search countries', prefixIcon: Icon(LucideIcons.search, size: 18)),
                onChanged: (v) => setState(() => _q = v.trim().toLowerCase()),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: ListView.builder(
                  itemCount: items.length,
                  itemBuilder: (_, i) => ListTile(
                    leading: CountryFlag(code: items[i].key, width: 26),
                    title: Text(items[i].value, style: AppText.label(14)),
                    onTap: () => Navigator.pop(context, items[i].key),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
