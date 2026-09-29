import 'package:flutter/foundation.dart';

/// Build-time configuration (`--dart-define=KEY=value`).
abstract final class Env {
  /// Talk to the local Firebase emulators instead of production.
  static const bool useEmulator =
      bool.fromEnvironment('RE_EMULATOR', defaultValue: kDebugMode);

  /// Host the emulators listen on.
  static const String emulatorHost =
      String.fromEnvironment('RE_EMULATOR_HOST', defaultValue: '127.0.0.1');

  /// Developer tools: voice simulator panel, debug overlays. Never in release.
  static const bool devTools =
      !kReleaseMode && bool.fromEnvironment('RE_DEV_TOOLS', defaultValue: true);

  /// Exposes JavaScript hooks used by the Playwright end-to-end suite.
  static const bool e2e = bool.fromEnvironment('RE_E2E');

  /// Headless test browsers render on the CPU; skip the space shader there
  /// unless a preview build asks for it (RE_E2E_BG=true).
  static const bool lightBackground = e2e && !bool.fromEnvironment('RE_E2E_BG');

  /// reCAPTCHA Enterprise site key for App Check on web (empty = disabled).
  static const String appCheckWebKey =
      String.fromEnvironment('RE_APPCHECK_WEB_KEY');

  static const String _apiOverride = String.fromEnvironment('RE_API_BASE');

  /// Base URL of the `api` Cloud Function.
  static String get apiBase {
    if (_apiOverride.isNotEmpty) return _apiOverride;
    if (useEmulator) {
      final host = (!kIsWeb && defaultTargetPlatform == TargetPlatform.android &&
              emulatorHost == '127.0.0.1')
          ? '10.0.2.2'
          : emulatorHost;
      return 'http://$host:5001/rockketeyes/us-central1/api';
    }
    return kIsWeb ? '/api' : 'https://rockketeyes.web.app/api';
  }

  /// OAuth web client ID (from google-services.json, client_type 3); the
  /// native Android Google picker needs it to issue a Firebase ID token.
  static const String googleServerClientId =
      '685148954018-l62kig231ki9b7kkl1q7mmd0jkvahjpa.apps.googleusercontent.com';

  static const String privacyUrl = 'https://thalamuxtech.github.io/Rockketeyes/privacy.html';
}
