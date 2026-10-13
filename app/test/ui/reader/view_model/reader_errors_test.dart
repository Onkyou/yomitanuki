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

  test('unknown errors get a fixed sentence', () {
    expect(
      describeReaderError(StateError('secret path')),
      isNot(contains('secret path')),
    );
  });
}
