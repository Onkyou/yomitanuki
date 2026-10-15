import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:translation_ios/translation_ios.dart';
import 'package:yomitanuki/data/services/translation/apple_sentence_translator.dart';
import 'package:yomitanuki/domain/errors.dart';
import 'package:yomitanuki/domain/models/translation_status.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('test/translation');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late List<MethodCall> calls;
  late AppleSentenceTranslator translator;

  void answer(Object? Function(MethodCall call) handler) {
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return handler(call);
    });
  }

  setUp(() {
    calls = [];
    translator = AppleSentenceTranslator(TranslationIos(channel: channel));
  });

  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  group('status', () {
    const expected = {
      'installed': TranslationStatus.installed,
      'supported': TranslationStatus.downloadNeeded,
      'unsupported': TranslationStatus.unsupported,
      'requiresNewerOs': TranslationStatus.requiresNewerOs,
    };
    for (final MapEntry(key: wire, value: status) in expected.entries) {
      test('"$wire" is $status', () async {
        answer((_) => wire);

        expect(await translator.status(), status);
      });
    }
  });

  group('translate', () {
    test('sends the one line and returns its translation', () async {
      answer((_) => <Object?>['Are you coming?']);

      expect(await translator.translate('来るの？'), 'Are you coming?');
      expect(calls.single.arguments, {
        'lines': ['来るの？'],
      });
    });

    for (final line in ['', '  ', '　\n']) {
      test(
        'a blank line (${line.length} chars) is empty without a call',
        () async {
          answer((_) => fail('the channel must not be called'));

          expect(await translator.translate(line), '');
          expect(calls, isEmpty);
        },
      );
    }

    test('notInstalled means the pack must be downloaded', () async {
      answer((_) => throw PlatformException(code: 'notInstalled'));

      await expectLater(
        translator.translate('こんにちは'),
        throwsA(
          isA<TranslationUnavailableError>().having(
            (e) => e.status,
            'status',
            TranslationStatus.downloadNeeded,
          ),
        ),
      );
    });

    test('requiresNewerOs means iOS 26 is needed', () async {
      answer((_) => throw PlatformException(code: 'requiresNewerOs'));

      await expectLater(
        translator.translate('こんにちは'),
        throwsA(
          isA<TranslationUnavailableError>().having(
            (e) => e.status,
            'status',
            TranslationStatus.requiresNewerOs,
          ),
        ),
      );
    });

    test('any other platform error is a failed translation', () async {
      answer(
        (_) => throw PlatformException(
          code: 'translationFailed',
          message: 'internal',
        ),
      );

      await expectLater(
        translator.translate('こんにちは'),
        throwsA(
          isA<TranslationFailedError>().having(
            (e) => e.reason,
            'reason',
            allOf(contains('translationFailed'), contains('internal')),
          ),
        ),
      );
    });

    test('an empty answer is a failed translation', () async {
      answer((_) => <Object?>[]);

      await expectLater(
        translator.translate('こんにちは'),
        throwsA(isA<TranslationFailedError>()),
      );
    });

    test('no translation for the line is a failed translation', () async {
      answer((_) => <Object?>[null]);

      await expectLater(
        translator.translate('こんにちは'),
        throwsA(isA<TranslationFailedError>()),
      );
    });
  });
}
