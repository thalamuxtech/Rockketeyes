import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';

import 'color_recognizer.dart';
import 'transcript_matcher.dart';
import 'vocab.dart';

@JS('rocketeyeSpeech')
external _SpeechBridge? get _bridge;

extension type _SpeechBridge._(JSObject _) implements JSObject {
  external bool supported();
  external JSString? lastError();
  external bool start(String lang, String wordsCsv, JSFunction onEvent);
  external void stop();
}

/// Web Speech API recogniser (Chrome, Edge, Safari) via `web/speech_bridge.js`.
class WebSpeechRecognizer implements ColorRecognizer {
  final _tokens = StreamController<RecognizedToken>.broadcast();
  final _transcripts = StreamController<String>.broadcast();
  final _levels = StreamController<double>.broadcast();
  final _status = StreamController<RecognizerStatus>.broadcast();
  TranscriptMatcher? _matcher;
  String? _lastError;

  @override
  Future<bool> isSupported() async => _bridge?.supported() ?? false;

  @override
  Future<void> start({required Set<String> allowedColors}) async {
    final bridge = _bridge;
    if (bridge == null || !bridge.supported()) {
      _status.add(RecognizerStatus.unsupported);
      return;
    }
    final vocab = await Vocab.load();
    _matcher = vocab.matcher(allowedColors)..reset();
    _status.add(RecognizerStatus.starting);
    final ok = bridge.start(
      vocab.locale,
      vocab.phrases(allowedColors).join(','),
      _onEvent.toJS,
    );
    if (!ok) {
      _lastError = 'start-failed';
      _status.add(RecognizerStatus.error);
    }
  }

  void _onEvent(String type, String payload) {
    final data = jsonDecode(payload) as Map<String, dynamic>;
    switch (type) {
      case 'start':
        _status.add(RecognizerStatus.listening);
      case 'level':
        _levels.add((data['v'] as num).toDouble());
      case 'error':
        _lastError = data['error'] as String?;
        if (_lastError != 'no-speech' && _lastError != 'aborted') {
          _status.add(RecognizerStatus.error);
        }
      case 'result':
        final session = data['session'];
        for (final r in (data['results'] as List).cast<Map<String, dynamic>>()) {
          final alts = (r['alts'] as List).cast<Map<String, dynamic>>();
          if (alts.isEmpty) continue;
          final text = alts.first['t'] as String;
          _transcripts.add(text.trim());
          final fresh = _matcher?.feed('$session:${r['i']}', text) ?? const [];
          for (final t in fresh) {
            _tokens.add(t);
          }
        }
    }
  }

  @override
  Future<void> stop() async {
    _bridge?.stop();
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
    _bridge?.stop();
    _tokens.close();
    _transcripts.close();
    _levels.close();
    _status.close();
  }
}

ColorRecognizer createPlatformRecognizer() => WebSpeechRecognizer();
