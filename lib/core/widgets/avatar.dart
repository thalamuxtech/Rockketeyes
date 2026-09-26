import 'package:flutter/material.dart';

import '../avatar/avatar_spec.dart';
import '../theme/app_theme.dart';

/// Renders an [AvatarSpec] string: DiceBear character or emoji, with an
/// initials fallback while images load or offline.
class PlayerAvatar extends StatelessWidget {
  const PlayerAvatar({
    super.key,
    required this.seed,
    required this.name,
    this.size = 44,
    this.ring,
  });

  /// Encoded avatar (see [AvatarSpec]).
  final String seed;
  final String name;
  final double size;
  final Color? ring;

  @override
  Widget build(BuildContext context) {
    final spec = AvatarSpec.parse(seed);
    final initials = name.trim().isEmpty
        ? '?'
        : name.trim().split(RegExp(r'\s+')).take(2).map((w) => w[0].toUpperCase()).join();
    final fallback = Center(
      child: Text(initials, style: AppText.label(size * 0.36, weight: FontWeight.w700)),
    );

    final Widget inner;
    final Gradient bg;
    switch (spec) {
      case EmojiAvatar(:final emoji, :final background):
        final colors = kAvatarBackgrounds[background];
        bg = LinearGradient(colors: colors, begin: Alignment.topLeft, end: Alignment.bottomRight);
        inner = Center(
          child: Text(emoji,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: size * 0.56, height: 1.1),
              semanticsLabel: 'Avatar of $name'),
        );
      case DicebearAvatar():
        bg = const LinearGradient(colors: [AppColors.violet, AppColors.bgIndigo]);
        inner = Image.network(
          spec.url,
          width: size,
          height: size,
          fit: BoxFit.cover,
          semanticLabel: 'Avatar of $name',
          errorBuilder: (_, _, _) => fallback,
          // Soft placeholder while loading; initials only if the image fails.
          frameBuilder: (context, child, frame, sync) => AnimatedSwitcher(
            duration: AppMotion.short,
            child: frame == null && !sync ? const SizedBox.expand(key: ValueKey('loading')) : child,
          ),
        );
    }

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: bg,
        border: Border.all(color: ring ?? AppColors.glassBorder, width: ring != null ? 2.5 : 1),
        boxShadow: [
          if (ring != null) BoxShadow(color: ring!.withValues(alpha: 0.45), blurRadius: 18),
        ],
      ),
      child: ClipOval(child: inner),
    );
  }
}

/// Country flag from flagcdn.com, falling back to the ISO code.
class CountryFlag extends StatelessWidget {
  const CountryFlag({super.key, required this.code, this.width = 22});

  final String code;
  final double width;

  @override
  Widget build(BuildContext context) {
    if (code.isEmpty) return SizedBox(width: width);
    final text = Text(code, style: AppText.label(10, color: AppColors.textMuted));
    return ClipRRect(
      borderRadius: BorderRadius.circular(3),
      child: Image.network(
        'https://flagcdn.com/w40/${code.toLowerCase()}.png',
        width: width,
        height: width * 0.72,
        fit: BoxFit.cover,
        semanticLabel: code,
        errorBuilder: (_, _, _) => text,
      ),
    );
  }
}
