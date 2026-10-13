import 'package:flutter_test/flutter_test.dart';

import 'fake_dictionary.dart';

void main() {
  test(
    'matches headwords and readings from the index, longest first',
    () async {
      final dict = FakeDictionary();

      final results = await dict.lookupAt('魔王の本', 0);

      expect(results.map((r) => r.surface).toList(), ['魔王']);
      expect((await dict.lookupAt('魔王の本', 3)).single.entry.headword, '本');
      expect((await dict.lookupAt('たべる', 0)).single.entry.id, 1358280);
      expect(await dict.lookupAt('xyz', 0), isEmpty);
      expect(dict.lookups, hasLength(4));
    },
  );

  test('kanji come from the map', () async {
    final dict = FakeDictionary();

    expect((await dict.kanji('食'))!.grade, 2);
    expect(await dict.kanji('本'), isNull);
  });
}
