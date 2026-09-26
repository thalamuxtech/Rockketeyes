import '../game/domain/color_keys.dart';
import '../game/domain/grid.dart';

enum RoomStatus { lobby, countdown, playing, finished }

enum PlayerState { waiting, playing, cleared, out, left }

/// Characters that are easy to read aloud and type (no 0/O, 1/I).
const kRoomAlphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';

class RoomConfig {
  const RoomConfig({required this.size, required this.colorSet, required this.voice});

  final GridSize size;
  final ColorSetId colorSet;
  final bool voice;

  Map<String, Object> toJson() => {
        'cols': size.cols,
        'rows': size.rows,
        'colorSet': colorSet.name,
        'mode': voice ? 'voice' : 'tap',
      };

  static RoomConfig fromJson(Map<String, dynamic>? j) => RoomConfig(
        size: GridSize((j?['cols'] as num?)?.toInt() ?? 4, (j?['rows'] as num?)?.toInt() ?? 4),
        colorSet: ColorSetId.values.asNameMap()['${j?['colorSet']}'] ?? ColorSetId.normal,
        voice: j?['mode'] != 'tap',
      );
}

class Room {
  const Room({
    required this.code,
    required this.hostUid,
    required this.hostName,
    required this.status,
    required this.config,
    required this.seed,
    required this.round,
  });

  final String code;
  final String hostUid;
  final String hostName;
  final RoomStatus status;
  final RoomConfig config;
  final int seed;
  final int round;

  factory Room.fromDoc(String code, Map<String, dynamic> d) => Room(
        code: code,
        hostUid: d['hostUid'] as String? ?? '',
        hostName: d['hostName'] as String? ?? 'Host',
        status: RoomStatus.values.asNameMap()['${d['status']}'] ?? RoomStatus.lobby,
        config: RoomConfig.fromJson((d['config'] as Map?)?.cast<String, dynamic>()),
        seed: (d['seed'] as num?)?.toInt() ?? 1,
        round: (d['round'] as num?)?.toInt() ?? 0,
      );
}

class RoomPlayer {
  const RoomPlayer({
    required this.uid,
    required this.nickname,
    required this.avatar,
    required this.round,
    required this.state,
    required this.correct,
    required this.cells,
    required this.score,
    required this.elapsedMs,
    this.joinedAtMs = 0,
  });

  final String uid;
  final String nickname;
  final String avatar;
  final int round;
  final PlayerState state;
  final int correct;
  final int cells;
  final int score;
  final int elapsedMs;
  final int joinedAtMs;

  bool get done => state == PlayerState.cleared || state == PlayerState.out || state == PlayerState.left;
  double get progress => cells == 0 ? 0 : (correct / cells).clamp(0, 1).toDouble();

  factory RoomPlayer.fromDoc(Map<String, dynamic> d) => RoomPlayer(
        uid: d['uid'] as String? ?? '',
        nickname: d['nickname'] as String? ?? 'Player',
        avatar: d['avatar'] as String? ?? '',
        round: (d['round'] as num?)?.toInt() ?? 0,
        state: PlayerState.values.asNameMap()['${d['state']}'] ?? PlayerState.waiting,
        correct: (d['correct'] as num?)?.toInt() ?? 0,
        cells: (d['cells'] as num?)?.toInt() ?? 0,
        score: (d['score'] as num?)?.toInt() ?? 0,
        elapsedMs: (d['elapsedMs'] as num?)?.toInt() ?? 0,
        joinedAtMs: (d['joinedAtMs'] as num?)?.toInt() ?? 0,
      );
}

/// Final or live ranking for a group round.
///
/// The first player to clear the board wins; everyone who cleared ranks by
/// finish time. Players who made a mistake rank by score (then progress).
/// Players still going rank by progress, and those who left come last.
List<RoomPlayer> standings(Iterable<RoomPlayer> players) {
  int bucket(RoomPlayer p) => switch (p.state) {
        PlayerState.cleared => 0,
        PlayerState.out => 1,
        PlayerState.playing || PlayerState.waiting => 2,
        PlayerState.left => 3,
      };
  final list = players.toList()
    ..sort((a, b) {
      final ba = bucket(a), bb = bucket(b);
      if (ba != bb) return ba.compareTo(bb);
      if (a.state == PlayerState.cleared) {
        final t = a.elapsedMs.compareTo(b.elapsedMs);
        return t != 0 ? t : b.score.compareTo(a.score);
      }
      final sc = b.score.compareTo(a.score);
      if (sc != 0) return sc;
      final cr = b.correct.compareTo(a.correct);
      if (cr != 0) return cr;
      return a.elapsedMs.compareTo(b.elapsedMs);
    });
  return list;
}
