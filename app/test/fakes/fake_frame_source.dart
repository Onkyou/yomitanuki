import 'dart:async';

import 'package:yomitanuki/domain/models/bgra_image.dart';
import 'package:yomitanuki/domain/ports/frame_source.dart';

/// A [FrameSource] the test drives by hand: [emit] pushes one frame to every
/// listener synchronously, so a test never has to pump for a frame to arrive.
class FakeFrameSource implements FrameSource {
  FakeFrameSource({this.startError});

  final _frames = StreamController<BgraImage>.broadcast(sync: true);

  /// Thrown by [start] when set, e.g. a permission error.
  Object? startError;

  int startCalls = 0;
  int stopCalls = 0;
  bool get running => _running;
  bool _running = false;

  @override
  Stream<BgraImage> get frames => _frames.stream;

  @override
  Future<void> start() async {
    startCalls++;
    final error = startError;
    if (error != null) {
      Error.throwWithStackTrace(error, StackTrace.current);
    }
    _running = true;
  }

  @override
  Future<void> stop() async {
    stopCalls++;
    _running = false;
  }

  void emit(BgraImage frame) => _frames.add(frame);

  /// What the real adapter does when the camera cannot be reopened after
  /// AnkiMobile foregrounds.
  void emitError(Object error) => _frames.addError(error);

  Future<void> close() => _frames.close();
}
