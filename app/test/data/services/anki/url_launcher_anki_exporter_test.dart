import 'package:flutter_test/flutter_test.dart';
import 'package:yomitanuki/data/services/anki/anki_url.dart';
import 'package:yomitanuki/data/services/anki/url_launcher_anki_exporter.dart';
import 'package:yomitanuki/domain/models/anki_note.dart';

void main() {
  const note = AnkiNote(
    deck: 'Japanese::Frieren Vol. 1',
    noteType: 'Frieren Vocab (JP→EN)',
    fields: {'Word': '食べる'},
  );

  test('launches the addnote URL and reports handedOver', () async {
    final asked = <Uri>[];
    final launched = <Uri>[];
    final exporter = UrlLauncherAnkiExporter(
      canLaunch: (u) async {
        asked.add(u);
        return true;
      },
      launch: (u) async {
        launched.add(u);
        return true;
      },
    );

    final outcome = await exporter.add(note);

    expect(outcome, AnkiExportOutcome.handedOver);
    final expected = AnkiUrlBuilder(
      returnUrl: UrlLauncherAnkiExporter.defaultReturnUrl,
    ).addNote(note);
    expect(asked, [expected]);
    expect(launched, [expected]);
    expect(
      expected.toString(),
      endsWith('&x-success=yomitanuki%3A%2F%2Fanki-return'),
    );
  });

  test(
    'no handler for anki:// reports ankiNotInstalled, never launches',
    () async {
      var launches = 0;
      final exporter = UrlLauncherAnkiExporter(
        canLaunch: (_) async => false,
        launch: (_) async {
          launches++;
          return true;
        },
      );

      expect(await exporter.add(note), AnkiExportOutcome.ankiNotInstalled);
      expect(launches, 0);
    },
  );

  test('a launch the OS refuses reports ankiNotInstalled (D5.4)', () async {
    final exporter = UrlLauncherAnkiExporter(
      canLaunch: (_) async => true,
      launch: (_) async => false,
    );

    expect(await exporter.add(note), AnkiExportOutcome.ankiNotInstalled);
  });

  test('allowDuplicates and returnUrl reach the URL', () async {
    Uri? launched;
    final exporter = UrlLauncherAnkiExporter(
      allowDuplicates: true,
      returnUrl: Uri.parse('yomitanuki://custom'),
      canLaunch: (_) async => true,
      launch: (u) async {
        launched = u;
        return true;
      },
    );

    await exporter.add(note);

    expect(launched.toString(), contains('&dupes=1'));
    expect(
      launched.toString(),
      endsWith('&x-success=yomitanuki%3A%2F%2Fcustom'),
    );
  });
}
