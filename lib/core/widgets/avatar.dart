import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// DiceBear-generated avatar (https://www.dicebear.com, free HTTP API),
/// with an initials fallback while offline.
class PlayerAvatar extends StatelessWidget {
  const PlayerAvatar({
    super.key,
    required this.seed,
    required this.name,
    this.size = 44,
    this.ring,
  });

  final String seed;
  final String name;
  final double size;
  final Color? ring;

  static String urlFor(String seed) =>
      'https://api.dicebear.com/9.x/glass/png?size=128&seed=${Uri.encodeComponent(seed)}';

  @override
  Widget build(BuildContext context) {
    final initials = name.trim().isEmpty
        ? '?'
        : name.trim().split(RegExp(r'\s+')).take(2).map((w) => w[0].toUpperCase()).join();
    final fallback = Center(
      child: Text(initials, style: AppText.label(size * 0.36, weight: FontWeight.w700)),
    );
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: const LinearGradient(colors: [AppColors.violet, AppColors.bgIndigo]),
        border: Border.all(color: ring ?? AppColors.glassBorder, width: ring != null ? 2.5 : 1),
        boxShadow: [
          if (ring != null) BoxShadow(color: ring!.withValues(alpha: 0.45), blurRadius: 18),
        ],
      ),
      child: ClipOval(
        child: seed.isEmpty
            ? fallback
            : Image.network(
                urlFor(seed),
                width: size,
                height: size,
                fit: BoxFit.cover,
                semanticLabel: 'Avatar of $name',
                errorBuilder: (_, _, _) => fallback,
                frameBuilder: (context, child, frame, sync) =>
                    frame == null && !sync ? fallback : child,
              ),
      ),
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
