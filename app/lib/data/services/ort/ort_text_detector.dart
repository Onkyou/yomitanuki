import 'dart:typed_data';
import 'dart:ui';

import 'package:ort_ffi/ort_ffi.dart';

import '../../../domain/models/bgra_image.dart';
import '../../../domain/models/text_block.dart';
import '../../../domain/ports/text_detector.dart';
import 'model_assets.dart';
import 'ort_inference_worker.dart';

/// [TextDetector] over the blocks-only comic-text-detector graph
/// (`detector.onnx`, WP0 D0.7, D0b.2): the graph takes the BGRA frame and
/// the confidence threshold and returns the post-NMS boxes in frame pixels;
/// this adapter only runs it in its worker isolate and maps the rows to
/// [TextBlock]s, clamped to the frame (the graph does not clip, D0b.8).
///
/// On the device the detector runs on the CoreML execution provider with
/// exactly D0.10 + D0b.6 (`NeuralNetwork`, `CPUAndNeuralEngine`,
/// `RequireStaticInputShapes=1`, a writable cache directory); `coreMl:
/// false` keeps it on the CPU provider, which is what the exactness tests
/// use because threshold-edge boxes flip under ANE fp16 (D0b.6).
class OrtTextDetector implements TextDetector {
  OrtTextDetector._(this._worker, this.confThreshold);

  /// Loads the detector graph from [assets] in a new worker isolate.
  ///
  /// [confThreshold] is the `obj * cls` cut-off, `0 <= t <= 1` (D0.11 chose
  /// 0.2: about 90 % of bubbles boxed). [coreMlCacheDirectory] defaults to
  /// [ModelAssets.coreMlCacheDirectory]; [ortLibraryPath] is for tests on
  /// macOS, the app looks ORT up in its own process (D2.5).
  static Future<OrtTextDetector> create({
    required ModelAssets assets,
    double confThreshold = 0.2,
    bool coreMl = true,
    String? coreMlCacheDirectory,
    String? ortLibraryPath,
  }) async {
    if (confThreshold.isNaN || confThreshold < 0 || confThreshold > 1) {
      throw ArgumentError.value(
        confThreshold,
        'confThreshold',
        'must be in [0, 1]',
      );
    }
    final worker = await OrtInferenceWorker.spawn(
      OrtWorkerConfig(
        assets: assets,
        graphs: const {WorkerGraphs.detector},
        ortLibraryPath: ortLibraryPath,
        detectorCoreMl: coreMl
            ? CoreMlOptions(
                modelCacheDirectory:
                    coreMlCacheDirectory ?? assets.coreMlCacheDirectory,
              )
            : null,
      ),
    );
    return OrtTextDetector._(worker, confThreshold);
  }

  final OrtInferenceWorker _worker;

  /// The threshold every [detect] runs with.
  final double confThreshold;

  @override
  Future<List<TextBlock>> detect(BgraImage image) async {
    final blocks = await _worker.detect(image, confThreshold: confThreshold);
    return toTextBlocks(blocks, width: image.width, height: image.height);
  }

  /// The graph's `blocks [N,5]` (x0, y0, x1, y1, score per row, flattened)
  /// as [TextBlock]s in the graph's order (score descending), each box
  /// clamped to the `width` x `height` frame.
  static List<TextBlock> toTextBlocks(
    Float32List blocks, {
    required int width,
    required int height,
  }) {
    if (blocks.length % 5 != 0) {
      throw ArgumentError.value(
        blocks.length,
        'blocks',
        'must hold five values per block',
      );
    }
    final w = width.toDouble();
    final h = height.toDouble();
    return [
      for (var i = 0; i < blocks.length; i += 5)
        TextBlock(
          box: Rect.fromLTRB(
            blocks[i].clamp(0, w),
            blocks[i + 1].clamp(0, h),
            blocks[i + 2].clamp(0, w),
            blocks[i + 3].clamp(0, h),
          ),
          confidence: blocks[i + 4],
        ),
    ];
  }

  @override
  Future<void> dispose() => _worker.dispose();
}
