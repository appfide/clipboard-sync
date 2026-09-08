import 'package:clipsync_core/clipsync_core.dart';

import 'backend_contract.dart';

void main() {
  runBackendContractTests(
    'MemoryBackend',
    () async {
      final b = MemoryBackend();
      await b.connect(const BackendConfig.empty('memory'));
      return b;
    },
    realtime: true,
  );
}
