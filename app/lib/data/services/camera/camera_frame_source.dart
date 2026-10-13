import 'dart:async';
import 'dart:developer' as developer;

import 'package:camera/camera.dart';
import 'package:flutter/widgets.dart';

import '../../../domain/errors.dart';
import '../../../domain/models/bgra_image.dart';
import '../../../domain/ports/frame_source.dart';
import 'camera_session.dart';
import 'frame_orientation.dart';

/// The `camera`-plugin [FrameSource]: back camera, 1080p stream (D0.12),
/// frames rotated to portrait, at most one frame per [emitInterval] on the
/// stream (D4.2), closed while the app is paused and reopened when it resumes
/// (the AnkiMobile round trip, C14).
///
/// Opening takes hundreds of milliseconds and the app can be stopped or
/// paused in the meantime; a close counts generations and an open that
/// finishes in a later generation tears its own session down instead of
/// streaming into nothing (D4.16).
class CameraFrameSource with WidgetsBindingObserver implements FrameSource {
  CameraFrameSource({
    this.openSession = openBackCamera,
    this.emitInterval = const Duration(milliseconds: 250),
    this.clock = DateTime.now,
    this.binding,
  });

  /// Opens a session; swapped for a fake in tests, and for a failing one to
  /// simulate a revoked permission.
  Future<CameraSession> Function() openSession;

  /// The plugin delivers ~30 frames/s; converting every one of them (an 8 MB
  /// copy at 1080p when rotation is needed) would be wasted on a consumer
  /// that samples at ~1 Hz (D0.13). Frames inside the interval are dropped
  /// before any copy is made.
  final Duration emitInterval;

  /// Seam for the throttle (testability-seams: time is injected).
  final DateTime Function() clock;

  /// Lifecycle observer target; `null` means [WidgetsBinding.instance].
  final WidgetsBinding? binding;
  final _frames = StreamController<BgraImage>.broadcast();

  /// The live controller for the preview widget, `null` while closed.
  final controller = ValueNotifier<CameraController?>(null);

  CameraSession? _session;
  bool _wanted = false;
  bool _opening = false;
  bool _observing = false;
  int _closes = 0;
  Future<void>? _closing;
  DateTime? _lastEmit;

  /// Registered as a lifecycle observer (exactly once while started).
  @visibleForTesting
  bool get observing => _observing;

  @override
  Stream<BgraImage> get frames => _frames.stream;

  @override
  Future<void> start() async {
    _wanted = true;
    if (!_observing) {
      (binding ?? WidgetsBinding.instance).addObserver(this);
      _observing = true;
    }
    await _open();
  }

  @override
  Future<void> stop() async {
    _wanted = false;
    if (_observing) {
      (binding ?? WidgetsBinding.instance).removeObserver(this);
      _observing = false;
    }
    await _close();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.paused:
        unawaited(_close());
      case AppLifecycleState.resumed:
        if (_wanted && _session == null && !_opening) {
          unawaited(_reopen());
        }
      case AppLifecycleState.detached:
      case AppLifecycleState.inactive:
      case AppLifecycleState.hidden:
        // inactive/hidden precede paused and also fire for the permission
        // prompt and Control Centre; closing there would tear down a session
        // that is still wanted a moment later.
        break;
    }
  }

  Future<void> _open() async {
    if (_session != null || _opening) {
      return;
    }
    _opening = true;
    try {
      // A resume can arrive while the paused close is still awaiting the
      // plugin; opening a second session before the first is disposed is
      // how two capture sessions end up fighting over the device.
      final closing = _closing;
      if (closing != null) {
        await closing;
      }
      final generation = _closes;
      final session = await openSession();
      try {
        await session.initialize();
        await session.startImageStream(_onImage);
      } on Object {
        await _disposeQuietly(session, 'dispose after a failed open');
        rethrow;
      }
      if (!_wanted || generation != _closes) {
        // stop() or paused ran while this open was in flight: the request
        // that started it is gone, so the new session must not stream.
        await _shutDown(session);
        return;
      }
      _session = session;
      controller.value = session.controller;
    } on CameraException catch (e) {
      // The only line with the plugin's own code; the typed error that
      // reaches the screen does not carry it.
      developer.log(
        'camera open failed: ${e.code}: ${e.description ?? ''}',
        name: 'camera',
      );
      throw _typed(e);
    } finally {
      _opening = false;
    }
  }

  /// A reopen after resume has no caller to throw to, so its failure goes
  /// down the stream for the view model to show (already logged in _open).
  Future<void> _reopen() async {
    try {
      await _open();
    } on Object catch (e) {
      _frames.addError(e);
    }
  }

  Future<void> _close() {
    _closes++;
    final session = _session;
    _session = null;
    controller.value = null;
    if (session == null) {
      return Future<void>.value();
    }
    final closing = _shutDown(session);
    _closing = closing;
    return closing.whenComplete(() {
      if (identical(_closing, closing)) {
        _closing = null;
      }
    });
  }

  /// Stops and disposes [session], logging instead of throwing: this runs
  /// from a lifecycle callback with nobody to catch.
  Future<void> _shutDown(CameraSession session) async {
    try {
      await session.stopImageStream();
    } on Object catch (e) {
      developer.log('stopImageStream failed', name: 'camera', error: e);
    }
    await _disposeQuietly(session, 'dispose failed');
  }

  Future<void> _disposeQuietly(CameraSession session, String what) async {
    try {
      await session.dispose();
    } on Object catch (e) {
      developer.log(what, name: 'camera', error: e);
    }
  }

  void _onImage(BgraImage raw) {
    final now = clock();
    final last = _lastEmit;
    if (last != null && now.difference(last) < emitInterval) {
      return;
    }
    _lastEmit = now;
    _frames.add(orientForPortrait(raw));
  }

  static Exception _typed(CameraException e) => switch (e.code) {
    'CameraAccessDenied' ||
    'CameraAccessDeniedWithoutPrompt' ||
    'CameraAccessRestricted' => const CameraPermissionDeniedError(),
    _ => const CameraUnavailableError('The camera could not be opened.'),
  };
}
