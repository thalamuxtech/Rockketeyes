import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/avatar/avatar_picker.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/avatar.dart';
import '../../core/widgets/glass.dart';
import '../../core/widgets/logo.dart';
import '../../core/widgets/nebula_background.dart';
import '../../services/audio_service.dart';
import '../../services/profile.dart';
import '../game/application/game_config.dart';
import '../game/application/round_controller.dart';
import '../game/domain/color_keys.dart';
import '../game/presentation/game_screen.dart';
import 'group_models.dart';
import 'room_repository.dart';

/// Player entry point: `/join` (type a PIN) or `/join/CODE` (from the QR).
class JoinScreen extends ConsumerStatefulWidget {
  const JoinScreen({super.key, this.code});

  final String? code;

  @override
  ConsumerState<JoinScreen> createState() => _JoinScreenState();
}

class _JoinScreenState extends ConsumerState<JoinScreen> {
  final _repo = RoomRepository();
  final _pin = TextEditingController();
  final _name = TextEditingController();
  String _avatar = '';
  String? _error;
  bool _busy = false;
  bool _joined = false;

  StreamSubscription<Room?>? _roomSub;
  StreamSubscription<List<RoomPlayer>>? _playersSub;
  Room? _room;
  bool _missing = false;
  List<RoomPlayer> _players = const [];
  int? _activeRound;
  bool _gameOpen = false;
  String? _uid;

  String? get _code => widget.code == null ? null : RoomRepository.normalise(widget.code!);

  @override
  void initState() {
    super.initState();
    AudioService.instance.setScene(MusicScene.menu);
    ref.read(profileProvider.future).then((p) {
      if (!mounted) return;
      _uid = p.uid;
      _name.text = p.nickname;
      setState(() => _avatar = p.avatarSeed);
      if (_code != null) _watch(_code!);
    });
  }

  int _retries = 0;

  void _watch(String code) {
    _roomSub?.cancel();
    _playersSub?.cancel();
    _roomSub = _repo.watchRoom(code).listen((room) {
      if (!mounted) return;
      _retries = 0;
      setState(() {
        _room = room;
        _missing = room == null;
      });
      if (room != null) _onRoom(room);
    }, onError: (Object e) => _retry(code, e));
    _playersSub = _repo.watchPlayers(code).listen((p) {
      if (!mounted) return;
      setState(() {
        _players = p;
        _joined = p.any((x) => x.uid == _uid);
      });
      // Room and player snapshots arrive independently; re-check either way.
      if (_room != null) _onRoom(_room!);
    }, onError: (Object e) => _retry(code, e));
  }

  /// A listener failed (usually sign-in still settling or a network blip):
  /// make sure we're signed in and listen again, rather than claiming the
  /// room doesn't exist.
  Future<void> _retry(String code, Object error) async {
    debugPrint('room listener error: $error');
    if (!mounted || _retries >= 5) {
      if (mounted) setState(() => _missing = true);
      return;
    }
    _retries++;
    await Future<void>.delayed(Duration(milliseconds: 400 * _retries));
    if (FirebaseAuth.instance.currentUser == null) {
      try {
        await FirebaseAuth.instance.signInAnonymously().timeout(const Duration(seconds: 30));
      } catch (_) {}
      ref.invalidate(profileProvider);
      final p = await ref.read(profileProvider.future);
      _uid = p.uid;
      if (_name.text.isEmpty) _name.text = p.nickname;
    }
    if (mounted) _watch(code);
  }

  void _onRoom(Room room) {
    if (!_joined) return;
    final starting = room.status == RoomStatus.countdown || room.status == RoomStatus.playing;
    if (starting && room.round != _activeRound) {
      final me = _players.where((p) => p.uid == _uid).firstOrNull;
      if (me == null || me.round != room.round) return; // joined after this round began
      _activeRound = room.round;
      _openGame(room);
    }
  }

  Future<void> _openGame(Room room) async {
    final nav = Navigator.of(context);
    if (_gameOpen) nav.pop();
    _gameOpen = true;
    final config = GameConfig(
      size: room.config.size,
      difficulty: switch (room.config.colorSet) {
        ColorSetId.easy => Difficulty.easy,
        ColorSetId.hard => Difficulty.hard,
        _ => Difficulty.normal,
      },
      colorblind: room.config.colorSet == ColorSetId.colorblind,
      mode: room.config.voice ? InputMode.voice : InputMode.tap,
    );
    final code = room.code;
    final round = room.round;
    var lastReport = 0;
    final run = GroupRun(
      code: code,
      round: round,
      seed: room.seed,
      onProgress: (correct, cells, elapsed) {
        final now = DateTime.now().millisecondsSinceEpoch;
        if (now - lastReport < 200 && correct < cells) return;
        lastReport = now;
        unawaited(_repo.reportProgress(code, round: round, correct: correct, cells: cells, elapsedMs: elapsed).catchError((_) {}));
      },
      onFinish: (b) => unawaited(_repo
          .reportFinish(code,
              round: round, cleared: b.cleared, correct: b.correct, cells: b.cells, score: b.score, elapsedMs: b.elapsedMs)
          .catchError((_) {})),
    );
    await nav.push(MaterialPageRoute<void>(
      builder: (_) => GameScreen(key: ValueKey('group-$code-$round'), config: config, group: run),
    ));
    _gameOpen = false;
    AudioService.instance.setScene(MusicScene.menu);
  }

  Future<void> _join() async {
    final code = _code;
    final name = _name.text.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (code == null) return;
    if (name.isEmpty || name.length > 16) {
      setState(() => _error = 'Pick a name up to 16 characters');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _repo.join(code, nickname: name, avatar: _avatar);
      HapticFeedback.mediumImpact();
      AudioService.instance.sfx(Sfx.go);
    } on RoomException catch (e) {
      setState(() => _error = e.message);
    } catch (e) {
      setState(() => _error = 'Could not join. Check your connection.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _submitPin() {
    final code = RoomRepository.normalise(_pin.text);
    if (code.length != 6) {
      setState(() => _error = 'The PIN has 6 letters and numbers');
      return;
    }
    context.go('/join/$code');
  }

  @override
  void dispose() {
    _roomSub?.cancel();
    _playersSub?.cancel();
    _pin.dispose();
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: NebulaBackground(
        intensity: 0.8,
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Row(children: [
                    GlassIconButton(
                      icon: LucideIcons.arrowLeft,
                      tooltip: 'Leave',
                      onPressed: () async {
                        if (_joined && _code != null) await _repo.leave(_code!);
                        if (context.mounted) context.go('/');
                      },
                    ),
                    const SizedBox(width: AppSpace.md),
                    const RockketeyesLogo(size: 40),
                    const SizedBox(width: AppSpace.sm),
                    Text('Join a game', style: AppText.heading(22)),
                  ]),
                  const SizedBox(height: AppSpace.xl),
                  if (_code == null) _pinEntry() else _roomBody(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _pinEntry() {
    return GlassPanel(
      padding: const EdgeInsets.all(AppSpace.xl),
      child: Column(children: [
        const Icon(LucideIcons.qrCode, color: AppColors.gold, size: 40),
        const SizedBox(height: 10),
        Text('Scan the QR code on the host screen, or type the game PIN',
            textAlign: TextAlign.center, style: AppText.body(15, color: AppColors.textMuted)),
        const SizedBox(height: AppSpace.lg),
        TextField(
          controller: _pin,
          autofocus: true,
          textAlign: TextAlign.center,
          textCapitalization: TextCapitalization.characters,
          maxLength: 6,
          style: AppText.display(34).copyWith(letterSpacing: 8),
          decoration: InputDecoration(hintText: 'PIN', counterText: '', errorText: _error),
          onSubmitted: (_) => _submitPin(),
        ),
        const SizedBox(height: AppSpace.lg),
        GoldButton(label: 'Enter', icon: LucideIcons.arrowRight, onPressed: _submitPin),
      ]),
    );
  }

  Widget _roomBody() {
    final room = _room;
    if (_missing) {
      return GlassPanel(
        padding: const EdgeInsets.all(AppSpace.xl),
        child: Column(children: [
          const Icon(LucideIcons.searchX, color: AppColors.error, size: 40),
          const SizedBox(height: 10),
          Text('No game with PIN $_code', style: AppText.heading(20)),
          const SizedBox(height: 6),
          Text('Check the PIN on the host screen and try again.', style: AppText.body(14, color: AppColors.textMuted)),
          const SizedBox(height: AppSpace.lg),
          GlassButton(label: 'Enter another PIN', onPressed: () => context.go('/join')),
        ]),
      );
    }
    if (room == null) return const Center(child: CircularProgressIndicator(color: AppColors.gold));
    if (!_joined) return _joinForm(room);
    return _waiting(room);
  }

  Widget _joinForm(Room room) {
    return GlassPanel(
      padding: const EdgeInsets.all(AppSpace.xl),
      child: Column(children: [
        Text("${room.hostName}'s game", style: AppText.heading(24), textAlign: TextAlign.center),
        const SizedBox(height: 4),
        Text('PIN ${room.code} · ${room.config.size.label} · ${room.config.voice ? 'voice' : 'tap'}',
            style: AppText.label(13, color: AppColors.textMuted)),
        const SizedBox(height: AppSpace.xl),
        GestureDetector(
          onTap: () async {
            final picked = await showAvatarPicker(context, current: _avatar, name: _name.text);
            if (picked != null) {
              setState(() => _avatar = picked);
              await ref.read(profileProvider.notifier).setLocalAvatar(picked);
            }
          },
          child: MouseRegion(
            cursor: SystemMouseCursors.click,
            child: Stack(clipBehavior: Clip.none, children: [
              PlayerAvatar(seed: _avatar, name: _name.text, size: 96, ring: AppColors.gold),
              const Positioned(
                right: -2,
                bottom: -2,
                child: CircleAvatar(
                  radius: 16,
                  backgroundColor: AppColors.gold,
                  child: Icon(LucideIcons.palette, size: 16, color: Color(0xFF1A1206)),
                ),
              ),
            ]),
          ),
        ),
        const SizedBox(height: AppSpace.sm),
        Text('Tap to pick your avatar', style: AppText.label(12, color: AppColors.textFaint)),
        const SizedBox(height: AppSpace.lg),
        TextField(
          controller: _name,
          maxLength: 16,
          textAlign: TextAlign.center,
          style: AppText.label(18),
          decoration: InputDecoration(labelText: 'Your name', errorText: _error, counterText: ''),
          onChanged: (_) => setState(() {}),
          onSubmitted: (_) => _join(),
        ),
        const SizedBox(height: AppSpace.lg),
        if (room.status != RoomStatus.lobby)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text('A round is in progress. You can join when the host opens the next one.',
                textAlign: TextAlign.center, style: AppText.body(13, color: AppColors.textMuted)),
          ),
        GoldButton(label: 'Join game', icon: LucideIcons.logIn, busy: _busy, onPressed: _join),
      ]),
    );
  }

  Widget _waiting(Room room) {
    final me = _players.where((p) => p.uid == _uid).firstOrNull;
    final others = [for (final p in _players) if (p.uid != _uid) p];
    final ranked = standings([for (final p in _players) if (p.round == room.round) p]);
    final place = me == null ? -1 : ranked.indexWhere((p) => p.uid == me.uid);
    final finished = room.status == RoomStatus.finished;
    return Column(children: [
      GlassPanel(
        padding: const EdgeInsets.all(AppSpace.xl),
        glow: AppColors.gold.withValues(alpha: 0.15),
        child: Column(children: [
          if (me != null) PlayerAvatar(seed: me.avatar, name: me.nickname, size: 96, ring: AppColors.gold),
          const SizedBox(height: 12),
          if (finished && place >= 0) ...[
            Text(place == 0 ? 'You won!' : 'You placed #${place + 1}', style: AppText.display(34)),
            const SizedBox(height: 4),
            Text(
              me!.state == PlayerState.cleared ? 'Cleared in ${formatClock(me.elapsedMs)}' : '${me.correct}/${me.cells} · ${me.score} pts',
              style: AppText.label(15, color: AppColors.gold),
            ),
            const SizedBox(height: 8),
            Text('Waiting for the host to start the next round', style: AppText.body(14, color: AppColors.textMuted)),
          ] else ...[
            Text("You're in!", style: AppText.display(34)),
            const SizedBox(height: 4),
            Text('Look at the host screen. The game starts when the host is ready.',
                textAlign: TextAlign.center, style: AppText.body(15, color: AppColors.textMuted)),
          ],
          const SizedBox(height: AppSpace.lg),
          Pill(label: 'PIN ${room.code} · ${room.config.size.label}', color: AppColors.violet),
        ]),
      ),
      const SizedBox(height: AppSpace.lg),
      if (finished && ranked.isNotEmpty)
        GlassPanel(
          child: Column(children: [
            for (var i = 0; i < ranked.length; i++)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 5),
                child: Row(children: [
                  SizedBox(width: 34, child: Text('#${i + 1}', style: AppText.numeric(14, color: AppColors.textMuted))),
                  PlayerAvatar(seed: ranked[i].avatar, name: ranked[i].nickname, size: 30),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(ranked[i].nickname,
                        style: AppText.label(14, color: ranked[i].uid == _uid ? AppColors.gold : AppColors.text)),
                  ),
                  Text(
                    ranked[i].state == PlayerState.cleared ? formatClock(ranked[i].elapsedMs) : '${ranked[i].score}',
                    style: AppText.numeric(14),
                  ),
                ]),
              ),
          ]),
        )
      else if (others.isNotEmpty)
        GlassPanel(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${others.length} other player${others.length == 1 ? '' : 's'}', style: AppText.label(14, color: AppColors.textMuted)),
            const SizedBox(height: 10),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final p in others)
                Tooltip(message: p.nickname, child: PlayerAvatar(seed: p.avatar, name: p.nickname, size: 40)),
            ]),
          ]),
        ),
    ]);
  }
}
