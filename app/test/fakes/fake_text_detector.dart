import 'dart:async';

import 'package:yomitanuki/domain/models/bgra_image.dart';
import 'package:yomitanuki/domain/models/text_block.dart';
import 'package:yomitanuki/domain/ports/text_detector.dart';

/// Returns [blocks] for every image, synchronously unless [hold] is set, in
/// which case every call waits until [release] is called (a detection in
/// flight).
class FakeTextDetector implements TextDetector {
  FakeTextDetector({this.blocks = const [], this.error});

  List<TextBlock> blocks;

  /// Thrown instead of returning [blocks] when set.
  Object? error;

  /// Every image [detect] was called with, in order.
  final List<BgraImage> calls = [];
  bool disposed = false;

  Completer<void>? _gate;

  /// Make the next calls block until [release].
  void hold() => _gate = Completer<void>();

  void release() {
    _gate?.complete();
    _gate = null;
  }

  @override
  Future<List<TextBlock>> detect(BgraImage image) async {
    calls.add(image);
    final gate = _gate;
    if (gate != null) {
      await gate.future;
    }
    final e = error;
    if (e != null) {
      Error.throwWithStackTrace(e, StackTrace.current);
    }
    return List.of(blocks);
  }

  @override
  Future<void> dispose() async => disposed = true;
}
