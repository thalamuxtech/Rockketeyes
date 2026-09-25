/// Pure-Dart color-set ids (no dart:ui) so tools and the server contract can use them.
enum Difficulty { easy, normal, hard }

/// Identifies which subset of [kAllColors] a round uses. Shared with server.
enum ColorSetId {
  easy(['red', 'blue', 'green', 'yellow']),
  normal(['red', 'blue', 'green', 'yellow', 'orange', 'purple']),
  hard(['red', 'blue', 'green', 'yellow', 'orange', 'purple', 'pink', 'white']),
  colorblind(['blue', 'orange', 'yellow', 'white', 'pink']);

  const ColorSetId(this.keys);
  final List<String> keys;

  static ColorSetId forDifficulty(Difficulty d, {bool colorblind = false}) {
    if (colorblind) return ColorSetId.colorblind;
    return switch (d) {
      Difficulty.easy => ColorSetId.easy,
      Difficulty.normal => ColorSetId.normal,
      Difficulty.hard => ColorSetId.hard,
    };
  }
}
