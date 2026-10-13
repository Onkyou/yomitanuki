import 'package:flutter_test/flutter_test.dart';
import 'package:yomitanuki/domain/errors.dart';
import 'package:yomitanuki/ui/reader/view_model/reader_errors.dart';

void main() {
  test('a missing dictionary names the fix, never the raw reason', () {
    final text = describeReaderError(
      const DictionaryUnavailableError('DictionaryAssetError: /private/x'),
    );

    expect(text, contains('make dict'));
    expect(text, isNot(contains('/private/x')));
  });

  test('missing OCR models name the fix, never the raw reason', () {
    final text = describeReaderError(
      const ModelsUnavailableError('ModelAssetsException: /private/models'),
    );

    expect(text, contains('make models'));
    expect(text, isNot(contains('/private/models')));
  });

  test('a failed inference pass invites a retry, without the cause', () {
    final text = describeReaderError(
      const InferenceFailedError('OrtException(fail [1]): /private/x'),
    );

    expect(text, 'Text recognition failed. Please try again.');
    expect(text, isNot(contains('/private/x')));
  });

  test('unknown errors get a fixed sentence', () {
    expect(
      describeReaderError(StateError('secret path')),
      isNot(contains('secret path')),
    );
  });
}
