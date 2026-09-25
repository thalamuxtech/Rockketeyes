import 'dart:math' as math;

/// How a round ended.
enum RoundEnd {
  /// Every cell named correctly.
  cleared,

  /// The player named a wrong color (or read the printed word).
  mistake,
}

/// Versioned "sudden death" scoring: the round runs until the board is
/// cleared or the first mistake. Mirrored in `functions/src/core/scoring.ts`;
/// the server result is authoritative for leaderboards.
class ScoringConfig {
  const ScoringConfig._();

  static const int version = 1;
  static const int parMsPerCell = 1100;
  static const double minSpeed = 0.25;
  static const double maxSpeed = 3.0;
  static const int pointsPerCorrect = 100;
  static const int streakThreshold = 5;
  static const int streakPointsPerCell = 10;
  static const int clearPointsPerCell = 50;
  static const double sizeWeight = 0.35;
}

class ScoreBreakdown {
  const ScoreBreakdown({
    required this.score,
    required this.correct,
    required this.cells,
    required this.end,
    required this.elapsedMs,
    required this.speedFactor,
    required this.streakBonus,
    required this.clearBonus,
    required this.sizeMultiplier,
  });

  final int score;
  final int correct;
  final int cells;
  final RoundEnd end;
  final int elapsedMs;
  final double speedFactor;
  final int streakBonus;
  final int clearBonus;
  final double sizeMultiplier;

  double get completion => cells == 0 ? 0 : correct / cells;
  bool get cleared => end == RoundEnd.cleared;
}

class ScoreCalculator {
  /// [correct] cells named before the round ended; [correctElapsedMs] is the
  /// timer value at the last correct answer (0 if none); [elapsedMs] is the
  /// timer value when the round ended.
  static ScoreBreakdown compute({
    required int cells,
    required int correct,
    required int correctElapsedMs,
    required int elapsedMs,
  }) {
    final end = correct >= cells ? RoundEnd.cleared : RoundEnd.mistake;
    final speed = correct == 0
        ? 0.0
        : (correct * ScoringConfig.parMsPerCell / math.max(1, correctElapsedMs))
            .clamp(ScoringConfig.minSpeed, ScoringConfig.maxSpeed)
            .toDouble();
    final sizeMult = cells <= 0
        ? 1.0
        : math.max(1.0, 1 + (math.log(cells / 12) / math.ln2) * ScoringConfig.sizeWeight);
    final streakBonus = correct >= ScoringConfig.streakThreshold
        ? (correct - (ScoringConfig.streakThreshold - 1)) * ScoringConfig.streakPointsPerCell
        : 0;
    final clearBonus =
        end == RoundEnd.cleared ? (cells * ScoringConfig.clearPointsPerCell * speed).round() : 0;
    final base = correct * ScoringConfig.pointsPerCorrect * speed;
    final score = ((base + streakBonus + clearBonus) * sizeMult).round();

    return ScoreBreakdown(
      score: score,
      correct: correct,
      cells: cells,
      end: end,
      elapsedMs: elapsedMs,
      speedFactor: speed,
      streakBonus: streakBonus,
      clearBonus: clearBonus,
      sizeMultiplier: sizeMult,
    );
  }
}
