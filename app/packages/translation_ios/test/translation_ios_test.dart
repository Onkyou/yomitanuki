import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:translation_ios/translation_ios.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('yomitanuki/translation');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  late List<MethodCall> calls;

  void answer(Object? Function(MethodCall call) handler) {
    calls = [];
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return handler(call);
    });
  }

  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  group('status', () {
    const expected = {
      'installed': TranslationIosStatus.installed,
      'supported': TranslationIosStatus.supported,
      'unsupported': TranslationIosStatus.unsupported,
      'requiresNewerOs': TranslationIosStatus.requiresNewerOs,
    };

    for (final MapEntry(key: wire, value: status) in expected.entries) {
      test('"$wire" is $status', () async {
        answer((_) => wire);

        expect(await TranslationIos().status(), status);
        expect(calls.single.method, 'status');
      });
    }

    test('a string the plugin does not know is unsupported', () async {
      answer((_) => 'somethingNew');

      expect(await TranslationIos().status(), TranslationIosStatus.unsupported);
    });

    test('a PlatformException propagates', () async {
      answer((_) => throw PlatformException(code: 'boom'));

      await expectLater(
        TranslationIos().status(),
        throwsA(isA<PlatformException>().having((e) => e.code, 'code', 'boom')),
      );
    });
  });

  group('translate', () {
    test('passes the lines through and returns the list', () async {
      answer((_) => <Object?>['hello', null, 'bye']);

      final out = await TranslationIos().translate(['a', 'b', 'c']);

      expect(out, ['hello', null, 'bye']);
      expect(calls.single.method, 'translate');
      expect(calls.single.arguments, {
        'lines': ['a', 'b', 'c'],
      });
    });

    test('a null answer is a list of nulls as long as the input', () async {
      answer((_) => null);

      expect(await TranslationIos().translate(['a', 'b']), [null, null]);
    });

    test('a PlatformException propagates with its code', () async {
      answer(
        (_) => throw PlatformException(code: 'notInstalled', message: 'no'),
      );

      await expectLater(
        TranslationIos().translate(['a']),
        throwsA(
          isA<PlatformException>().having(
            (e) => e.code,
            'code',
            'notInstalled',
          ),
        ),
      );
    });

    test('a channel can be injected', () async {
      const other = MethodChannel('elsewhere');
      messenger.setMockMethodCallHandler(other, (_) async => 'installed');
      addTearDown(() => messenger.setMockMethodCallHandler(other, null));

      expect(
        await TranslationIos(channel: other).status(),
        TranslationIosStatus.installed,
      );
    });
  });
}
