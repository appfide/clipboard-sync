import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nija/app/router.dart';
import 'package:nija/providers.dart';
import 'package:nija/ui/app_theme.dart';

/// Root widget.
class NijaApp extends ConsumerWidget {
  /// Creates the app.
  const NijaApp({super.key});

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
      title: 'Nija',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: mode,
      routerConfig: router,
    );
  }
}
