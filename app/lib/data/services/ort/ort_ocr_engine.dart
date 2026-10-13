import '../../../domain/models/bgra_image.dart';
import '../../../domain/models/ocr_result.dart';
import '../../../domain/ports/ocr_engine.dart';
import 'model_assets.dart';
import 'ort_inference_worker.dart';

/// [OcrEngine] over manga-ocr as two graphs (`ocr_encoder.onnx`,
/// `ocr_decoder.onnx`, WP0b) and the greedy loop (D0.2): the encoder runs
/// once per crop, then each step runs the decoder on the whole prefix and
/// takes the argmax of the last row, until `[SEP]` or [maxLength] ids; the
/// ids become text through the vocabulary and manga-ocr's `post_process`.
/// All of it runs in the adapter's worker isolate, on the CPU execution
/// provider (int8 graphs have no CoreML kernels, D0b.6).
class OrtOcrEngine implements OcrEngine {
  OrtOcrEngine._(this._worker, this.maxLength);

  /// Loads both OCR graphs and `vocab.txt` from [assets] in a new worker
  /// isolate. [ortLibraryPath] is for tests on macOS; the app looks ORT up
  /// in its own process (D2.5).
  static Future<OrtOcrEngine> create({
    required ModelAssets assets,
    int maxLength = 300,
    String? ortLibraryPath,
  }) async {
    if (maxLength < 2) {
      throw ArgumentError.value(
        maxLength,
        'maxLength',
        'must leave room for at least one generated token',
      );
    }
    final worker = await OrtInferenceWorker.spawn(
      OrtWorkerConfig(
        assets: assets,
        graphs: const {WorkerGraphs.ocr},
        ortLibraryPath: ortLibraryPath,
      ),
    );
    return OrtOcrEngine._(worker, maxLength);
  }

  final OrtInferenceWorker _worker;

  /// The longest id sequence the loop produces, start token included
  /// (`MAX_LEN` 300 in the reference).
  final int maxLength;

  /// The port's answer: the text and how long the worker took.
  @override
  Future<OcrResult> recognise(BgraImage crop) async {
    final crop0 = await recogniseDetailed(crop);
    return OcrResult(text: crop0.text, elapsed: crop0.total);
  }

  /// [recognise] with the id sequence and the per-stage timings, for the
  /// golden tests and the on-device timing (PLAN WP2 task 1).
  Future<RecognisedCrop> recogniseDetailed(BgraImage crop) =>
      _worker.recognise(crop, maxLength: maxLength);

  @override
  Future<void> dispose() => _worker.dispose();
}
