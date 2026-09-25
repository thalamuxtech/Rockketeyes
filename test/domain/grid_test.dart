import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:rocketeye/features/game/domain/color_set.dart';
import 'package:rocketeye/features/game/domain/grid.dart';
import 'package:rocketeye/features/game/domain/prng.dart';

void main() {
  group('Mulberry32', () {
    test('matches the JavaScript reference sequence for seed 42', () {
      // Reference values from the canonical JS mulberry32 (Math.imul).
      final rng = Mulberry32(42);
      final values = List.generate(5, (_) => rng.nextUint32());
      expect(values, [2581720956, 1925393290, 3661312704, 2876485805, 750819978]);
    });

    test('imul wraps like Math.imul', () {
      expect(Mulberry32.imul(0xFFFFFFFF, 5), (-5) & 0xFFFFFFFF);
      expect(Mulberry32.imul(0x12345678, 0x9ABCDEF0), 0x242D2080);
    });

    test('nextInt stays in range', () {
      final rng = Mulberry32(7);
      for (var i = 0; i < 10000; i++) {
        final v = rng.nextInt(6);
        expect(v, inInclusiveRange(0, 5));
      }
    });
  });

  group('GridGenerator', () {
    test('is deterministic for a seed', () {
      final a = GridGenerator.generate(
          size: const GridSize(8, 8), colorKeys: ColorSetId.normal.keys, seed: 99);
      final b = GridGenerator.generate(
          size: const GridSize(8, 8), colorKeys: ColorSetId.normal.keys, seed: 99);
      expect(a.map((c) => c.toJson()).toList(), b.map((c) => c.toJson()).toList());
    });

    for (final set in ColorSetId.values) {
      for (final size in GridSize.presets) {
        test('constraints hold for ${set.name} ${size.id} over 200 seeds', () {
          var repeats = 0;
          for (var seed = 1; seed <= 200; seed++) {
            final cells = GridGenerator.generate(
                size: size, colorKeys: set.keys, seed: seed * 7919);
            expect(cells.length, size.cells);
            final counts = <String, int>{};
            for (final c in cells) {
              expect(c.word, isNot(c.ink), reason: 'no congruent cells by default');
              counts[c.ink] = (counts[c.ink] ?? 0) + 1;
              final i = c.index;
              if (i > 0 && cells[i - 1].ink == c.ink) repeats++;
              if (i % size.cols > 0) {
                // Word differs from left neighbour unless impossible.
                if (set.keys.length > 3) {
                  expect(c.word, isNot(cells[i - 1].word));
                }
              }
            }
            final min = counts.values.reduce((a, b) => a < b ? a : b);
            final max = counts.values.reduce((a, b) => a > b ? a : b);
            expect(max - min, lessThanOrEqualTo(1), reason: 'balanced inks');
          }
          // Consecutive same-ink should be essentially eliminated.
          expect(repeats, lessThanOrEqualTo(2));
        });
      }
    }

    test('congruent ratio produces some congruent cells', () {
      final cells = GridGenerator.generate(
          size: const GridSize(10, 10),
          colorKeys: ColorSetId.normal.keys,
          seed: 5,
          congruentRatio: 0.3);
      final congruent = cells.where((c) => c.congruent).length;
      expect(congruent, inInclusiveRange(15, 45));
    });

    test('matches golden fixtures shared with the server', () {
      final golden = _golden();
      for (final g in (golden['grids'] as List).cast<Map<String, dynamic>>()) {
        final size = GridSize.tryParse(g['size'] as String)!;
        final cells = GridGenerator.generate(
          size: size,
          colorKeys: ColorSetId.values.byName(g['set'] as String).keys,
          seed: g['seed'] as int,
          congruentRatio: (g['congruent'] as num).toDouble(),
        );
        expect(cells.map((c) => c.ink).join(','), g['ink'], reason: '${g['size']} ${g['seed']}');
        expect(cells.map((c) => c.word).join(','), g['word']);
      }
    });
  });
}

Map<String, dynamic> _golden() => jsonDecode(
        File('test/fixtures/golden.json').readAsStringSync())
    as Map<String, dynamic>;
