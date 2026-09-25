import 'dart:convert';

import 'package:flutter/services.dart';

import 'transcript_matcher.dart';

/// Loaded color vocabulary (aliases per color key).
class Vocab {
  Vocab(this.locale, this.aliases, this.loose);

  final String locale;
  final Map<String, List<String>> aliases;
  final Set<String> loose;

  static Vocab? _cached;

  static Future<Vocab> load() async {
    if (_cached != null) return _cached!;
    final raw = jsonDecode(await rootBundle.loadString('assets/vocab/en.json')) as Map<String, dynamic>;
    final colors = (raw['colors'] as Map<String, dynamic>).map(
      (k, v) => MapEntry(k, (v as List).cast<String>()),
    );
    return _cached = Vocab(
      raw['locale'] as String? ?? 'en-US',
      colors,
      ((raw['loose'] as List?) ?? const []).cast<String>().toSet(),
    );
  }

  TranscriptMatcher matcher(Set<String> allowed) =>
      TranscriptMatcher(aliases: aliases, loose: loose, allowed: allowed);

  /// Phrases to bias the recogniser toward.
  List<String> phrases(Set<String> allowed) => [
        for (final k in allowed) k,
      ];
}
