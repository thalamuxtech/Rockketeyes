import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'audio_service.dart';
import 'local_store.dart';

class AppSettings {
  const AppSettings({
    this.musicVolume = 0.55,
    this.sfxVolume = 0.8,
    this.playMusic = PlayMusicLevel.low,
    this.haptics = true,
    this.colorblind = false,
    this.onboarded = false,
    this.showSimulator = true,
  });

  final double musicVolume;
  final double sfxVolume;
  final PlayMusicLevel playMusic;
  final bool haptics;
  final bool colorblind;
  final bool onboarded;
  final bool showSimulator;

  AppSettings copyWith({
    double? musicVolume,
    double? sfxVolume,
    PlayMusicLevel? playMusic,
    bool? haptics,
    bool? colorblind,
    bool? onboarded,
    bool? showSimulator,
  }) =>
      AppSettings(
        musicVolume: musicVolume ?? this.musicVolume,
        sfxVolume: sfxVolume ?? this.sfxVolume,
        playMusic: playMusic ?? this.playMusic,
        haptics: haptics ?? this.haptics,
        colorblind: colorblind ?? this.colorblind,
        onboarded: onboarded ?? this.onboarded,
        showSimulator: showSimulator ?? this.showSimulator,
      );
}

class SettingsController extends Notifier<AppSettings> {
  LocalStore get _store => LocalStore.instance;

  @override
  AppSettings build() {
    final s = AppSettings(
      musicVolume: _store.get<double>('musicVolume') ?? 0.55,
      sfxVolume: _store.get<double>('sfxVolume') ?? 0.8,
      playMusic: PlayMusicLevel.values.asNameMap()[_store.get<String>('playMusic')] ??
          PlayMusicLevel.low,
      haptics: _store.get<bool>('haptics') ?? true,
      colorblind: _store.get<bool>('colorblind') ?? false,
      onboarded: _store.get<bool>('onboarded') ?? false,
      showSimulator: _store.get<bool>('showSimulator') ?? true,
    );
    _applyAudio(s);
    return s;
  }

  void _applyAudio(AppSettings s) => AudioService.instance
      .applyVolumes(music: s.musicVolume, sfx: s.sfxVolume, level: s.playMusic);

  Future<void> update(AppSettings next) async {
    state = next;
    _applyAudio(next);
    await Future.wait([
      _store.set('musicVolume', next.musicVolume),
      _store.set('sfxVolume', next.sfxVolume),
      _store.set('playMusic', next.playMusic.name),
      _store.set('haptics', next.haptics),
      _store.set('colorblind', next.colorblind),
      _store.set('onboarded', next.onboarded),
      _store.set('showSimulator', next.showSimulator),
    ]);
  }
}

final settingsProvider = NotifierProvider<SettingsController, AppSettings>(SettingsController.new);
