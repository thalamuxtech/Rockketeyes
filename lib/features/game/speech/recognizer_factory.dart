import 'color_recognizer.dart';
import 'native_speech_recognizer.dart'
    if (dart.library.js_interop) 'web_speech_recognizer.dart' as platform;

/// Creates the best recogniser for the current platform.
ColorRecognizer createRecognizer() => platform.createPlatformRecognizer();
