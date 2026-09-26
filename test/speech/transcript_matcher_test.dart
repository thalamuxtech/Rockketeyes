import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:rocketeye/features/game/speech/transcript_matcher.dart';

void main() {
  final raw = jsonDecode(File('assets/vocab/en.json').readAsStringSync()) as Map<String, dynamic>;
  final aliases = (raw['colors'] as Map<String, dynamic>).map((k, v) => MapEntry(k, (v as List).cast<String>()));
  final loose = (raw['loose'] as List).cast<String>().toSet();

  TranscriptMatcher m({Set<String>? allowed}) =>
      TranscriptMatcher(aliases: aliases, loose: loose, allowed: allowed);

  test('growing interim transcripts emit each color once', () {
    final t = m();
    expect(t.feed('1:0', 'red').map((e) => e.color), ['red']);
    expect(t.feed('1:0', 'red blue').map((e) => e.color), ['blue']);
    expect(t.feed('1:0', 'red blue').map((e) => e.color), isEmpty);
    expect(t.feed('1:0', 'Red, blue. Green!').map((e) => e.color), ['green']);
  });

  test('separate result slots are independent', () {
    final t = m();
    expect(t.feed('1:0', 'red').length, 1);
    expect(t.feed('1:1', 'red').length, 1);
    expect(t.feed('2:0', 'red').length, 1);
  });

  test('revisions that shrink the transcript do not re-emit', () {
    final t = m();
    t.feed('s', 'red blue green');
    expect(t.feed('s', 'red blue'), isEmpty);
    expect(t.feed('s', 'red blue green yellow').map((e) => e.color), ['yellow']);
  });

  test('homophones map to colors', () {
    final t = m();
    expect(t.colorsIn('read blew greene yello orang purpel'),
        ['red', 'blue', 'green', 'yellow', 'orange', 'purple']);
  });

  test('sound-alike everyday words are flagged loose', () {
    final t = m();
    final tokens = t.tokensIn('hello red why');
    expect(tokens.map((e) => e.color), ['yellow', 'red', 'white']);
    expect(tokens.map((e) => e.loose), [true, false, true]);
  });

  test('colors outside the round are ignored', () {
    final t = m(allowed: {'red', 'blue', 'green', 'yellow'});
    expect(t.colorsIn('pink white red orange'), ['red']);
  });

  test('Android: repeated final phrases in one session each count', () {
    final t = m();
    expect(t.feedPhrase('s1', 'yellow', isFinal: true).map((e) => e.color), ['yellow']);
    expect(t.feedPhrase('s1', 'yellow', isFinal: true).map((e) => e.color), ['yellow']);
    expect(t.feedPhrase('s1', 'red', isFinal: false).map((e) => e.color), ['red']);
    expect(t.feedPhrase('s1', 'red', isFinal: true), isEmpty, reason: 'final repeats the partial');
    expect(t.feedPhrase('s1', 'red', isFinal: true).map((e) => e.color), ['red']);
  });

  test('Android: a phrase that grows still counts once per word', () {
    final t = m();
    expect(t.feedPhrase('s', 'blue', isFinal: false).map((e) => e.color), ['blue']);
    expect(t.feedPhrase('s', 'blue green', isFinal: false).map((e) => e.color), ['green']);
    expect(t.feedPhrase('s', 'blue green', isFinal: true), isEmpty);
    expect(t.feedPhrase('s', 'green', isFinal: false).map((e) => e.color), ['green']);
  });

  test('Android: a new phrase without a final result still counts', () {
    final t = m();
    expect(t.feedPhrase('s', 'yellow', isFinal: false).length, 1);
    expect(t.feedPhrase('s', 'pink', isFinal: false).map((e) => e.color), ['pink']);
  });

  test('non-color chatter produces nothing', () {
    expect(m().colorsIn('um okay wait what'), isEmpty);
  });
}
