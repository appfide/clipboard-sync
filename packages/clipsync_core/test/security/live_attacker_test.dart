// The signed-group threat model against a real database. Runs only with
// CLIPSYNC_TEST_SUPABASE_URL / _ANON_KEY set (`dart test -t live`). Every
// row it creates carries the `live-` prefix and is removed at the end.
@Tags(['live'])
library;

import 'dart:io';

import 'package:clipsync_core/clipsync_core.dart';
import 'package:supabase/supabase.dart' as sb;
import 'package:test/test.dart';
import 'package:uuid/uuid.dart';

import '../helpers/fakes.dart';

const _run = 'live';

class LiveNode {
  LiveNode._(this.id, this.name, this.backend, this.keys);

  static Future<LiveNode> create(
    BackendConfig cfg,
    String id,
    String name, {
    DeviceKeys? keys,
  }) async {
    final b = SupabaseBackend();
    await b.connect(cfg);
    return LiveNode._(id, name, b, keys ?? await DeviceKeys.generate());
  }

  final String id;
  final String name;
  final SupabaseBackend backend;
  final DeviceKeys keys;
  final FakeLocalStore store = FakeLocalStore();
  final Map<int, String> passphrases = {};
  final List<String> log = [];
  SyncEngine? engine;

  Future<SyncEngine> start({
    AdminKey? adminKey,
    String? trustedAdminPub,
    Map<int, String>? passphrases,
    bool encrypted = true,
  }) async {
    if (passphrases != null) this.passphrases.addAll(passphrases);
    final ring = await CipherRing.fromPassphrases(
      this.passphrases,
      keyScope: 'live',
    );
    final e = SyncEngine(
      backend: backend,
      store: store,
      device: Device(
        id: id,
        name: name,
        platform: 'test',
        lastSeen: DateTime.now().toUtc(),
      ),
      identity: keys,
      adminKey: adminKey,
      trustedAdminPub: trustedAdminPub,
      cipherRing: encrypted ? ring : null,
      onKeyReceived: (v, p) async {
        this.passphrases[v] = p;
        ring.add(v, await ClipCipher.fromPassphrase(p, keyScope: 'live'));
      },
      pollInterval: const Duration(hours: 1),
      heartbeatInterval: const Duration(hours: 1),
      logger: (m, {error}) => log.add(m),
    );
    await e.start();
    engine = e;
    return e;
  }

  Future<ClipItem> say(String text) async {
    final item = ClipItem.create(
      id: const Uuid().v4(),
      deviceId: id,
      deviceName: name,
      type: ClipContentType.text,
      content: text,
      contentHash: sha256Hex(text),
      sizeBytes: text.length,
      now: DateTime.now().toUtc(),
    );
    store.capture(item);
    await engine!.syncNow();
    return item;
  }

  Iterable<String> get received => store.items.values
      .where((i) => i.deviceId != id && !i.isDeleted)
      .map((i) => i.content);

  Future<void> stop() async {
    await engine?.dispose();
    await backend.dispose();
  }
}

void main() {
  final env = Platform.environment;
  final url = env['CLIPSYNC_TEST_SUPABASE_URL'];
  final key = env['CLIPSYNC_TEST_SUPABASE_ANON_KEY'];
  if (url == null || key == null) {
    test(
      'live attacker (skipped: env not set)',
      () {},
      skip: 'set CLIPSYNC_TEST_SUPABASE_*',
    );
    return;
  }
  final cfg = BackendConfig(
    backendId: 'supabase',
    values: {'url': url, 'anon_key': key},
  );
  // The attacker: raw database access with the same credentials.
  late sb.SupabaseClient raw;
  final ids = <String>[];
  String newId(String tag) {
    final id = '$_run-$tag-${const Uuid().v4().substring(0, 8)}';
    ids.add(id);
    return id;
  }

  setUpAll(() => raw = sb.SupabaseClient(url, key));
  tearDownAll(() async {
    if (ids.isNotEmpty) {
      await raw.from('clip_items').delete().inFilter('device_id', ids);
      await raw.from('devices').delete().inFilter('id', ids);
    }
    await raw.dispose();
  });

  test(
    'signed, encrypted group on Supabase resists database-side attacks',
    () async {
      const pass1 = 'live passphrase v1';
      final adminKey = await AdminKey.generate();
      final aId = newId('admin');
      final bId = newId('member');
      final mId = newId('rogue');

      final admin = await LiveNode.create(cfg, aId, 'Admin');
      await admin.start(
        adminKey: adminKey,
        trustedAdminPub: adminKey.publicKey,
        passphrases: {1: pass1},
      );
      await admin.engine!.secureGroup();
      expect(admin.engine!.status.selfVerified, isTrue);

      // Invite B with sealed passphrase; B joins and receives it.
      final bKeys = await DeviceKeys.generate();
      await admin.engine!.inviteDevice(
        id: bId,
        role: DeviceRole.full,
        signPub: bKeys.signPub,
        boxPub: bKeys.boxPub,
        passphrase: pass1,
      );
      final member = await LiveNode.create(cfg, bId, 'Phone', keys: bKeys);
      await member.start(trustedAdminPub: adminKey.publicKey);
      expect(member.passphrases, {1: pass1});
      expect(member.engine!.status.selfVerified, isTrue);

      // Honest traffic both ways; database holds only ciphertext + signatures.
      await admin.say('hello from admin');
      await member.engine!.syncNow();
      expect(member.received, ['hello from admin']);
      await member.say('hi from phone');
      await admin.engine!.syncNow();
      expect(admin.received, ['hi from phone']);
      final rows = await raw.from('clip_items').select().inFilter('device_id', [
        aId,
        bId,
      ]);
      for (final r in rows) {
        expect(r['encrypted'], isTrue);
        expect(r['sig'], isNotNull);
        expect(r['content'], isNot(contains('from')));
        expect(r['key_version'], 1);
      }

      // Attack 1: unsigned clip injected as the phone.
      final forgedId = const Uuid().v4();
      final now = DateTime.now().toUtc().toIso8601String();
      await raw.from('clip_items').insert({
        'id': forgedId,
        'device_id': bId,
        'device_name': 'Phone',
        'content_type': 'text',
        'content': 'forged',
        'content_hash': sha256Hex('forged'),
        'size_bytes': 6,
        'created_at': now,
        'updated_at': now,
      });
      await admin.engine!.syncNow();
      expect(admin.received, ['hi from phone']);
      expect(admin.log.any((l) => l.contains('rejected 1')), isTrue);

      // Attack 2: rogue device registers itself and sends signed clips.
      final rogue = await LiveNode.create(cfg, mId, 'Rogue');
      await rogue.start(trustedAdminPub: adminKey.publicKey, encrypted: false);
      expect(rogue.engine!.status.selfVerified, isFalse);
      await rogue.say('from rogue');
      await admin.engine!.syncNow();
      await member.engine!.syncNow();
      expect(admin.received, isNot(contains('from rogue')));
      expect(member.received, isNot(contains('from rogue')));

      // Attack 3: block the phone by editing its row (no admin key).
      await raw.from('devices').update({'status': 'blocked'}).eq('id', bId);
      await member.engine!.refreshDevices();
      expect(
        member.engine!.isRunning,
        isTrue,
        reason: 'unsigned block ignored',
      );
      await admin.engine!.unblockDevice(bId); // admin re-signs the truth
      expect(admin.engine!.trustedDevices.containsKey(bId), isTrue);

      // Attack 4: genuine block, then restore the old signed row (rollback).
      final oldRow = await raw.from('devices').select().eq('id', bId).single();
      await admin.engine!.blockDevice(bId);
      await member.engine!.refreshDevices();
      expect(member.engine!.status.phase, SyncPhase.revoked);
      await raw.from('devices').upsert(oldRow, onConflict: 'id');
      await admin.engine!.refreshDevices();
      expect(admin.engine!.trustedDevices.containsKey(bId), isFalse);
      expect(admin.log.any((l) => l.contains('rolled-back')), isTrue);

      // Rotation: a new member gets v2; the blocked phone does not.
      final cId = newId('member2');
      final cKeys = await DeviceKeys.generate();
      await admin.engine!.inviteDevice(
        id: cId,
        role: DeviceRole.full,
        signPub: cKeys.signPub,
        boxPub: cKeys.boxPub,
        passphrase: pass1,
      );
      final c = await LiveNode.create(cfg, cId, 'Laptop', keys: cKeys);
      await c.start(trustedAdminPub: adminKey.publicKey);
      final issued = await admin.engine!.rotatePassphrase('live passphrase v2');
      expect(issued, 2, reason: 'admin + laptop');
      await c.engine!.refreshDevices();
      expect(c.passphrases[2], 'live passphrase v2');
      await admin.say('after rotation');
      await c.engine!.syncNow();
      expect(c.received, contains('after rotation'));
      final blockedRow = await raw
          .from('devices')
          .select()
          .eq('id', bId)
          .single();
      expect(blockedRow['key_version'], 1);
      // A rogue copy of the phone holding v1 cannot read v2.
      final rogueB = await LiveNode.create(cfg, bId, 'Phone', keys: bKeys);
      await raw.from('devices').update({'status': 'active'}).eq('id', bId);
      await rogueB.start(passphrases: {1: pass1});
      await rogueB.engine!.syncNow();
      expect(rogueB.received, isNot(contains('after rotation')));
      expect(rogueB.log.any((l) => l.contains('no key v2')), isTrue);

      for (final n in [rogueB, c, rogue, member, admin]) {
        await n.stop();
      }
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
