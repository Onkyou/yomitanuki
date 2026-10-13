import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:yomitanuki/domain/models/bgra_image.dart';
import 'package:yomitanuki/domain/models/text_block.dart';

import 'png.dart';

/// The WP0b synthetic goldens under `test/goldens/` (`.claude/wp0/NOTES.md`
/// D0b.8): what the graphs produced on rendered text, with the sha256 of the
/// graphs they were recorded with. Mirrors `wp0/check_goldens.py`: a fixture
/// without its JSON sidecar is an error, and the JSON's tolerance is capped.

/// `check_goldens.py`'s TOLERANCE_CEILING: a golden may not loosen itself
/// past this.
const double tolerancePxCeiling = 4;
const double toleranceScoreCeiling = 0.05;

/// One `ocr/*.json` sidecar with its decoded fixture.
class OcrGolden {
  OcrGolden({
    required this.name,
    required this.image,
    required this.ids,
    required this.text,
    required this.modelsSha256,
  });

  /// The fixture file name, e.g. `v_single.png` or `bgra_padded_237.bgra`.
  final String name;

  /// Row-padded for the `.bgra` fixtures (`bytesPerRow > width * 4`).
  final BgraImage image;
  final List<int> ids;
  final String text;
  final Map<String, String> modelsSha256;

  bool get rowPadded => image.bytesPerRow != image.width * 4;
}

/// One `detector/*.json` sidecar with its decoded page.
class DetectorGolden {
  DetectorGolden({
    required this.name,
    required this.image,
    required this.confThreshold,
    required this.blocks,
    required this.tolerancePx,
    required this.toleranceScore,
    required this.modelsSha256,
  });

  final String name;
  final BgraImage image;
  final double confThreshold;

  /// `[x0, y0, x1, y1, score]` per block, score descending.
  final List<List<double>> blocks;
  final double tolerancePx;
  final double toleranceScore;
  final Map<String, String> modelsSha256;
}

List<OcrGolden> loadOcrGoldens(Directory goldens) => [
  for (final (fixture, sidecar) in _fixturesWithSidecars(
    Directory('${goldens.path}/ocr'),
  ))
    _ocrGolden(fixture, _readJson(sidecar)),
];

List<DetectorGolden> loadDetectorGoldens(Directory goldens) => [
  for (final (fixture, sidecar) in _fixturesWithSidecars(
    Directory('${goldens.path}/detector'),
  ))
    _detectorGolden(fixture, _readJson(sidecar)),
];

/// `check_goldens.check_detector` in Dart: the same block count, every golden
/// block matched one-to-one by an output block within the tolerance, no
/// output block left over. Empty when the page matches.
List<String> blockMismatches(
  List<TextBlock> got,
  DetectorGolden golden, {
  double? tolerancePx,
  double? toleranceScore,
}) {
  final px = tolerancePx ?? golden.tolerancePx;
  final score = toleranceScore ?? golden.toleranceScore;
  final errors = <String>[];
  if (got.length != golden.blocks.length) {
    errors.add(
      'block count differs: got ${got.length} expected ${golden.blocks.length}',
    );
  }
  final unused = List.generate(got.length, (i) => i);
  for (final want in golden.blocks) {
    final hit = unused
        .where((j) => _within(got[j], want, px, score))
        .firstOrNull;
    if (hit == null) {
      errors.add('no output block within tolerance of $want');
    } else {
      unused.remove(hit);
    }
  }
  for (final j in unused) {
    errors.add('unexpected output block ${got[j]}');
  }
  return errors;
}

bool _within(TextBlock got, List<double> want, double px, double score) {
  final b = got.box;
  return (b.left - want[0]).abs() <= px &&
      (b.top - want[1]).abs() <= px &&
      (b.right - want[2]).abs() <= px &&
      (b.bottom - want[3]).abs() <= px &&
      (got.confidence - want[4]).abs() <= score;
}

List<(File, File)> _fixturesWithSidecars(Directory folder) {
  final files = folder.listSync().whereType<File>().toList()
    ..sort((a, b) => a.path.compareTo(b.path));
  final out = <(File, File)>[];
  for (final f in files) {
    if (!f.path.endsWith('.png') && !f.path.endsWith('.bgra')) continue;
    final sidecar = File(
      '${f.path.substring(0, f.path.lastIndexOf('.'))}.json',
    );
    if (!sidecar.existsSync()) {
      throw StateError('${f.path} has no JSON sidecar');
    }
    out.add((f, sidecar));
  }
  if (out.isEmpty) {
    throw StateError('no fixtures in ${folder.path}');
  }
  return out;
}

Map<String, Object?> _readJson(File sidecar) =>
    jsonDecode(sidecar.readAsStringSync()) as Map<String, Object?>;

OcrGolden _ocrGolden(File fixture, Map<String, Object?> g) {
  final BgraImage image;
  if (g case {'bgra': final String _}) {
    final width = g['width']! as int;
    final height = g['height']! as int;
    final bytesPerRow = g['bytesPerRow']! as int;
    final bytes = fixture.readAsBytesSync();
    if (bytes.length != height * bytesPerRow) {
      throw StateError(
        '${fixture.path}: ${bytes.length} bytes, expected '
        'height*bytesPerRow = ${height * bytesPerRow}',
      );
    }
    image = BgraImage(
      width: width,
      height: height,
      bytes: Uint8List.fromList(bytes),
      bytesPerRow: bytesPerRow,
    );
  } else {
    image = readPng(fixture.path);
  }
  return OcrGolden(
    name: fixture.uri.pathSegments.last,
    image: image,
    ids: (g['ids']! as List<Object?>).cast<int>(),
    text: g['text']! as String,
    modelsSha256: _sha256s(g),
  );
}

DetectorGolden _detectorGolden(File fixture, Map<String, Object?> g) {
  final tolerance = g['tolerance']! as Map<String, Object?>;
  final px = (tolerance['px']! as num).toDouble();
  final score = (tolerance['score']! as num).toDouble();
  return DetectorGolden(
    name: fixture.uri.pathSegments.last,
    image: readPng(fixture.path),
    confThreshold: (g['conf_threshold']! as num).toDouble(),
    blocks: [
      for (final block in g['blocks']! as List<Object?>)
        [for (final v in block! as List<Object?>) (v! as num).toDouble()],
    ],
    tolerancePx: px < tolerancePxCeiling ? px : tolerancePxCeiling,
    toleranceScore: score < toleranceScoreCeiling
        ? score
        : toleranceScoreCeiling,
    modelsSha256: _sha256s(g),
  );
}

Map<String, String> _sha256s(Map<String, Object?> g) =>
    (g['models_sha256']! as Map<String, Object?>).cast<String, String>();
