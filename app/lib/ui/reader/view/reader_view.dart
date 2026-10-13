import 'dart:async';

import 'package:flutter/material.dart';

import '../view_model/frame_mapping.dart';
import '../view_model/reader_state.dart';
import '../view_model/reader_view_model.dart';
import 'bgra_image_view.dart';
import 'block_overlay.dart';
import 'ocr_sheet.dart';

/// The reader: a full-screen preview with the detected blocks drawn over it,
/// the OCR sheet at the bottom once a block is tapped. [cameraPreview] is
/// whatever the camera adapter renders; this widget never sees the camera.
class ReaderView extends StatefulWidget {
  const ReaderView({
    required this.viewModel,
    required this.cameraPreview,
    super.key,
  });

  final ReaderViewModel viewModel;
  final Widget cameraPreview;

  @override
  State<ReaderView> createState() => _ReaderViewState();
}

class _ReaderViewState extends State<ReaderView> {
  @override
  void initState() {
    super.initState();
    widget.viewModel.addListener(_showAnkiMessage);
    unawaited(widget.viewModel.start());
  }

  @override
  void dispose() {
    widget.viewModel.removeListener(_showAnkiMessage);
    unawaited(widget.viewModel.stop());
    super.dispose();
  }

  /// Anki outcomes are one-shot: show once, then consume.
  void _showAnkiMessage() {
    final message = widget.viewModel.ankiMessage;
    if (message == null || !mounted) {
      return;
    }
    widget.viewModel.consumeAnkiMessage();
    final text = switch (message) {
      AnkiHandedOver(:final word) => 'Handed "$word" to AnkiMobile.',
      AnkiNotInstalled() => 'AnkiMobile is not installed on this device.',
      AnkiFailed(:final message) => message,
    };
    ScaffoldMessenger.maybeOf(context)
      ?..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  @override
  Widget build(BuildContext context) {
    final vm = widget.viewModel;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Yomitanuki'),
        actions: [
          ListenableBuilder(
            listenable: vm,
            builder: (context, _) => vm.source == ReaderSource.photo
                ? IconButton(
                    key: const Key('reader.backToCamera'),
                    tooltip: 'Back to the camera',
                    icon: const Icon(Icons.videocam_outlined),
                    onPressed: () => unawaited(vm.backToCamera()),
                  )
                : IconButton(
                    key: const Key('reader.pickPhoto'),
                    tooltip: 'Read a photo',
                    icon: const Icon(Icons.photo_library_outlined),
                    onPressed: () => unawaited(vm.pickPhoto()),
                  ),
          ),
          IconButton(
            key: const Key('reader.settings'),
            tooltip: 'Settings',
            icon: const Icon(Icons.settings_outlined),
            onPressed: () =>
                unawaited(Navigator.pushNamed(context, 'settings')),
          ),
          IconButton(
            key: const Key('reader.about'),
            tooltip: 'About',
            icon: const Icon(Icons.info_outline),
            onPressed: () => unawaited(Navigator.pushNamed(context, 'about')),
          ),
        ],
      ),
      body: ListenableBuilder(
        listenable: vm,
        builder: (context, _) => Stack(
          fit: StackFit.expand,
          children: [
            _surface(vm),
            _overlay(context, vm),
            if (vm.scanning)
              const Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: LinearProgressIndicator(
                  key: Key('reader.scanning'),
                  minHeight: 2,
                ),
              ),
            if (vm.detectionError case final message?)
              Positioned(
                top: 12,
                left: 12,
                right: 12,
                child: _Notice(message: message),
              ),
            if (vm.source == ReaderSource.camera) _cameraStatus(context, vm),
            if (vm.ocrState is! OcrIdle)
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: OcrSheet(
                  ocrState: vm.ocrState,
                  lookupState: vm.lookupState,
                  onTapCharacter: (i) => unawaited(vm.onTapCharacter(i)),
                  onAddToAnki: (r) => unawaited(vm.addToAnki(r)),
                  onClose: vm.dismissOcr,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _surface(ReaderViewModel vm) {
    final frame = vm.frame;
    if (vm.source == ReaderSource.photo && frame != null) {
      return BgraImageView(image: frame);
    }
    return widget.cameraPreview;
  }

  /// Boxes and hit-testing share one [FrameMapping], so a tap lands on the
  /// box the reader sees.
  Widget _overlay(BuildContext context, ReaderViewModel vm) {
    final color = Theme.of(context).colorScheme.primary;
    return LayoutBuilder(
      builder: (context, constraints) {
        final frameSize = vm.frameSize;
        final size = constraints.biggest;
        final mapping = frameSize == null
            ? null
            : vm.source == ReaderSource.photo
            ? FrameMapping.contain(frame: frameSize, preview: size)
            : FrameMapping.cover(frame: frameSize, preview: size);
        final selected = switch (vm.ocrState) {
          OcrRunning(:final block) ||
          OcrText(:final block) ||
          OcrFailed(:final block) => mapping?.toPreview(block.box),
          OcrIdle() => null,
        };
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapUp: mapping == null
              ? null
              : (details) {
                  final block = mapping.blockAt(
                    details.localPosition,
                    vm.blocks,
                  );
                  if (block != null) {
                    unawaited(vm.onTapBlock(block));
                  }
                },
          child: CustomPaint(
            key: const Key('reader.overlay'),
            painter: BlockOverlayPainter(
              boxes: [
                if (mapping != null)
                  for (final b in vm.blocks) mapping.toPreview(b.box),
              ],
              color: color,
              selected: selected,
            ),
          ),
        );
      },
    );
  }

  Widget _cameraStatus(BuildContext context, ReaderViewModel vm) {
    return switch (vm.cameraState) {
      CameraIdle() || CameraLive() => const SizedBox.shrink(),
      CameraStarting() => const Center(child: CircularProgressIndicator()),
      CameraFailed(:final message) => Center(
        child: Card(
          margin: const EdgeInsets.all(24),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.videocam_off_outlined,
                  size: 40,
                  color: Theme.of(context).colorScheme.error,
                ),
                const SizedBox(height: 12),
                Text(message, textAlign: TextAlign.center),
                const SizedBox(height: 16),
                FilledButton(
                  key: const Key('reader.retry'),
                  onPressed: () => unawaited(vm.start()),
                  child: const Text('Try again'),
                ),
              ],
            ),
          ),
        ),
      ),
    };
  }
}

/// A non-blocking message over the preview (a port failed; the camera and
/// the rest of the screen keep working).
class _Notice extends StatelessWidget {
  const _Notice({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.errorContainer,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          children: [
            Icon(Icons.error_outline, color: scheme.onErrorContainer),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                message,
                style: TextStyle(color: scheme.onErrorContainer),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
