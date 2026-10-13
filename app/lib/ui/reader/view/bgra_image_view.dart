import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../../domain/models/bgra_image.dart';

/// Shows a [BgraImage] (the picked photo) letterboxed in its box, the way
/// `FrameMapping.contain` places the blocks. The pixels are uploaded once per
/// image through `decodeImageFromPixels`; until that completes the box is
/// blank, which is also what a widget test sees.
class BgraImageView extends StatefulWidget {
  const BgraImageView({required this.image, super.key});

  final BgraImage image;

  @override
  State<BgraImageView> createState() => _BgraImageViewState();
}

class _BgraImageViewState extends State<BgraImageView> {
  ui.Image? _decoded;

  @override
  void initState() {
    super.initState();
    _decode();
  }

  @override
  void didUpdateWidget(BgraImageView old) {
    super.didUpdateWidget(old);
    if (!identical(old.image, widget.image)) {
      _decoded?.dispose();
      _decoded = null;
      _decode();
    }
  }

  void _decode() {
    final image = widget.image;
    ui.decodeImageFromPixels(
      image.bytes,
      image.width,
      image.height,
      ui.PixelFormat.bgra8888,
      rowBytes: image.bytesPerRow,
      (decoded) {
        if (!mounted || !identical(widget.image, image)) {
          decoded.dispose();
          return;
        }
        setState(() => _decoded = decoded);
      },
    );
  }

  @override
  void dispose() {
    _decoded?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox.expand(
      child: FittedBox(
        fit: BoxFit.contain,
        child: SizedBox(
          width: widget.image.width.toDouble(),
          height: widget.image.height.toDouble(),
          child: RawImage(image: _decoded, fit: BoxFit.fill),
        ),
      ),
    );
  }
}
