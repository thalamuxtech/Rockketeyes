/**
 * Pure request validation and server-side replay. No Firebase imports, so it
 * is unit-tested directly (see `test/validate.test.ts`).
 */
import { colorKeysFor, isColorSetId, type ColorSetId } from './colors.js';
import { ApiError, invalid } from './errors.js';
import { cellCount, GENERATOR_VERSION, generateGrid, isPreset, isValidSize, sizeId } from './grid.js';
import { computeScore, SCORING_VERSION, type ScoreBreakdown } from './scoring.js';

export type GameMode = 'voice' | 'tap';
export const MODES: readonly GameMode[] = ['voice', 'tap'];

export const ROUND_TTL_MS = 30 * 60 * 1000;
export const RATE_LIMIT_WINDOW_MS = 60 * 1000;
export const RATE_LIMIT_MAX_ROUNDS = 12;

/** Anti-cheat thresholds. */
export const Limits = {
  maxElapsedVsLastEventMs: 1500,
  wallClockSlackMs: 1000,
  minMeanMsPerCell: 250,
  fastGapMs: 120,
  fastGapMaxFraction: 0.2,
  tooFastMinEvents: 3,
  perfectReviewMinCells: 64,
  perfectReviewMeanMs: 400,
  maxCongruentRatio: 0.5,
} as const;

function isPlainObject(v: unknown): v is Record<string, unknown> {
  return typeof v === 'object' && v !== null && !Array.isArray(v);
}

// ---------------------------------------------------------------------------
// POST /round/start
// ---------------------------------------------------------------------------

export interface RoundStartInput {
  cols: number;
  rows: number;
  colorSet: ColorSetId;
  congruentRatio: number;
  mode: GameMode;
}

export interface RoundPlan extends RoundStartInput {
  sizeId: string;
  boardId: string;
  ranked: boolean;
  generatorVersion: number;
  scoringVersion: number;
}

export function parseRoundStart(body: unknown): RoundPlan {
  if (!isPlainObject(body)) throw invalid('invalid_argument', 'Body must be a JSON object.');
  const { cols, rows, colorSet, mode } = body;
  const congruentRatio = body.congruentRatio ?? 0;
  if (typeof cols !== 'number' || typeof rows !== 'number' || !isValidSize({ cols, rows })) {
    throw invalid('invalid_size', 'cols must be an integer 3-16 and rows an integer 4-16.');
  }
  if (!isColorSetId(colorSet)) {
    throw invalid('invalid_color_set', "colorSet must be one of 'easy', 'normal', 'hard', 'colorblind'.");
  }
  if (
    typeof congruentRatio !== 'number' ||
    !Number.isFinite(congruentRatio) ||
    congruentRatio < 0 ||
    congruentRatio > Limits.maxCongruentRatio
  ) {
    throw invalid('invalid_congruent_ratio', 'congruentRatio must be a number in [0, 0.5].');
  }
  if (typeof mode !== 'string' || !(MODES as readonly string[]).includes(mode)) {
    throw invalid('invalid_mode', "mode must be 'voice' or 'tap'.");
  }
  const size = { cols, rows };
  const sid = sizeId(size);
  return {
    cols,
    rows,
    colorSet,
    congruentRatio,
    mode: mode as GameMode,
    sizeId: sid,
    boardId: `${sid}.${colorSet}.${mode}`,
    ranked: isPreset(size) && congruentRatio === 0,
    generatorVersion: GENERATOR_VERSION,
    scoringVersion: SCORING_VERSION,
  };
}

// ---------------------------------------------------------------------------
// POST /score/submit
// ---------------------------------------------------------------------------

export interface SubmitEvent {
  /** Cell index. */
  i: number;
  /** Spoken/tapped color key (must be in the round's color set). */
  c: string;
  /** ms since timer start. */
  t: number;
}

export interface SubmitInput {
  roundId: string;
  elapsedMs: number;
  events: SubmitEvent[];
}

/** Shape-only parse of the submit body (before the round is loaded). */
export function parseSubmit(body: unknown): SubmitInput {
  if (!isPlainObject(body)) throw invalid('invalid_argument', 'Body must be a JSON object.');
  const { roundId, elapsedMs, events } = body;
  if (typeof roundId !== 'string' || !/^[A-Za-z0-9_-]{1,64}$/.test(roundId)) {
    throw invalid('invalid_round_id', 'roundId must be a non-empty id string.');
  }
  if (typeof elapsedMs !== 'number' || !Number.isInteger(elapsedMs) || elapsedMs < 0) {
    throw invalid('invalid_elapsed', 'elapsedMs must be a non-negative integer.');
  }
  if (!Array.isArray(events) || events.length > 16 * 16) {
    throw invalid('invalid_events', 'events must be an array of at most 256 items.');
  }
  const parsed: SubmitEvent[] = events.map((e, idx) => {
    if (
      !isPlainObject(e) ||
      typeof e.i !== 'number' ||
      !Number.isInteger(e.i) ||
      typeof e.c !== 'string' ||
      typeof e.t !== 'number' ||
      !Number.isInteger(e.t)
    ) {
      throw invalid('invalid_events', `events[${idx}] must be {i: int, c: string, t: int}.`);
    }
    return { i: e.i, c: e.c, t: e.t };
  });
  return { roundId, elapsedMs, events: parsed };
}

/** The persisted round document (`rounds/{roundId}`). */
export interface RoundDoc {
  uid: string;
  seed: number;
  cols: number;
  rows: number;
  sizeId: string;
  colorSet: ColorSetId;
  congruentRatio: number;
  mode: GameMode;
  boardId: string;
  ranked: boolean;
  generatorVersion: number;
  scoringVersion: number;
  issuedAt: number;
  expiresAt: number;
  used: boolean;
}

/**
 * Checks that the round may be consumed by `uid` at `now`. Throws 403/410.
 * Called before the round is marked used.
 */
export function checkRoundUsable(round: RoundDoc, uid: string, now: number): void {
  if (round.uid !== uid) throw new ApiError(403, 'permission_denied', 'This round belongs to another user.');
  if (round.used) throw new ApiError(410, 'round_used', 'This round was already submitted.');
  if (now > round.expiresAt) throw new ApiError(410, 'round_expired', 'This round has expired.');
}

export type MistakeKind = 'word' | 'color';

export interface Verdict extends ScoreBreakdown {
  /** Timer value at the last correct answer (0 if none). */
  correctElapsedMs: number;
  /** When end === 'mistake': 'word' if the player read the printed word, else 'color'. */
  mistakeKind: MistakeKind | null;
  review: boolean;
}

/**
 * Validates a sudden-death event log against the round and replays it into a
 * score. The log is 1..cells events; every event but the last must be
 * correct; a wrong last event ends the round ('mistake'), a full correct log
 * clears it. Throws ApiError(400, ...) on any inconsistency.
 */
export function validateAndScore(round: RoundDoc, input: SubmitInput, now: number): Verdict {
  const cells = cellCount(round);
  const { events } = input;
  const n = events.length;
  const keys = colorKeysFor(round.colorSet);

  if (n < 1 || n > cells) {
    throw invalid('wrong_event_count', `Expected 1..${cells} events, got ${n}.`);
  }
  for (let k = 0; k < n; k++) {
    const e = events[k]!;
    if (e.i !== k) throw invalid('bad_index', `events[${k}].i must be ${k}.`);
    if (k === 0 ? e.t < 0 : e.t < events[k - 1]!.t) {
      throw invalid('bad_timing', `events[${k}].t must be >= 0 and non-decreasing.`);
    }
    if (!keys.includes(e.c)) {
      throw invalid('bad_color', `events[${k}].c '${e.c}' is not in color set '${round.colorSet}'.`);
    }
  }

  const grid = generateGrid({
    size: { cols: round.cols, rows: round.rows },
    colorKeys: keys,
    seed: round.seed,
    congruentRatio: round.congruentRatio,
  });
  for (let k = 0; k < n - 1; k++) {
    if (events[k]!.c !== grid[k]!.ink) {
      throw invalid('invalid_events', `events[${k}] is wrong but the round continued (sudden death).`);
    }
  }
  const last = events[n - 1]!;
  const lastCorrect = last.c === grid[n - 1]!.ink;
  if (lastCorrect && n < cells) {
    throw invalid('invalid_events', 'The round ended without a mistake before the board was cleared.');
  }
  const correct = lastCorrect ? n : n - 1;
  const correctElapsedMs = correct === 0 ? 0 : events[correct - 1]!.t;
  const lastT = last.t;

  if (Math.abs(input.elapsedMs - lastT) > Limits.maxElapsedVsLastEventMs) {
    throw invalid('elapsed_mismatch', 'elapsedMs does not match the last event time.');
  }
  if (input.elapsedMs > now - round.issuedAt + Limits.wallClockSlackMs) {
    throw invalid('elapsed_exceeds_wallclock', 'elapsedMs is longer than the time since the round was issued.');
  }
  if (n >= Limits.tooFastMinEvents && lastT / n < Limits.minMeanMsPerCell) {
    throw invalid('too_fast', `Mean time per cell ${(lastT / n).toFixed(0)} ms is below ${Limits.minMeanMsPerCell} ms.`);
  }

  // Server-authoritative elapsed time is the last event's timestamp.
  const breakdown = computeScore({ cells, correct, correctElapsedMs, elapsedMs: lastT });
  const mistakeKind: MistakeKind | null =
    breakdown.end === 'mistake' ? (last.c === grid[n - 1]!.word ? 'word' : 'color') : null;

  let fastGaps = 0;
  for (let k = 1; k < n; k++) {
    if (events[k]!.t - events[k - 1]!.t < Limits.fastGapMs) fastGaps++;
  }
  const gapCount = n - 1;
  const review =
    (gapCount > 0 && fastGaps / gapCount > Limits.fastGapMaxFraction) ||
    (correct >= Limits.perfectReviewMinCells &&
      breakdown.end === 'cleared' &&
      correctElapsedMs / correct < Limits.perfectReviewMeanMs);

  return { ...breakdown, correctElapsedMs, mistakeKind, review };
}

