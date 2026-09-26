import 'color_recognizer.dart';

/// Turns streaming speech transcripts into a de-duplicated sequence of color
/// tokens.
///
/// Recognisers send growing interim transcripts ("red" → "red blue" →
/// "red blue green") and occasionally revise them. For every result slot we
/// remember how many color tokens were already emitted and only emit new ones.
class TranscriptMatcher {
  TranscriptMatcher({
    required Map<String, List<String>> aliases,
    Set<String> loose = const {},
    Set<String>? allowed,
  }) {
    for (final entry in aliases.entries) {
      if (allowed != null && !allowed.contains(entry.key)) continue;
      for (final word in entry.value) {
        _lookup[_norm(word)] = entry.key;
        if (loose.contains(word)) _loose.add(_norm(word));
      }
    }
  }

  final Map<String, String> _lookup = {};
  final Set<String> _loose = {};
  final Map<String, int> _consumed = {};

  static String _norm(String s) => s.toLowerCase().replaceAll(RegExp(r"[^a-z']"), '');

  /// Color tokens found in [text], in order.
  List<RecognizedToken> tokensIn(String text) {
    final out = <RecognizedToken>[];
    for (final raw in text.split(RegExp(r'[\s,.;:!?-]+'))) {
      final w = _norm(raw);
      if (w.isEmpty) continue;
      final key = _lookup[w];
      if (key == null) continue;
      out.add(RecognizedToken(key, w, loose: _loose.contains(w)));
    }
    return out;
  }

  /// Color keys found in [text] (convenience for tests).
  List<String> colorsIn(String text) => [for (final t in tokensIn(text)) t.color];

  /// Feed the current transcript of result [slot] (e.g. "session:index").
  /// Returns only tokens not emitted before for that slot.
  List<RecognizedToken> feed(String slot, String transcript) {
    final colors = tokensIn(transcript);
    final done = _consumed[slot] ?? 0;
    if (colors.length <= done) return const [];
    _consumed[slot] = colors.length;
    return colors.sublist(done);
  }

  final Map<String, int> _segment = {};
  final Map<String, String> _lastText = {};
  final Set<String> _closed = {};

  /// For engines (like Android's) that report each phrase separately inside
  /// one listening [session]. A new phrase starts after a final result, after
  /// an empty result (Android sends one when the next utterance begins), or
  /// when the text no longer extends the previous phrase. Each phrase gets its
  /// own slot, so saying the same color twice counts twice.
  List<RecognizedToken> feedPhrase(String session, String transcript, {required bool isFinal}) {
    final norm = transcript.trim().toLowerCase();
    final last = _lastText[session] ?? '';
    if (norm.isEmpty) {
      if (last.isNotEmpty) _closed.add(session);
      _lastText[session] = '';
      return const [];
    }
    final continues = last.isEmpty || norm.startsWith(last) || last.startsWith(norm);
    if (_closed.remove(session) || !continues) {
      _segment[session] = (_segment[session] ?? 0) + 1;
    }
    _lastText[session] = norm;
    final out = feed('$session#${_segment[session] ?? 0}', transcript);
    if (isFinal) {
      _closed.add(session);
      _lastText[session] = '';
    }
    return out;
  }

  /// Forget all slots (new round).
  void reset() {
    _consumed.clear();
    _segment.clear();
    _lastText.clear();
    _closed.clear();
  }
}
