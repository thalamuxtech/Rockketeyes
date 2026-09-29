import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/theme/app_theme.dart';
import '../../core/widgets/avatar.dart';
import '../../core/widgets/glass.dart';
import '../../core/widgets/google_connect.dart';
import '../../core/widgets/nebula_background.dart';
import '../../services/profile.dart';
import '../game/application/game_config.dart';
import '../game/domain/color_set.dart';
import '../game/domain/grid.dart';
import '../game/presentation/game_screen.dart' show formatClock;
import 'leaderboard_repository.dart';

class LegendsScreen extends ConsumerStatefulWidget {
  const LegendsScreen({super.key, this.initialBoard});

  final String? initialBoard;

  @override
  ConsumerState<LegendsScreen> createState() => _LegendsScreenState();
}

class _LegendsScreenState extends ConsumerState<LegendsScreen> {
  final _repo = LeaderboardRepository(FirebaseFirestore.instance);

  /// null = all boards together (the default view).
  GridSize? _size;
  Set<String> _myBoards = const {};
  ColorSetId _set = ColorSetId.normal;
  InputMode _mode = InputMode.voice;
  LegendPeriod _period = LegendPeriod.all;
  bool _myCountry = false;

  Future<List<LegendEntry>>? _top;
  Future<({LegendEntry entry, int rank})?>? _mine;

  @override
  void initState() {
    super.initState();
    final parts = widget.initialBoard?.split('.');
    if (parts != null && parts.length == 3) {
      final g = GridSize.tryParse(parts[0]);
      _size = g != null && g.isPreset ? g : null;
      _set = ColorSetId.values.asNameMap()[parts[1]] ?? _set;
      _mode = InputMode.values.asNameMap()[parts[2]] ?? _mode;
    }
    _load();
    ref.read(profileProvider.future).then((p) async {
      final boards = await _repo
          .myBoards(p.uid)
          .catchError((Object _) => <String>{});
      if (mounted) setState(() => _myBoards = boards);
    });
  }

  String? get _boardId =>
      _size == null ? null : '${_size!.id}.${_set.name}.${_mode.name}';

  void _load() {
    final profile = ref.read(profileProvider).value;
    final country = _myCountry ? profile?.country : null;
    final board = _boardId;
    final top = _repo.top(board, _period, country: country);
    setState(() {
      _top = top;
      _mine = profile == null
          ? Future.value(null)
          : (board == null
                ? top.then(
                    (list) => _repo.mine(
                      profile.uid,
                      null,
                      _period,
                      country: country,
                      topAll: list,
                    ),
                  )
                : _repo.mine(profile.uid, board, _period, country: country));
    });
  }

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(profileProvider).value;
    return Scaffold(
      body: NebulaBackground(
        intensity: 0.8,
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 760),
              child: CustomScrollView(
                slivers: [
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                    sliver: SliverToBoxAdapter(child: _header(context)),
                  ),
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                    sliver: SliverToBoxAdapter(child: _filters(profile)),
                  ),
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(16, 20, 16, 120),
                    sliver: SliverToBoxAdapter(child: _board(profile)),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
      bottomNavigationBar: profile == null
          ? null
          : _MineBar(
              future: _mine,
              profile: profile,
              onChanged: _load,
              showBoard: _size == null,
            ),
    );
  }

  Widget _header(BuildContext context) => Row(
    children: [
      GlassIconButton(
        icon: LucideIcons.arrowLeft,
        tooltip: 'Back',
        onPressed: () => context.canPop() ? context.pop() : context.go('/'),
      ),
      const SizedBox(width: AppSpace.lg),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Global Legends', style: AppText.heading(26)),
            Text(
              'The sharpest eyes on the planet',
              style: AppText.body(13, color: AppColors.textMuted),
            ),
          ],
        ),
      ),
      GlassIconButton(
        icon: LucideIcons.refreshCw,
        tooltip: 'Refresh',
        onPressed: _load,
      ),
    ],
  );

  Widget _filters(Profile? profile) {
    return GlassPanel(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            height: 48,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: GridSize.presets.length + 1,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (_, i) {
                if (i == 0) {
                  return ChoiceChipX(
                    label: 'All boards',
                    selected: _size == null,
                    onTap: () {
                      _size = null;
                      _load();
                    },
                  );
                }
                final g = GridSize.presets[i - 1];
                final played = _myBoards.any((b) => b.startsWith('${g.id}.'));
                return ChoiceChipX(
                  label: g.label,
                  sublabel: played ? '• played' : null,
                  selected: g == _size,
                  onTap: () {
                    _size = g;
                    // Jump to the difficulty and mode you played on this board.
                    final mine = _myBoards
                        .where((b) => b.startsWith('${g.id}.'))
                        .toList();
                    if (mine.isNotEmpty &&
                        !mine.contains('${g.id}.${_set.name}.${_mode.name}')) {
                      final parts = mine.first.split('.');
                      _set = ColorSetId.values.asNameMap()[parts[1]] ?? _set;
                      _mode = InputMode.values.asNameMap()[parts[2]] ?? _mode;
                    }
                    _load();
                  },
                );
              },
            ),
          ),
          if (_size != null) ...[
            const SizedBox(height: 12),
            Segmented<ColorSetId>(
              values: ColorSetId.values,
              selected: _set,
              labelOf: (s) => switch (s) {
                ColorSetId.easy => 'Easy',
                ColorSetId.normal => 'Normal',
                ColorSetId.hard => 'Hard',
                ColorSetId.colorblind => 'CB-safe',
              },
              onChanged: (s) {
                _set = s;
                _load();
              },
            ),
          ],
          const SizedBox(height: 10),
          Builder(builder: (context) {
            final period = Segmented<LegendPeriod>(
              values: LegendPeriod.values,
              selected: _period,
              labelOf: (p) => switch (p) {
                LegendPeriod.today => 'Today',
                LegendPeriod.week => 'Week',
                LegendPeriod.all => 'All-time',
              },
              onChanged: (p) {
                _period = p;
                _load();
              },
            );
            if (_size == null) return period;
            final mode = Segmented<InputMode>(
              values: InputMode.values,
              selected: _mode,
              labelOf: (m) => m == InputMode.voice ? 'Voice' : 'Tap',
              iconOf: (m) => m == InputMode.voice ? LucideIcons.mic : LucideIcons.pointer,
              onChanged: (m) {
                _mode = m;
                _load();
              },
            );
            // Side by side only when both fit; phones stack them.
            if (MediaQuery.sizeOf(context).width < 420) {
              return Column(children: [period, const SizedBox(height: 10), mode]);
            }
            return Row(children: [
              Expanded(child: period),
              const SizedBox(width: 10),
              SizedBox(width: 150, child: mode),
            ]);
          }),
          if (profile != null && profile.country.isNotEmpty) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                const Icon(
                  LucideIcons.globe,
                  size: 16,
                  color: AppColors.textMuted,
                ),
                const SizedBox(width: 8),
                Text(
                  'World',
                  style: AppText.label(
                    13,
                    color: _myCountry ? AppColors.textMuted : AppColors.text,
                  ),
                ),
                Switch(
                  value: _myCountry,
                  onChanged: (v) {
                    _myCountry = v;
                    _load();
                  },
                ),
                CountryFlag(code: profile.country),
                const SizedBox(width: 6),
                Text(
                  'My country',
                  style: AppText.label(
                    13,
                    color: _myCountry ? AppColors.text : AppColors.textMuted,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _board(Profile? profile) {
    return FutureBuilder<List<LegendEntry>>(
      future: _top,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done)
          return const _Skeleton();
        if (snap.hasError) {
          return _EmptyState(
            icon: LucideIcons.cloudOff,
            title: 'Legends are out of reach',
            body: 'Check your connection and try again.',
            action: GlassButton(
              label: 'Retry',
              icon: LucideIcons.refreshCw,
              onPressed: _load,
              expand: false,
            ),
          );
        }
        final list = snap.data ?? const [];
        if (list.isEmpty) {
          return _EmptyState(
            icon: LucideIcons.rocket,
            title: 'No legends yet',
            body: _size == null
                ? 'Nobody is on Global Legends ${_period == LegendPeriod.today
                      ? 'today'
                      : _period == LegendPeriod.week
                      ? 'this week'
                      : ''} yet. Be the first.'
                : 'Nobody has claimed ${_size!.label} on this difficulty ${_period == LegendPeriod.today ? 'today' : ''}. Be the first.',
            action: GoldButton(
              label: 'Play ${(_size ?? const GridSize(4, 4)).label}',
              icon: LucideIcons.play,
              expand: false,
              onPressed: () => context.go(
                '/play',
                extra: GameConfig(
                  size: _size ?? const GridSize(4, 4),
                  difficulty: switch (_set) {
                    ColorSetId.easy => Difficulty.easy,
                    ColorSetId.hard => Difficulty.hard,
                    _ => Difficulty.normal,
                  },
                  colorblind: _set == ColorSetId.colorblind,
                  mode: _mode,
                ),
              ),
            ),
          );
        }
        return Column(
          children: [
            _Podium(
              entries: list.take(3).toList(),
              me: profile?.uid,
              showBoard: _size == null,
            ),
            const SizedBox(height: AppSpace.lg),
            for (var i = 3; i < list.length; i++)
              _Row(
                rank: i + 1,
                entry: list[i],
                me: list[i].uid == profile?.uid,
                showBoard: _size == null,
              ),
          ],
        );
      },
    );
  }
}

class _Podium extends StatelessWidget {
  const _Podium({
    required this.entries,
    required this.me,
    this.showBoard = false,
  });

  final bool showBoard;

  final List<LegendEntry> entries;
  final String? me;

  @override
  Widget build(BuildContext context) {
    Widget slot(int place) {
      if (place > entries.length) return const Expanded(child: SizedBox());
      final e = entries[place - 1];
      final color = [
        AppColors.gold,
        AppColors.silver,
        AppColors.bronze,
      ][place - 1];
      final height = [150.0, 118.0, 96.0][place - 1];
      return Expanded(
        child: TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: 1),
          duration: Duration(milliseconds: 500 + place * 120),
          curve: Curves.easeOutBack,
          builder: (context, t, child) => Opacity(
            opacity: t.clamp(0, 1),
            child: Transform.translate(
              offset: Offset(0, 30 * (1 - t)),
              child: child,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (place == 1)
                const Icon(LucideIcons.crown, color: AppColors.gold, size: 26),
              const SizedBox(height: 4),
              PlayerAvatar(
                seed: e.avatarSeed,
                name: e.nickname,
                size: place == 1 ? 72 : 58,
                ring: color,
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CountryFlag(code: e.country, width: 16),
                  if (e.country.isNotEmpty) const SizedBox(width: 5),
                  Flexible(
                    child: Text(
                      e.nickname,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.label(
                        13,
                        color: e.uid == me ? AppColors.gold : AppColors.text,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 2),
              Text(_fmt(e.score), style: AppText.numeric(16, color: color)),
              if (showBoard)
                Text(
                  boardLabel(e.boardId),
                  style: AppText.label(10, color: AppColors.textFaint),
                ),
              const SizedBox(height: 8),
              Container(
                height: height,
                margin: const EdgeInsets.symmetric(horizontal: 6),
                decoration: BoxDecoration(
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(AppRadius.sm + 4),
                  ),
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      color.withValues(alpha: 0.35),
                      color.withValues(alpha: 0.04),
                    ],
                  ),
                  border: Border.all(color: color.withValues(alpha: 0.5)),
                ),
                alignment: Alignment.topCenter,
                padding: const EdgeInsets.only(top: 10),
                child: Text('$place', style: AppText.display(34, color: color)),
              ),
            ],
          ),
        ),
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [slot(2), slot(1), slot(3)],
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({
    required this.rank,
    required this.entry,
    required this.me,
    this.showBoard = false,
  });

  final bool showBoard;

  final int rank;
  final LegendEntry entry;
  final bool me;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: GlassPanel(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        radius: AppRadius.sm + 4,
        borderColor: me
            ? AppColors.gold.withValues(alpha: 0.6)
            : AppColors.glassBorder,
        child: _EntryLine(
          rank: rank,
          entry: entry,
          me: me,
          showBoard: showBoard,
        ),
      ),
    );
  }
}

class _EntryLine extends StatelessWidget {
  const _EntryLine({
    required this.rank,
    required this.entry,
    required this.me,
    this.showBoard = false,
  });

  final bool showBoard;

  final int rank;
  final LegendEntry entry;
  final bool me;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 40,
          child: Text(
            '#$rank',
            style: AppText.numeric(15, color: AppColors.textMuted),
          ),
        ),
        PlayerAvatar(seed: entry.avatarSeed, name: entry.nickname, size: 36),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Flexible(
                    child: Text(
                      me ? '${entry.nickname} (you)' : entry.nickname,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.label(
                        14,
                        color: me ? AppColors.gold : AppColors.text,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  CountryFlag(code: entry.country, width: 16),
                ],
              ),
              Text(
                '${showBoard ? '${boardLabel(entry.boardId)} · ' : ''}${entry.correct}/${entry.cells}${entry.cleared ? ' · cleared' : ''} · ${formatClock(entry.elapsedMs)}',
                style: AppText.body(12, color: AppColors.textFaint),
              ),
            ],
          ),
        ),
        Text(_fmt(entry.score), style: AppText.numeric(17)),
      ],
    );
  }
}

class _MineBar extends ConsumerWidget {
  const _MineBar({
    required this.future,
    required this.profile,
    required this.onChanged,
    this.showBoard = false,
  });

  final bool showBoard;

  final Future<({LegendEntry entry, int rank})?>? future;
  final Profile profile;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    Widget shell(Widget child) => SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        child: Center(
          heightFactor: 1,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 728),
            child: GlassPanel(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              fill: const Color(0xE6141026),
              borderColor: AppColors.gold.withValues(alpha: 0.5),
              radius: AppRadius.sm + 6,
              child: child,
            ),
          ),
        ),
      ),
    );

    final rename = GlassIconButton(
      icon: LucideIcons.pencil,
      tooltip: 'Edit name and avatar',
      size: 40,
      onPressed: () => context.push('/profile'),
    );

    if (!profile.linked) {
      return shell(
        Row(
          children: [
            PlayerAvatar(
              seed: profile.avatarSeed,
              name: profile.nickname,
              size: 36,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Connect Google to join Global Legends',
                style: AppText.label(13, color: AppColors.textMuted),
                maxLines: 2,
              ),
            ),
            GoogleButton(
              label: 'Connect',
              onPressed: () async {
                if (await connectGoogleFlow(context, ref)) onChanged();
              },
            ),
          ],
        ),
      );
    }

    return FutureBuilder<({LegendEntry entry, int rank})?>(
      future: future,
      builder: (context, snap) {
        final mine = snap.data;
        return shell(
          Row(
            children: [
              Expanded(
                child: mine == null
                    ? Row(
                        children: [
                          PlayerAvatar(
                            seed: profile.avatarSeed,
                            name: profile.nickname,
                            size: 36,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              snap.connectionState == ConnectionState.done
                                  ? 'You haven\'t ranked on this board yet'
                                  : 'Finding your rank…',
                              style: AppText.label(
                                13,
                                color: AppColors.textMuted,
                              ),
                            ),
                          ),
                        ],
                      )
                    : _EntryLine(
                        rank: mine.rank,
                        entry: mine.entry,
                        me: true,
                        showBoard: showBoard,
                      ),
              ),
              const SizedBox(width: 8),
              rename,
            ],
          ),
        );
      },
    );
  }
}

class _Skeleton extends StatefulWidget {
  const _Skeleton();

  @override
  State<_Skeleton> createState() => _SkeletonState();
}

class _SkeletonState extends State<_Skeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) => Column(
        children: [
          for (var i = 0; i < 6; i++)
            Container(
              height: 58,
              margin: const EdgeInsets.only(bottom: 8),
              decoration: BoxDecoration(
                color: Color.lerp(
                  AppColors.glassFill,
                  AppColors.glassFillStrong,
                  _c.value,
                ),
                borderRadius: BorderRadius.circular(AppRadius.sm + 4),
              ),
            ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.icon,
    required this.title,
    required this.body,
    required this.action,
  });

  final IconData icon;
  final String title;
  final String body;
  final Widget action;

  @override
  Widget build(BuildContext context) {
    return GlassPanel(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 36),
      child: Column(
        children: [
          Icon(icon, size: 40, color: AppColors.gold),
          const SizedBox(height: 12),
          Text(title, style: AppText.heading(20)),
          const SizedBox(height: 6),
          Text(
            body,
            textAlign: TextAlign.center,
            style: AppText.body(14, color: AppColors.textMuted),
          ),
          const SizedBox(height: 20),
          action,
        ],
      ),
    );
  }
}

String _fmt(int n) {
  final s = n.toString();
  final b = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) b.write(',');
    b.write(s[i]);
  }
  return b.toString();
}

/// `8x8.easy.voice` -> `8×8 · Easy · Voice`
String boardLabel(String id) {
  final p = id.split('.');
  if (p.length != 3) return id;
  String cap(String x) => x.isEmpty ? x : x[0].toUpperCase() + x.substring(1);
  final set = p[1] == 'colorblind' ? 'CB-safe' : cap(p[1]);
  return '${p[0].replaceAll('x', '×')} · $set · ${cap(p[2])}';
}
