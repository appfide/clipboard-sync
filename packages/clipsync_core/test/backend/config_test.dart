import 'package:clipsync_core/clipsync_core.dart';
import 'package:test/test.dart';

void main() {
  group('ConfigField.validate', () {
    const url = ConfigField(key: 'u', label: 'URL', kind: ConfigFieldKind.url);
    const opt = ConfigField(
      key: 'o',
      label: 'Opt',
      kind: ConfigFieldKind.text,
      required: false,
    );
    const num = ConfigField(
      key: 'n',
      label: 'N',
      kind: ConfigFieldKind.integer,
    );
    const choice = ConfigField(
      key: 'c',
      label: 'C',
      kind: ConfigFieldKind.choice,
      choices: ['a', 'b'],
    );

    test(
      'required empty',
      () => expect(url.validate(''), contains('required')),
    );
    test('optional empty ok', () => expect(opt.validate(null), isNull));
    test('url needs scheme+host', () {
      expect(url.validate('example.com'), contains('absolute URL'));
      expect(url.validate('ftp://x.com'), contains('http'));
      expect(url.validate('https://ok.example.com'), isNull);
    });
    test('url rejects embedded credentials', () {
      expect(url.validate('https://u:p@x.com'), contains('credentials'));
    });
    test('integer', () {
      expect(num.validate('12'), isNull);
      expect(num.validate('x'), contains('whole number'));
    });
    test('choice', () {
      expect(choice.validate('a'), isNull);
      expect(choice.validate('z'), contains('one of'));
    });
  });

  group('BackendConfig', () {
    test('validates against descriptor and reports per-field', () {
      final cfg = const BackendConfig.empty(
        'supabase',
      ).set('url', 'nope').set('anon_key', 'k');
      final errors = cfg.validate(SupabaseBackend.descriptorStatic);
      expect(errors.keys, contains('url'));
      expect(errors.keys, isNot(contains('anon_key')));
      expect(errors.keys, isNot(contains('email')));
    });

    test('typed accessors', () {
      final cfg = const BackendConfig.empty(
        'x',
      ).set('a', ' 5 ').set('b', 'true').set('u', 'https://h/');
      expect(cfg.intOr('a', 0), 5);
      expect(cfg.boolOr('b', fallback: false), isTrue);
      expect(cfg.boolOr('zz', fallback: true), isTrue);
      expect(cfg.url('u'), 'https://h');
      expect(() => cfg.require('missing'), throwsStateError);
    });
  });

  group('BackendRegistry', () {
    test('built-in registry exposes every adapter', () {
      final r = BackendRegistry.builtIn();
      expect(
        r.descriptors.map((d) => d.id),
        containsAll([
          'supabase',
          'pocketbase',
          'couchdb',
          'firestore',
          'mongodb',
          'memory',
        ]),
      );
      expect(r.create('memory'), isA<MemoryBackend>());
      expect(() => r.create('nope'), throwsArgumentError);
    });

    test('every secret-looking field is flagged sensitive', () {
      for (final d in BackendRegistry.builtIn().descriptors) {
        for (final f in d.configSchema) {
          final looksSecret = RegExp(
            '(key|password|secret|token|uri)',
            caseSensitive: false,
          ).hasMatch(f.key);
          if (looksSecret) {
            expect(
              f.isSensitive,
              isTrue,
              reason: '${d.id}.${f.key} should be a secret field',
            );
          }
        }
      }
    });
  });
}
