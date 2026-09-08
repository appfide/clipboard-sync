import 'package:clipboard_sync/ui/app_theme.dart';
import 'package:flutter/material.dart';

/// Titled card grouping related rows; the standard settings container.
class SectionCard extends StatelessWidget {
  /// Creates a section.
  const SectionCard({
    required this.title,
    required this.children,
    this.subtitle,
    this.trailing,
    super.key,
  });

  /// Section heading.
  final String title;

  /// Optional description under the heading.
  final String? subtitle;

  /// Optional widget at the end of the header row.
  final Widget? trailing;

  /// Rows; separated by hairlines automatically.
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: theme.textTheme.titleSmall),
                      if (subtitle != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(
                            subtitle!,
                            style: theme.textTheme.bodySmall,
                          ),
                        ),
                    ],
                  ),
                ),
                ?trailing,
              ],
            ),
          ),
          Card(
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                for (var i = 0; i < children.length; i++) ...[
                  if (i > 0) const Divider(),
                  children[i],
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A settings row with a tinted leading icon.
class SettingRow extends StatelessWidget {
  /// Creates a row.
  const SettingRow({
    required this.icon,
    required this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
    this.tint,
    super.key,
  });

  /// Leading icon.
  final IconData icon;

  /// Title.
  final String title;

  /// Subtitle.
  final String? subtitle;

  /// Trailing widget (switch, chevron, value).
  final Widget? trailing;

  /// Tap handler; adds a chevron when [trailing] is null.
  final VoidCallback? onTap;

  /// Icon tint; defaults to primary.
  final Color? tint;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final c = tint ?? scheme.primary;
    return ListTile(
      onTap: onTap,
      mouseCursor: onTap == null
          ? SystemMouseCursors.basic
          : SystemMouseCursors.click,
      leading: LeadingIcon(icon: icon, color: c),
      title: Text(title),
      subtitle: subtitle == null ? null : Text(subtitle!),
      trailing:
          trailing ??
          (onTap == null
              ? null
              : Icon(Icons.chevron_right_rounded, color: context.colors.muted)),
    );
  }
}

/// Icon in a tinted rounded square.
class LeadingIcon extends StatelessWidget {
  /// Creates the icon.
  const LeadingIcon({
    required this.icon,
    required this.color,
    this.size = 36,
    super.key,
  });

  /// Glyph.
  final IconData icon;

  /// Tint.
  final Color color;

  /// Container size.
  final double size;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(size * 0.28),
    ),
    child: Icon(icon, color: color, size: size * 0.55),
  );
}

/// A toggle row inside a [SectionCard].
class SwitchRow extends StatelessWidget {
  /// Creates a toggle row.
  const SwitchRow({
    required this.icon,
    required this.title,
    required this.value,
    required this.onChanged,
    this.subtitle,
    super.key,
  });

  /// Leading icon.
  final IconData icon;

  /// Title.
  final String title;

  /// Subtitle.
  final String? subtitle;

  /// Current value.
  final bool value;

  /// Change handler.
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) => SettingRow(
    icon: icon,
    title: title,
    subtitle: subtitle,
    onTap: () => onChanged(!value),
    trailing: Switch(value: value, onChanged: onChanged),
  );
}

/// Centers content and caps its width on wide screens.
class ContentColumn extends StatelessWidget {
  /// Creates the column.
  const ContentColumn({
    required this.child,
    this.maxWidth = AppTokens.contentMaxWidth,
    super.key,
  });

  /// Content.
  final Widget child;

  /// Width cap.
  final double maxWidth;

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.topCenter,
    child: ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth),
      child: child,
    ),
  );
}
