import 'dart:async';

import 'package:flutter/material.dart';

import '../../../domain/models/bgra_image.dart';
import 'bgra_image_view.dart';

/// The bubble crop, nearly full screen and zoomable: the sheet's thumbnail is
/// too small to check a small character against the page (D6e.4). A tap
/// outside the picture or the X closes it.
class CropZoom extends StatelessWidget {
  const CropZoom({required this.image, super.key});

  final BgraImage image;

  static Future<void> show(BuildContext context, BgraImage image) =>
      showDialog<void>(
        context: context,
        builder: (_) => CropZoom(image: image),
      );

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.all(12),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          InteractiveViewer(
            key: const Key('ocr.crop.zoom'),
            maxScale: 6,
            child: BgraImageView(image: image),
          ),
          Positioned(
            top: 0,
            right: 0,
            child: IconButton(
              key: const Key('ocr.crop.zoom.close'),
              tooltip: 'Close',
              icon: const Icon(Icons.close),
              onPressed: () => Navigator.pop(context),
            ),
          ),
        ],
      ),
    );
  }
}
