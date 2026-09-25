import { describe, expect, it } from 'vitest';

import { COLOR_SETS } from '../src/core/colors.js';
import { ApiError } from '../src/core/errors.js';
import { generateGrid } from '../src/core/grid.js';
import { parseProfile } from '../src/core/profile.js';
import { computeScore } from '../src/core/scoring.js';
import { dayKey, isoWeekKey } from '../src/core/time.js';
import {
  checkRoundUsable,
  parseRoundStart,
  parseSubmit,
  validateAndScore,
  type RoundDoc,
  type SubmitEvent,
} from '../src/core/validate.js';

const ISSUED = 1_700_000_000_000;

function round(over: Partial<RoundDoc> = {}): RoundDoc {
  const cols = over.cols ?? 3;
  const rows = over.rows ?? 4;
  const colorSet = over.colorSet ?? 'normal';
  return {
    uid: 'u1',
    seed: 12345,
    cols,
    rows,
    sizeId: `${cols}x${rows}`,
    colorSet,
    congruentRatio: 0,
    mode: 'voice',
    boardId: `${cols}x${rows}.${colorSet}.voice`,
    ranked: true,
    generatorVersion: 1,
    scoringVersion: 1,
    issuedAt: ISSUED,
    expiresAt: ISSUED + 30 * 60 * 1000,
    used: false,
    ...over,
  };
}

function correctEvents(r: RoundDoc, stepMs = 600): SubmitEvent[] {
  const grid = generateGrid({
    size: { cols: r.cols, rows: r.rows },
    colorKeys: COLOR_SETS[r.colorSet],
    seed: r.seed,
    congruentRatio: r.congruentRatio,
  });
  return grid.map((c, k) => ({ i: k, c: c.ink, t: (k + 1) * stepMs }));
}

function expectApiError(fn: () => unknown, status: number, code: string): void {
  try {
    fn();
  } catch (e) {
    expect(e).toBeInstanceOf(ApiError);
    expect({ status: (e as ApiError).status, code: (e as ApiError).code }).toEqual({ status, code });
    return;
  }
  throw new Error(`expected ApiError ${status} ${code}`);
}

const NOW = ISSUED + 60_000;

function gridOf(r: RoundDoc) {
  return generateGrid({
    size: { cols: r.cols, rows: r.rows },
    colorKeys: COLOR_SETS[r.colorSet],
    seed: r.seed,
    congruentRatio: r.congruentRatio,
  });
}

/** `correctCount` correct answers, then one wrong answer (the printed word, or another wrong color). */
function eventsEndingInMistake(r: RoundDoc, correctCount: number, kind: 'word' | 'color', stepMs = 600): SubmitEvent[] {
  const grid = gridOf(r);
  const events = correctEvents(r, stepMs).slice(0, correctCount);
  const cell = grid[correctCount]!;
  const wrongKey =
    kind === 'word' ? cell.word : COLOR_SETS[r.colorSet].find((k) => k !== cell.ink && k !== cell.word)!;
  events.push({ i: correctCount, c: wrongKey, t: (correctCount + 1) * stepMs });
  return events;
}

describe('validateAndScore', () => {
  it('accepts a cleared round and scores it server-side', () => {
    const r = round();
    const events = correctEvents(r);
    const v = validateAndScore(r, { roundId: 'x', elapsedMs: 7200, events }, NOW);
    expect(v.end).toBe('cleared');
    expect(v.correct).toBe(12);
    expect(v.cells).toBe(12);
    expect(v.completion).toBe(1);
    expect(v.correctElapsedMs).toBe(7200);
    expect(v.elapsedMs).toBe(7200);
    expect(v.mistakeKind).toBeNull();
    expect(v.score).toBe(computeScore({ cells: 12, correct: 12, correctElapsedMs: 7200, elapsedMs: 7200 }).score);
    expect(v.score).toBeGreaterThan(0);
    expect(v.review).toBe(false);
  });

  it('accepts a round ending on a wrong color (mistake)', () => {
    const r = round();
    const events = eventsEndingInMistake(r, 4, 'color'); // 4 correct, wrong at cell index 4 (5th cell)
    const v = validateAndScore(r, { roundId: 'x', elapsedMs: 3000, events }, NOW);
    expect(v.end).toBe('mistake');
    expect(v.correct).toBe(4);
    expect(v.correctElapsedMs).toBe(2400);
    expect(v.elapsedMs).toBe(3000);
    expect(v.mistakeKind).toBe('color');
    expect(v.completion).toBeCloseTo(4 / 12);
    expect(v.score).toBe(computeScore({ cells: 12, correct: 4, correctElapsedMs: 2400, elapsedMs: 3000 }).score);
  });

  it('detects reading the printed word', () => {
    const r = round();
    const events = eventsEndingInMistake(r, 6, 'word');
    const v = validateAndScore(r, { roundId: 'x', elapsedMs: 4200, events }, NOW);
    expect(v.end).toBe('mistake');
    expect(v.mistakeKind).toBe('word');
  });

  it('accepts a mistake on the very first cell', () => {
    const r = round();
    const events = eventsEndingInMistake(r, 0, 'color');
    const v = validateAndScore(r, { roundId: 'x', elapsedMs: 600, events }, NOW);
    expect(v.correct).toBe(0);
    expect(v.correctElapsedMs).toBe(0);
    expect(v.score).toBe(0);
  });

  it('rejects a wrong answer before the last event', () => {
    const r = round();
    const events = eventsEndingInMistake(r, 4, 'color');
    events.push({ i: 5, c: gridOf(r)[5]!.ink, t: 3600 });
    expectApiError(() => validateAndScore(r, { roundId: 'x', elapsedMs: 3600, events }, NOW), 400, 'invalid_events');
  });

  it('rejects a partial log that ends on a correct answer', () => {
    const r = round();
    const events = correctEvents(r).slice(0, 5);
    expectApiError(() => validateAndScore(r, { roundId: 'x', elapsedMs: 3000, events }, NOW), 400, 'invalid_events');
  });

  it('rejects too fast (mean < 250 ms per event)', () => {
    const r = round();
    const events = correctEvents(r, 200);
    expectApiError(() => validateAndScore(r, { roundId: 'x', elapsedMs: 2400, events }, NOW), 400, 'too_fast');
  });

  it('does not apply too_fast to fewer than 3 events', () => {
    const r = round();
    const events = eventsEndingInMistake(r, 1, 'color', 100);
    const v = validateAndScore(r, { roundId: 'x', elapsedMs: 200, events }, NOW);
    expect(v.end).toBe('mistake');
  });

  it('rejects reordered indices', () => {
    const r = round();
    const events = correctEvents(r);
    const a = events[2]!;
    const b = events[3]!;
    events[2] = { ...b, t: a.t };
    events[3] = { ...a, t: b.t };
    expectApiError(() => validateAndScore(r, { roundId: 'x', elapsedMs: 7200, events }, NOW), 400, 'bad_index');
  });

  it('rejects the wrong event count', () => {
    const r = round();
    const tooMany = [...correctEvents(r), { i: 12, c: 'red', t: 7800 }];
    expectApiError(
      () => validateAndScore(r, { roundId: 'x', elapsedMs: 7800, events: tooMany }, NOW),
      400,
      'wrong_event_count',
    );
    expectApiError(() => validateAndScore(r, { roundId: 'x', elapsedMs: 0, events: [] }, NOW), 400, 'wrong_event_count');
  });

  it("rejects a color key outside the round color set (including 'skip')", () => {
    const r = round({ colorSet: 'easy', boardId: '3x4.easy.voice' });
    const events = correctEvents(r);
    events[11] = { ...events[11]!, c: 'purple' }; // not in easy
    expectApiError(() => validateAndScore(r, { roundId: 'x', elapsedMs: 7200, events }, NOW), 400, 'bad_color');
    events[11] = { ...events[11]!, c: 'skip' };
    expectApiError(() => validateAndScore(r, { roundId: 'x', elapsedMs: 7200, events }, NOW), 400, 'bad_color');
  });

  it('rejects non-monotonic timestamps', () => {
    const r = round();
    const events = correctEvents(r);
    events[4] = { ...events[4]!, t: 100 };
    expectApiError(() => validateAndScore(r, { roundId: 'x', elapsedMs: 7200, events }, NOW), 400, 'bad_timing');
  });

  it('rejects elapsedMs that does not match the last event', () => {
    const r = round();
    const events = correctEvents(r); // last t = 7200
    expectApiError(
      () => validateAndScore(r, { roundId: 'x', elapsedMs: 7200 + 1501, events }, NOW),
      400,
      'elapsed_mismatch',
    );
    expect(() => validateAndScore(r, { roundId: 'x', elapsedMs: 7200 + 1500, events }, NOW)).not.toThrow();
  });

  it('rejects elapsedMs longer than wall-clock time since issue', () => {
    const r = round();
    const events = correctEvents(r);
    expectApiError(
      () => validateAndScore(r, { roundId: 'x', elapsedMs: 7200, events }, ISSUED + 5000),
      400,
      'elapsed_exceeds_wallclock',
    );
  });

  it('flags review when >20% of gaps are < 120 ms', () => {
    const r = round();
    const events = correctEvents(r);
    // Bursty timing: 4 of 11 gaps are 50 ms; mean per cell still >= 250 ms.
    let t = 0;
    const gaps = [800, 50, 800, 50, 800, 50, 800, 50, 800, 800, 800, 800];
    const timed = events.map((e, k) => ({ ...e, t: (t += gaps[k]!) }));
    const v = validateAndScore(r, { roundId: 'x', elapsedMs: t, events: timed }, NOW);
    expect(v.review).toBe(true);
  });

  it('flags review for a cleared large board with mean < 400 ms', () => {
    const r = round({ cols: 8, rows: 8, boardId: '8x8.normal.voice' });
    const events = correctEvents(r, 300);
    const v = validateAndScore(r, { roundId: 'x', elapsedMs: 64 * 300, events }, NOW);
    expect(v.end).toBe('cleared');
    expect(v.review).toBe(true);
    const slow = validateAndScore(r, { roundId: 'x', elapsedMs: 64 * 450, events: correctEvents(r, 450) }, NOW);
    expect(slow.review).toBe(false);
  });
});

describe('checkRoundUsable', () => {
  it('rejects other users, used and expired rounds', () => {
    expectApiError(() => checkRoundUsable(round(), 'u2', NOW), 403, 'permission_denied');
    expectApiError(() => checkRoundUsable(round({ used: true }), 'u1', NOW), 410, 'round_used');
    expectApiError(() => checkRoundUsable(round(), 'u1', ISSUED + 31 * 60 * 1000), 410, 'round_expired');
    expect(() => checkRoundUsable(round(), 'u1', NOW)).not.toThrow();
  });
});

describe('parseSubmit', () => {
  it('rejects malformed bodies', () => {
    expectApiError(() => parseSubmit(null), 400, 'invalid_argument');
    expectApiError(() => parseSubmit({ roundId: '', elapsedMs: 1, events: [] }), 400, 'invalid_round_id');
    expectApiError(() => parseSubmit({ roundId: 'a', elapsedMs: 1.5, events: [] }), 400, 'invalid_elapsed');
    expectApiError(() => parseSubmit({ roundId: 'a', elapsedMs: 1, events: [{ i: 0 }] }), 400, 'invalid_events');
  });
});

describe('parseRoundStart', () => {
  it('derives boardId and ranked', () => {
    const p = parseRoundStart({ cols: 8, rows: 8, colorSet: 'normal', congruentRatio: 0, mode: 'voice' });
    expect(p.boardId).toBe('8x8.normal.voice');
    expect(p.ranked).toBe(true);
    expect(parseRoundStart({ cols: 7, rows: 9, colorSet: 'hard', congruentRatio: 0, mode: 'tap' }).ranked).toBe(false);
    expect(parseRoundStart({ cols: 8, rows: 8, colorSet: 'hard', congruentRatio: 0.2, mode: 'tap' }).ranked).toBe(false);
  });

  it('validates inputs', () => {
    const ok = { cols: 3, rows: 4, colorSet: 'easy', congruentRatio: 0, mode: 'voice' };
    expectApiError(() => parseRoundStart({ ...ok, cols: 2 }), 400, 'invalid_size');
    expectApiError(() => parseRoundStart({ ...ok, rows: 17 }), 400, 'invalid_size');
    expectApiError(() => parseRoundStart({ ...ok, colorSet: 'rainbow' }), 400, 'invalid_color_set');
    expectApiError(() => parseRoundStart({ ...ok, congruentRatio: 0.6 }), 400, 'invalid_congruent_ratio');
    expectApiError(() => parseRoundStart({ ...ok, mode: 'mind' }), 400, 'invalid_mode');
  });
});

describe('parseProfile', () => {
  it('normalizes and validates nicknames', () => {
    const p = parseProfile({ nickname: '  Space   Cadet ', avatarSeed: 'abc', country: 'GB' });
    expect(p.nickname).toBe('Space Cadet');
    expect(p.nicknameLower).toBe('space cadet');
    expectApiError(() => parseProfile({ nickname: 'ab' }), 400, 'invalid_nickname');
    expectApiError(() => parseProfile({ nickname: 'bad-chars!' }), 400, 'invalid_nickname');
    expectApiError(() => parseProfile({ nickname: 'fuckface' }), 400, 'profane');
    expectApiError(() => parseProfile({ nickname: 'Pilot', country: 'gb' }), 400, 'invalid_country');
    expectApiError(() => parseProfile({ nickname: 'Pilot', avatarSeed: 'x'.repeat(65) }), 400, 'invalid_avatar_seed');
  });
});

describe('time keys', () => {
  it('computes UTC day and ISO week', () => {
    expect(dayKey(Date.UTC(2026, 8, 25, 23, 59))).toBe('2026-09-25');
    expect(isoWeekKey(Date.UTC(2026, 8, 25))).toBe('2026-W39');
    expect(isoWeekKey(Date.UTC(2021, 0, 3))).toBe('2020-W53');
    expect(isoWeekKey(Date.UTC(2024, 11, 30))).toBe('2025-W01');
  });
});
