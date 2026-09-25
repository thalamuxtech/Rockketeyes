/**
 * Versioned "sudden death" scoring: the round runs until the board is cleared
 * or the first mistake. Bit-exact port of
 * `lib/features/game/domain/scoring.dart`; verified by the golden test.
 * The server result is authoritative for leaderboards.
 */
export type RoundEnd = 'cleared' | 'mistake';

export const ScoringConfig = {
  version: 1,
  parMsPerCell: 1100,
  minSpeed: 0.25,
  maxSpeed: 3.0,
  pointsPerCorrect: 100,
  streakThreshold: 5,
  streakPointsPerCell: 10,
  clearPointsPerCell: 50,
  sizeWeight: 0.35,
} as const;

export const SCORING_VERSION = ScoringConfig.version;

export interface ScoreBreakdown {
  score: number;
  correct: number;
  cells: number;
  end: RoundEnd;
  elapsedMs: number;
  speedFactor: number;
  streakBonus: number;
  clearBonus: number;
  sizeMultiplier: number;
  /** correct / cells (0 when cells == 0). */
  completion: number;
}

const clamp = (v: number, lo: number, hi: number): number => Math.min(hi, Math.max(lo, v));

/**
 * Dart `double.round()`: half away from zero. Identical to Math.round for
 * non-negative inputs (all scores are non-negative), written out for clarity.
 */
const dartRound = (v: number): number => (v < 0 ? -Math.round(-v) : Math.round(v));

/**
 * @param cells board size
 * @param correct cells named before the round ended
 * @param correctElapsedMs timer value at the last correct answer (0 if none)
 * @param elapsedMs timer value when the round ended
 */
export function computeScore(args: {
  cells: number;
  correct: number;
  correctElapsedMs: number;
  elapsedMs: number;
}): ScoreBreakdown {
  const { cells, correct, correctElapsedMs, elapsedMs } = args;
  const end: RoundEnd = correct >= cells ? 'cleared' : 'mistake';
  const speed =
    correct === 0
      ? 0.0
      : clamp(
          (correct * ScoringConfig.parMsPerCell) / Math.max(1, correctElapsedMs),
          ScoringConfig.minSpeed,
          ScoringConfig.maxSpeed,
        );
  const sizeMult =
    cells <= 0 ? 1.0 : Math.max(1.0, 1 + (Math.log(cells / 12) / Math.LN2) * ScoringConfig.sizeWeight);
  const streakBonus =
    correct >= ScoringConfig.streakThreshold
      ? (correct - (ScoringConfig.streakThreshold - 1)) * ScoringConfig.streakPointsPerCell
      : 0;
  const clearBonus = end === 'cleared' ? dartRound(cells * ScoringConfig.clearPointsPerCell * speed) : 0;
  const base = correct * ScoringConfig.pointsPerCorrect * speed;
  const score = dartRound((base + streakBonus + clearBonus) * sizeMult);

  return {
    score,
    correct,
    cells,
    end,
    elapsedMs,
    speedFactor: speed,
    streakBonus,
    clearBonus,
    sizeMultiplier: sizeMult,
    completion: cells === 0 ? 0 : correct / cells,
  };
}
