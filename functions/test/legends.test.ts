import { describe, expect, it } from 'vitest';

import { bestPerBoard, hasGoogleProvider, type ScoreRow } from '../src/core/legends.js';
import { isValidAvatarSeed, parseProfile } from '../src/core/profile.js';
import { ApiError } from '../src/core/errors.js';

const DAY = '2026-09-26';
const WEEK = '2026-W39';

function s(over: Partial<ScoreRow>): ScoreRow {
  return { boardId: '3x4.normal.voice', score: 100, ranked: true, review: false, day: DAY, week: WEEK, createdAtMs: 1, ...over };
}

describe('hasGoogleProvider', () => {
  it('detects google.com', () => {
    expect(hasGoogleProvider([{ providerId: 'password' }, { providerId: 'google.com' }])).toBe(true);
  });
  it('anonymous / other providers are not eligible', () => {
    expect(hasGoogleProvider([])).toBe(false);
    expect(hasGoogleProvider(undefined)).toBe(false);
    expect(hasGoogleProvider([{ providerId: 'apple.com' }])).toBe(false);
  });
});

describe('bestPerBoard', () => {
  it('returns nothing for no eligible scores', () => {
    expect(bestPerBoard([], DAY, WEEK)).toEqual([]);
    expect(bestPerBoard([s({ ranked: false }), s({ review: true }), s({ ranked: undefined })], DAY, WEEK)).toEqual([]);
  });

  it('computes all/day/week bests per board', () => {
    const rows = [
      s({ score: 500, day: '2026-09-20', week: '2026-W38', createdAtMs: 10 }), // old: all-time only
      s({ score: 300, day: '2026-09-22', week: WEEK, createdAtMs: 20 }), // this week
      s({ score: 200, createdAtMs: 30 }), // today
      s({ score: 150, createdAtMs: 40 }), // today, lower
      s({ boardId: '4x4.hard.tap', score: 50, createdAtMs: 50 }),
      s({ boardId: '4x4.hard.tap', score: 999, review: true }), // excluded
    ];
    const out = bestPerBoard(rows, DAY, WEEK).map((b) => [b.boardId, b.period, b.score.score]);
    expect(out).toEqual([
      ['3x4.normal.voice', 'all', 500],
      ['3x4.normal.voice', `d${DAY}`, 200],
      ['3x4.normal.voice', `w${WEEK}`, 300],
      ['4x4.hard.tap', 'all', 50],
      ['4x4.hard.tap', `d${DAY}`, 50],
      ['4x4.hard.tap', `w${WEEK}`, 50],
    ]);
  });

  it('breaks ties by the earliest score', () => {
    const out = bestPerBoard([s({ score: 7, createdAtMs: 9 }), s({ score: 7, createdAtMs: 3 })], DAY, WEEK);
    expect(out.every((b) => b.score.createdAtMs === 3)).toBe(true);
  });

  it('omits day/week when no score falls in them', () => {
    const out = bestPerBoard([s({ day: '2020-01-01', week: '2020-W01' })], DAY, WEEK);
    expect(out.map((b) => b.period)).toEqual(['all']);
  });

  it('ignores malformed rows', () => {
    expect(bestPerBoard([s({ boardId: '' }), s({ score: Number.NaN })], DAY, WEEK)).toEqual([]);
  });
});

describe('avatarSeed validation', () => {
  it('accepts encoded avatars and legacy seeds', () => {
    for (const v of ['dicebear:adventurer:Nova42', 'emoji:🦊:3', 'seed-1', 'x', 'x'.repeat(64), 'emoji:👩‍🚀:12']) {
      expect(isValidAvatarSeed(v)).toBe(true);
      expect(parseProfile({ nickname: 'Pilot', avatarSeed: v }).avatarSeed).toBe(v);
    }
  });

  it('rejects too long, control chars and non-strings', () => {
    for (const v of ['x'.repeat(65), 'a\u0000b', 'tab\there', 'new\nline', 'del\u007F', '\u001F']) {
      expect(isValidAvatarSeed(v)).toBe(false);
      try {
        parseProfile({ nickname: 'Pilot', avatarSeed: v });
        expect.unreachable();
      } catch (e) {
        expect(e).toBeInstanceOf(ApiError);
        expect((e as ApiError).code).toBe('invalid_avatar_seed');
      }
    }
    expect(isValidAvatarSeed('')).toBe(false);
    expect(isValidAvatarSeed(42)).toBe(false);
    expect(() => parseProfile({ nickname: 'Pilot', avatarSeed: 42 })).toThrow(ApiError);
  });

  it('64 UTF-16 code units: 32 emoji fit, 33 do not', () => {
    expect(isValidAvatarSeed('🦊'.repeat(32))).toBe(true);
    expect(isValidAvatarSeed('🦊'.repeat(33))).toBe(false);
  });

  it('missing or empty avatarSeed is still accepted (no avatar chosen)', () => {
    expect(parseProfile({ nickname: 'Pilot' }).avatarSeed).toBe('');
    expect(parseProfile({ nickname: 'Pilot', avatarSeed: '' }).avatarSeed).toBe('');
  });
});
