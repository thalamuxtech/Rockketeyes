import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:rocketeye/features/game/domain/scoring.dart';

void main() {
  test('zero correct scores zero', () {
    final s = ScoreCalculator.compute(cells: 12, correct: 0, correctElapsedMs: 0, elapsedMs: 900);
    expect(s.score, 0);
    expect(s.end, RoundEnd.mistake);
  });

  test('clearing the board beats stopping one short', () {
    final full = ScoreCalculator.compute(cells: 12, correct: 12, correctElapsedMs: 9000, elapsedMs: 9000);
    final short = ScoreCalculator.compute(cells: 12, correct: 11, correctElapsedMs: 8250, elapsedMs: 8800);
    expect(full.cleared, isTrue);
    expect(full.score, greaterThan(short.score));
  });

  test('faster is better at the same progress', () {
    final fast = ScoreCalculator.compute(cells: 64, correct: 30, correctElapsedMs: 18000, elapsedMs: 18500);
    final slow = ScoreCalculator.compute(cells: 64, correct: 30, correctElapsedMs: 36000, elapsedMs: 36500);
    expect(fast.score, greaterThan(slow.score));
  });

  test('bigger boards weigh more', () {
    final small = ScoreCalculator.compute(cells: 12, correct: 12, correctElapsedMs: 12000, elapsedMs: 12000);
    final big = ScoreCalculator.compute(cells: 256, correct: 12, correctElapsedMs: 12000, elapsedMs: 12500);
    expect(big.sizeMultiplier, greaterThan(small.sizeMultiplier));
  });

  test('matches golden scoring cases shared with the server', () {
    final golden = jsonDecode(File('test/fixtures/golden.json').readAsStringSync()) as Map<String, dynamic>;
    for (final c in (golden['scoring'] as List).cast<Map<String, dynamic>>()) {
      final s = ScoreCalculator.compute(
        cells: c['cells'] as int,
        correct: c['correct'] as int,
        correctElapsedMs: c['correctElapsedMs'] as int,
        elapsedMs: c['elapsedMs'] as int,
      );
      expect(s.score, c['score']);
      expect(s.end.name, c['end']);
    }
  });
}
