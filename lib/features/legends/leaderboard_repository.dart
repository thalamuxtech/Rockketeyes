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

  Query<Map<String, dynamic>> _query(String boardId, LegendPeriod period, String? country) {
    var q = _db
        .collection('bests')
        .where('period', isEqualTo: PeriodKeys.of(period, DateTime.now()))
        .where('boardId', isEqualTo: boardId);
    if (country != null && country.isNotEmpty) q = q.where('country', isEqualTo: country);
    return q.orderBy('score', descending: true);
  }

  Future<List<LegendEntry>> top(String boardId, LegendPeriod period, {String? country, int limit = 50}) async {
    final snap = await _query(boardId, period, country).limit(limit).get();
    return snap.docs.map((d) => LegendEntry.fromMap(d.data())).toList();
  }

  /// The player's own best on this board/period and its rank.
  Future<({LegendEntry entry, int rank})?> mine(String uid, String boardId, LegendPeriod period,
      {String? country}) async {
    final id = '${PeriodKeys.of(period, DateTime.now())}_${boardId}_$uid';
    final doc = await _db.collection('bests').doc(id).get();
    final data = doc.data();
    if (data == null) return null;
    final entry = LegendEntry.fromMap(data);
    if (country != null && country.isNotEmpty && entry.country != country) return null;
    var q = _db
        .collection('bests')
        .where('period', isEqualTo: PeriodKeys.of(period, DateTime.now()))
        .where('boardId', isEqualTo: boardId);
    if (country != null && country.isNotEmpty) q = q.where('country', isEqualTo: country);
    final agg = await q.where('score', isGreaterThan: entry.score).count().get();
    return (entry: entry, rank: (agg.count ?? 0) + 1);
  }
}
