import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:go_router/go_router.dart';

import '../../features/game/application/game_config.dart';
import '../../features/game/application/round_controller.dart';
import '../../features/game/domain/color_set.dart';
import '../../features/game/domain/grid.dart';
import '../../features/group/host_screen.dart' show currentHostedRoom;

void install(GoRouter router, {required Future<Object?> Function() connectGoogle}) {
  final api = JSObject();

  api.setProperty('hostedRoom'.toJS, (() => currentHostedRoom?.toJS).toJS);
  api.setProperty(
    'connectGoogle'.toJS,
    (() => connectGoogle().then((_) => 'ok'.toJS, onError: (Object e) => 'error: $e'.toJS).toJS).toJS,
  );

  api.setProperty(
    'state'.toJS,
    (() {
      final c = RoundController.current;
      Map<String, Object?> round = {};
      try {
        final s = c?.snapshot;
        if (s != null) {
          round = {
            'phase': s.phase.name,
            'active': s.activeIndex,
            'cells': s.cells.length,
            'ink': s.activeCell?.ink,
            'word': s.activeCell?.word,
            'correct': s.events.where((e) => e.correct).length,
            'mistake': s.mistake?.kind.name,
            'score': s.breakdown?.score,
            'serverScore': s.server?.score,
            'submit': s.submit.name,
            'rankAll': s.server?.rankAll,
            'ranked': s.ranked,
            'input': s.inputMode.name,
            'mic': s.micStatus.name,
            'group': s.group?.code,
            'legendsEligible': s.server?.legendsEligible,
          };
        }
      } catch (_) {}
      return jsonEncode({
        'route': router.routerDelegate.currentConfiguration.uri.toString(),
        'round': round,
      }).toJS;
    }).toJS,
  );

  api.setProperty(
    'say'.toJS,
    ((JSString color) {
      RoundController.current?.answer(color.toDart, heard: color.toDart);
    }).toJS,
  );

  api.setProperty(
    'sayCorrect'.toJS,
    (() {
      final c = RoundController.current;
      final ink = c?.snapshot.activeCell?.ink;
      if (ink != null) c!.answer(ink, heard: ink);
    }).toJS,
  );

  api.setProperty('go'.toJS, ((JSString path) => router.go(path.toDart)).toJS);

  api.setProperty(
    'play'.toJS,
    ((JSString size, JSString difficulty, JSString mode) {
      router.go(
        '/play',
        extra: GameConfig(
          size: GridSize.tryParse(size.toDart) ?? const GridSize(3, 4),
          difficulty: Difficulty.values.asNameMap()[difficulty.toDart] ?? Difficulty.normal,
          mode: InputMode.values.asNameMap()[mode.toDart] ?? InputMode.voice,
        ),
      );
    }).toJS,
  );

  globalContext.setProperty('reE2E'.toJS, api);
}
