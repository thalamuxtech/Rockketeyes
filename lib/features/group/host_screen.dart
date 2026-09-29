import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../core/theme/app_theme.dart';
import '../../core/widgets/avatar.dart';
import '../../core/widgets/glass.dart';
import '../../core/widgets/logo.dart';
import '../../core/widgets/nebula_background.dart';
import '../../core/widgets/toast.dart';
import '../../services/audio_service.dart';
import '../../services/profile.dart';
import '../game/domain/color_keys.dart';
import '../game/domain/grid.dart';
import '../game/presentation/game_screen.dart' show formatClock;
import 'group_models.dart';
import 'room_repository.dart';

/// Latest room code this device is hosting (read by the E2E hooks).
String? currentHostedRoom;

/// Host setup: choose the board, then open a room.
class HostSetupScreen extends ConsumerStatefulWidget {
  const HostSetupScreen({super.key});

  @override
  ConsumerState<HostSetupScreen> createState() => _HostSetupScreenState();
}

class _HostSetupScreenState extends ConsumerState<HostSetupScreen> {
  GridSize _size = const GridSize(4, 4);
  ColorSetId _set = ColorSetId.normal;
  bool _voice = true;
  bool _busy = false;

  Future<void> _create() async {
    setState(() => _busy = true);
    try {
      final profile = await ref.read(profileProvider.future);
      final code = await RoomRepository().createRoom(
        config: RoomConfig(size: _size, colorSet: _set, voice: _voice),
        hostName: profile.nickname.isEmpty ? 'Host' : profile.nickname,
      );
      if (mounted) context.go('/group/host/$code');
    } catch (e) {
      if (mounted) showToast(context, e is RoomException ? e.message : 'Could not create the room.', icon: Icons.error_outline_rounded);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: NebulaBackground(
        intensity: 0.8,
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 620),
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
                    Expanded(child: Text('Group challenge', style: AppText.heading(26))),
                  ]),
                  const SizedBox(height: AppSpace.xl),
                  GlassPanel(
                    padding: const EdgeInsets.all(AppSpace.xl),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const _HowItWorks(),
                        const SizedBox(height: AppSpace.xl),
                        _label('Board'),
                        Wrap(spacing: 8, runSpacing: 8, children: [
                          for (final g in GridSize.presets.where((g) => g.cells <= 144))
                            ChoiceChipX(label: g.label, sublabel: '${g.cells} words', selected: g == _size,
                                onTap: () => setState(() => _size = g)),
                        ]),
                        const SizedBox(height: AppSpace.lg),
                        _label('Difficulty'),
                        Segmented<ColorSetId>(
                          values: const [ColorSetId.easy, ColorSetId.normal, ColorSetId.hard],
                          selected: _set,
                          labelOf: (s) => switch (s) {
                            ColorSetId.easy => 'Easy · 4',
                            ColorSetId.normal => 'Normal · 6',
                            _ => 'Hard · 8',
                          },
                          onChanged: (s) => setState(() => _set = s),
                        ),
                        const SizedBox(height: AppSpace.lg),
                        _label('Players answer by'),
                        Segmented<bool>(
                          values: const [true, false],
                          selected: _voice,
                          labelOf: (v) => v ? 'Voice' : 'Tap',
                          iconOf: (v) => v ? LucideIcons.mic : LucideIcons.pointer,
                          onChanged: (v) => setState(() => _voice = v),
                        ),
                        const SizedBox(height: AppSpace.xl),
                        GoldButton(label: 'Open room', icon: LucideIcons.qrCode, busy: _busy, onPressed: _create),
                      ],
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

  Widget _label(String t) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Text(t.toUpperCase(), style: AppText.label(11, color: AppColors.textFaint).copyWith(letterSpacing: 1.5)),
      );
}

class _HowItWorks extends StatelessWidget {
  const _HowItWorks();

  @override
  Widget build(BuildContext context) {
    Widget step(IconData icon, String title, String body) => Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(color: AppColors.gold.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(10)),
              child: Icon(icon, size: 18, color: AppColors.gold),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, style: AppText.label(15)),
                Text(body, style: AppText.body(13, color: AppColors.textMuted)),
              ]),
            ),
          ]),
        );
    return Column(children: [
      step(LucideIcons.monitor, 'This device hosts', 'Put it on a big screen. It shows the QR code, the lobby and the live race.'),
      step(LucideIcons.smartphone, 'Players join on their phones', 'Scan the QR code or type the PIN. No install needed.'),
      step(LucideIcons.flag, 'Everyone gets the same board', 'First to clear it wins. If nobody clears it, the highest score wins.'),
    ]);
  }
}

/// The serving device: lobby with QR code, live race, podium.
class HostScreen extends ConsumerStatefulWidget {
  const HostScreen({super.key, required this.code});

  final String code;

  @override
  ConsumerState<HostScreen> createState() => _HostScreenState();
}

class _HostScreenState extends ConsumerState<HostScreen> {
  final _repo = RoomRepository();
  StreamSubscription<Room?>? _roomSub;
  StreamSubscription<List<RoomPlayer>>? _playersSub;
  Room? _room;
  List<RoomPlayer> _players = const [];
  bool _missing = false;
  final Stopwatch _race = Stopwatch();
  Timer? _ticker;
  int _countdown = 0;

  @override
  void initState() {
    super.initState();
    currentHostedRoom = widget.code;
    AudioService.instance.setScene(MusicScene.menu);
    ref.read(profileProvider.future).then((_) {
      _roomSub = _repo.watchRoom(widget.code).listen(_onRoom, onError: (_) => setState(() => _missing = true));
      _playersSub = _repo.watchPlayers(widget.code).listen((p) {
        final joined = p.length > _players.length;
        setState(() => _players = p);
        if (joined) AudioService.instance.sfx(Sfx.tap);
        _maybeFinish();
      });
    });
  }

  void _onRoom(Room? room) {
    if (room == null) {
      setState(() => _missing = true);
      return;
    }
    final prev = _room;
    setState(() => _room = room);
    if (room.status == RoomStatus.countdown && prev?.status != RoomStatus.countdown) _runCountdown(room);
  }

  Future<void> _runCountdown(Room room) async {
    AudioService.instance.setScene(MusicScene.play);
    for (var n = 3; n >= 1; n--) {
      if (!mounted) return;
      setState(() => _countdown = n);
      AudioService.instance.sfx(Sfx.tick);
      await Future<void>.delayed(const Duration(milliseconds: 800));
    }
    if (!mounted) return;
    setState(() => _countdown = 0);
    AudioService.instance.sfx(Sfx.go);
    await Future<void>.delayed(const Duration(milliseconds: 450));
    _race
      ..reset()
      ..start();
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(milliseconds: 200), (_) {
      if (!mounted) return;
      setState(() {});
      _maybeFinish();
    });
    await _repo.setStatus(room.code, RoomStatus.playing);
  }

  List<RoomPlayer> get _active => [for (final p in _players) if (p.state != PlayerState.left) p];

  void _maybeFinish() {
    final room = _room;
    if (room == null || room.status != RoomStatus.playing) return;
    final inRound = [for (final p in _active) if (p.round == room.round) p];
    final allDone = inRound.isNotEmpty && inRound.every((p) => p.done);
    // Safety cap so a silent player can't hold the room forever.
    final cap = Duration(milliseconds: room.config.size.cells * 4000 + 15000);
    if (allDone || _race.elapsed > cap) _finish();
  }

  Future<void> _finish() async {
    final room = _room;
    if (room == null || room.status == RoomStatus.finished) return;
    _race.stop();
    _ticker?.cancel();
    AudioService.instance.setScene(MusicScene.menu);
    AudioService.instance.sfx(Sfx.finish);
    await _repo.setStatus(room.code, RoomStatus.finished);
  }

  @override
  void dispose() {
    _roomSub?.cancel();
    _playersSub?.cancel();
    _ticker?.cancel();
    if (currentHostedRoom == widget.code) currentHostedRoom = null;
    AudioService.instance.setScene(MusicScene.menu);
    super.dispose();
  }

  Future<void> _close() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('Close this room?', style: AppText.heading(20)),
        content: Text('Players will be disconnected.', style: AppText.body(14, color: AppColors.textMuted)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Keep open')),
          TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('Close room')),
        ],
      ),
    );
    if (ok != true) return;
    await _repo.closeRoom(widget.code).catchError((_) {});
    if (mounted) context.go('/');
  }

  @override
  Widget build(BuildContext context) {
    final room = _room;
    return Scaffold(
      body: NebulaBackground(
        intensity: 0.7,
        child: SafeArea(
          child: _missing
              ? _Centered(
                  icon: LucideIcons.doorClosed,
                  title: 'This room is closed',
                  action: GoldButton(label: 'Home', expand: false, onPressed: () => context.go('/')),
                )
              : room == null
                  ? const Center(child: CircularProgressIndicator(color: AppColors.gold))
                  : Stack(children: [
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(children: [
                          _TopBar(room: room, onClose: _close, players: _active.length),
                          const SizedBox(height: AppSpace.lg),
                          Expanded(
                            child: switch (room.status) {
                              RoomStatus.lobby => _Lobby(
                                  room: room,
                                  players: _active,
                                  onStart: _active.isEmpty ? null : () => _repo.startRound(room, _active),
                                  onKick: (uid) => _repo.kick(room.code, uid),
                                ),
                              RoomStatus.countdown || RoomStatus.playing => _Race(
                                  room: room,
                                  players: _active,
                                  elapsedMs: _race.elapsedMilliseconds,
                                  onEnd: _finish,
                                ),
                              RoomStatus.finished => _Podium(
                                  room: room,
                                  players: [for (final p in _active) if (p.round == room.round) p],
                                  onAgain: () => _repo.startRound(room, _active),
                                  onLobby: () => _repo.backToLobby(room, _active),
                                ),
                            },
                          ),
                        ]),
                      ),
                      if (room.status == RoomStatus.countdown && _countdown > 0) _BigCountdown(value: _countdown),
                    ]),
        ),
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({required this.room, required this.onClose, required this.players});

  final Room room;
  final VoidCallback onClose;
  final int players;

  @override
  Widget build(BuildContext context) {
    final c = room.config;
    // Phones have no room for the title: the pills shrink to fit instead.
    final narrow = MediaQuery.sizeOf(context).width < 600;
    final pills = Row(mainAxisSize: MainAxisSize.min, children: [
      Pill(label: '${c.size.label} · ${c.colorSet.name.toUpperCase()} · ${c.voice ? 'VOICE' : 'TAP'}',
          color: AppColors.violet, icon: LucideIcons.grid3x3),
      const SizedBox(width: AppSpace.sm),
      Pill(label: '$players PLAYER${players == 1 ? '' : 'S'}', icon: LucideIcons.users),
    ]);
    return Row(children: [
      GlassIconButton(icon: LucideIcons.x, tooltip: 'Close room', onPressed: onClose),
      const SizedBox(width: AppSpace.md),
      const RockketeyesLogo(size: 40),
      const SizedBox(width: AppSpace.sm),
      Expanded(
        child: narrow
            ? Align(
                alignment: Alignment.centerRight,
                child: FittedBox(fit: BoxFit.scaleDown, child: pills),
              )
            : Text('Group challenge', style: AppText.heading(20), overflow: TextOverflow.ellipsis),
      ),
      if (!narrow) pills,
    ]);
  }
}

class _Lobby extends StatelessWidget {
  const _Lobby({required this.room, required this.players, required this.onStart, required this.onKick});

  final Room room;
  final List<RoomPlayer> players;
  final VoidCallback? onStart;
  final void Function(String uid) onKick;

  @override
  Widget build(BuildContext context) {
    final url = RoomRepository.joinUrl(room.code);
    final wide = MediaQuery.sizeOf(context).width > 820;
    final join = GlassPanel(
      padding: const EdgeInsets.all(AppSpace.xl),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Text('Scan to join', style: AppText.heading(22)),
        const SizedBox(height: AppSpace.lg),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(AppRadius.md)),
          child: Semantics(
            label: 'QR code to join room ${room.code}',
            image: true,
            child: QrImageView(
              data: url,
              size: wide ? 240 : 200,
              eyeStyle: const QrEyeStyle(eyeShape: QrEyeShape.circle, color: Color(0xFF141026)),
              dataModuleStyle: const QrDataModuleStyle(dataModuleShape: QrDataModuleShape.circle, color: Color(0xFF141026)),
            ),
          ),
        ),
        const SizedBox(height: AppSpace.lg),
        Text('or go to', style: AppText.body(13, color: AppColors.textMuted)),
        SelectableText(url.replaceFirst(RegExp(r'^https?://'), '').replaceFirst(RegExp(r'/join/.*$'), '/join'),
            style: AppText.label(15)),
        const SizedBox(height: AppSpace.sm),
        Text('GAME PIN', style: AppText.label(11, color: AppColors.textFaint).copyWith(letterSpacing: 2)),
        GestureDetector(
          onTap: () {
            Clipboard.setData(ClipboardData(text: url));
            showToast(context, 'Join link copied');
          },
          child: ShaderMask(
            shaderCallback: (b) => AppColors.goldGradient.createShader(b),
            child: Text(room.code,
                semanticsLabel: 'Game PIN ${room.code.split('').join(' ')}',
                style: AppText.display(52, color: Colors.white).copyWith(letterSpacing: 6)),
          ),
        ),
      ]),
    );

    final list = GlassPanel(
      padding: const EdgeInsets.all(AppSpace.xl),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Text('Players', style: AppText.heading(20)),
          const Spacer(),
          Text('${players.length} joined', style: AppText.label(14, color: AppColors.gold)),
        ]),
        const SizedBox(height: AppSpace.lg),
        Expanded(
          child: players.isEmpty
              ? Center(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(LucideIcons.users, size: 36, color: AppColors.textFaint),
                    const SizedBox(height: 8),
                    Text('Waiting for players to join…', style: AppText.label(15, color: AppColors.textMuted)),
                  ]),
                )
              : SingleChildScrollView(
                  child: Wrap(spacing: 12, runSpacing: 12, children: [
                    for (final p in players)
                      TweenAnimationBuilder<double>(
                        key: ValueKey(p.uid),
                        tween: Tween(begin: 0, end: 1),
                        duration: const Duration(milliseconds: 420),
                        curve: Curves.easeOutBack,
                        builder: (context, t, child) => Transform.scale(scale: t, child: child),
                        child: Tooltip(
                          message: 'Remove ${p.nickname}',
                          child: InkWell(
                            borderRadius: BorderRadius.circular(999),
                            onLongPress: () => onKick(p.uid),
                            child: Container(
                              padding: const EdgeInsets.fromLTRB(6, 6, 14, 6),
                              decoration: BoxDecoration(
                                color: AppColors.glassFillStrong,
                                borderRadius: BorderRadius.circular(999),
                                border: Border.all(color: AppColors.glassBorder),
                              ),
                              child: Row(mainAxisSize: MainAxisSize.min, children: [
                                PlayerAvatar(seed: p.avatar, name: p.nickname, size: 36),
                                const SizedBox(width: 8),
                                Text(p.nickname, style: AppText.label(15)),
                              ]),
                            ),
                          ),
                        ),
                      ),
                  ]),
                ),
        ),
        const SizedBox(height: AppSpace.lg),
        GoldButton(label: players.isEmpty ? 'Waiting for players' : 'Start game', icon: LucideIcons.play, onPressed: onStart),
      ]),
    );

    return wide
        ? Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            SizedBox(width: 380, child: SingleChildScrollView(child: join)),
            const SizedBox(width: AppSpace.lg),
            Expanded(child: list),
          ])
        : Column(children: [
            Flexible(child: SingleChildScrollView(child: join)),
            const SizedBox(height: AppSpace.lg),
            SizedBox(height: 280, child: list),
          ]);
  }
}

class _Race extends StatelessWidget {
  const _Race({required this.room, required this.players, required this.elapsedMs, required this.onEnd});

  final Room room;
  final List<RoomPlayer> players;
  final int elapsedMs;
  final VoidCallback onEnd;

  @override
  Widget build(BuildContext context) {
    final inRound = [for (final p in players) if (p.round == room.round) p];
    final ranked = standings(inRound);
    return GlassPanel(
      padding: const EdgeInsets.all(AppSpace.xl),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          const Icon(LucideIcons.flame, color: AppColors.gold),
          const SizedBox(width: 8),
          Text('Live race', style: AppText.heading(22)),
          const Spacer(),
          Text(formatClock(elapsedMs), style: AppText.numeric(24, color: AppColors.gold)),
        ]),
        const SizedBox(height: AppSpace.lg),
        Expanded(
          child: ListView.separated(
            itemCount: ranked.length,
            separatorBuilder: (_, _) => const SizedBox(height: 10),
            itemBuilder: (_, i) => _RaceLane(rank: i + 1, player: ranked[i]),
          ),
        ),
        const SizedBox(height: AppSpace.md),
        Align(
          alignment: Alignment.centerRight,
          child: GlassButton(label: 'End round now', icon: LucideIcons.flagTriangleRight, expand: false, onPressed: onEnd),
        ),
      ]),
    );
  }
}

class _RaceLane extends StatelessWidget {
  const _RaceLane({required this.rank, required this.player});

  final int rank;
  final RoomPlayer player;

  @override
  Widget build(BuildContext context) {
    final p = player;
    final color = switch (p.state) {
      PlayerState.cleared => AppColors.gold,
      PlayerState.out => AppColors.error,
      _ => AppColors.success,
    };
    final status = switch (p.state) {
      PlayerState.cleared => 'Cleared in ${formatClock(p.elapsedMs)}',
      PlayerState.out => 'Out · ${p.score} pts',
      PlayerState.playing => '${p.correct}/${p.cells}',
      _ => 'Ready',
    };
    return AnimatedContainer(
      duration: AppMotion.short,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.glassFill,
        borderRadius: BorderRadius.circular(AppRadius.sm + 4),
        border: Border.all(color: p.state == PlayerState.cleared ? AppColors.gold.withValues(alpha: 0.6) : AppColors.glassBorder),
      ),
      child: Row(children: [
        SizedBox(width: 32, child: Text('#$rank', style: AppText.numeric(15, color: AppColors.textMuted))),
        PlayerAvatar(seed: p.avatar, name: p.nickname, size: 38),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(child: Text(p.nickname, style: AppText.label(15), overflow: TextOverflow.ellipsis)),
              Text(status, style: AppText.label(13, color: color)),
            ]),
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: TweenAnimationBuilder<double>(
                tween: Tween(end: p.progress),
                duration: AppMotion.short,
                builder: (context, v, _) => LinearProgressIndicator(
                  value: v,
                  minHeight: 8,
                  backgroundColor: AppColors.glassFillStrong,
                  color: color,
                ),
              ),
            ),
          ]),
        ),
      ]),
    );
  }
}

class _Podium extends StatelessWidget {
  const _Podium({required this.room, required this.players, required this.onAgain, required this.onLobby});

  final Room room;
  final List<RoomPlayer> players;
  final VoidCallback onAgain;
  final VoidCallback onLobby;

  @override
  Widget build(BuildContext context) {
    final ranked = standings(players);
    final top = ranked.take(3).toList();
    Widget slot(int place) {
      if (place > top.length) return const Expanded(child: SizedBox());
      final p = top[place - 1];
      final color = [AppColors.gold, AppColors.silver, AppColors.bronze][place - 1];
      final height = [170.0, 130.0, 104.0][place - 1];
      return Expanded(
        child: TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: 1),
          duration: Duration(milliseconds: 600 + (3 - place) * 250),
          curve: Curves.easeOutBack,
          builder: (context, t, child) => Opacity(
            opacity: t.clamp(0, 1),
            child: Transform.translate(offset: Offset(0, 50 * (1 - t)), child: child),
          ),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            if (place == 1) const Icon(LucideIcons.crown, color: AppColors.gold, size: 34),
            PlayerAvatar(seed: p.avatar, name: p.nickname, size: place == 1 ? 88 : 68, ring: color),
            const SizedBox(height: 8),
            Text(p.nickname, style: AppText.heading(place == 1 ? 20 : 16), overflow: TextOverflow.ellipsis),
            Text(
              p.state == PlayerState.cleared ? formatClock(p.elapsedMs) : '${p.score} pts',
              style: AppText.numeric(15, color: color),
            ),
            const SizedBox(height: 8),
            Container(
              height: height,
              margin: const EdgeInsets.symmetric(horizontal: 8),
              alignment: Alignment.topCenter,
              padding: const EdgeInsets.only(top: 10),
              decoration: BoxDecoration(
                borderRadius: const BorderRadius.vertical(top: Radius.circular(AppRadius.sm + 4)),
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [color.withValues(alpha: 0.4), color.withValues(alpha: 0.05)],
                ),
                border: Border.all(color: color.withValues(alpha: 0.55)),
              ),
              child: Text('$place', style: AppText.display(40, color: color)),
            ),
          ]),
        ),
      );
    }

    final winner = ranked.isEmpty ? null : ranked.first;
    return SingleChildScrollView(
      child: Column(children: [
        if (winner != null)
          Text(
            winner.state == PlayerState.cleared ? '${winner.nickname} cleared it first!' : '${winner.nickname} wins with the top score!',
            textAlign: TextAlign.center,
            style: AppText.display(34),
          ),
        const SizedBox(height: AppSpace.xl),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [slot(2), slot(1), slot(3)]),
        ),
        const SizedBox(height: AppSpace.xl),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: Column(children: [
            for (var i = 3; i < ranked.length; i++)
              Padding(padding: const EdgeInsets.only(bottom: 8), child: _RaceLane(rank: i + 1, player: ranked[i])),
          ]),
        ),
        const SizedBox(height: AppSpace.lg),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Row(children: [
            Expanded(child: GoldButton(label: 'Play again', icon: LucideIcons.rotateCcw, onPressed: onAgain)),
            const SizedBox(width: AppSpace.md),
            Expanded(child: GlassButton(label: 'Change board', icon: LucideIcons.settings2, onPressed: onLobby)),
          ]),
        ),
      ]),
    );
  }
}

class _BigCountdown extends StatelessWidget {
  const _BigCountdown({required this.value});

  final int value;

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: IgnorePointer(
        child: ColoredBox(
          color: const Color(0x88050410),
          child: Center(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 380),
              transitionBuilder: (c, a) => FadeTransition(
                opacity: a,
                child: ScaleTransition(scale: Tween(begin: 1.9, end: 1.0).animate(a), child: c),
              ),
              child: ShaderMask(
                key: ValueKey(value),
                shaderCallback: (b) => AppColors.goldGradient.createShader(b),
                child: Text('$value', style: AppText.display(160, color: Colors.white)),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Centered extends StatelessWidget {
  const _Centered({required this.icon, required this.title, required this.action});

  final IconData icon;
  final String title;
  final Widget action;

  @override
  Widget build(BuildContext context) => Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 44, color: AppColors.gold),
          const SizedBox(height: 12),
          Text(title, style: AppText.heading(22)),
          const SizedBox(height: 20),
          action,
        ]),
      );
}
