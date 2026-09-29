import 'package:hive_ce_flutter/hive_ce_flutter.dart';

/// Device-local persistence: settings, personal bests and recent history.
class LocalStore {
  LocalStore._(this._settings, this._bests, this._history);

  static late final LocalStore instance;

  final Box<dynamic> _settings;
  final Box<dynamic> _bests;
  final Box<dynamic> _history;

  static Future<void> init() async {
    await Hive.initFlutter('rocketeye');
    instance = LocalStore._(
      await Hive.openBox<dynamic>('settings'),
      await Hive.openBox<dynamic>('bests'),
      await Hive.openBox<dynamic>('history'),
    );
  }

  T? get<T>(String key) {
    final v = _settings.get(key);
    return v is T ? v : null;
  }

  Future<void> set(String key, Object? value) => _settings.put(key, value);

  int bestFor(String boardId) => (_bests.get(boardId) as int?) ?? 0;

  /// Returns true when [score] is a new personal best.
  Future<bool> recordBest(String boardId, int score) async {
    if (score <= bestFor(boardId)) return false;
    await _bests.put(boardId, score);
    return true;
  }

  Map<String, int> allBests() => {
        for (final k in _bests.keys) k as String: _bests.get(k) as int,
      };

  Future<void> addHistory(Map<String, Object?> entry) async {
    await _history.add(entry);
    while (_history.length > 60) {
      await _history.deleteAt(0);
    }
  }

  List<Map<String, Object?>> history() => [
        for (final v in _history.values)
          if (v is Map) v.cast<String, Object?>(),
      ].reversed.toList();

  /// Forgets the player (profile, bests, history) but keeps device settings.
  Future<void> clearPlayer() async {
    await _settings.deleteAll(['nickname', 'avatarSeed', 'country', 'registered']);
    await _bests.clear();
    await _history.clear();
  }

  Future<void> clearAll() async {
    await _settings.clear();
    await _bests.clear();
    await _history.clear();
  }
}
