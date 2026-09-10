import 'package:clipboard_sync/core/relative_time.dart';
import 'package:clipboard_sync/ui/app_theme.dart';
import 'package:clipboard_sync/ui/widgets/section_card.dart';
import 'package:clipsync_core/clipsync_core.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

/// Icon for a device platform wire value.
IconData platformIcon(String platform) => switch (platform) {
  'ios' => Icons.phone_iphone_rounded,
  'android' => Icons.phone_android_rounded,
  'macos' => Icons.laptop_mac_rounded,
  'windows' => Icons.desktop_windows_rounded,
  'linux' => Icons.computer_rounded,
  _ => Icons.devices_other_rounded,
};

/// Human label for a platform wire value.
String platformLabel(String platform) => switch (platform) {
  'ios' => 'iOS',
  'android' => 'Android',
  'macos' => 'macOS',
  'windows' => 'Windows',
  'linux' => 'Linux',
  '' => 'Not connected yet',
  _ => platform,
};

/// Options offered for membership expiry, in the order shown.
final Map<Duration?, String> accessDurations = {
  null: 'No expiry',
  const Duration(hours: 1): '1 hour',
  const Duration(hours: 24): '24 hours',
  const Duration(days: 7): '7 days',
  const Duration(days: 30): '30 days',
};

/// Small tinted label.
class Chip2 extends StatelessWidget {
  /// Creates the chip.
  const Chip2(this.label, {required this.color, this.icon, super.key});

  /// Text.
  final String label;

  /// Tint.
  final Color color;

  /// Optional leading glyph.
  final IconData? icon;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.10),
      borderRadius: BorderRadius.circular(999),
      border: Border.all(color: color.withValues(alpha: 0.25)),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null) ...[
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
        ],
        Text(
          label,
          style: Theme.of(
            context,
          ).textTheme.labelSmall?.copyWith(color: color),
        ),
      ],
    ),
  );
}

/// One device in the list with its status chips and actions menu.
class DeviceTile extends StatelessWidget {
  /// Creates the tile.
  const DeviceTile({
    required this.device,
    required this.isSelf,
    this.onAction,
    super.key,
  });

  /// The device.
  final Device device;

  /// Whether this row is the current device.
  final bool isSelf;

  /// Menu handler; `null` hides the menu.
  final void Function(String action)? onAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final c = context.colors;
    final now = DateTime.now().toUtc();
    final d = device;
    final online = !d.isPending && d.isOnline(now);
    final tint = switch (d.status) {
      DeviceStatus.blocked => scheme.error,
      DeviceStatus.removed => c.muted,
      DeviceStatus.active =>
        d.isExpired(now) ? c.warning : (online ? c.success : scheme.primary),
    };

    final chips = <Widget>[
      if (isSelf)
        Chip2('This device', color: scheme.primary, icon: Icons.star_rounded),
      if (d.isPending)
        Chip2(
          'Invited · waiting',
          color: c.warning,
          icon: Icons.hourglass_top_rounded,
        ),
      if (d.status == DeviceStatus.blocked)
        Chip2('Blocked', color: scheme.error, icon: Icons.block_rounded),
      if (d.status == DeviceStatus.removed)
        Chip2('Removed', color: c.muted, icon: Icons.person_remove_rounded),
      if (d.role != DeviceRole.full)
        Chip2(
          d.role.label,
          color: c.muted,
          icon: d.role == DeviceRole.sendOnly
              ? Icons.upload_rounded
              : Icons.download_rounded,
        ),
      if (d.expiresAt != null)
        Chip2(
          d.isExpired(now)
              ? 'Access expired'
              : 'Expires in ${RelativeTime.until(d.expiresAt!, now: now)}',
          color: d.isExpired(now) ? c.warning : c.muted,
          icon: Icons.schedule_rounded,
        ),
    ];

    final presence = d.isPending
        ? 'Not connected yet'
        : '${online ? 'Online' : 'Last seen ${RelativeTime.ago(d.lastSeen, now: now)}'}'
              ' · ${platformLabel(d.platform)}'
              '${d.appVersion != null && d.appVersion != 'dev' ? ' · v${d.appVersion}' : ''}';

    return ListTile(
      key: ValueKey('device-${d.id}'),
      leading: LeadingIcon(icon: platformIcon(d.platform), color: tint),
      title: Text(d.name.isEmpty ? 'Unnamed device' : d.name),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(presence),
          if (chips.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Wrap(spacing: 6, runSpacing: 4, children: chips),
            ),
        ],
      ),
      isThreeLine: chips.isNotEmpty,
      trailing: onAction == null
          ? null
          : PopupMenuButton<String>(
              key: ValueKey('device-menu-${d.id}'),
              tooltip: 'Manage',
              icon: const Icon(Icons.more_horiz_rounded),
              onSelected: onAction,
              itemBuilder: (_) => [
                if (d.status == DeviceStatus.blocked)
                  const PopupMenuItem(
                    value: 'unblock',
                    child: _MenuRow(
                      Icons.check_circle_outline_rounded,
                      'Unblock',
                    ),
                  )
                else if (d.status == DeviceStatus.active)
                  const PopupMenuItem(
                    value: 'block',
                    child: _MenuRow(Icons.block_rounded, 'Block'),
                  ),
                if (d.status != DeviceStatus.removed) ...[
                  const PopupMenuItem(
                    value: 'role',
                    child: _MenuRow(Icons.swap_vert_rounded, 'Change role…'),
                  ),
                  const PopupMenuItem(
                    value: 'expiry',
                    child: _MenuRow(Icons.schedule_rounded, 'Access duration…'),
                  ),
                  const PopupMenuDivider(),
                  PopupMenuItem(
                    value: 'remove',
                    child: _MenuRow(
                      Icons.person_remove_rounded,
                      'Remove',
                      color: scheme.error,
                    ),
                  ),
                ],
                if (d.status == DeviceStatus.removed || d.isPending)
                  PopupMenuItem(
                    value: 'forget',
                    child: _MenuRow(
                      Icons.delete_forever_rounded,
                      'Forget',
                      color: scheme.error,
                    ),
                  ),
              ],
            ),
    );
  }
}

class _MenuRow extends StatelessWidget {
  const _MenuRow(this.icon, this.label, {this.color});
  final IconData icon;
  final String label;
  final Color? color;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Icon(icon, size: 18, color: color ?? context.colors.muted),
      const SizedBox(width: 10),
      Text(label, style: TextStyle(color: color)),
    ],
  );
}

/// Explains that enforcement is cooperative, with a link to the docs.
class EnforcementNote extends StatelessWidget {
  /// Creates the note.
  const EnforcementNote({super.key});

  /// Docs page.
  static final Uri docsUrl = Uri.parse(
    'https://github.com/appfide/clipboard-sync/blob/main/docs/devices.md',
  );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = context.colors;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: c.surfaceSunken,
        borderRadius: BorderRadius.circular(AppTokens.radius),
        border: Border.all(color: c.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline_rounded, size: 18, color: c.muted),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Every device holds the same database credentials. Block, remove and expiry are honoured by the app on each device — the database itself does not enforce them.',
                  style: theme.textTheme.bodySmall,
                ),
                TextButton(
                  style: TextButton.styleFrom(
                    padding: EdgeInsets.zero,
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  onPressed: () =>
                      launchUrl(docsUrl, mode: LaunchMode.externalApplication),
                  child: const Text('How device access works'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Picks a [DeviceRole].
Future<DeviceRole?> pickRole(BuildContext context, DeviceRole current) =>
    showDialog<DeviceRole>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Device role'),
        children: [
          RadioGroup<DeviceRole>(
            groupValue: current,
            onChanged: (v) => Navigator.pop(ctx, v),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final r in DeviceRole.values)
                  RadioListTile<DeviceRole>(
                    key: ValueKey('role-${r.wire}'),
                    value: r,
                    title: Text(r.label),
                    subtitle: Text(switch (r) {
                      DeviceRole.full =>
                        'Shares its clipboard and receives everything.',
                      DeviceRole.sendOnly =>
                        'Pushes what it copies; never sees the shared history.',
                      DeviceRole.receiveOnly =>
                        'Receives clips; what it copies stays on that device.',
                    }),
                  ),
              ],
            ),
          ),
        ],
      ),
    );

/// Picks an access duration; returns the chosen [Duration] or `null` for
/// "no expiry". The outer `null` means cancelled.
Future<(Duration?,)?> pickAccessDuration(BuildContext context) =>
    showDialog<(Duration?,)>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Access duration'),
        children: [
          for (final e in accessDurations.entries)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, (e.key,)),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Text(e.value),
              ),
            ),
        ],
      ),
    );

/// Yes / no confirmation.
Future<bool> confirm(
  BuildContext context, {
  required String title,
  required String message,
  String action = 'Continue',
  bool destructive = false,
}) async {
  final scheme = Theme.of(context).colorScheme;
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Text(message),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          style: destructive
              ? FilledButton.styleFrom(backgroundColor: scheme.error)
              : null,
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(action),
        ),
      ],
    ),
  );
  return ok ?? false;
}
