import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:rocketeye/features/game/speech/transcript_matcher.dart';

void main() {
  test('replays the Pixel 8 sequence', () {
    final raw = jsonDecode(File('assets/vocab/en.json').readAsStringSync()) as Map<String, dynamic>;
    final aliases = (raw['colors'] as Map<String, dynamic>).map((k, v) => MapEntry(k, (v as List).cast<String>()));
    final m = TranscriptMatcher(aliases: aliases, allowed: {'red', 'blue', 'green', 'yellow', 'orange', 'purple'});
    final seq = [('', false), (' yellow', true), ('', false), (' purple', true), ('', false), (' green', true)];
    final got = [for (final (t, f) in seq) m.feedPhrase('1', t, isFinal: f).map((e) => e.color).join()];
    expect(got, ['', 'yellow', '', 'purple', '', 'green']);
  });

  test('Pixel 8: partial-only results separated by empty results', () {
    final raw = jsonDecode(File('assets/vocab/en.json').readAsStringSync()) as Map<String, dynamic>;
    final aliases = (raw['colors'] as Map<String, dynamic>).map((k, v) => MapEntry(k, (v as List).cast<String>()));
    final m = TranscriptMatcher(aliases: aliases, allowed: {'red', 'blue', 'green', 'yellow', 'orange', 'purple'});
    // Exactly what the device logged: no final results at all.
    final seq = ['', ' yellow', '', ' purple', '', ' green', '', ' green', ' green', '', ' yellow'];
    final got = [for (final t in seq) m.feedPhrase('1', t, isFinal: false).map((e) => e.color).join()];
    expect(got, ['', 'yellow', '', 'purple', '', 'green', '', 'green', '', '', 'yellow']);
  });
}
