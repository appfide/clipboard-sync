import 'package:clipboard_sync/app/router.dart';
import 'package:clipboard_sync/providers.dart';
import 'package:clipboard_sync/ui/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Root widget.
class ClipboardSyncApp extends ConsumerWidget {
  /// Creates the app.
  const ClipboardSyncApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);
    final mode = switch (ref.watch(
      settingsProvider.select((s) => s.themeMode),
    )) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      _ => ThemeMode.system,
    };
    return MaterialApp.router(
      title: 'Clipboard Sync',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: mode,
      routerConfig: router,
    );
  }
}
