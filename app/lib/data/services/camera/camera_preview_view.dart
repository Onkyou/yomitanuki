import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import 'camera_frame_source.dart';

/// The live preview of a [CameraFrameSource], filling its box the way the
/// reader maps blocks (`FrameMapping.cover`): the frame's short side fits,
/// the long side is cropped symmetrically. Empty while the camera is closed.
///
/// The preview widget lives in the adapter module, not the domain: the
/// domain only ever sees frames (`FrameSource`).
class CameraPreviewView extends StatelessWidget {
  const CameraPreviewView({required this.source, super.key});

  final CameraFrameSource source;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<CameraController?>(
      valueListenable: source.controller,
      builder: (context, controller, _) {
        if (controller == null || !controller.value.isInitialized) {
          return const SizedBox.expand();
        }
        // previewSize is reported in sensor (landscape) orientation; the
        // capture orientation is locked to portrait, so swap.
        final size = controller.value.previewSize ?? const Size(1080, 1920);
        return SizedBox.expand(
          child: FittedBox(
            fit: BoxFit.cover,
            clipBehavior: Clip.hardEdge,
            child: SizedBox(
              width: size.shortestSide,
              height: size.longestSide,
              child: CameraPreview(controller),
            ),
          ),
        );
      },
    );
  }
}
