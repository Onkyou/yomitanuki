import 'package:flutter_test/flutter_test.dart';
import 'package:yomitanuki/data/services/anki/anki_url.dart';
import 'package:yomitanuki/domain/models/anki_note.dart';

void main() {
  final returnUrl = Uri.parse('yomitanuki://anki-return');
  final builder = AnkiUrlBuilder(returnUrl: returnUrl);

  test('ASCII note: the documented addnote shape, x-success last', () {
    const note = AnkiNote(
      deck: 'Default',
      noteType: 'Basic',
      fields: {'Front': 'front text', 'Back': 'back text'},
      tags: ['manga', 'frieren'],
    );

    expect(
      builder.addNote(note).toString(),
      'anki://x-callback-url/addnote'
      '?type=Basic'
      '&deck=Default'
      '&fldFront=front%20text'
      '&fldBack=back%20text'
      '&tags=manga%20frieren'
      '&x-success=yomitanuki%3A%2F%2Fanki-return',
    );
  });

  test('Japanese note: UTF-8 percent-encoding of every byte', () {
    const note = AnkiNote(
      deck: 'Japanese::Frieren Vol. 1',
      noteType: 'Frieren Vocab (JP→EN)',
      fields: {
        'Word': '食べる',
        'Reading': 'たべる',
        'Meaning': 'to eat; to have a meal',
        'Example': 'パンを食べる。',
      },
    );

    expect(
      builder.addNote(note).toString(),
      'anki://x-callback-url/addnote'
      '?type=Frieren%20Vocab%20%28JP%E2%86%92EN%29'
      '&deck=Japanese%3A%3AFrieren%20Vol.%201'
      '&fldWord=%E9%A3%9F%E3%81%B9%E3%82%8B'
      '&fldReading=%E3%81%9F%E3%81%B9%E3%82%8B'
      '&fldMeaning=to%20eat%3B%20to%20have%20a%20meal'
      '&fldExample=%E3%83%91%E3%83%B3%E3%82%92%E9%A3%9F%E3%81%B9%E3%82%8B%E3%80%82'
      '&x-success=yomitanuki%3A%2F%2Fanki-return',
    );
  });

  test('every value round-trips through Uri.queryParameters', () {
    const note = AnkiNote(
      deck: 'Japanese::Frieren Vol. 1',
      noteType: 'Frieren Vocab (JP→EN)',
      fields: {'Word': '食べる', 'Meaning': "a & b = c? #1 + 100% (yes!) *'~"},
      tags: ['x', 'y'],
    );

    final q = builder.addNote(note).queryParameters;

    expect(q['type'], 'Frieren Vocab (JP→EN)');
    expect(q['deck'], 'Japanese::Frieren Vol. 1');
    expect(q['fldWord'], '食べる');
    expect(q['fldMeaning'], "a & b = c? #1 + 100% (yes!) *'~");
    expect(q['tags'], 'x y');
    expect(q['x-success'], 'yomitanuki://anki-return');
  });

  test('only RFC 3986 unreserved characters are left bare', () {
    const note = AnkiNote(
      deck: 'd',
      noteType: 't',
      fields: {'F': "AZaz09-._~ ::()→!*'&=+#/?%"},
    );

    expect(
      builder.addNote(note).toString(),
      contains(
        '&fldF=AZaz09-._~%20%3A%3A%28%29%E2%86%92%21%2A%27%26%3D%2B%23%2F%3F%25',
      ),
    );
  });

  test(
    'an empty field, empty tags and the default dupes policy are omitted',
    () {
      const note = AnkiNote(
        deck: 'd',
        noteType: 't',
        fields: {'Word': 'w', 'ExampleEN': '', 'Note': ''},
      );

      final url = builder.addNote(note).toString();

      expect(
        url,
        'anki://x-callback-url/addnote?type=t&deck=d&fldWord=w'
        '&x-success=yomitanuki%3A%2F%2Fanki-return',
      );
      expect(url, isNot(contains('dupes')));
      expect(url, isNot(contains('tags')));
    },
  );

  test('allowDuplicates adds dupes=1 (D5.2)', () {
    final permissive = AnkiUrlBuilder(
      returnUrl: returnUrl,
      allowDuplicates: true,
    );
    const note = AnkiNote(deck: 'd', noteType: 't', fields: {'Word': 'w'});

    expect(
      permissive.addNote(note).toString(),
      'anki://x-callback-url/addnote?type=t&deck=d&fldWord=w&dupes=1'
      '&x-success=yomitanuki%3A%2F%2Fanki-return',
    );
  });
}
