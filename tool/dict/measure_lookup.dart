// Measures SqliteDictionary.lookupAt on a built dictionary (D3.6 numbers in
// .claude/wp3/NOTES.md).
//
//   cd tool/dict && dart run measure_lookup.dart --sqlite ../../app/assets/dict/dictionary.sqlite
//   cd tool/dict && dart run measure_lookup.dart --jmdict <mini.json> --kanjidic <mini.json>
//
// With --jmdict/--kanjidic the dictionary is built into a temporary file
// first, so the same script measures the test fixture and the real asset.
import 'dart:convert';
import 'dart:io';

import 'package:yomitanuki/data/services/dictionary/dict_builder.dart';
import 'package:yomitanuki/data/services/dictionary/sqlite_dictionary.dart';

/// Lines like the OCR produces, tapped at a few positions each.
const samples = <(String, int)>[
  ('食べられなかった', 0),
  ('魔王を倒した勇者は冒険の時代が終わるのを知っていた', 0),
  ('魔王を倒した勇者は冒険の時代が終わるのを知っていた', 3),
  ('魔王を倒した勇者は冒険の時代が終わるのを知っていた', 10),
  ('魔王を倒した勇者は冒険の時代が終わるのを知っていた', 20),
  ('来るはずだったのに', 0),
  ('来るはずだったのに', 2),
  ('大きくなかったらしい', 0),
  ('コーヒーを飲みすぎちゃったみたいです', 0),
  ('コーヒーを飲みすぎちゃったみたいです', 5),
  ('ああああああああああああああああああああああああ', 0),
];

Future<void> main(List<String> args) async {
  final options = <String, String>{};
  for (var i = 0; i + 1 < args.length; i += 2) {
    options[args[i]] = args[i + 1];
  }
  Directory? tmp;
  var path = options['--sqlite'];
  if (path == null) {
    final jmdict = options['--jmdict'];
    final kanjidic = options['--kanjidic'];
    if (jmdict == null || kanjidic == null) {
      stderr.writeln(
        'usage: --sqlite <file> | --jmdict <json> --kanjidic <json>',
      );
      exitCode = 2;
      return;
    }
    tmp = Directory.systemTemp.createTempSync('yomitanuki_measure_');
    path = '${tmp.path}/dictionary.sqlite';
    Map<String, Object?> load(String p) =>
        jsonDecode(File(p).readAsStringSync()) as Map<String, Object?>;
    DictBuilder.build(
      jmdict: load(jmdict),
      kanjidic: load(kanjidic),
      outPath: path,
    );
  }

  final dict = SqliteDictionary.openFile(path);
  try {
    // Warm up: JIT, page cache, prepared statements.
    for (final (text, index) in samples) {
      dict.lookupAtSync(text, index);
    }
    const rounds = 20;
    var total = Duration.zero;
    var worst = Duration.zero;
    String? worstSample;
    for (var r = 0; r < rounds; r++) {
      for (final (text, index) in samples) {
        final sw = Stopwatch()..start();
        final results = dict.lookupAtSync(text, index);
        sw.stop();
        total += sw.elapsed;
        if (sw.elapsed > worst) {
          worst = sw.elapsed;
          worstSample = '$text@$index (${results.length} results)';
        }
      }
    }
    final calls = rounds * samples.length;
    stdout
      ..writeln(path)
      ..writeln('  ${File(path).lengthSync() ~/ (1024 * 1024)} MB')
      ..writeln(
        '  $calls lookups: mean ${(total.inMicroseconds / calls / 1000).toStringAsFixed(2)} ms, '
        'max ${(worst.inMicroseconds / 1000).toStringAsFixed(2)} ms on $worstSample',
      );
    for (final (text, index) in samples.take(4)) {
      final results = dict.lookupAtSync(text, index);
      final shown = results
          .take(3)
          .map((r) => '${r.surface}→${r.entry.headword}${r.reasons}')
          .join(', ');
      stdout.writeln('  $text@$index: ${results.length} results: $shown');
    }
  } finally {
    dict.close();
    tmp?.deleteSync(recursive: true);
  }
}
