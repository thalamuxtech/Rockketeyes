import '../domain/color_set.dart';
import '../domain/grid.dart';

enum InputMode { voice, tap }

/// Everything chosen on the setup sheet.
class GameConfig {
  const GameConfig({
    this.size = const GridSize(3, 4),
    this.difficulty = Difficulty.normal,
    this.colorblind = false,
    this.mode = InputMode.voice,
  });

  final GridSize size;
  final Difficulty difficulty;
  final bool colorblind;
  final InputMode mode;

  ColorSetId get colorSet => ColorSetId.forDifficulty(difficulty, colorblind: colorblind);

  /// Leaderboard id, e.g. `8x8.normal.voice`.
  String get boardId => '${size.id}.${colorSet.name}.${mode.name}';

  bool get rankable => size.isPreset;

  GameConfig copyWith({GridSize? size, Difficulty? difficulty, bool? colorblind, InputMode? mode}) =>
      GameConfig(
        size: size ?? this.size,
        difficulty: difficulty ?? this.difficulty,
        colorblind: colorblind ?? this.colorblind,
        mode: mode ?? this.mode,
      );

  Map<String, Object> toJson() => {
        'size': size.id,
        'difficulty': difficulty.name,
        'colorblind': colorblind,
        'mode': mode.name,
      };

  static GameConfig fromJson(Map<dynamic, dynamic>? j) {
    if (j == null) return const GameConfig();
    return GameConfig(
      size: GridSize.tryParse('${j['size']}') ?? const GridSize(3, 4),
      difficulty: Difficulty.values.asNameMap()['${j['difficulty']}'] ?? Difficulty.normal,
      colorblind: j['colorblind'] == true,
      mode: InputMode.values.asNameMap()['${j['mode']}'] ?? InputMode.voice,
    );
  }
}
