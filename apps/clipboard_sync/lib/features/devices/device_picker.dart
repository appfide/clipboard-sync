import 'package:clipboard_sync/features/devices/device_widgets.dart';
import 'package:clipboard_sync/ui/widgets/section_card.dart';
import 'package:clipsync_core/clipsync_core.dart';
import 'package:flutter/material.dart';

/// Devices a clip can be sent to: active, not expired, not this one, and
/// able to receive.
List<Device> sendTargets(List<Device> devices, String ownId) {
  final now = DateTime.now().toUtc();
  return devices
      .where(
        (d) =>
            d.id != ownId &&
            !d.isPending &&
            d.canSync(now) &&
            d.role.canReceive,
      )
      .toList();
}

/// Bottom sheet listing [devices]; resolves with the chosen id or `null`.
Future<String?> pickDevice(BuildContext context, List<Device> devices) =>
    showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Send to device',
                  style: Theme.of(ctx).textTheme.titleMedium,
                ),
              ),
            ),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final d in devices)
                    ListTile(
                      key: ValueKey('target-${d.id}'),
                      leading: LeadingIcon(
                        icon: platformIcon(d.platform),
                        color: Theme.of(ctx).colorScheme.primary,
                      ),
                      title: Text(d.name),
                      subtitle: Text(platformLabel(d.platform)),
                      onTap: () => Navigator.pop(ctx, d.id),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
