// Regenerates test/fixtures/golden.json — the cross-language contract between
// the Dart client and the TypeScript server (functions/src/core).
//
//   dart run tool/gen_golden.dart
//
// The PRNG reference values are taken from a canonical JavaScript mulberry32
// run (see functions/test/golden.test.ts) and must never change.
import 'dart:convert';
import 'dart:io';

import 'package:rocketeye/features/game/domain/color_keys.dart';
import 'package:rocketeye/features/game/domain/grid.dart';
import 'package:rocketeye/features/game/domain/prng.dart';
import 'package:rocketeye/features/game/domain/scoring.dart';

void main() {
  final rng = Mulberry32(42);
  final prng42 = List.generate(5, (_) => rng.nextUint32());

  final grids = <Map<String, Object>>[];
  const seeds = [1, 2, 3, 42, 99, 7919, 123456789, 0xDEADBEEF, 0xFFFFFFFF, 2026];
  for (final set in ColorSetId.values) {
    for (final size in GridSize.presets) {
      for (final seed in seeds) {
        for (final congruent in [0.0, 0.25]) {
          final cells = GridGenerator.generate(
            size: size,
            colorKeys: set.keys,
            seed: seed,
            congruentRatio: congruent,
          );
          grids.add({
            'set': set.name,
            'size': size.id,
            'seed': seed,
            'congruent': congruent,
            'ink': cells.map((c) => c.ink).join(','),
            'word': cells.map((c) => c.word).join(','),
          });
        }
      }
    }
  }

  // Scoring cases: cells, correct, correctElapsedMs, elapsedMs → score.
  final scoringCases = <Map<String, Object>>[];
  final caseRng = Mulberry32(314159);
  for (var t = 0; t < 80; t++) {
    final cells = GridSize.presets[t % GridSize.presets.length].cells;
    final correct = t % 5 == 0 ? cells : caseRng.nextInt(cells + 1);
    final perCell = 300 + caseRng.nextInt(1700);
    final correctElapsed = correct * perCell;
    final elapsed = correct == cells ? correctElapsed : correctElapsed + 200 + caseRng.nextInt(900);
    final s = ScoreCalculator.compute(
        cells: cells, correct: correct, correctElapsedMs: correctElapsed, elapsedMs: elapsed);
    scoringCases.add({
      'cells': cells,
      'correct': correct,
      'correctElapsedMs': correctElapsed,
      'elapsedMs': elapsed,
      'score': s.score,
      'end': s.end.name,
    });
  }

  final out = {
    'generatorVersion': GridGenerator.generatorVersion,
    'scoringVersion': ScoringConfig.version,
    'prng42': prng42,
    'grids': grids,
    'scoring': scoringCases,
  };
  final file = File('test/fixtures/golden.json')..createSync(recursive: true);
  file.writeAsStringSync(const JsonEncoder.withIndent(' ').convert(out));
  stdout.writeln('Wrote ${grids.length} grids, ${scoringCases.length} scoring cases');
}
