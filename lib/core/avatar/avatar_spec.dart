import 'package:flutter/material.dart';

/// An avatar, stored as a compact string (max 64 chars) on the profile:
///   `dicebear:<style>:<seed>`  illustrated character from DiceBear
///   `emoji:<emoji>:<bg>`       emoji on one of [kAvatarBackgrounds]
///   anything else              legacy seed, shown as a DiceBear character
sealed class AvatarSpec {
  const AvatarSpec();

  static AvatarSpec parse(String raw) {
    if (raw.startsWith('emoji:')) {
      final rest = raw.substring(6);
      final i = rest.lastIndexOf(':');
      if (i > 0) {
        final bg = int.tryParse(rest.substring(i + 1)) ?? 0;
        return EmojiAvatar(rest.substring(0, i), bg % kAvatarBackgrounds.length);
      }
    }
    if (raw.startsWith('dicebear:')) {
      final parts = raw.split(':');
      if (parts.length >= 3 && kDicebearStyles.any((s) => s.id == parts[1])) {
        return DicebearAvatar(parts[1], parts.sublist(2).join(':'));
      }
    }
    return DicebearAvatar('adventurer', raw.isEmpty ? 'pilot' : raw);
  }

  String encode();
}

class DicebearAvatar extends AvatarSpec {
  const DicebearAvatar(this.style, this.seed);

  final String style;
  final String seed;

  String get url =>
      'https://api.dicebear.com/9.x/$style/png?size=160&radius=50'
      '&backgroundType=gradientLinear&backgroundColor=b6e3f4,c0aede,d1d4f9,ffd5dc,ffdfbf'
      '&seed=${Uri.encodeComponent(seed)}';

  @override
  String encode() {
    final s = 'dicebear:$style:$seed';
    return s.length <= 64 ? s : s.substring(0, 64);
  }
}

class EmojiAvatar extends AvatarSpec {
  const EmojiAvatar(this.emoji, this.background);

  final String emoji;
  final int background;

  @override
  String encode() => 'emoji:$emoji:$background';
}

class DicebearStyle {
  const DicebearStyle(this.id, this.label);

  final String id;
  final String label;
}

/// Illustrated styles from DiceBear (https://www.dicebear.com, free API).
const kDicebearStyles = [
  DicebearStyle('adventurer', 'Adventurer'),
  DicebearStyle('avataaars', 'Classic'),
  DicebearStyle('big-smile', 'Big smile'),
  DicebearStyle('lorelei', 'Lorelei'),
  DicebearStyle('micah', 'Micah'),
  DicebearStyle('notionists', 'Sketch'),
  DicebearStyle('open-peeps', 'Peeps'),
  DicebearStyle('personas', 'Personas'),
  DicebearStyle('miniavs', 'Mini'),
  DicebearStyle('fun-emoji', 'Fun face'),
  DicebearStyle('bottts', 'Robots'),
  DicebearStyle('pixel-art', 'Pixel'),
  DicebearStyle('thumbs', 'Thumbs'),
  DicebearStyle('croodles', 'Doodles'),
];

/// Gradient backdrops for emoji avatars.
const kAvatarBackgrounds = <List<Color>>[
  [Color(0xFF7C5CFF), Color(0xFF3B2A99)],
  [Color(0xFFF5B83D), Color(0xFFD9651E)],
  [Color(0xFF2EE59D), Color(0xFF0E8F6E)],
  [Color(0xFF4D8DFF), Color(0xFF1D3FA8)],
  [Color(0xFFFF6FCF), Color(0xFFA3237F)],
  [Color(0xFFFF4D5E), Color(0xFF9E1B2D)],
  [Color(0xFF3DDCFF), Color(0xFF1570A8)],
  [Color(0xFFB57BFF), Color(0xFF5E2CA5)],
  [Color(0xFFFFD93D), Color(0xFFB88A00)],
  [Color(0xFF9AA4B8), Color(0xFF3A4152)],
  [Color(0xFF241D45), Color(0xFF07060F)],
  [Color(0xFFFFE3A3), Color(0xFFF5B83D)],
];

class EmojiCategory {
  const EmojiCategory(this.label, this.emojis);

  final String label;
  final List<String> emojis;
}

const kEmojiCategories = [
  EmojiCategory('Faces', [
    '😀', '😎', '🤩', '🥳', '😇', '🤓', '🧐', '😏', '😜', '🤠', '🥸', '😺',
    '🤖', '👽', '👾', '🎃', '👻', '🤡', '😈', '💀', '🙂', '😴', '🤯', '🫡',
  ]),
  EmojiCategory('Animals', [
    '🦊', '🐼', '🐯', '🦁', '🐸', '🐵', '🦉', '🐧', '🐙', '🦄', '🐲', '🦖',
    '🐺', '🐨', '🐰', '🐻', '🦋', '🐝', '🐬', '🦈', '🐢', '🦅', '🐱', '🐶',
  ]),
  EmojiCategory('Space', [
    '🚀', '🛸', '🌟', '⭐', '🌙', '☄️', '🪐', '🌍', '🌌', '👨‍🚀', '👩‍🚀', '🔭',
    '🛰️', '🌞', '🌠', '✨',
  ]),
  EmojiCategory('Sports', [
    '⚽', '🏀', '🏈', '⚾', '🎾', '🏐', '🏓', '🥊', '🏆', '🥇', '🎯', '🏎️',
    '🛹', '🏄', '🧗', '♟️',
  ]),
  EmojiCategory('Fun', [
    '🎮', '🎧', '🎸', '🎨', '🎲', '🧩', '🎭', '🎤', '💎', '🔥', '⚡', '🌈',
    '🍕', '🍩', '🍉', '🍓', '🧁', '🍦', '👑', '🕶️', '🧠', '👁️', '💡', '🪄',
  ]),
];
