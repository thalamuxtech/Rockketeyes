import 'package:flutter_test/flutter_test.dart';
import 'package:rocketeye/core/avatar/avatar_spec.dart';

void main() {
  test('emoji avatars round-trip', () {
    const raw = 'emoji:🦊:3';
    final spec = AvatarSpec.parse(raw);
    expect(spec, isA<EmojiAvatar>());
    expect((spec as EmojiAvatar).emoji, '🦊');
    expect(spec.background, 3);
    expect(spec.encode(), raw);
  });

  test('multi-codepoint emoji survive', () {
    final spec = AvatarSpec.parse('emoji:👩‍🚀:0') as EmojiAvatar;
    expect(spec.emoji, '👩‍🚀');
  });

  test('dicebear avatars round-trip and build a URL', () {
    final spec = AvatarSpec.parse('dicebear:bottts:abc7') as DicebearAvatar;
    expect(spec.style, 'bottts');
    expect(spec.url, contains('/9.x/bottts/png'));
    expect(spec.encode(), 'dicebear:bottts:abc7');
  });

  test('legacy seeds become a character', () {
    final spec = AvatarSpec.parse('uid-123');
    expect(spec, isA<DicebearAvatar>());
  });

  test('every encoded avatar fits the 64-char server limit', () {
    for (final c in kEmojiCategories) {
      for (final e in c.emojis) {
        expect(EmojiAvatar(e, 11).encode().length, lessThanOrEqualTo(64));
      }
    }
    for (final s in kDicebearStyles) {
      expect(DicebearAvatar(s.id, 'zzz18').encode().length, lessThanOrEqualTo(64));
    }
  });
}
