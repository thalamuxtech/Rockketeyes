import 'dart:async';
import 'dart:math' as math;

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

enum Sfx { correct, wrong, tick, go, finish, whoosh, tap }

enum MusicScene { menu, play }

/// How loud music plays while the microphone is listening.
enum PlayMusicLevel {
  off(0),
  low(0.15),
  normal(1);

  const PlayMusicLevel(this.factor);
  final double factor;
}

/// Ambient music + low-latency sound effects.
///
/// Browsers block audio until the first user gesture; [unlock] is called from
/// the app root on the first pointer event.
class AudioService {
  AudioService._();
  static final AudioService instance = AudioService._();

  static const _menuTracks = ['audio/music/menu_ambient.mp3'];
  static const _playTracks = ['audio/music/play_focus_1.mp3', 'audio/music/play_focus_2.mp3'];

  final AudioPlayer _music = AudioPlayer(playerId: 'music');
  final Map<Sfx, List<AudioPlayer>> _pools = {};
  final Map<Sfx, int> _next = {};

  bool _unlocked = false;
  AudioPlayer? _probe;
  bool _initialised = false;
  double musicVolume = 0.55;
  double sfxVolume = 0.8;
  PlayMusicLevel playLevel = PlayMusicLevel.low;
  MusicScene? _scene;
  bool _ducked = false;
  int _playIndex = 0;
  Timer? _fade;

  Future<void> init() async {
    if (_initialised) return;
    _initialised = true;
    AudioLogger.logLevel = AudioLogLevel.info; // surface playback errors in logs
    try {
      await AudioPlayer.global.setAudioContext(AudioContextConfig(
        focus: AudioContextConfigFocus.mixWithOthers,
      ).build());
    } catch (_) {}
    await _music.setReleaseMode(ReleaseMode.loop);
    for (final s in Sfx.values) {
      final size = s == Sfx.correct || s == Sfx.tap || s == Sfx.wrong ? 3 : 1;
      _pools[s] = [
        for (var i = 0; i < size; i++)
          // Standard players everywhere: Android's low-latency SoundPool mode
          // can fail silently on some devices.
          AudioPlayer(playerId: 'sfx_${s.name}_$i')..setPlayerMode(PlayerMode.mediaPlayer),
      ];
      _next[s] = 0;
      for (final p in _pools[s]!) {
        unawaited(p.setSource(AssetSource('audio/sfx/${s.name}.mp3')).catchError((_) {}));
        unawaited(p.setReleaseMode(ReleaseMode.stop));
      }
    }
  }

  /// Call once after a user gesture.
  void unlock() {
    if (_unlocked) return;
    _unlocked = true;
    final scene = _scene ?? MusicScene.menu;
    _scene = scene;
    // Browsers only allow audio that starts inside the user's gesture, so
    // start the music and wake every effect player right now, not after an
    // await or fade.
    final track = scene == MusicScene.menu ? _menuTracks.first : _playTracks[_playIndex++ % _playTracks.length];
    unawaited(_music.play(AssetSource(track), volume: _targetMusicVolume).catchError((Object e) {
      debugPrint('music start blocked: $e');
      _unlocked = false; // try again on the next tap
    }));
    for (final pool in _pools.values) {
      for (final p in pool) {
        unawaited(() async {
          try {
            await p.setVolume(0);
            await p.resume();
            await Future<void>.delayed(const Duration(milliseconds: 60));
            await p.stop();
          } catch (_) {}
        }());
      }
    }
  }

  /// Plays a short chime on a fresh player at full effect volume, and makes
  /// sure the music is running (sound check in onboarding/settings).
  Future<void> testSound() async {
    unlock();
    // One reusable player: re-creating players with the same id is ignored.
    final probe = _probe ??= AudioPlayer(playerId: 'sound_check')..setReleaseMode(ReleaseMode.stop);
    try {
      await probe.stop();
      await probe.play(AssetSource('audio/sfx/finish.mp3'), volume: math.max(sfxVolume, 0.9));
      debugPrint('sound check: chime playing');
    } catch (e) {
      debugPrint('sound check failed: $e');
    }
    if (_music.state != PlayerState.playing) {
      debugPrint('sound check: music was ${_music.state.name}, restarting');
      final scene = _scene ?? MusicScene.menu;
      _scene = null;
      await setScene(scene);
    }
  }

  bool get unlocked => _unlocked;

  double get _targetMusicVolume {
    if (_scene == MusicScene.play && _ducked) return musicVolume * playLevel.factor;
    return musicVolume;
  }

  Future<void> setScene(MusicScene scene) async {
    if (_scene == scene) return;
    _scene = scene;
    if (!_unlocked) return;
    final track = scene == MusicScene.menu
        ? _menuTracks.first
        : _playTracks[_playIndex++ % _playTracks.length];
    try {
      await _fadeTo(0, const Duration(milliseconds: 500));
      await _music.stop();
      await _music.setVolume(0);
      await _music.play(AssetSource(track), volume: 0);
      debugPrint('music: playing $track');
      await _fadeTo(_targetMusicVolume, const Duration(milliseconds: 1600));
    } catch (e) {
      debugPrint('music error: $e');
    }
  }

  /// Lower music while the mic is listening so it doesn't leak into speech.
  void duck(bool on) {
    _ducked = on;
    if (_unlocked) unawaited(_fadeTo(_targetMusicVolume, const Duration(milliseconds: 400)));
  }

  void applyVolumes({required double music, required double sfx, required PlayMusicLevel level}) {
    musicVolume = music;
    sfxVolume = sfx;
    playLevel = level;
    if (_unlocked) unawaited(_music.setVolume(_targetMusicVolume));
  }

  Future<void> _fadeTo(double target, Duration d) {
    _fade?.cancel();
    final start = _music.volume;
    if ((start - target).abs() < 0.01) {
      return _music.setVolume(target);
    }
    final completer = Completer<void>();
    const step = Duration(milliseconds: 50);
    final steps = math.max(1, d.inMilliseconds ~/ step.inMilliseconds);
    var i = 0;
    _fade = Timer.periodic(step, (t) {
      i++;
      final v = start + (target - start) * (i / steps);
      unawaited(_music.setVolume(v.clamp(0, 1)));
      if (i >= steps) {
        t.cancel();
        if (!completer.isCompleted) completer.complete();
      }
    });
    return completer.future;
  }

  /// Fire-and-forget sound effect. [pitchStep] raises correct chimes on streaks.
  void sfx(Sfx s, {int pitchStep = 0}) {
    if (!_unlocked || sfxVolume <= 0) return;
    final pool = _pools[s];
    if (pool == null || pool.isEmpty) return;
    final idx = _next[s]!;
    _next[s] = (idx + 1) % pool.length;
    final p = pool[idx];
    final rate = math.pow(2, pitchStep.clamp(0, 7) / 12).toDouble();
    unawaited(() async {
      try {
        await p.stop();
        await p.setVolume(sfxVolume);
        if (!kIsWeb) await p.setPlaybackRate(rate);
        await p.resume();
      } catch (e) {
        debugPrint('sfx ${s.name} failed: $e');
      }
    }());
  }

  Future<void> pauseAll() async {
    try {
      await _music.pause();
    } catch (_) {}
  }

  Future<void> resumeAll() async {
    if (!_unlocked) return;
    try {
      await _music.resume();
    } catch (_) {}
  }
}
