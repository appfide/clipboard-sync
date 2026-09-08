@Tags(['live'])
library;

import 'dart:io';

import 'package:clipsync_core/clipsync_core.dart';
import 'package:test/test.dart';

import 'backend_contract.dart';

/// Runs the contract suite against real databases. Skipped unless the
/// matching env vars are set, e.g.
///
/// ```sh
/// CLIPSYNC_TEST_SUPABASE_URL=https://xxx.supabase.co \
/// CLIPSYNC_TEST_SUPABASE_ANON_KEY=... dart test -t live
/// ```
///
/// Never commit these values; CI does not run this file.
void main() {
  final env = Platform.environment;

  BackendConfig? cfg(String id, Map<String, String> keys) {
    final values = <String, String>{};
    for (final e in keys.entries) {
      final v = env['CLIPSYNC_TEST_${id.toUpperCase()}_${e.key.toUpperCase()}'];
      if (v != null) values[e.key] = v;
    }
    final missing = keys.entries.where(
      (e) => e.value == 'required' && !values.containsKey(e.key),
    );
    if (missing.isNotEmpty) return null;
    return BackendConfig(backendId: id, values: values);
  }

  final registry = BackendRegistry.builtIn();
  final specs = <String, (Map<String, String>, bool)>{
    'supabase': (
      {
        'url': 'required',
        'anon_key': 'required',
        'email': 'optional',
        'password': 'optional',
      },
      true,
    ),
    'pocketbase': (
      {
        'url': 'required',
        'identity': 'optional',
        'password': 'optional',
        'auth_collection': 'optional',
      },
      true,
    ),
    'couchdb': (
      {
        'url': 'required',
        'username': 'required',
        'password': 'required',
        'database': 'optional',
      },
      true,
    ),
    'firestore': (
      {
        'project_id': 'required',
        'api_key': 'required',
        'email': 'optional',
        'password': 'optional',
      },
      false,
    ),
    'mongodb': ({'uri': 'required'}, false),
  };

  for (final e in specs.entries) {
    final c = cfg(e.key, e.value.$1);
    if (c == null) {
      test(
        '${e.key} live (skipped: env not set)',
        () {},
        skip: 'set CLIPSYNC_TEST_${e.key.toUpperCase()}_* to run',
      );
      continue;
    }
    runBackendContractTests(
      e.key,
      () async {
        final b = registry.create(e.key);
        await b.connect(c);
        return b;
      },
      realtime: e.value.$2,
    );
  }
}
