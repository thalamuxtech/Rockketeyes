import { readFileSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { describe, expect, it } from 'vitest';

import { COLOR_SETS, isColorSetId } from '../src/core/colors.js';
import { generateGrid, GENERATOR_VERSION, tryParseSize } from '../src/core/grid.js';
import { Mulberry32 } from '../src/core/prng.js';
import { computeScore, SCORING_VERSION } from '../src/core/scoring.js';

interface Golden {
  generatorVersion: number;
  scoringVersion: number;
  prng42: number[];
  grids: { set: string; size: string; seed: number; congruent: number; ink: string; word: string }[];
  scoring: { cells: number; correct: number; correctElapsedMs: number; elapsedMs: number; score: number; end: string }[];
}

const here = dirname(fileURLToPath(import.meta.url));
// functions/test -> app/test/fixtures/golden.json
const golden = JSON.parse(readFileSync(resolve(here, '../../test/fixtures/golden.json'), 'utf8')) as Golden;

describe('golden fixtures (Dart <-> TS parity)', () => {
  it('versions match', () => {
    expect(golden.generatorVersion).toBe(GENERATOR_VERSION);
    expect(golden.scoringVersion).toBe(SCORING_VERSION);
  });

  it('mulberry32 seed 42', () => {
    const rng = new Mulberry32(42);
    const got = Array.from({ length: golden.prng42.length }, () => rng.nextUint32());
    expect(got).toEqual(golden.prng42);
    expect(got).toEqual([2581720956, 1925393290, 3661312704, 2876485805, 750819978]);
  });

  it(`all ${golden.grids.length} grids match`, () => {
    expect(golden.grids.length).toBeGreaterThan(0);
    const mismatches: string[] = [];
    for (const g of golden.grids) {
      if (!isColorSetId(g.set)) throw new Error(`unknown set ${g.set}`);
      const size = tryParseSize(g.size);
      if (!size) throw new Error(`bad size ${g.size}`);
      const cells = generateGrid({ size, colorKeys: COLOR_SETS[g.set], seed: g.seed, congruentRatio: g.congruent });
      const ink = cells.map((c) => c.ink).join(',');
      const word = cells.map((c) => c.word).join(',');
      if (ink !== g.ink || word !== g.word) mismatches.push(`${g.set}/${g.size}/${g.seed}/${g.congruent}`);
    }
    expect(mismatches).toEqual([]);
  });

  it(`all ${golden.scoring.length} scoring cases match`, () => {
    expect(golden.scoring.length).toBeGreaterThan(0);
    const mismatches: string[] = [];
    for (const c of golden.scoring) {
      const r = computeScore({
        cells: c.cells,
        correct: c.correct,
        correctElapsedMs: c.correctElapsedMs,
        elapsedMs: c.elapsedMs,
      });
      if (r.score !== c.score || r.end !== c.end) {
        mismatches.push(`${JSON.stringify(c)} -> score=${r.score} end=${r.end}`);
      }
    }
    expect(mismatches).toEqual([]);
  });
});
