import 'dart:async';

enum RecognizerStatus { idle, starting, listening, error, unsupported }

/// A recognised color word.
class RecognizedToken {
  const RecognizedToken(this.color, this.heard, {this.loose = false});

  /// Color key (e.g. `red`).
  final String color;

  /// Raw word/phrase that produced it (shown in the "heard" chip).
  final String heard;

  /// Came from a sound-alike word ("why" → white). Loose tokens may confirm
  /// the expected color but must never count as a mistake.
  final bool loose;
}

/// Platform speech engine that continuously listens for color words.
abstract class ColorRecognizer {
  /// Whether this platform/browser can recognise speech at all.
  Future<bool> isSupported();

  /// Start continuous listening. Emits on [tokens]; keeps listening across
  /// engine timeouts until [stop].
  Future<void> start({required Set<String> allowedColors});

  Future<void> stop();

  Stream<RecognizedToken> get tokens;

  /// Latest partial transcript, for the live "heard" indicator.
  Stream<String> get transcripts;

  /// Normalised microphone level 0..1 (when the engine exposes it).
  Stream<double> get levels;

  Stream<RecognizerStatus> get status;

  /// Human-readable description of the last error.
  String? get lastError;

  void dispose();
}
