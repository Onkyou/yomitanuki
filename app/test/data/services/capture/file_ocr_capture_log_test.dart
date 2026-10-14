import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:yomitanuki/data/services/capture/file_ocr_capture_log.dart';
import 'package:yomitanuki/domain/models/bgra_image.dart';
import 'package:yomitanuki/domain/models/ocr_capture.dart';

import '../../../fakes/images.dart';

// Plain `test`, not `testWidgets`: file I/O and the PNG encoder need real
// async, which the widget tester's fake-async zone would starve.
void main() {
  late Directory documents;

  setUp(() async {
    documents = await Directory.systemTemp.createTemp('captures_test');
  });

  tearDown(() async {
    await documents.delete(recursive: true);
  });

  FileOcrCaptureLog logger() => FileOcrCaptureLog(() async => documents);

  final at = DateTime(2026, 10, 14, 9, 8, 7, 6);

  OcrCapture capture({
    BgraImage? crop,
    String text = '食べる',
    Duration elapsed = const Duration(milliseconds: 412),
    DateTime? at,
  }) => OcrCapture(
    crop: crop ?? testImage(23, 31),
    frameWidth: 1080,
    frameHeight: 1920,
    text: text,
    elapsed: elapsed,
    at: at ?? DateTime(2026, 10, 14, 9, 8, 7, 6),
  );

  Future<ui.Image> decodePng(File file) async {
    final codec = await ui.instantiateImageCodec(await file.readAsBytes());
    return (await codec.getNextFrame()).image;
  }

  test('a text record and a failure record: header plus two rows, both PNGs '
      'decode to the crop size', () async {
    final log = logger();

    await log.record(capture());
    await log.record(
      capture(
        crop: testImage(10, 12),
        text: '',
        elapsed: Duration.zero,
        at: at.add(const Duration(milliseconds: 5)),
      ),
    );

    final dir = Directory('${documents.path}/ocr-captures');
    final lines = File('${dir.path}/captures.tsv').readAsLinesSync();
    expect(lines, hasLength(3));
    expect(
      lines[0],
      'timestamp\tpng\tcrop_w\tcrop_h\tframe_w\tframe_h\telapsed_ms\ttext',
    );
    final first = lines[1].split('\t');
    expect(first, hasLength(8));
    expect(first[0], at.toIso8601String());
    expect(first[1], '20261014-090807-006.png');
    expect(first.sublist(2), ['23', '31', '1080', '1920', '412', '食べる']);
    final second = lines[2].split('\t');
    expect(second[1], '20261014-090807-011.png');
    expect(second.sublist(2), ['10', '12', '1080', '1920', '0', '']);

    final png1 = File('${dir.path}/${first[1]}');
    final png2 = File('${dir.path}/${second[1]}');
    final image1 = await decodePng(png1);
    final image2 = await decodePng(png2);
    expect((image1.width, image1.height), (23, 31));
    expect((image2.width, image2.height), (10, 12));
  });

  test(
    'tabs and newlines in the text become a space, one line per record',
    () async {
      await logger().record(capture(text: 'a\tb\nc\r\nd'));

      final lines = File('${documents.path}/ocr-captures/captures.tsv')
          .readAsLinesSync();
      expect(lines, hasLength(2));
      final columns = lines[1].split('\t');
      expect(columns, hasLength(8));
      expect(columns.last, 'a b c  d');
    },
  );

  test('the header is written once, however many records follow', () async {
    final log = logger();

    await Future.wait([
      log.record(capture()),
      log.record(capture()),
      log.record(capture()),
    ]);

    final dir = Directory('${documents.path}/ocr-captures');
    final lines = File('${dir.path}/captures.tsv').readAsLinesSync();
    expect(lines.where((l) => l.startsWith('timestamp\t')), hasLength(1));
    expect(lines, hasLength(4));
    // Same `at` three times: three files, none overwritten, each row its own.
    final names = lines.sublist(1).map((l) => l.split('\t')[1]).toList();
    expect(names, [
      '20261014-090807-006.png',
      '20261014-090807-006-1.png',
      '20261014-090807-006-2.png',
    ]);
    for (final name in names) {
      expect(File('${dir.path}/$name').existsSync(), isTrue, reason: name);
    }
  });

  test('a write failure is swallowed, not thrown into the reader', () async {
    // A file where the directory should be: createSync fails.
    File('${documents.path}/ocr-captures').writeAsStringSync('in the way');

    await expectLater(logger().record(capture()), completes);
  });

  test('a failing documents lookup is swallowed too', () async {
    final log = FileOcrCaptureLog(() async => throw StateError('no home'));

    await expectLater(log.record(capture()), completes);
  });

  test('the PNG signature is written', () async {
    await logger().record(capture());

    final bytes = File('${documents.path}/ocr-captures/20261014-090807-006.png')
        .readAsBytesSync();
    expect(Uint8List.sublistView(bytes, 0, 4), [0x89, 0x50, 0x4e, 0x47]);
  });
}
