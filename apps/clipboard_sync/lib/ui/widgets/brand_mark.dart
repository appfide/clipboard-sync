import 'package:clipboard_sync/ui/app_theme.dart';
import 'package:flutter/material.dart';

/// App logo: rounded tile with a clipboard glyph and a sync arc.
class BrandMark extends StatelessWidget {
  /// Creates the mark.
  const BrandMark({this.size = 40, super.key});

  /// Edge length.
  final double size;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            scheme.primary,
            Color.lerp(scheme.primary, AppTokens.slate900, 0.35)!,
          ],
        ),
        borderRadius: BorderRadius.circular(size * 0.28),
        boxShadow: [
          BoxShadow(
            color: scheme.primary.withValues(alpha: 0.25),
            blurRadius: size * 0.4,
            offset: Offset(0, size * 0.15),
          ),
        ],
      ),
      child: Icon(
        Icons.content_paste_rounded,
        color: scheme.onPrimary,
        size: size * 0.55,
      ),
    );
  }
}
