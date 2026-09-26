import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../services/api_client.dart';
import '../../../services/audio_service.dart';
import '../../../services/local_store.dart';
import '../../../services/settings.dart';
import '../domain/grid.dart';
import '../domain/scoring.dart';
import '../speech/color_recognizer.dart';
import '../speech/recognizer_factory.dart';
import 'game_config.dart';

enum RoundPhase {
  /// Fetching a seed from the server.
  preparing,

  /// Waiting for the microphone to come online.
  arming,

  /// 3-2-1.
  countdown,
  playing,
  paused,

  /// Mistake or clear animation before the results sheet.
  ending,
  results,
}

enum MistakeKind {
  /// Said a different color than the ink.
  color,

  /// Read the printed word instead of the ink.
  word,
}

enum SubmitStatus { none, submitting, done, failed, offline }

class AnswerEvent {
  const AnswerEvent(this.index, this.color, this.tMs, {required this.correct});

  final int index;
  final String color;
  final int tMs;
  final bool correct;

  Map<String, Object> toJson() => {'i': index, 'c': color, 't': tMs};
}

class Mistake {
  const Mistake({required this.index, required this.said, required this.kind});

  final int index;
  final String said;
  final MistakeKind kind;
}

class ServerResult {
  const ServerResult({
    required this.score,
    required this.ranked,
    required this.review,
    required this.personalBest,
    this.legendsEligible = true,
    this.rankDay,
    this.rankWeek,
    this.rankAll,
  });

  final int score;
  final bool ranked;
  final bool review;
  final bool personalBest;

  /// False when the player hasn't connected Google (not on Global Legends).
  final bool legendsEligible;
  final int? rankDay;
  final int? rankWeek;
  final int? rankAll;

  factory ServerResult.fromJson(Map<String, dynamic> j) {
    final rank = (j['rank'] as Map?)?.cast<String, dynamic>();
    return ServerResult(
      score: (j['score'] as num?)?.toInt() ?? 0,
      ranked: j['ranked'] == true,
      review: j['review'] == true,
      personalBest: j['personalBest'] == true,
      legendsEligible: j['legendsEligible'] != false,
      rankDay: (rank?['day'] as num?)?.toInt(),
      rankWeek: (rank?['week'] as num?)?.toInt(),
      rankAll: (rank?['all'] as num?)?.toInt(),
    );
  }
}

/// A round played inside a group challenge room.
class GroupRun {
  const GroupRun({
    required this.code,
    required this.round,
    required this.seed,
    required this.onProgress,
    required this.onFinish,
  });

  final String code;
  final int round;
  final int seed;
  final void Function(int correct, int cells, int elapsedMs) onProgress;
  final void Function(ScoreBreakdown result) onFinish;
}

class RoundState {
  const RoundState({
    this.phase = RoundPhase.preparing,
    this.config = const GameConfig(),
    this.cells = const [],
    this.activeIndex = 0,
    this.events = const [],
    this.countdown = 3,
    this.mistake,
    this.heard = '',
    this.lastCorrectIndex = -1,
    this.micStatus = RecognizerStatus.idle,
    this.micError,
    this.inputMode = InputMode.voice,
    this.roundId,
    this.offline = false,
    this.breakdown,
    this.submit = SubmitStatus.none,
    this.server,
    this.localBest = false,
    this.previousBest = 0,
    this.idleHint = false,
    this.notice,
    this.group,
  });

  final RoundPhase phase;
  final GameConfig config;
  final List<Cell> cells;
  final int activeIndex;
  final List<AnswerEvent> events;
  final int countdown;
  final Mistake? mistake;
  final String heard;
  final int lastCorrectIndex;
  final RecognizerStatus micStatus;
  final String? micError;

  /// Effective input (voice may fall back to tap when unsupported).
  final InputMode inputMode;
  final String? roundId;
  final bool offline;
  final ScoreBreakdown? breakdown;
  final SubmitStatus submit;
  final ServerResult? server;
  final bool localBest;
  final int previousBest;
  final bool idleHint;
  final String? notice;

  /// Set when this round belongs to a group challenge.
  final GroupRun? group;

  int get streak => events.where((e) => e.correct).length;
  Cell? get activeCell =>
      activeIndex < cells.length ? cells[activeIndex] : null;
  bool get ranked => roundId != null && config.rankable && !offline;

  RoundState copyWith({
    RoundPhase? phase,
    GameConfig? config,
    List<Cell>? cells,
    int? activeIndex,
    List<AnswerEvent>? events,
    int? countdown,
    Mistake? mistake,
    bool clearMistake = false,
    String? heard,
    int? lastCorrectIndex,
    RecognizerStatus? micStatus,
    String? micError,
    InputMode? inputMode,
    String? roundId,
    bool clearRound = false,
    bool? offline,
    ScoreBreakdown? breakdown,
    bool clearBreakdown = false,
    SubmitStatus? submit,
    ServerResult? server,
    bool clearServer = false,
    bool? localBest,
    int? previousBest,
    bool? idleHint,
    String? notice,
    bool clearNotice = false,
  }) => RoundState(
    phase: phase ?? this.phase,
    config: config ?? this.config,
    cells: cells ?? this.cells,
    activeIndex: activeIndex ?? this.activeIndex,
    events: events ?? this.events,
    countdown: countdown ?? this.countdown,
    mistake: clearMistake ? null : (mistake ?? this.mistake),
    heard: heard ?? this.heard,
    lastCorrectIndex: lastCorrectIndex ?? this.lastCorrectIndex,
    micStatus: micStatus ?? this.micStatus,
    micError: micError ?? this.micError,
    inputMode: inputMode ?? this.inputMode,
    roundId: clearRound ? null : (roundId ?? this.roundId),
    offline: offline ?? this.offline,
    breakdown: clearBreakdown ? null : (breakdown ?? this.breakdown),
    submit: submit ?? this.submit,
    server: clearServer ? null : (server ?? this.server),
    localBest: localBest ?? this.localBest,
    previousBest: previousBest ?? this.previousBest,
    idleHint: idleHint ?? this.idleHint,
    notice: clearNotice ? null : (notice ?? this.notice),
    group: group,
  );
}

/// Runs one sudden-death round: countdown → continuous listening → highlight
/// advances on each correct color → ends on the first mistake or a cleared
/// board → score saved locally and submitted to the Global Legends.
class RoundController extends Notifier<RoundState> {
  /// Most recent live controller (used by the E2E hooks and dev simulator).
  static RoundController? current;

  final Stopwatch _clock = Stopwatch();
  ColorRecognizer? _recognizer;
  final List<StreamSubscription<Object?>> _subs = [];
  Timer? _timer;
  Timer? _idle;
  int _generation = 0;
  final ValueNotifier<double> micLevel = ValueNotifier(0);

  @override
  RoundState build() {
    current = this;
    ref.onDispose(() {
      _generation++;
      _timer?.cancel();
      _idle?.cancel();
      for (final s in _subs) {
        s.cancel();
      }
      _recognizer?.dispose();
      _recognizer = null;
      AudioService.instance.duck(false);
      micLevel.dispose();
      if (identical(current, this)) current = null;
    });
    return const RoundState();
  }

  int get elapsedMs => _clock.elapsedMilliseconds;

  /// Read-only view of the current state for tooling (E2E hooks).
  RoundState get snapshot => state;

  bool get _haptics => ref.read(settingsProvider).haptics;

  Future<void> start(GameConfig config, {GroupRun? group}) async {
    final gen = ++_generation;
    _timer?.cancel();
    _idle?.cancel();
    _clock
      ..stop()
      ..reset();
    await _stopListening();
    if (group == null)
      await LocalStore.instance.set('lastConfig', config.toJson());

    state = RoundState(
      config: config,
      inputMode: config.mode,
      previousBest: LocalStore.instance.bestFor(config.boardId),
      group: group,
    );

    // 1. Seed: ranked rounds get theirs from the server.
    int seed;
    String? roundId;
    var offline = false;
    if (group != null) {
      seed = group.seed;
    } else {
      try {
        final res = await ApiClient.instance.post('/round/start', {
          'cols': config.size.cols,
          'rows': config.size.rows,
          'colorSet': config.colorSet.name,
          'congruentRatio': 0,
          'mode': config.mode.name,
        });
        seed = (res['seed'] as num).toInt();
        roundId = res['roundId'] as String?;
      } catch (e) {
        debugPrint('round/start failed, playing offline: $e');
        seed = math.Random().nextInt(0x7FFFFFFF);
        offline = true;
      }
    }
    if (gen != _generation) return;

    final cells = GridGenerator.generate(
      size: config.size,
      colorKeys: config.colorSet.keys,
      seed: seed,
    );
    state = state.copyWith(
      cells: cells,
      roundId: roundId,
      offline: offline,
      phase: RoundPhase.arming,
      notice: offline && group == null
          ? 'You are offline. This round is practice only.'
          : null,
    );

    // 2. Microphone.
    if (config.mode == InputMode.voice) {
      final ok = await _startListening(config);
      if (gen != _generation) return;
      if (!ok) {
        state = state.copyWith(
          inputMode: InputMode.tap,
          notice: 'Voice isn\'t available here, so we switched to tap mode (unranked).',
          clearRound: true,
        );
      }
    }

    // 3. Countdown.
    await _countdown(gen);
  }

  Future<void> _countdown(int gen) async {
    for (var n = 3; n >= 1; n--) {
      if (gen != _generation) return;
      state = state.copyWith(phase: RoundPhase.countdown, countdown: n);
      AudioService.instance.sfx(Sfx.tick);
      await Future<void>.delayed(const Duration(milliseconds: 800));
    }
    if (gen != _generation) return;
    state = state.copyWith(countdown: 0);
    AudioService.instance.sfx(Sfx.go);
    if (_haptics) unawaited(HapticFeedback.mediumImpact());
    await Future<void>.delayed(const Duration(milliseconds: 450));
    if (gen != _generation) return;
    state = state.copyWith(phase: RoundPhase.playing);
    if (state.inputMode == InputMode.voice) AudioService.instance.duck(true);
    _clock.start();
    _armIdle();
  }

  Future<bool> _startListening(GameConfig config) async {
    final rec = _recognizer ??= createRecognizer();
    if (!await rec.isSupported()) {
      state = state.copyWith(
        micStatus: RecognizerStatus.unsupported,
        micError: rec.lastError,
      );
      return false;
    }
    for (final s in _subs) {
      await s.cancel();
    }
    _subs
      ..clear()
      ..add(
        rec.tokens.listen(
          (t) => answer(t.color, heard: t.heard, loose: t.loose),
        ),
      )
      ..add(
        rec.transcripts.listen((t) {
          if (state.phase == RoundPhase.playing && t.isNotEmpty) {
            state = state.copyWith(
              heard: t.split(' ').where((w) => w.isNotEmpty).lastOrNull ?? '',
            );
          }
        }),
      )
      ..add(rec.levels.listen((v) => micLevel.value = v))
      ..add(
        rec.status.listen(
          (s) => state = state.copyWith(micStatus: s, micError: rec.lastError),
        ),
      );

    final ready = Completer<bool>();
    late final StreamSubscription<RecognizerStatus> waitSub;
    waitSub = rec.status.listen((s) {
      if (ready.isCompleted) return;
      if (s == RecognizerStatus.listening) ready.complete(true);
      if (s == RecognizerStatus.unsupported) ready.complete(false);
      if (s == RecognizerStatus.error &&
          (rec.lastError == 'not-allowed' ||
              rec.lastError == 'service-not-allowed' ||
              rec.lastError == 'audio-capture')) {
        ready.complete(false);
      }
    });
    await rec.start(allowedColors: config.colorSet.keys.toSet());
    // Some engines never report "listening"; don't block the game on it.
    final ok = await ready.future.timeout(
      const Duration(seconds: 6),
      onTimeout: () => true,
    );
    await waitSub.cancel();
    return ok;
  }

  Future<void> _stopListening() async {
    try {
      await _recognizer?.stop();
    } catch (_) {}
    micLevel.value = 0;
  }

  void _armIdle() {
    _idle?.cancel();
    if (state.idleHint) state = state.copyWith(idleHint: false);
    _idle = Timer(const Duration(seconds: 6), () {
      if (state.phase == RoundPhase.playing)
        state = state.copyWith(idleHint: true);
    });
  }

  /// A color was spoken (or tapped). [loose] tokens only count when correct.
  void answer(String color, {String heard = '', bool loose = false}) {
    final s = state;
    if (s.phase != RoundPhase.playing) return;
    final cell = s.activeCell;
    if (cell == null) return;
    final t = _clock.elapsedMilliseconds;

    if (color == cell.ink) {
      final events = [
        ...s.events,
        AnswerEvent(cell.index, color, t, correct: true),
      ];
      final next = s.activeIndex + 1;
      AudioService.instance.sfx(
        Sfx.correct,
        pitchStep: math.min(7, events.length ~/ 4),
      );
      if (_haptics) unawaited(HapticFeedback.selectionClick());
      state = s.copyWith(
        events: events,
        activeIndex: next,
        lastCorrectIndex: cell.index,
        heard: heard.isEmpty ? color : heard,
      );
      _armIdle();
      s.group?.onProgress(events.length, s.cells.length, t);
      if (next >= s.cells.length) unawaited(_end(null));
      return;
    }

    if (loose) return; // sound-alike noise, not a real attempt
    final events = [
      ...s.events,
      AnswerEvent(cell.index, color, t, correct: false),
    ];
    final kind = color == cell.word ? MistakeKind.word : MistakeKind.color;
    state = s.copyWith(
      events: events,
      heard: heard.isEmpty ? color : heard,
      mistake: Mistake(index: cell.index, said: color, kind: kind),
    );
    AudioService.instance.sfx(Sfx.wrong);
    if (_haptics) unawaited(HapticFeedback.heavyImpact());
    unawaited(_end(kind));
  }

  Future<void> _end(MistakeKind? mistake) async {
    final gen = _generation;
    _clock.stop();
    _idle?.cancel();
    await _stopListening();
    AudioService.instance.duck(false);

    final s = state;
    final correctEvents = s.events.where((e) => e.correct).toList();
    final breakdown = ScoreCalculator.compute(
      cells: s.cells.length,
      correct: correctEvents.length,
      correctElapsedMs: correctEvents.isEmpty ? 0 : correctEvents.last.tMs,
      elapsedMs: s.events.isEmpty
          ? _clock.elapsedMilliseconds
          : s.events.last.tMs,
    );
    state = s.copyWith(
      phase: RoundPhase.ending,
      breakdown: breakdown,
      idleHint: false,
    );
    if (mistake == null) AudioService.instance.sfx(Sfx.finish);

    // Personal record + history (local, always).
    // Group rounds are party games: they don't change solo personal bests.
    final pb =
        s.group == null &&
        await LocalStore.instance.recordBest(s.config.boardId, breakdown.score);
    await LocalStore.instance.addHistory({
      'boardId': s.config.boardId,
      'score': breakdown.score,
      'correct': breakdown.correct,
      'cells': breakdown.cells,
      'end': breakdown.end.name,
      'elapsedMs': breakdown.elapsedMs,
      'at': DateTime.now().millisecondsSinceEpoch,
    });
    if (gen != _generation) return;
    state = state.copyWith(localBest: pb && breakdown.score > 0);

    final group = state.group;
    if (group != null) {
      state = state.copyWith(submit: SubmitStatus.offline);
      group.onFinish(breakdown);
    } else {
      unawaited(_submit(gen));
    }
    await Future<void>.delayed(
      Duration(milliseconds: mistake == null ? 1400 : 1700),
    );
    if (gen != _generation) return;
    state = state.copyWith(phase: RoundPhase.results);
    AudioService.instance.sfx(Sfx.whoosh);
  }

  Future<void> _submit(int gen) async {
    final s = state;
    if (s.roundId == null || s.offline || s.inputMode != s.config.mode) {
      state = state.copyWith(submit: SubmitStatus.offline);
      return;
    }
    state = state.copyWith(submit: SubmitStatus.submitting);
    try {
      final res = await ApiClient.instance.post('/score/submit', {
        'roundId': s.roundId,
        'elapsedMs': s.breakdown?.elapsedMs ?? 0,
        'events': [for (final e in s.events) e.toJson()],
      });
      if (gen != _generation) return;
      state = state.copyWith(
        submit: SubmitStatus.done,
        server: ServerResult.fromJson(res),
      );
    } catch (e) {
      debugPrint('submit failed: $e');
      if (gen != _generation) return;
      state = state.copyWith(submit: SubmitStatus.failed);
    }
  }

  void pause() {
    if (state.phase != RoundPhase.playing) return;
    _clock.stop();
    _idle?.cancel();
    unawaited(_stopListening());
    AudioService.instance.duck(false);
    state = state.copyWith(phase: RoundPhase.paused);
  }

  Future<void> resume() async {
    if (state.phase != RoundPhase.paused) return;
    final gen = _generation;
    if (state.inputMode == InputMode.voice) {
      await _startListening(state.config);
    }
    if (gen != _generation) return;
    // Short countdown so the player isn't caught off guard.
    for (var n = 3; n >= 1; n--) {
      state = state.copyWith(phase: RoundPhase.countdown, countdown: n);
      AudioService.instance.sfx(Sfx.tick);
      await Future<void>.delayed(const Duration(milliseconds: 600));
      if (gen != _generation) return;
    }
    state = state.copyWith(phase: RoundPhase.playing);
    if (state.inputMode == InputMode.voice) AudioService.instance.duck(true);
    _clock.start();
    _armIdle();
  }

  /// Abandon the round (back button).
  Future<void> quit() async {
    _generation++;
    _clock.stop();
    _idle?.cancel();
    await _stopListening();
    AudioService.instance.duck(false);
  }

  void clearNotice() => state = state.copyWith(clearNotice: true);
}

final roundProvider = NotifierProvider.autoDispose<RoundController, RoundState>(
  RoundController.new,
);
