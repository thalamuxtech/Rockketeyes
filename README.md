# Rockketeyes

**Say the color, not the word.** A premium voice-controlled Stroop challenge for Android and the web, with Global Legends leaderboards.

- A board of color words appears, each printed in a *different* ink color.
- After a 3-2-1 countdown the microphone stays open. Say each **ink color** aloud; the gold highlight glides to the next word.
- **One mistake ends the run**: naming a wrong color, or reading the printed word. Clear the board fast for the top score.
- Boards from **3×4 up to 16×16** (custom sizes are practice-only). Easy / Normal / Hard use 4 / 6 / 8 colors, plus a colorblind-safe set.
- Scores are validated server-side and ranked **Today / This week / All-time**, per board, worldwide or by country.

## Stack

| Layer | Tech |
|---|---|
| App | Flutter 3.47 (Dart 3.13), Riverpod 3, go_router, custom "Cosmic Glass" design system, GLSL nebula shader |
| Voice | Web Speech API via `web/speech_bridge.js` (Chrome, Edge, Safari); Android SpeechRecognizer via `speech_to_text` |
| Audio | `audioplayers`: CC0 ambient music plus SFX, auto-ducked while the mic listens |
| Backend | Firebase Auth (anonymous plus Google link), Cloud Firestore, Cloud Functions (`functions/`, TypeScript) |
| Hosting | Firebase Hosting (`build/web`, `/api/**` → `api` function) |

The board generator (mulberry32 PRNG) and scoring are **bit-identical in Dart and TypeScript**. `test/fixtures/golden.json` is checked by both test suites. The server rebuilds every board from its seed and replays the answers before a score is ranked.

## Project layout

```
lib/
  core/            env, router, theme tokens, glass widgets, logo, nebula background, E2E hooks
  features/
    game/          domain (prng, grid, scoring), speech (recognizers, matcher), round controller, board & results UI
    home/ legends/ onboarding/ profile/ settings/
  services/        audio, local store (Hive), settings, profile/auth, API client
functions/         Cloud Functions: /round/start, /score/submit, /profile (+ unit, golden and smoke tests)
firebase/          Firestore rules and indexes
e2e/               Playwright end-to-end suite (simulated speech through the real pipeline)
tool/gen_golden.dart   regenerates the cross-language fixtures
```

## Run locally (web, against emulators)

Prerequisites: Flutter stable, Node 22, Java 17+, `firebase-tools`.

```bash
flutter pub get
(cd functions && npm install && npm run build)

# terminal 1: local backend (Auth, Firestore, Functions)
firebase emulators:start --only auth,firestore,functions --project rockketeyes

# terminal 2: the app (debug builds use the emulators automatically)
flutter run -d chrome
```

Debug builds show a **Voice simulator** strip of color buttons under the mic panel. It feeds the same pipeline as the microphone, and you can hide it in Settings → Developer. The real microphone works alongside it; Chrome asks for permission on the first round.

## Tests

```bash
flutter analyze
flutter test                              # domain, scoring, golden fixtures, transcript matcher
(cd functions && npm test)                # server core, golden parity, replay validator
(cd functions && npm run smoke)           # full API flow against emulators

# End-to-end (web build + emulators + Playwright with installed Chrome)
flutter build web --release --dart-define=RE_EMULATOR=true --dart-define=RE_E2E=true
(cd e2e && npm install && node serve.mjs &) && (cd e2e && node run.mjs out)
```

## Build configuration (`--dart-define`)

| Key | Default | Purpose |
|---|---|---|
| `RE_EMULATOR` | `true` in debug | Use local Firebase emulators |
| `RE_EMULATOR_HOST` | `127.0.0.1` | Emulator host (Android emulator maps to `10.0.2.2`) |
| `RE_API_BASE` | auto | Override the functions base URL |
| `RE_APPCHECK_WEB_KEY` | empty | reCAPTCHA Enterprise site key; enables App Check on web |
| `RE_DEV_TOOLS` | `true` (non-release) | Voice simulator and developer settings |
| `RE_E2E` | `false` | Expose `window.reE2E` hooks for Playwright |

## Deploy (production)

1. In the Firebase console for **rockketeyes**:
   - Upgrade to **Blaze** (needed for Cloud Functions) and set a budget alert.
   - Enable **Cloud Firestore** in `nam5`.
   - Enable **Authentication → Anonymous** and **Google**.
2. `firebase deploy --only firestore,functions --project rockketeyes`
3. `flutter build web --release --wasm && firebase deploy --only hosting --project rockketeyes`
4. Optional hardening: create a reCAPTCHA Enterprise key and register App Check (Play Integrity for Android, reCAPTCHA for web). Then build with `--dart-define=RE_APPCHECK_WEB_KEY=…` and set `APPCHECK_ENFORCE=true` on the function.

## Android release (Google Play)

- Application ID: `com.rockketeyes.app`
- Create an upload keystore and `android/key.properties` (git-ignored):
  ```
  storePassword=…
  keyPassword=…
  keyAlias=upload
  storeFile=/absolute/path/to/upload-keystore.jks
  ```
- `flutter build appbundle --release --obfuscate --split-debug-info=build/symbols`
- Play Console → Data safety: speech is processed by the device's speech service and is not stored by Rockketeyes. Nickname, country and scores are collected for leaderboards under an anonymous account ID. The privacy policy is served at `/privacy.html`.

Asset credits and licenses are listed in [ASSET_LICENSES.md](ASSET_LICENSES.md).
