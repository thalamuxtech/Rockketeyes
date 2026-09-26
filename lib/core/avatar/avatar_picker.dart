import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../theme/app_theme.dart';
import '../widgets/avatar.dart';
import '../widgets/glass.dart';
import 'avatar_spec.dart';

/// Opens the avatar studio. Returns the encoded avatar, or null if dismissed.
Future<String?> showAvatarPicker(
  BuildContext context, {
  required String current,
  required String name,
}) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: const Color(0x99050410),
    builder: (_) => _AvatarStudio(initial: current, name: name),
  );
}

enum _Tab { characters, emoji }

class _AvatarStudio extends StatefulWidget {
  const _AvatarStudio({required this.initial, required this.name});

  final String initial;
  final String name;

  @override
  State<_AvatarStudio> createState() => _AvatarStudioState();
}

class _AvatarStudioState extends State<_AvatarStudio> {
  late String _value = widget.initial;
  late _Tab _tab;
  late String _style;
  String _batch = '';
  int _category = 0;
  int _bg = 0;
  final _rng = math.Random();

  @override
  void initState() {
    super.initState();
    final spec = AvatarSpec.parse(widget.initial);
    switch (spec) {
      case EmojiAvatar(:final background):
        _tab = _Tab.emoji;
        _style = kDicebearStyles.first.id;
        _bg = background;
      case DicebearAvatar(:final style):
        _tab = _Tab.characters;
        _style = style;
    }
    _batch = _newBatch();
  }

  String _newBatch() => List.generate(
    3,
    (_) => String.fromCharCode(97 + _rng.nextInt(26)),
  ).join();

  List<String> get _seeds => [for (var i = 0; i < 18; i++) '$_batch${i + 1}'];

  @override
  Widget build(BuildContext context) {
    final height = MediaQuery.sizeOf(context).height;
    return SafeArea(
      top: false,
      child: Center(
        heightFactor: 1,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: 620, maxHeight: height * 0.9),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            child: GlassPanel(
              fill: const Color(0xF0141026),
              radius: AppRadius.lg,
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 44,
                    height: 5,
                    decoration: BoxDecoration(
                      color: AppColors.glassBorder,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      AnimatedSwitcher(
                        duration: AppMotion.short,
                        transitionBuilder: (c, a) =>
                            ScaleTransition(scale: a, child: c),
                        child: PlayerAvatar(
                          key: ValueKey(_value),
                          seed: _value,
                          name: widget.name,
                          size: 76,
                          ring: AppColors.gold,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Avatar studio', style: AppText.heading(22)),
                            Text(
                              'Pick a character or an emoji. It shows on every leaderboard.',
                              style: AppText.body(
                                13,
                                color: AppColors.textMuted,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Segmented<_Tab>(
                    values: _Tab.values,
                    selected: _tab,
                    labelOf: (t) =>
                        t == _Tab.characters ? 'Characters' : 'Emoji',
                    iconOf: (t) => t == _Tab.characters
                        ? LucideIcons.userRound
                        : LucideIcons.smile,
                    onChanged: (t) => setState(() => _tab = t),
                  ),
                  const SizedBox(height: 14),
                  Flexible(
                    child: AnimatedSwitcher(
                      duration: AppMotion.short,
                      child: _tab == _Tab.characters ? _characters() : _emoji(),
                    ),
                  ),
                  const SizedBox(height: 16),
                  GoldButton(
                    label: 'Use this avatar',
                    icon: LucideIcons.check,
                    onPressed: () => Navigator.of(context).pop(_value),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _characters() {
    return Column(
      key: const ValueKey('chars'),
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          height: 44,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: kDicebearStyles.length,
            separatorBuilder: (_, _) => const SizedBox(width: 8),
            itemBuilder: (_, i) {
              final s = kDicebearStyles[i];
              final selected = s.id == _style;
              return _Chip(
                label: s.label,
                selected: selected,
                onTap: () => setState(() => _style = s.id),
              );
            },
          ),
        ),
        const SizedBox(height: 12),
        Flexible(
          child: GridView.builder(
            shrinkWrap: true,
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 84,
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
            ),
            itemCount: _seeds.length,
            itemBuilder: (_, i) {
              final value = DicebearAvatar(_style, _seeds[i]).encode();
              return _Option(
                label: 'Character ${i + 1}',
                selected: value == _value,
                onTap: () => setState(() => _value = value),
                child: PlayerAvatar(seed: value, name: widget.name, size: 64),
              );
            },
          ),
        ),
        const SizedBox(height: 8),
        TextButton.icon(
          onPressed: () => setState(() => _batch = _newBatch()),
          icon: const Icon(
            LucideIcons.shuffle,
            size: 16,
            color: AppColors.gold,
          ),
          label: Text(
            'Show me more',
            style: AppText.label(14, color: AppColors.gold),
          ),
        ),
      ],
    );
  }

  Widget _emoji() {
    final cat = kEmojiCategories[_category];
    return Column(
      key: const ValueKey('emoji'),
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          height: 44,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: kEmojiCategories.length,
            separatorBuilder: (_, _) => const SizedBox(width: 8),
            itemBuilder: (_, i) => _Chip(
              label: kEmojiCategories[i].label,
              selected: i == _category,
              onTap: () => setState(() => _category = i),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Flexible(
          child: GridView.builder(
            shrinkWrap: true,
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 64,
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
            ),
            itemCount: cat.emojis.length,
            itemBuilder: (_, i) {
              final value = EmojiAvatar(cat.emojis[i], _bg).encode();
              return _Option(
                label: 'Emoji ${cat.emojis[i]}',
                selected: value == _value,
                onTap: () => setState(() => _value = value),
                child: PlayerAvatar(seed: value, name: widget.name, size: 52),
              );
            },
          ),
        ),
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.centerLeft,
          child: Text(
            'BACKGROUND',
            style: AppText.label(
              11,
              color: AppColors.textFaint,
            ).copyWith(letterSpacing: 1.5),
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (var i = 0; i < kAvatarBackgrounds.length; i++)
              Semantics(
                button: true,
                selected: i == _bg,
                label: 'Background ${i + 1}',
                child: GestureDetector(
                  onTap: () => setState(() {
                    _bg = i;
                    final spec = AvatarSpec.parse(_value);
                    if (spec is EmojiAvatar)
                      _value = EmojiAvatar(spec.emoji, i).encode();
                  }),
                  child: MouseRegion(
                    cursor: SystemMouseCursors.click,
                    child: AnimatedContainer(
                      duration: AppMotion.micro,
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: LinearGradient(colors: kAvatarBackgrounds[i]),
                        border: Border.all(
                          color: i == _bg
                              ? AppColors.gold
                              : AppColors.glassBorder,
                          width: i == _bg ? 2.5 : 1,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      excludeSemantics: true,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: onTap,
          child: AnimatedContainer(
            duration: AppMotion.micro,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: selected
                  ? AppColors.gold.withValues(alpha: 0.16)
                  : AppColors.glassFill,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(
                color: selected ? AppColors.gold : AppColors.glassBorder,
              ),
            ),
            child: Text(
              label,
              style: AppText.label(
                13,
                color: selected ? AppColors.gold : AppColors.text,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Option extends StatelessWidget {
  const _Option({
    required this.selected,
    required this.onTap,
    required this.child,
    required this.label,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      excludeSemantics: true,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: onTap,
          child: AnimatedContainer(
            duration: AppMotion.micro,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppRadius.sm + 4),
              color: selected
                  ? AppColors.gold.withValues(alpha: 0.14)
                  : Colors.transparent,
              border: Border.all(
                color: selected ? AppColors.gold : Colors.transparent,
                width: 2,
              ),
            ),
            alignment: Alignment.center,
            child: child,
          ),
        ),
      ),
    );
  }
}
