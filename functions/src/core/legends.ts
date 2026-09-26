/**
 * Global Legends eligibility and the pure part of POST /legends/claim.
 *
 * Only players with a linked Google account appear on the global boards
 * (`bests`). Scores of everybody are kept in `scores`, so a player who links
 * Google later can "claim" their earlier ranked results.
 */

export const GOOGLE_PROVIDER_ID = 'google.com';

export function hasGoogleProvider(providerData: readonly { providerId: string }[] | undefined | null): boolean {
  return (providerData ?? []).some((p) => p.providerId === GOOGLE_PROVIDER_ID);
}

/** The subset of a `scores` document that claim needs. */
export interface ScoreRow {
  boardId: string;
  score: number;
  ranked?: boolean;
  review?: boolean;
  day?: string;
  week?: string;
  createdAtMs?: number;
  [k: string]: unknown;
}

export type LegendsPeriod = 'all' | `d${string}` | `w${string}`;

export interface BoardBest<T extends ScoreRow = ScoreRow> {
  period: LegendsPeriod;
  boardId: string;
  score: T;
}

/** a beats b: higher score, then earlier (smaller createdAtMs). */
function beats(a: ScoreRow, b: ScoreRow): boolean {
  if (a.score !== b.score) return a.score > b.score;
  return (a.createdAtMs ?? Number.MAX_SAFE_INTEGER) < (b.createdAtMs ?? Number.MAX_SAFE_INTEGER);
}

/**
 * Best eligible score per board for the all-time period, the given UTC day
 * (`d{day}`, only scores with `day === day`) and ISO week (`w{week}`, only
 * scores with `week === week`). Only `ranked === true && review !== true`
 * scores count. Output is sorted by boardId, then period order all/day/week.
 */
export function bestPerBoard<T extends ScoreRow>(scores: readonly T[], day: string, week: string): BoardBest<T>[] {
  const best = new Map<string, BoardBest<T>>();
  const consider = (period: LegendsPeriod, s: T) => {
    const key = `${period}\u0000${s.boardId}`;
    const cur = best.get(key);
    if (!cur || beats(s, cur.score)) best.set(key, { period, boardId: s.boardId, score: s });
  };
  for (const s of scores) {
    if (s.ranked !== true || s.review === true) continue;
    if (typeof s.boardId !== 'string' || s.boardId === '' || typeof s.score !== 'number' || !Number.isFinite(s.score)) {
      continue;
    }
    consider('all', s);
    if (s.day === day) consider(`d${day}`, s);
    if (s.week === week) consider(`w${week}`, s);
  }
  const order = (p: LegendsPeriod) => (p === 'all' ? 0 : p.startsWith('d') ? 1 : 2);
  return [...best.values()].sort((a, b) =>
    a.boardId === b.boardId ? order(a.period) - order(b.period) : a.boardId < b.boardId ? -1 : 1,
  );
}
