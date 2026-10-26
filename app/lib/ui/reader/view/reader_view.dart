import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/theme.dart';
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
  final _zoom = TransformationController();
  ReaderSource _lastSource = ReaderSource.camera;

  @override
  void initState() {
    super.initState();
    widget.viewModel.addListener(_onViewModelChanged);
    unawaited(widget.viewModel.start());
  }

  @override
  void dispose() {
    widget.viewModel.removeListener(_onViewModelChanged);
    unawaited(widget.viewModel.stop());
    _zoom.dispose();
    super.dispose();
  }

  void _onViewModelChanged() {
    _showAnkiMessage();
    // A new photo (or the camera) starts unzoomed.
    final source = widget.viewModel.source;
    if (source != _lastSource) {
      _lastSource = source;
      _zoom.value = Matrix4.identity();
    }
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
            builder: (context, _) {
              final (icon, tooltip) = switch (vm.wakeState) {
                WakeState.held => (
                  Icons.stay_current_portrait,
                  'Screen stays awake. Tap to allow locking.',
                ),
                WakeState.released => (
                  Icons.screen_lock_portrait_outlined,
                  'Screen may lock. Tap to keep it awake.',
                ),
                WakeState.off => (
                  Icons.screen_lock_portrait,
                  'Auto-lock as usual. Tap to keep the screen awake.',
                ),
              };
              return IconButton(
                key: const Key('reader.keepAwake'),
                tooltip: tooltip,
                icon: Icon(icon),
                onPressed: () => unawaited(vm.toggleKeepAwake()),
              );
            },
          ),
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
            // A still photo can be zoomed; the overlay is inside the same
            // transform, so FrameMapping and hit-testing are unchanged (a
            // tap arrives in the untransformed child's coordinates).
            if (vm.source == ReaderSource.photo)
              InteractiveViewer(
                key: const Key('reader.zoom'),
                transformationController: _zoom,
                minScale: 1,
                maxScale: 6,
                child: Stack(
                  fit: StackFit.expand,
                  children: [_surface(vm), _overlay(context, vm)],
                ),
              )
            else ...[
              _surface(vm),
              _overlay(context, vm),
            ],
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
            if (vm.notice case final message?)
              Positioned(
                top: 12,
                left: 12,
                right: 12,
                child: _Notice(message: message, onClose: vm.dismissNotice),
              ),
            if (vm.noBlocksHint && vm.ocrState is OcrIdle)
              const Positioned(
                left: 24,
                right: 24,
                bottom: 32,
                child: _Hint(
                  key: Key('reader.noBlocks'),
                  text: 'No bubbles found. Move closer or hold steady.',
                ),
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
                  translationActive: vm.translationActive,
                  translationNote: vm.translationNote,
                  showHint: vm.showTapHint,
                  onTapCharacter: (i) => unawaited(vm.onTapCharacter(i)),
                  onAddToAnki: (r) => unawaited(vm.addToAnki(r)),
                  onAddSentence: () => unawaited(vm.addSentenceToAnki()),
                  onDismissTranslationNote: vm.dismissTranslationNote,
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
    return LayoutBuilder(
      builder: (context, constraints) {
        final frameSize = vm.frameSize;
        final size = constraints.biggest;
        final mapping = frameSize == null
            ? null
            : vm.source == ReaderSource.photo
            ? FrameMapping.contain(frame: frameSize, preview: size)
            : FrameMapping.cover(frame: frameSize, preview: size);
        final selectedBox = vm.selectedBox;
        final selected = selectedBox == null
            ? null
            : mapping?.toPreview(selectedBox);
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
              color: overlayColor,
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
  const _Notice({required this.message, required this.onClose});

  final String message;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.errorContainer,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.only(left: 14, top: 4, bottom: 4),
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
            IconButton(
              key: const Key('reader.notice.close'),
              tooltip: 'Dismiss',
              icon: Icon(Icons.close, color: scheme.onErrorContainer),
              onPressed: onClose,
            ),
          ],
        ),
      ),
    );
  }
}

/// A quiet, non-interactive hint over the preview.
class _Hint extends StatelessWidget {
  const _Hint({required this.text, super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Material(
        color: scheme.inverseSurface.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Text(
            text,
            textAlign: TextAlign.center,
            style: TextStyle(color: scheme.onInverseSurface),
          ),
        ),
      ),
    );
  }
}
