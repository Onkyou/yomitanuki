import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yomitanuki/data/services/camera/camera_frame_source.dart';
import 'package:yomitanuki/data/services/camera/camera_session.dart';
import 'package:yomitanuki/domain/errors.dart';
import 'package:yomitanuki/domain/models/bgra_image.dart';

import '../../../fakes/images.dart';

/// Stands in for the plugin: records calls into a [log] shared by every
/// session the test opens (so ordering across sessions is observable),
/// throws what the test sets, and lets the test gate `initialize` and
/// `stopImageStream` to simulate the plugin's latency. `startError` is
/// thrown by `startImageStream` until the test clears it.
class FakeCameraSession implements CameraSession {
  FakeCameraSession(this.id, this.log, {this.initializeError});

  final int id;
  final List<String> log;
  CameraException? initializeError;
  CameraException? startError;
  Exception? stopError;
  Exception? disposeError;
  Completer<void>? initializeGate;
  Completer<void>? stopGate;
  void Function(BgraImage)? onFrame;

  List<String> get calls => [
    for (final line in log)
      if (line.startsWith('$id:')) line.substring(2),
  ];

  @override
  CameraController? get controller => null;

  @override
  Future<void> initialize() async {
    log.add('$id:initialize');
    final gate = initializeGate;
    if (gate != null) {
      await gate.future;
    }
    final e = initializeError;
    if (e != null) {
      throw e;
    }
  }

  @override
  Future<void> startImageStream(void Function(BgraImage) onImage) async {
    log.add('$id:start');
    final e = startError;
    if (e != null) {
      throw e;
    }
    onFrame = onImage;
  }

  @override
  Future<void> stopImageStream() async {
    log.add('$id:stop');
    onFrame = null;
    final gate = stopGate;
    if (gate != null) {
      await gate.future;
    }
    final e = stopError;
    if (e != null) {
      throw e;
    }
  }

  @override
  Future<void> dispose() async {
    log.add('$id:dispose');
    final e = disposeError;
    if (e != null) {
      throw e;
    }
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late List<FakeCameraSession> sessions;
  late List<String> log;

  /// [prepare] customises each new session before it is handed out.
  CameraFrameSource source({void Function(FakeCameraSession s)? prepare}) {
    sessions = [];
    log = [];
    return CameraFrameSource(
      openSession: () async {
        final s = FakeCameraSession(sessions.length + 1, log);
        prepare?.call(s);
        sessions.add(s);
        return s;
      },
    );
  }

  test(
    'start() opens a session without streaming; stop() disposes it',
    () async {
      final s = source();

      await s.start();
      expect(sessions.single.calls, ['initialize']);

      await s.stop();
      expect(sessions.single.calls, ['initialize', 'dispose']);
    },
  );

  test('frames are rotated to portrait before they reach the stream', () async {
    final s = source();
    final received = <BgraImage>[];
    final sub = s.frames.listen(received.add);
    await s.start();
    s.requestFrame();
    await pumpEventQueue();

    sessions.single.onFrame!(testImage(4, 2));
    await pumpEventQueue();

    expect(received.single.width, 2);
    expect(received.single.height, 4);
    await sub.cancel();
    await s.stop();
  });

  group('frame requests', () {
    test('one request streams one frame and stops the stream', () async {
      final s = source();
      final received = <BgraImage>[];
      final sub = s.frames.listen(received.add);
      await s.start();

      s.requestFrame();
      await pumpEventQueue();
      expect(sessions.single.calls, ['initialize', 'start']);

      sessions.single.onFrame!(testImage(4, 2));
      await pumpEventQueue();

      expect(received, hasLength(1));
      expect(sessions.single.calls.last, 'stop');
      expect(sessions.single.onFrame, isNull);
      await sub.cancel();
      await s.stop();
    });

    test(
      'a frame that arrives while the stop is in flight is dropped',
      () async {
        final s = source(prepare: (fake) => fake.stopGate = Completer());
        final received = <BgraImage>[];
        final sub = s.frames.listen(received.add);
        await s.start();
        s.requestFrame();
        await pumpEventQueue();
        final push = sessions.single.onFrame!;

        push(testImage(4, 2, seed: 1));
        await pumpEventQueue();
        expect(sessions.single.calls.last, 'stop');
        push(testImage(4, 2, seed: 2));
        await pumpEventQueue();
        expect(received, hasLength(1));

        sessions.single.stopGate!.complete();
        await pumpEventQueue();
        expect(received, hasLength(1));
        expect(sessions.single.calls, ['initialize', 'start', 'stop']);
        await sub.cancel();
        await s.stop();
      },
    );

    test('two requests before the frame coalesce into one start and one '
        'frame', () async {
      final s = source();
      final received = <BgraImage>[];
      final sub = s.frames.listen(received.add);
      await s.start();

      s.requestFrame();
      s.requestFrame();
      await pumpEventQueue();
      expect(sessions.single.calls, ['initialize', 'start']);

      final push = sessions.single.onFrame!;
      push(testImage(4, 2, seed: 1));
      push(testImage(4, 2, seed: 2));
      await pumpEventQueue();

      expect(received, hasLength(1));
      expect(sessions.single.calls, ['initialize', 'start', 'stop']);
      await sub.cancel();
      await s.stop();
    });

    test('a request during the stop starts the stream again after it '
        'settles', () async {
      final s = source(prepare: (fake) => fake.stopGate = Completer());
      final received = <BgraImage>[];
      final sub = s.frames.listen(received.add);
      await s.start();
      s.requestFrame();
      await pumpEventQueue();
      sessions.single.onFrame!(testImage(4, 2, seed: 1));
      await pumpEventQueue();
      expect(sessions.single.calls, ['initialize', 'start', 'stop']);

      s.requestFrame();
      await pumpEventQueue();
      expect(sessions.single.calls, ['initialize', 'start', 'stop']);

      sessions.single.stopGate!.complete();
      await pumpEventQueue();
      expect(sessions.single.calls, ['initialize', 'start', 'stop', 'start']);

      sessions.single.onFrame!(testImage(4, 2, seed: 2));
      await pumpEventQueue();
      expect(received, hasLength(2));
      await sub.cancel();
      await s.stop();
    });

    test('a request made while paused is served after the reopen on '
        'resume', () async {
      final s = source();
      final received = <BgraImage>[];
      final sub = s.frames.listen(received.add);
      await s.start();

      s.didChangeAppLifecycleState(AppLifecycleState.paused);
      await pumpEventQueue();
      expect(sessions.single.calls, ['initialize', 'dispose']);

      s.requestFrame();
      await pumpEventQueue();
      expect(sessions, hasLength(1));

      s.didChangeAppLifecycleState(AppLifecycleState.resumed);
      await pumpEventQueue();
      expect(sessions.last.calls, ['initialize', 'start']);

      sessions.last.onFrame!(testImage(4, 2));
      await pumpEventQueue();
      expect(received, hasLength(1));
      await sub.cancel();
      await s.stop();
    });

    test('stop() with a request outstanding clears it: the next start() '
        'does not stream', () async {
      final s = source();
      await s.start();
      s.requestFrame();
      await pumpEventQueue();

      await s.stop();
      await s.start();
      await pumpEventQueue();

      expect(sessions, hasLength(2));
      expect(sessions.last.calls, ['initialize']);
      await s.stop();
    });

    test('a failed startImageStream is logged and the next request tries '
        'again', () async {
      final s = source(
        prepare: (fake) => fake.startError = CameraException('boom', ''),
      );
      final received = <BgraImage>[];
      final sub = s.frames.listen(received.add);
      await s.start();

      s.requestFrame();
      await pumpEventQueue();
      expect(sessions.single.calls, ['initialize', 'start']);
      expect(received, isEmpty);

      sessions.single.startError = null;
      s.requestFrame();
      await pumpEventQueue();
      expect(sessions.single.calls, ['initialize', 'start', 'start']);

      sessions.single.onFrame!(testImage(4, 2));
      await pumpEventQueue();
      expect(received, hasLength(1));
      await sub.cancel();
      await s.stop();
    });
  });

  group('permission mapping', () {
    for (final code in [
      'CameraAccessDenied',
      'CameraAccessDeniedWithoutPrompt',
      'CameraAccessRestricted',
    ]) {
      test('$code becomes CameraPermissionDeniedError', () async {
        final s = source(
          prepare: (fake) => fake.initializeError = CameraException(code, ''),
        );

        await expectLater(s.start, throwsA(isA<CameraPermissionDeniedError>()));
      });
    }

    test('any other CameraException becomes a CameraUnavailableError '
        'without the plugin text', () async {
      final s = source(
        prepare: (fake) =>
            fake.initializeError = CameraException('CameraNotFound', 'xyz'),
      );

      await expectLater(
        s.start,
        throwsA(
          isA<CameraUnavailableError>().having(
            (e) => e.reason,
            'reason',
            isNot(contains('xyz')),
          ),
        ),
      );
    });

    test('a failed open disposes its session, and a dispose that throws '
        'does not mask the original error', () async {
      final s = source(
        prepare: (fake) => fake
          ..initializeError = CameraException('CameraAccessDenied', '')
          ..disposeError = Exception('dispose exploded'),
      );

      await expectLater(s.start, throwsA(isA<CameraPermissionDeniedError>()));
      expect(sessions.single.calls, ['initialize', 'dispose']);
    });
  });

  group('lifecycle', () {
    test('paused closes the session, resumed reopens it (AnkiMobile round '
        'trip)', () async {
      final s = source();
      await s.start();

      s.didChangeAppLifecycleState(AppLifecycleState.paused);
      await pumpEventQueue();
      expect(sessions.single.calls, ['initialize', 'dispose']);

      s.didChangeAppLifecycleState(AppLifecycleState.resumed);
      await pumpEventQueue();
      expect(sessions, hasLength(2));
      expect(sessions.last.calls, ['initialize']);

      await s.stop();
    });

    test('paused while streaming stops the stream before disposing', () async {
      final s = source();
      await s.start();
      s.requestFrame();
      await pumpEventQueue();

      s.didChangeAppLifecycleState(AppLifecycleState.paused);
      await pumpEventQueue();

      expect(sessions.single.calls, ['initialize', 'start', 'stop', 'dispose']);
      await s.stop();
    });

    test(
      'resumed does nothing when the source was stopped on purpose',
      () async {
        final s = source();
        await s.start();
        await s.stop();

        s.didChangeAppLifecycleState(AppLifecycleState.resumed);
        await pumpEventQueue();

        expect(sessions, hasLength(1));
      },
    );

    test('a failed reopen on resume surfaces on the stream as a typed '
        'error', () async {
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
    });

    test('stop() during an in-flight open shuts the new session down '
        'instead of leaving it streaming', () async {
      final s = source(prepare: (fake) => fake.initializeGate = Completer());
      final starting = s.start();
      await pumpEventQueue();
      expect(sessions.single.calls, ['initialize']);

      await s.stop();
      sessions.single.initializeGate!.complete();
      await starting;

      expect(sessions.single.calls, ['initialize', 'dispose']);
      expect(s.controller.value, isNull);
    });

    test(
      'paused during an in-flight open shuts the new session down',
      () async {
        final s = source(prepare: (fake) => fake.initializeGate = Completer());
        final starting = s.start();
        await pumpEventQueue();

        s.didChangeAppLifecycleState(AppLifecycleState.paused);
        sessions.single.initializeGate!.complete();
        await starting;

        expect(sessions.single.calls, ['initialize', 'dispose']);
        await s.stop();
      },
    );

    test('resumed while the paused close is still awaiting the plugin '
        'waits for it before opening again', () async {
      final s = source(prepare: (fake) => fake.stopGate = Completer());
      await s.start();
      s.requestFrame();
      await pumpEventQueue();
      s.didChangeAppLifecycleState(AppLifecycleState.paused);
      await pumpEventQueue();
      expect(sessions.single.calls, ['initialize', 'start', 'stop']);

      s.didChangeAppLifecycleState(AppLifecycleState.resumed);
      await pumpEventQueue();
      expect(sessions, hasLength(1), reason: 'no second session yet');

      sessions.single.stopGate!.complete();
      await pumpEventQueue();

      expect(log, [
        '1:initialize',
        '1:start',
        '1:stop',
        '1:dispose',
        '2:initialize',
        '2:start',
      ]);
      sessions.last.stopGate = null;
      await s.stop();
    });

    test('a throwing stopImageStream on paused is logged, not unhandled, '
        'and the session is still disposed', () async {
      final s = source(
        prepare: (fake) => fake.stopError = Exception('stop exploded'),
      );
      await s.start();
      s.requestFrame();
      await pumpEventQueue();

      s.didChangeAppLifecycleState(AppLifecycleState.paused);
      await pumpEventQueue();

      expect(sessions.single.calls, ['initialize', 'start', 'stop', 'dispose']);
      expect(s.controller.value, isNull);
    });

    test('two concurrent start() calls open one session', () async {
      final s = source(prepare: (fake) => fake.initializeGate = Completer());
      final first = s.start();
      final second = s.start();
      await pumpEventQueue();

      sessions.single.initializeGate!.complete();
      await first;
      await second;

      expect(sessions, hasLength(1));
      expect(sessions.single.calls, ['initialize']);
      await s.stop();
    });

    test('the lifecycle observer is registered once, even after a failed '
        'start, and removed by stop()', () async {
      var attempts = 0;
      final s = source(
        prepare: (fake) {
          if (attempts++ == 0) {
            fake.initializeError = CameraException('CameraNotFound', '');
          }
        },
      );

      await expectLater(s.start, throwsA(isA<CameraUnavailableError>()));
      expect(s.observing, isTrue);
      await s.start();
      expect(s.observing, isTrue);

      await s.stop();
      expect(s.observing, isFalse);
    });
  });
}
