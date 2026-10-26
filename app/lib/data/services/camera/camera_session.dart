import 'package:camera/camera.dart';
import 'package:flutter/services.dart';

import '../../../domain/models/bgra_image.dart';

/// The slice of the `camera` plugin that [CameraFrameSource] drives: one
/// opened camera that can stream raw frames. The seam exists so the lifecycle
/// logic (permission mapping, pause/resume, the stream duty cycle, rotation)
/// is tested against a fake; the plugin-backed implementation below is four
/// forwarding calls and is exercised on the device only.
abstract interface class CameraSession {
  /// Throws the plugin's [CameraException] (codes `CameraAccessDenied…`).
  Future<void> initialize();

  /// Frames as the plugin delivers them: one BGRA plane with its own row
  /// stride, in whatever orientation the platform chose.
  Future<void> startImageStream(void Function(BgraImage) onImage);

  Future<void> stopImageStream();

  Future<void> dispose();

  /// For the preview widget; `null` until initialised, and in fakes.
  CameraController? get controller;
}

/// Opens the back camera at the 1080p stream preset (D0.12), BGRA8888, no
/// audio, autofocus and auto-exposure, capture orientation locked to portrait.
///
/// 15 fps pinned (D6f.4): the plugin keeps the 1080p format and sets the
/// device's min and max frame duration to 1/15 s; sensor, ISP, preview and
/// whatever the plugin does per frame halve.
Future<CameraSession> openBackCamera() async {
  final cameras = await availableCameras();
  final back = cameras.where(
    (c) => c.lensDirection == CameraLensDirection.back,
  );
  if (back.isEmpty) {
    throw CameraException('CameraNotFound', 'this device has no back camera');
  }
  return PluginCameraSession(
    CameraController(
      back.first,
      ResolutionPreset.veryHigh,
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.bgra8888,
      fps: 15,
    ),
  );
}

class PluginCameraSession implements CameraSession {
  PluginCameraSession(this.controller);

  @override
  final CameraController controller;

  @override
  Future<void> initialize() async {
    await controller.initialize();
    await controller.lockCaptureOrientation(DeviceOrientation.portraitUp);
    await controller.setFocusMode(FocusMode.auto);
    await controller.setExposureMode(ExposureMode.auto);
  }

  @override
  Future<void> startImageStream(void Function(BgraImage) onImage) =>
      controller.startImageStream((CameraImage image) {
        // BGRA8888 on iOS is a single interleaved plane; the plugin hands a
        // fresh Uint8List per frame, so keeping a reference is safe.
        final plane = image.planes.first;
        onImage(
          BgraImage(
            width: image.width,
            height: image.height,
            bytes: plane.bytes,
            bytesPerRow: plane.bytesPerRow,
          ),
        );
      });

  @override
  Future<void> stopImageStream() => controller.stopImageStream();

  @override
  Future<void> dispose() => controller.dispose();
}
