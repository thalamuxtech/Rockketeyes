import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/theme/app_theme.dart';
import '../../core/widgets/avatar.dart';
import '../../core/widgets/glass.dart';
import '../game/application/round_controller.dart';
import '../game/presentation/game_screen.dart' show formatClock;
import 'group_models.dart';
import 'room_repository.dart';

/// Shown on a player's device after their group round ends: their result and
/// the live standings until everyone finishes.
class GroupResultsView extends StatefulWidget {
  const GroupResultsView({super.key, required this.state, required this.onBack});

  final RoundState state;
  final VoidCallback onBack;

  @override
  State<GroupResultsView> createState() => _GroupResultsViewState();
}

class _GroupResultsViewState extends State<GroupResultsView> {
  final _repo = RoomRepository();
  StreamSubscription<Room?>? _roomSub;
  StreamSubscription<List<RoomPlayer>>? _playersSub;
  Room? _room;
  List<RoomPlayer> _players = const [];

  GroupRun get _run => widget.state.group!;

  @override
  void initState() {
    super.initState();
    _roomSub = _repo.watchRoom(_run.code).listen((r) => setState(() => _room = r));
    _playersSub = _repo.watchPlayers(_run.code).listen((p) => setState(() => _players = p));
  }

  @override
  void dispose() {
    _roomSub?.cancel();
    _playersSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final b = widget.state.breakdown!;
    final inRound = [for (final p in _players) if (p.round == _run.round) p];
    final ranked = standings(inRound);
    final finished = _room?.status == RoomStatus.finished && _room?.round == _run.round;
    final waiting = inRound.where((p) => !p.done).length;
    return Positioned.fill(
      child: ColoredBox(
        color: const Color(0xC7050410),
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: GlassPanel(
                padding: const EdgeInsets.all(AppSpace.xl),
                fill: const Color(0xCC141026),
                radius: AppRadius.lg,
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Icon(b.cleared ? LucideIcons.trophy : LucideIcons.flag,
                      color: b.cleared ? AppColors.gold : AppColors.textMuted, size: 34),
                  const SizedBox(height: 6),
                  Text(b.cleared ? 'Board cleared in ${formatClock(b.elapsedMs)}' : '${b.correct}/${b.cells} before the mistake',
                      textAlign: TextAlign.center, style: AppText.heading(22)),
                  const SizedBox(height: 4),
                  Text('${b.score} points', style: AppText.numeric(18, color: AppColors.gold)),
                  const SizedBox(height: AppSpace.lg),
                  AnimatedSwitcher(
                    duration: AppMotion.short,
                    child: Text(
                      finished ? 'Final results' : (waiting > 0 ? 'Waiting for $waiting player${waiting == 1 ? '' : 's'}…' : 'Tallying…'),
                      key: ValueKey('$finished$waiting'),
                      style: AppText.label(14, color: AppColors.textMuted),
                    ),
                  ),
                  const SizedBox(height: AppSpace.md),
                  for (var i = 0; i < ranked.length; i++)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 5),
                      child: Row(children: [
                        SizedBox(
                          width: 34,
                          child: Text('#${i + 1}',
                              style: AppText.numeric(14, color: i == 0 && finished ? AppColors.gold : AppColors.textMuted)),
                        ),
                        PlayerAvatar(seed: ranked[i].avatar, name: ranked[i].nickname, size: 30),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(ranked[i].nickname,
                              overflow: TextOverflow.ellipsis,
                              style: AppText.label(14, color: ranked[i].uid == _mine ? AppColors.gold : AppColors.text)),
                        ),
                        Text(
                          switch (ranked[i].state) {
                            PlayerState.cleared => formatClock(ranked[i].elapsedMs),
                            PlayerState.out => '${ranked[i].score}',
                            _ => '${ranked[i].correct}/${ranked[i].cells}',
                          },
                          style: AppText.numeric(14),
                        ),
                      ]),
                    ),
                  const SizedBox(height: AppSpace.xl),
                  GoldButton(label: 'Back to the lobby', icon: LucideIcons.users, onPressed: widget.onBack),
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }

  String? get _mine => FirebaseAuth.instance.currentUser?.uid;
}
