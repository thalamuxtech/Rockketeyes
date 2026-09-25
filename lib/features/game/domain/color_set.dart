import 'dart:ui';

import 'color_keys.dart';

export 'color_keys.dart';

/// A color the player can name.
class GameColor {
  const GameColor({
    required this.key,
    required this.word,
    required this.inkDark,
    required this.inkLight,
  });

  /// Stable id used in events, storage and the server replay.
  final String key;

  /// Word printed on the board and spoken by the player.
  final String word;
  final Color inkDark;
  final Color inkLight;

  Color ink({required bool darkBoard}) => darkBoard ? inkDark : inkLight;
}

/// Full palette, ordered. The order is part of the grid-generation contract
/// shared with the server; append new colors, never reorder.
const List<GameColor> kAllColors = [
  GameColor(key: 'red', word: 'RED', inkDark: Color(0xFFFF4D5E), inkLight: Color(0xFFD7263D)),
  GameColor(key: 'blue', word: 'BLUE', inkDark: Color(0xFF4D8DFF), inkLight: Color(0xFF1D4ED8)),
  GameColor(key: 'green', word: 'GREEN', inkDark: Color(0xFF2EE59D), inkLight: Color(0xFF15803D)),
  GameColor(key: 'yellow', word: 'YELLOW', inkDark: Color(0xFFFFD93D), inkLight: Color(0xFFA16207)),
  GameColor(key: 'orange', word: 'ORANGE', inkDark: Color(0xFFFF9F1C), inkLight: Color(0xFFEA580C)),
  GameColor(key: 'purple', word: 'PURPLE', inkDark: Color(0xFFB57BFF), inkLight: Color(0xFF7E22CE)),
  GameColor(key: 'pink', word: 'PINK', inkDark: Color(0xFFFF6FCF), inkLight: Color(0xFFDB2777)),
  GameColor(key: 'white', word: 'WHITE', inkDark: Color(0xFFF5F5F7), inkLight: Color(0xFF111111)),
];

GameColor colorByKey(String key) => kAllColors.firstWhere((c) => c.key == key);

extension ColorSetColors on ColorSetId {
  List<GameColor> get colors => keys.map(colorByKey).toList(growable: false);
}
