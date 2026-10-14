import 'dart:async';
import 'dart:developer' as developer;
import 'dart:io';
import 'dart:ui' as ui;

import '../../../domain/models/bgra_image.dart';
import '../../../domain/models/ocr_capture.dart';
import '../../../domain/ports/ocr_capture_log.dart';

/// [OcrCaptureLog] on the app's Documents folder (D6a.4). Writes
/// `<documents>/ocr-captures/<yyyyMMdd-HHmmss-SSS>.png` per capture and one
/// line per capture to `captures.tsv` beside them; `UIFileSharingEnabled`
/// makes the folder visible in Finder and the Files app.
///
/// The Documents directory is injected: `main.dart` passes
/// `getApplicationDocumentsDirectory`, tests a temp directory. The PNG is
/// named after [OcrCapture.at] (local time, ms); a name already taken (a
/// clock set back, a DST repeat) gets a `-1`, `-2`, … suffix rather than
/// overwriting, so every TSV row keeps its own file.
///
/// Records are written one at a time, in call order, so the header is written
/// once. Any failure is logged under `capture` and swallowed: a diagnostics
/// write never breaks reading.
class FileOcrCaptureLog implements OcrCaptureLog {
  FileOcrCaptureLog(this._documents);

  final Future<Directory> Function() _documents;

  static const folderName = 'ocr-captures';
  static const tsvName = 'captures.tsv';
  static const header =
      'timestamp\tpng\tcrop_w\tcrop_h\tframe_w\tframe_h\telapsed_ms\ttext';

  Future<void> _tail = Future<void>.value();

  @override
  Future<void> record(OcrCapture capture) {
    // `_write` never throws, so the chain cannot break.
    final run = _tail.then((_) => _write(capture));
    _tail = run;
    return run;
  }

  Future<void> _write(OcrCapture capture) async {
    try {
      final dir = Directory('${(await _documents()).path}/$folderName');
      await dir.create(recursive: true);
      final base = _stamp(capture.at);
      var pngName = '$base.png';
      for (var n = 1; await File('${dir.path}/$pngName').exists(); n++) {
        pngName = '$base-$n.png';
      }
      await File('${dir.path}/$pngName')
          .writeAsBytes(await _encodePng(capture.crop));
      final tsv = File('${dir.path}/$tsvName');
      final row = [
        capture.at.toIso8601String(),
        pngName,
        capture.crop.width,
        capture.crop.height,
        capture.frameWidth,
        capture.frameHeight,
        capture.elapsed.inMilliseconds,
        capture.text.replaceAll(_rowBreakers, ' '),
      ].join('\t');
      final prefix = await tsv.exists() ? '' : '$header\n';
      await tsv.writeAsString('$prefix$row\n', mode: FileMode.append);
    } on Object catch (e, stack) {
      developer.log(
        'capture write failed',
        name: 'capture',
        error: e,
        stackTrace: stack,
        level: 900,
      );
    }
  }

  /// Everything a TSV reader might take for a row or cell break: tab, CR,
  /// LF, VT, FF, the C1 separators, NEL and the Unicode line/paragraph
  /// separators (Python's `splitlines` splits on all of them).
  static final _rowBreakers = RegExp(
    r'[\t\r\n\x0B\x0C\x1C-\x1E\x85\u2028\u2029]',
  );

  static String _stamp(DateTime t) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${t.year.toString().padLeft(4, '0')}${two(t.month)}${two(t.day)}-'
        '${two(t.hour)}${two(t.minute)}${two(t.second)}-'
        '${t.millisecond.toString().padLeft(3, '0')}';
  }

  /// PNG through `dart:ui`, the way `BgraImageView` uploads pixels.
  static Future<List<int>> _encodePng(BgraImage image) async {
    final decoded = Completer<ui.Image>();
    ui.decodeImageFromPixels(
      image.bytes,
      image.width,
      image.height,
      ui.PixelFormat.bgra8888,
      rowBytes: image.bytesPerRow,
      decoded.complete,
    );
    final ui.Image uiImage = await decoded.future;
    try {
      final data = await uiImage.toByteData(format: ui.ImageByteFormat.png);
      if (data == null) {
        throw StateError('PNG encoding returned no data');
      }
      return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
    } finally {
      uiImage.dispose();
    }
  }
}
