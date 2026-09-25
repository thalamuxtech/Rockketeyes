import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/theme/app_theme.dart';
import '../../core/widgets/glass.dart';
import '../../services/local_store.dart';
import '../../services/settings.dart';
import '../game/application/game_config.dart';
import '../game/domain/color_set.dart';
import '../game/domain/grid.dart';

Future<void> showSetupSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: const Color(0x99050410),
    builder: (_) => const SetupSheet(),
  );
}

class SetupSheet extends ConsumerStatefulWidget {
  const SetupSheet({super.key});

  @override
  ConsumerState<SetupSheet> createState() => _SetupSheetState();
}

class _SetupSheetState extends ConsumerState<SetupSheet> {
  late GameConfig _config;
  late bool _custom;

  @override
  void initState() {
    super.initState();
    final saved = LocalStore.instance.get<Map<dynamic, dynamic>>('lastConfig');
    _config = GameConfig.fromJson(saved).copyWith(colorblind: ref.read(settingsProvider).colorblind);
    _custom = !_config.size.isPreset;
  }

  void _set(GameConfig c) => setState(() => _config = c);

  @override
  Widget build(BuildContext context) {
    final size = _config.size;
    final best = LocalStore.instance.bestFor(_config.boardId);
    return SafeArea(
      top: false,
      child: Center(
        heightFactor: 1,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 620),
          child: Padding(
            padding: EdgeInsets.fromLTRB(12, 0, 12, 12 + MediaQuery.viewInsetsOf(context).bottom),
            child: GlassPanel(
              fill: const Color(0xE6141026),
              radius: AppRadius.lg,
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(
                        width: 44,
                        height: 5,
                        decoration: BoxDecoration(
                            color: AppColors.glassBorder, borderRadius: BorderRadius.circular(3)),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(child: Text('New round', style: AppText.heading(24))),
                        if (_config.rankable)
                          const Pill(label: 'RANKED', icon: LucideIcons.trophy)
                        else
                          const Pill(label: 'PRACTICE', color: AppColors.textMuted, icon: LucideIcons.dumbbell),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text('One mistake ends the round. Clear the board as fast as you can.',
                        style: AppText.body(13, color: AppColors.textMuted)),
                    const SizedBox(height: 20),
                    _label('Board size'),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final g in GridSize.presets)
                          ChoiceChipX(
                            label: g.label,
                            sublabel: '${g.cells} words',
                            selected: !_custom && size == g,
                            onTap: () {
                              _custom = false;
                              _set(_config.copyWith(size: g));
                            },
                          ),
                        ChoiceChipX(
                          label: 'Custom',
                          sublabel: _custom ? size.label : 'any size',
                          selected: _custom,
                          onTap: () => setState(() => _custom = true),
                        ),
                      ],
                    ),
                    AnimatedSize(
                      duration: AppMotion.short,
                      curve: AppMotion.curve,
                      child: _custom
                          ? Padding(
                              padding: const EdgeInsets.only(top: 12),
                              child: Column(children: [
                                _slider('Columns', size.cols, GridSize.minCols, GridSize.maxCols,
                                    (v) => _set(_config.copyWith(size: GridSize(v, size.rows)))),
                                _slider('Rows', size.rows, GridSize.minRows, GridSize.maxRows,
                                    (v) => _set(_config.copyWith(size: GridSize(size.cols, v)))),
                                if (!size.isPreset)
                                  Text('Custom sizes are practice only. Presets are ranked.',
                                      style: AppText.body(12, color: AppColors.textFaint)),
                              ]),
                            )
                          : const SizedBox(width: double.infinity),
                    ),
                    const SizedBox(height: 20),
                    _label('Difficulty'),
                    Segmented<Difficulty>(
                      values: Difficulty.values,
                      selected: _config.difficulty,
                      labelOf: (d) => switch (d) {
                        Difficulty.easy => 'Easy · 4',
                        Difficulty.normal => 'Normal · 6',
                        Difficulty.hard => 'Hard · 8',
                      },
                      onChanged: (d) => _set(_config.copyWith(difficulty: d)),
                    ),
                    const SizedBox(height: 10),
                    _ColorPreview(set: _config.colorSet),
                    const SizedBox(height: 20),
                    _label('Answer by'),
                    Segmented<InputMode>(
                      values: InputMode.values,
                      selected: _config.mode,
                      labelOf: (m) => m == InputMode.voice ? 'Voice' : 'Tap',
                      iconOf: (m) => m == InputMode.voice ? LucideIcons.mic : LucideIcons.pointer,
                      onChanged: (m) => _set(_config.copyWith(mode: m)),
                    ),
                    const SizedBox(height: 24),
                    GoldButton(
                      label: 'Start',
                      icon: LucideIcons.play,
                      onPressed: () {
                        Navigator.of(context).pop();
                        context.go('/play', extra: _config);
                      },
                    ),
                    if (best > 0) ...[
                      const SizedBox(height: 10),
                      Center(
                        child: Text('Your best on this board: $best',
                            style: AppText.label(13, color: AppColors.textMuted)),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _label(String t) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Text(t.toUpperCase(),
            style: AppText.label(11, color: AppColors.textFaint).copyWith(letterSpacing: 1.5)),
      );

  Widget _slider(String label, int value, int min, int max, ValueChanged<int> onChanged) {
    return Row(
      children: [
        SizedBox(width: 80, child: Text(label, style: AppText.label(14, color: AppColors.textMuted))),
        Expanded(
          child: Slider(
            value: value.toDouble(),
            min: min.toDouble(),
            max: max.toDouble(),
            divisions: max - min,
            label: '$value',
            onChanged: (v) => onChanged(v.round()),
          ),
        ),
        SizedBox(width: 32, child: Text('$value', textAlign: TextAlign.right, style: AppText.numeric(16))),
      ],
    );
  }
}

class _ColorPreview extends StatelessWidget {
  const _ColorPreview({required this.set});

  final ColorSetId set;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (final c in set.colors)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: AppColors.board,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.boardEdge),
            ),
            child: Text(c.word[0] + c.word.substring(1).toLowerCase(),
                style: AppText.label(12, weight: FontWeight.w700, color: c.inkDark)),
          ),
      ],
    );
  }
}
