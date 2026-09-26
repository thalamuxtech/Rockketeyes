import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';

import 'color_recognizer.dart';
import 'transcript_matcher.dart';
import 'vocab.dart';

/// Android recogniser built on the platform SpeechRecognizer
/// (`speech_to_text`), in continuous dictation mode with partial results and
/// automatic restarts when the engine times out.
class NativeSpeechRecognizer implements ColorRecognizer {
  final SpeechToText _stt = SpeechToText();
  final _tokens = StreamController<RecognizedToken>.broadcast();
  final _transcripts = StreamController<String>.broadcast();
  final _levels = StreamController<double>.broadcast();
  final _status = StreamController<RecognizerStatus>.broadcast();

  TranscriptMatcher? _matcher;
  Vocab? _vocab;
  Set<String> _allowed = const {};
  bool _wanted = false;
  bool _ready = false;
  int _session = 0;
  String? _lastError;
  Timer? _restart;

  @override
  Future<bool> isSupported() async {
    if (_ready) return true;
    // initialize() shows the RECORD_AUDIO permission prompt when needed.
    _ready = await _stt.initialize(
      onError: (e) {
        _lastError = e.errorMsg;
        // Timeouts/no-match are routine in continuous play: restart quietly.
        if (_wanted) _scheduleRestart();
      },
      onStatus: (s) {
        if (s == SpeechToText.listeningStatus) _status.add(RecognizerStatus.listening);
        if ((s == SpeechToText.doneStatus || s == SpeechToText.notListeningStatus) && _wanted) {
          _scheduleRestart();
        }
      },
    );
    if (!_ready) _lastError ??= 'not-allowed';
    return _ready;
  }

  @override
  Future<void> start({required Set<String> allowedColors}) async {
    if (!await isSupported()) {
      _status.add(RecognizerStatus.unsupported);
      return;
    }
    _vocab = await Vocab.load();
    _allowed = allowedColors;
    _matcher = _vocab!.matcher(allowedColors)..reset();
    _wanted = true;
    _status.add(RecognizerStatus.starting);
    await _listen();
  }

  Future<void> _listen() async {
    if (!_wanted) return;
    _session++;
    final session = _session;
    try {
      await _stt.listen(
        onResult: (SpeechRecognitionResult r) => _onResult(session, r),
        onSoundLevelChange: (level) {
          // Android reports roughly -2..10 dB.
          _levels.add(((level + 2) / 12).clamp(0.0, 1.0));
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
    } catch (e) {
      debugPrint('listen failed: $e');
      _scheduleRestart();
    }
  }

  void _onResult(int session, SpeechRecognitionResult r) {
    final text = r.recognizedWords;
    _transcripts.add(text);
    final tokens = _matcher?.feedPhrase('$session', text, isFinal: r.finalResult) ?? const <RecognizedToken>[];
    debugPrint('stt[$session${r.finalResult ? ' final' : ''}] "$text" -> ${tokens.map((t) => t.color).join(',')}');
    for (final t in tokens) {
      _tokens.add(t);
    }
    if (r.finalResult && _wanted) _scheduleRestart();
  }

  void _scheduleRestart() {
    _restart?.cancel();
    _restart = Timer(const Duration(milliseconds: 120), () async {
      if (!_wanted) return;
      if (_stt.isListening) return;
      await _listen();
    });
  }

  @override
  Future<void> stop() async {
    _wanted = false;
    _restart?.cancel();
    await _stt.cancel();
    _status.add(RecognizerStatus.idle);
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
    _stt.cancel();
    _tokens.close();
    _transcripts.close();
    _levels.close();
    _status.close();
  }
}

ColorRecognizer createPlatformRecognizer() => NativeSpeechRecognizer();
