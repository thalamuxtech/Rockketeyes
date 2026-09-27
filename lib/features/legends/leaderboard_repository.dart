import 'package:cloud_firestore/cloud_firestore.dart';

enum LegendPeriod { today, week, all }

class LegendEntry {
  const LegendEntry({
    required this.uid,
    required this.nickname,
    required this.avatarSeed,
    required this.country,
    required this.score,
    required this.correct,
    required this.cells,
    required this.elapsedMs,
    required this.cleared,
    this.boardId = '',
  });

  final String uid;
  final String nickname;
  final String avatarSeed;
  final String country;
  final int score;
  final int correct;
  final int cells;
  final int elapsedMs;
  final bool cleared;

  /// e.g. `8x8.easy.voice`
  final String boardId;

  factory LegendEntry.fromMap(Map<String, dynamic> d) => LegendEntry(
    uid: d['uid'] as String? ?? '',
    nickname: d['nickname'] as String? ?? 'Pilot',
    avatarSeed: d['avatarSeed'] as String? ?? '',
    country: d['country'] as String? ?? '',
    score: (d['score'] as num?)?.toInt() ?? 0,
    correct: (d['correct'] as num?)?.toInt() ?? 0,
    cells: (d['cells'] as num?)?.toInt() ?? 0,
    elapsedMs: (d['elapsedMs'] as num?)?.toInt() ?? 0,
    cleared: d['end'] == 'cleared',
    boardId: d['boardId'] as String? ?? '',
  );
}

/// Period keys shared with the server (UTC).
abstract final class PeriodKeys {
  static String day(DateTime now) {
    final u = now.toUtc();
    return 'd${u.year.toString().padLeft(4, '0')}-${u.month.toString().padLeft(2, '0')}-${u.day.toString().padLeft(2, '0')}';
  }

  /// ISO-8601 week, e.g. `w2026-W39`.
  static String week(DateTime now) {
    final u = now.toUtc();
    final date = DateTime.utc(u.year, u.month, u.day);
    final thursday = date.add(Duration(days: 4 - (date.weekday)));
    final firstThursdayYear = thursday.year;
    final jan1 = DateTime.utc(firstThursdayYear, 1, 1);
    final week = 1 + (thursday.difference(jan1).inDays ~/ 7);
    return 'w$firstThursdayYear-W${week.toString().padLeft(2, '0')}';
  }

  static String of(LegendPeriod p, DateTime now) => switch (p) {
    LegendPeriod.today => day(now),
    LegendPeriod.week => week(now),
    LegendPeriod.all => 'all',
  };
}

class LeaderboardRepository {
  LeaderboardRepository(this._db);

  final FirebaseFirestore _db;

  /// [boardId] null means all boards together.
  Query<Map<String, dynamic>> _query(
    String? boardId,
    LegendPeriod period,
    String? country,
  ) {
    Query<Map<String, dynamic>> q = _db
        .collection('bests')
        .where('period', isEqualTo: PeriodKeys.of(period, DateTime.now()));
    if (boardId != null) q = q.where('boardId', isEqualTo: boardId);
    if (country != null && country.isNotEmpty)
      q = q.where('country', isEqualTo: country);
    return q.orderBy('score', descending: true);
  }

  /// Top players. For all boards, each player appears once with their best.
  Future<List<LegendEntry>> top(
    String? boardId,
    LegendPeriod period, {
    String? country,
    int limit = 50,
  }) async {
    final snap = await _query(
      boardId,
      period,
      country,
    ).limit(boardId == null ? limit * 3 : limit).get();
    final all = snap.docs.map((d) => LegendEntry.fromMap(d.data()));
    if (boardId != null) return all.toList();
    final seen = <String>{};
    return [
      for (final e in all)
        if (seen.add(e.uid)) e,
    ].take(limit).toList();
  }

  /// The player's own best on this board (or on any board) and its rank.
  Future<({LegendEntry entry, int rank})?> mine(
    String uid,
    String? boardId,
    LegendPeriod period, {
    String? country,
    List<LegendEntry>? topAll,
  }) async {
    final periodKey = PeriodKeys.of(period, DateTime.now());
    if (boardId == null) {
      final snap = await _db
          .collection('bests')
          .where('period', isEqualTo: periodKey)
          .where('uid', isEqualTo: uid)
          .get();
      final mine =
          snap.docs
              .map((d) => LegendEntry.fromMap(d.data()))
              .where(
                (e) =>
                    country == null || country.isEmpty || e.country == country,
              )
              .toList()
            ..sort((a, b) => b.score.compareTo(a.score));
      if (mine.isEmpty) return null;
      final best = mine.first;
      final list =
          topAll ?? await top(null, period, country: country, limit: 100);
      final idx = list.indexWhere((e) => e.uid == uid);
      return (entry: best, rank: idx >= 0 ? idx + 1 : list.length + 1);
    }
    final doc = await _db
        .collection('bests')
        .doc('${periodKey}_${boardId}_$uid')
        .get();
    final data = doc.data();
    if (data == null) return null;
    final entry = LegendEntry.fromMap(data);
    if (country != null && country.isNotEmpty && entry.country != country)
      return null;
    var q = _db
        .collection('bests')
        .where('period', isEqualTo: periodKey)
        .where('boardId', isEqualTo: boardId);
    if (country != null && country.isNotEmpty)
      q = q.where('country', isEqualTo: country);
    final agg = await q
        .where('score', isGreaterThan: entry.score)
        .count()
        .get();
    return (entry: entry, rank: (agg.count ?? 0) + 1);
  }

  /// Boards this player has an all-time best on (to mark them in filters).
  Future<Set<String>> myBoards(String uid) async {
    final snap = await _db
        .collection('bests')
        .where('period', isEqualTo: 'all')
        .where('uid', isEqualTo: uid)
        .get();
    return {for (final d in snap.docs) (d.data()['boardId'] as String? ?? '')};
  }
}
