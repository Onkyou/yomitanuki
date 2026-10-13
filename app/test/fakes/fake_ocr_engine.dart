import 'dart:async';

import 'package:yomitanuki/domain/models/bgra_image.dart';
import 'package:yomitanuki/domain/models/ocr_result.dart';
import 'package:yomitanuki/domain/ports/ocr_engine.dart';

/// Returns [text] for every crop and records the crops it was given.
class FakeOcrEngine implements OcrEngine {
  FakeOcrEngine({this.text = '', this.error});

  String text;
  Object? error;

  final List<BgraImage> crops = [];
  bool disposed = false;

  Completer<void>? _gate;

  void hold() => _gate = Completer<void>();

  void release() {
    _gate?.complete();
    _gate = null;
  }

  @override
  Future<OcrResult> recognise(BgraImage crop) async {
    crops.add(crop);
    final gate = _gate;
    if (gate != null) {
      await gate.future;
    }
    final e = error;
    if (e != null) {
      Error.throwWithStackTrace(e, StackTrace.current);
    }
    return OcrResult(text: text, elapsed: const Duration(milliseconds: 1));
  }

  @override
  Future<void> dispose() async => disposed = true;
}
