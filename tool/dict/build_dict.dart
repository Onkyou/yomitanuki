// Builds app/assets/dict/dictionary.sqlite from pinned jmdict-simplified
// releases (PLAN.md §1 data sources, .claude/wp3/NOTES.md D3.2).
//
//   make dict          (from the repo root; builds when absent or stale)
//   cd tool/dict && dart run build_dict.dart --out <sqlite> --downloads <dir>
//
// Each source is downloaded once into --downloads (gitignored, data only),
// verified against the sha256 pinned below, unzipped in memory, decoded and
// handed to DictBuilder. The downloaded files are never executed or opened
// by anything but the JSON decoder.
import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:yomitanuki/data/services/dictionary/dict_builder.dart';

/// One pinned upstream release asset.
class Source {
  const Source({
    required this.name,
    required this.release,
    required this.fileName,
    required this.sha256,
  });

  final String name;
  final String release;
  final String fileName;
  final String sha256;

  Uri get url => Uri.parse(
    'https://github.com/scriptin/jmdict-simplified/releases/download/'
    '${Uri.encodeComponent(release)}/${Uri.encodeComponent(fileName)}',
  );
}

const release = '3.6.2+20261012204142';

const jmdict = Source(
  name: 'jmdict',
  release: release,
  fileName: 'jmdict-eng-$release.json.zip',
  sha256: '9a04fc1d0facf87645f8ec7cdaa370647d4a8f59131f6e2a614bcd680f855b85',
);

const kanjidic = Source(
  name: 'kanjidic',
  release: release,
  fileName: 'kanjidic2-en-$release.json.zip',
  sha256: '55e83fe744ca681075ef97772f9cafeab761fabbe3d8d7f1015638136e0ac837',
);

Future<void> main(List<String> args) async {
  final options = _parse(args);
  final out = options['--out'];
  final downloads = options['--downloads'];
  if (out == null || downloads == null) {
    stderr.writeln(
      'usage: dart run build_dict.dart --out <sqlite> --downloads <dir>',
    );
    exitCode = 2;
    return;
  }
  final started = Stopwatch()..start();
  Directory(downloads).createSync(recursive: true);
  Directory(p.dirname(out)).createSync(recursive: true);

  final jmdictJson = await _fetchJson(jmdict, downloads);
  final kanjidicJson = await _fetchJson(kanjidic, downloads);
  stdout.writeln('decoded both sources in ${started.elapsed}');

  final stats = DictBuilder.build(
    jmdict: jmdictJson,
    kanjidic: kanjidicJson,
    outPath: out,
    meta: {
      'jmdict_release': jmdict.release,
      'jmdict_sha256': jmdict.sha256,
      'kanjidic_release': kanjidic.release,
      'kanjidic_sha256': kanjidic.sha256,
    },
  );
  // The stamp names the pins, the schema and the built file's own hash, so a
  // rebuild under the same pins (new builder, new rule) is still recopied
  // on device (BundledDictionaryAsset compares the whole string).
  final built = File(out).readAsBytesSync();
  final version =
      'jmdict ${jmdict.release} kanjidic ${kanjidic.release} '
      'schema ${DictBuilder.schemaVersion} sha256 ${sha256.convert(built)}';
  File('${p.withoutExtension(out)}.version').writeAsStringSync(version);

  final bytes = built.length;
  stdout
    ..writeln('wrote $out')
    ..writeln('  $stats')
    ..writeln(
      '  ${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB in ${started.elapsed}',
    )
    ..writeln('  version: $version');
}

Map<String, String> _parse(List<String> args) {
  final options = <String, String>{};
  for (var i = 0; i + 1 < args.length; i += 2) {
    options[args[i]] = args[i + 1];
  }
  return options;
}

Future<Map<String, Object?>> _fetchJson(Source source, String downloads) async {
  final file = File(p.join(downloads, source.fileName));
  if (!file.existsSync()) {
    stdout.writeln('downloading ${source.url}');
    await _download(source.url, file);
  }
  final bytes = file.readAsBytesSync();
  final digest = sha256.convert(bytes).toString();
  if (digest != source.sha256) {
    throw StateError(
      '${file.path}: sha256 $digest does not match the pin ${source.sha256}; '
      'delete the file to re-download, or update the pin deliberately.',
    );
  }
  stdout.writeln('${source.name}: ${file.path} verified');
  final archive = ZipDecoder().decodeBytes(bytes);
  final entry = archive.files.singleWhere(
    (f) => f.isFile && f.name.endsWith('.json'),
  );
  final content = entry.readBytes();
  if (content == null) {
    throw StateError('${file.path}: ${entry.name} has no content');
  }
  return json.fuse(utf8).decode(content) as Map<String, Object?>;
}

Future<void> _download(Uri url, File target) async {
  final client = HttpClient();
  try {
    final request = await client.getUrl(url);
    final response = await request.close();
    if (response.statusCode != HttpStatus.ok) {
      throw HttpException('HTTP ${response.statusCode}', uri: url);
    }
    final partial = File('${target.path}.part');
    final sink = partial.openWrite();
    await sink.addStream(response);
    await sink.close();
    partial.renameSync(target.path);
  } finally {
    client.close();
  }
}
