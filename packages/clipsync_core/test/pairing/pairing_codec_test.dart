import 'package:clipsync_core/clipsync_core.dart';
import 'package:test/test.dart';

void main() {
  final issued = DateTime.utc(2026, 9, 10, 12);
  final payload = PairingPayload(
    backendId: 'supabase',
    values: const {
      'url': 'https://abc.supabase.co',
      'anon_key': 'sb_publishable_xxxxxxxxxxxxxxxxxxxxxxxx',
      'email': 'me@example.com',
      'password': 'hunter2',
    },
    deviceId: '11111111-1111-4111-8111-111111111111',
    issuedAt: issued,
    validUntil: issued.add(const Duration(minutes: 5)),
    hostDeviceId: 'host',
    hostDeviceName: 'MacBook',
    passphrase: 'correct horse',
    role: DeviceRole.sendOnly,
    expiresAt: issued.add(const Duration(days: 1)),
  );

  test('pin generation and formatting', () {
    final pin = PairingCodec.generatePin();
    expect(pin, matches(RegExp(r'^\d{8}$')));
    expect(PairingCodec.formatPin('12345678'), '1234 5678');
    expect(PairingCodec.validatePin('1234 5678'), isNull);
    expect(PairingCodec.validatePin('1234'), isNotNull);
    expect(PairingCodec.validatePin('abcdefgh'), isNotNull);
  });

  test('seal → open round-trip keeps every field', () async {
    final code = await PairingCodec.seal(payload, '12345678');
    expect(PairingCodec.looksLikeCode(code), isTrue);
    expect(code, isNot(contains('hunter2')));
    expect(code, isNot(contains('supabase')));
    final back = await PairingCodec.open(
      code,
      '1234 5678',
      now: issued.add(const Duration(minutes: 1)),
    );
    expect(back.backendId, 'supabase');
    expect(back.values, payload.values);
    expect(back.deviceId, payload.deviceId);
    expect(back.passphrase, 'correct horse');
    expect(back.role, DeviceRole.sendOnly);
    expect(back.expiresAt, payload.expiresAt);
    expect(back.hostDeviceName, 'MacBook');
    expect(back.validUntil, payload.validUntil);
  });

  test('wrong PIN is rejected', () async {
    final code = await PairingCodec.seal(payload, '12345678');
    expect(
      () => PairingCodec.open(code, '12345679'),
      throwsA(
        isA<PairingException>().having(
          (e) => e.message,
          'message',
          contains('Wrong PIN'),
        ),
      ),
    );
  });

  test('stale code is rejected when now is given', () async {
    final code = await PairingCodec.seal(payload, '12345678');
    expect(
      () => PairingCodec.open(
        code,
        '12345678',
        now: issued.add(const Duration(minutes: 10)),
      ),
      throwsA(
        isA<PairingException>().having(
          (e) => e.message,
          'message',
          contains('expired'),
        ),
      ),
    );
    // Within skew tolerance it still opens.
    await PairingCodec.open(
      code,
      '12345678',
      now: issued.add(const Duration(minutes: 6)),
    );
  });

  test('foreign or damaged input fails cleanly', () async {
    expect(
      () => PairingCodec.open('hello', '12345678'),
      throwsA(isA<PairingException>()),
    );
    expect(
      () => PairingCodec.open('${PairingCodec.prefix}not-base64!!', '12345678'),
      throwsA(isA<PairingException>()),
    );
    final code = await PairingCodec.seal(payload, '12345678');
    final damaged = code.substring(0, code.length - 6);
    expect(
      () => PairingCodec.open(damaged, '12345678'),
      throwsA(isA<PairingException>()),
    );
  });

  test('payload from a newer format version is refused', () {
    expect(
      () => PairingPayload.fromJson(const {'v': 99}),
      throwsA(
        isA<PairingException>().having(
          (e) => e.message,
          'message',
          contains('newer'),
        ),
      ),
    );
  });
}
