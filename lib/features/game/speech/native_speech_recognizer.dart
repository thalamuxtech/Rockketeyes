import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:speech_to_text/speech_recognition_error.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';

import 'color_recognizer.dart';
import 'transcript_matcher.dart';
import 'vocab.dart';

/// Android recogniser built on the platform SpeechRecognizer
/// (`speech_to_text`), in continuous dictation mode with partial results and
/// automatic restarts when the engine pauses.
///
/// The plugin is a single shared engine that keeps the callbacks from its
/// *first* `initialize()`. So the engine is initialised once here, and its
/// callbacks are forwarded to whichever recogniser is currently active (the
/// setup check, then the game, and so on).
class NativeSpeechRecognizer implements ColorRecognizer {
  static final SpeechToText _stt = SpeechToText();
  static Future<bool>? _init;
  static NativeSpeechRecognizer? _active;

  final _tokens = StreamController<RecognizedToken>.broadcast();
  final _transcripts = StreamController<String>.broadcast();
  final _levels = StreamController<double>.broadcast();
  final _status = StreamController<RecognizerStatus>.broadcast();

  TranscriptMatcher? _matcher;
  Vocab? _vocab;
  Set<String> _allowed = const {};
  bool _wanted = false;
  bool _disposed = false;
  int _session = 0;
  String? _lastError;
  Timer? _restart;

  static Future<bool> _ensureEngine() => _init ??= _stt
          .initialize(
            onError: (SpeechRecognitionError e) => _active?._onEngineError(e),
            onStatus: (String s) => _active?._onEngineStatus(s),
          )
          .then((ok) {
        if (!ok) _init = null; // e.g. permission denied: allow asking again
        return ok;
      }).catchError((Object e) {
        debugPrint('speech init failed: $e');
        _init = null;
        return false;
      });

  void _emit<T>(StreamController<T> c, T v) {
    if (!_disposed && !c.isClosed) c.add(v);
  }

  void _onEngineError(SpeechRecognitionError e) {
    _lastError = e.errorMsg;
    debugPrint('stt error: ${e.errorMsg} permanent=${e.permanent}');
    if (e.errorMsg.contains('permission') || e.errorMsg == 'error_insufficient_permissions') {
      _lastError = 'not-allowed';
      _emit(_status, RecognizerStatus.error);
      return;
    }
    // Timeouts / no-match are routine in continuous play: restart quietly.
    if (_wanted) _scheduleRestart();
  }

  void _onEngineStatus(String s) {
    debugPrint('stt status: $s');
    if (s == SpeechToText.listeningStatus) _emit(_status, RecognizerStatus.listening);
    if ((s == SpeechToText.doneStatus || s == SpeechToText.notListeningStatus) && _wanted) {
      _scheduleRestart();
    }
  }

  @override
  Future<bool> isSupported() async {
    // initialize() shows the RECORD_AUDIO permission prompt when needed.
    final ok = await _ensureEngine();
    if (!ok) _lastError ??= 'not-allowed';
    return ok;
  }

  @override
  Future<void> start({required Set<String> allowedColors}) async {
    if (!await isSupported()) {
      _emit(_status, RecognizerStatus.unsupported);
      return;
    }
    // Take over the shared engine from any previous recogniser.
    final previous = _active;
    if (previous != null && !identical(previous, this)) {
      previous._wanted = false;
      previous._restart?.cancel();
    }
    _active = this;
    if (_stt.isListening) await _stt.cancel();
    _vocab = await Vocab.load();
    _allowed = allowedColors;
    _matcher = _vocab!.matcher(allowedColors)..reset();
    _wanted = true;
    _emit(_status, RecognizerStatus.starting);
    await _listen();
  }

  Future<void> _listen() async {
    if (!_wanted || !identical(_active, this)) return;
    _session++;
    final session = _session;
    try {
      await _stt.listen(
        onResult: (SpeechRecognitionResult r) => _onResult(session, r),
        onSoundLevelChange: (level) {
          // Android reports roughly -2..10 dB.
          _emit(_levels, ((level + 2) / 12).clamp(0.0, 1.0));
        },
        listenOptions: SpeechListenOptions(
          partialResults: true,
          cancelOnError: false,
          listenMode: ListenMode.dictation,
          listenFor: const Duration(minutes: 5),
          pauseFor: const Duration(seconds: 30),
          localeId: _vocab?.locale.replaceAll('-', '_'),
          contextualPhrases: _vocab?.phrases(_allowed),
        ),
      );
      _emit(_status, RecognizerStatus.listening);
    } catch (e) {
      debugPrint('listen failed: $e');
      _scheduleRestart();
    }
  }

  void _onResult(int session, SpeechRecognitionResult r) {
    if (!identical(_active, this)) return;
    final text = r.recognizedWords;
    _emit(_transcripts, text);
    final tokens = _matcher?.feedPhrase('$session', text, isFinal: r.finalResult) ?? const <RecognizedToken>[];
    debugPrint('stt[$session${r.finalResult ? ' final' : ''}] "$text" -> ${tokens.map((t) => t.color).join(',')}');
    for (final t in tokens) {
      _emit(_tokens, t);
    }
    if (r.finalResult && _wanted) _scheduleRestart();
  }

  void _scheduleRestart() {
    _restart?.cancel();
    _restart = Timer(const Duration(milliseconds: 150), () async {
      if (!_wanted || !identical(_active, this)) return;
      if (_stt.isListening) return;
      await _listen();
    });
  }

  @override
  Future<void> stop() async {
    _wanted = false;
    _restart?.cancel();
    if (identical(_active, this)) {
      try {
        await _stt.cancel();
      } catch (_) {}
    }
    _emit(_status, RecognizerStatus.idle);
  }

  @override
  Stream<RecognizedToken> get tokens => _tokens.stream;

  @override
  Stream<String> get transcripts => _transcripts.stream;

  @override
  Stream<double> get levels => _levels.stream;

  @override
  Stream<RecognizerStatus> get status => _status.stream;

  @override
  String? get lastError => _lastError;

  @override
  void dispose() {
    _wanted = false;
    _restart?.cancel();
    if (identical(_active, this)) {
      _active = null;
      _stt.cancel().catchError((_) {});
    }
    _disposed = true;
    _tokens.close();
    _transcripts.close();
    _levels.close();
    _status.close();
  }
}

ColorRecognizer createPlatformRecognizer() => NativeSpeechRecognizer();
