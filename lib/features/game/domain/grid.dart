import 'prng.dart';

/// One word on the board.
class Cell {
  const Cell({required this.index, required this.word, required this.ink});

  final int index;

  /// Color key of the printed word (what the player must NOT say).
  final String word;

  /// Color key of the ink (what the player must say).
  final String ink;

  bool get congruent => word == ink;

  Map<String, Object> toJson() => {'i': index, 'w': word, 'k': ink};
}

/// Board dimensions. Label convention: "cols×rows" (e.g. 3×4 = 3 wide, 4 tall).
class GridSize {
  const GridSize(this.cols, this.rows);

  static const int minCols = 3, maxCols = 16, minRows = 4, maxRows = 16;

  final int cols;
  final int rows;

  int get cells => cols * rows;
  String get id => '${cols}x$rows';
  String get label => '$cols×$rows';

  bool get isValid =>
      cols >= minCols && cols <= maxCols && rows >= minRows && rows <= maxRows;

  /// Ranked presets. Anything else is playable but unranked.
  static const List<GridSize> presets = [
    GridSize(3, 4),
    GridSize(4, 4),
    GridSize(5, 5),
    GridSize(6, 6),
    GridSize(8, 8),
    GridSize(10, 10),
    GridSize(12, 12),
    GridSize(16, 16),
  ];

  bool get isPreset => presets.contains(this);

  static GridSize? tryParse(String id) {
    final m = RegExp(r'^(\d+)x(\d+)$').firstMatch(id);
    if (m == null) return null;
    final g = GridSize(int.parse(m[1]!), int.parse(m[2]!));
    return g.isValid ? g : null;
  }

  @override
  bool operator ==(Object other) =>
      other is GridSize && other.cols == cols && other.rows == rows;

  @override
  int get hashCode => Object.hash(cols, rows);
}

/// Deterministic Stroop board generator.
///
/// CONTRACT: this algorithm is mirrored in `functions/src/core/grid.ts` and
/// verified by golden tests. Any change must be made in both places and bump
/// [generatorVersion].
class GridGenerator {
  static const int generatorVersion = 1;

  static List<Cell> generate({
    required GridSize size,
    required List<String> colorKeys,
    required int seed,
    double congruentRatio = 0,
  }) {
    final rng = Mulberry32(seed);
    final n = size.cells;
    final cols = size.cols;
    final k = colorKeys.length;

    // 1. Balanced ink bag, shuffled (Fisher, Yates, high to low).
    final ink = List<String>.generate(n, (i) => colorKeys[i % k]);
    for (var i = n - 1; i > 0; i--) {
      final j = rng.nextInt(i + 1);
      final tmp = ink[i];
      ink[i] = ink[j];
      ink[j] = tmp;
    }

    // 2. Break consecutive repeats in reading order by swapping (no RNG use).
    for (var i = 1; i < n; i++) {
      if (ink[i] != ink[i - 1]) continue;
      var swapped = false;
      for (var j = i + 1; j < n && !swapped; j++) {
        if (j == i + 1) {
          if (ink[j] != ink[i - 1] && (j + 1 >= n || ink[i] != ink[j + 1])) {
            _swap(ink, i, j);
            swapped = true;
          }
        } else if (ink[j] != ink[i - 1] &&
            (i + 1 >= n || ink[j] != ink[i + 1]) &&
            ink[i] != ink[j - 1] &&
            (j + 1 >= n || ink[i] != ink[j + 1])) {
          _swap(ink, i, j);
          swapped = true;
        }
      }
      for (var j = 0; j < i - 1 && !swapped; j++) {
        if (ink[j] != ink[i - 1] &&
            (i + 1 >= n || ink[j] != ink[i + 1]) &&
            (j == 0 || ink[i] != ink[j - 1]) &&
            ink[i] != ink[j + 1]) {
          _swap(ink, i, j);
          swapped = true;
        }
      }
    }

    // 3. Words: never the ink (unless congruent roll), never equal to the
    //    left or above neighbour's word.
    final words = List<String>.filled(n, '');
    for (var i = 0; i < n; i++) {
      final r = i ~/ cols;
      final c = i % cols;
      if (congruentRatio > 0) {
        final roll = rng.nextDouble();
        if (roll < congruentRatio) {
          words[i] = ink[i];
          continue;
        }
      }
      final left = c > 0 ? words[i - 1] : null;
      final above = r > 0 ? words[i - cols] : null;
      var candidates = [
        for (final key in colorKeys)
          if (key != ink[i] && key != left && key != above) key,
      ];
      if (candidates.isEmpty) {
        candidates = [
          for (final key in colorKeys)
            if (key != ink[i]) key,
        ];
      }
      words[i] = candidates[rng.nextInt(candidates.length)];
    }

    return List<Cell>.generate(
      n,
      (i) => Cell(index: i, word: words[i], ink: ink[i]),
      growable: false,
    );
  }

  static void _swap(List<String> a, int i, int j) {
    final t = a[i];
    a[i] = a[j];
    a[j] = t;
  }
}
