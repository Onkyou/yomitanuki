import 'package:camera/camera.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yomitanuki/data/services/camera/camera_frame_source.dart';
import 'package:yomitanuki/data/services/camera/camera_session.dart';
import 'package:yomitanuki/domain/errors.dart';
import 'package:yomitanuki/domain/models/bgra_image.dart';

import '../../../fakes/images.dart';

/// Stands in for the plugin: records calls, throws what the test sets, and
/// lets the test push raw sensor frames into the stream callback.
class FakeCameraSession implements CameraSession {
  FakeCameraSession({this.initializeError});

  CameraException? initializeError;
  final List<String> calls = [];
  void Function(BgraImage)? onFrame;

  @override
  CameraController? get controller => null;

  @override
  Future<void> initialize() async {
    calls.add('initialize');
    final e = initializeError;
    if (e != null) {
      throw e;
    }
  }

  @override
  Future<void> startImageStream(void Function(BgraImage) onImage) async {
    calls.add('start');
    onFrame = onImage;
  }

  @override
  Future<void> stopImageStream() async {
    calls.add('stop');
    onFrame = null;
  }

  @override
  Future<void> dispose() async => calls.add('dispose');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late List<FakeCameraSession> sessions;
  late DateTime now;

  CameraFrameSource source({CameraException? initializeError}) {
    sessions = [];
    now = DateTime.utc(2026, 10, 13);
    return CameraFrameSource(
      openSession: () async {
        final s = FakeCameraSession(initializeError: initializeError);
        sessions.add(s);
        return s;
      },
      emitInterval: const Duration(milliseconds: 250),
      clock: () => now,
    );
  }

  test('start() opens a session and streams; stop() tears it down', () async {
    final s = source();

    await s.start();
    expect(sessions.single.calls, ['initialize', 'start']);

    await s.stop();
    expect(sessions.single.calls, ['initialize', 'start', 'stop', 'dispose']);
  });

  test('frames are rotated to portrait before they reach the stream', () async {
    final s = source();
    final received = <BgraImage>[];
    final sub = s.frames.listen(received.add);
    await s.start();

    sessions.single.onFrame!(testImage(4, 2));
    await pumpEventQueue();

    expect(received.single.width, 2);
    expect(received.single.height, 4);
    await sub.cancel();
    await s.stop();
  });

  test('at most one frame per emitInterval is converted and emitted', () async {
    final s = source();
    final received = <BgraImage>[];
    final sub = s.frames.listen(received.add);
    await s.start();
    final push = sessions.single.onFrame!;

    push(testImage(4, 2, seed: 1));
    now = now.add(const Duration(milliseconds: 100));
    push(testImage(4, 2, seed: 2));
    now = now.add(const Duration(milliseconds: 150));
    push(testImage(4, 2, seed: 3));
    await pumpEventQueue();

    expect(received.map((f) => f.bytes[2]), [1, 3]);
    await sub.cancel();
    await s.stop();
  });

  test('CameraAccessDenied becomes CameraPermissionDeniedError', () async {
    final s = source(
      initializeError: CameraException('CameraAccessDenied', 'denied'),
    );

    await expectLater(s.start, throwsA(isA<CameraPermissionDeniedError>()));
  });

  test('any other CameraException becomes CameraUnavailableError', () async {
    final s = source(
      initializeError: CameraException('CameraNotFound', 'no back camera'),
    );

    await expectLater(
      s.start,
      throwsA(
        isA<CameraUnavailableError>().having(
          (e) => e.reason,
          'reason',
          contains('no back camera'),
        ),
      ),
    );
  });

  test(
    'paused closes the session, resumed reopens it (AnkiMobile round trip)',
    () async {
      final s = source();
      await s.start();

      s.didChangeAppLifecycleState(AppLifecycleState.paused);
      await pumpEventQueue();
      expect(sessions.single.calls, ['initialize', 'start', 'stop', 'dispose']);

      s.didChangeAppLifecycleState(AppLifecycleState.resumed);
      await pumpEventQueue();
      expect(sessions, hasLength(2));
      expect(sessions.last.calls, ['initialize', 'start']);

      await s.stop();
    },
  );

  test('resumed does nothing when the source was stopped on purpose', () async {
    final s = source();
    await s.start();
    await s.stop();

    s.didChangeAppLifecycleState(AppLifecycleState.resumed);
    await pumpEventQueue();

    expect(sessions, hasLength(1));
  });

  test(
    'a failed reopen on resume surfaces on the stream as a typed error',
    () async {
      final s = source();
      final errors = <Object>[];
      final sub = s.frames.listen((_) {}, onError: errors.add);
      await s.start();
      s.didChangeAppLifecycleState(AppLifecycleState.paused);
      await pumpEventQueue();

      s.openSession = () async {
        throw CameraException('CameraAccessDenied', 'revoked in Settings');
      };
      s.didChangeAppLifecycleState(AppLifecycleState.resumed);
      await pumpEventQueue();

      expect(errors.single, isA<CameraPermissionDeniedError>());
      await sub.cancel();
      await s.stop();
    },
  );
}
