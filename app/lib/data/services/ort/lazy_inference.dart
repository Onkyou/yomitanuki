import 'dart:async';

import 'package:flutter/services.dart';
import 'package:ort_ffi/ort_ffi.dart';

import '../../../domain/errors.dart';
import '../../../domain/models/bgra_image.dart';
import '../../../domain/models/ocr_result.dart';
import '../../../domain/models/text_block.dart';
import '../../../domain/ports/ocr_engine.dart';
import '../../../domain/ports/text_detector.dart';
import 'inference_error.dart';
import 'model_assets.dart';
import 'ort_ocr_engine.dart';
import 'ort_text_detector.dart';

/// Prepares the model files.
typedef PrepareModels = Future<ModelAssets> Function();

/// Creates the real adapter over prepared models.
typedef CreateDetector = Future<TextDetector> Function(ModelAssets assets);
typedef CreateOcr = Future<OcrEngine> Function(ModelAssets assets);

/// The detector and the OCR engine, created on first use (the
/// `LazyDictionary` pattern, WP3): app start never waits for the 145 MB
/// asset copy, the worker isolates or the CoreML compile. One in-flight
/// preparation is shared by concurrent first calls; a failed step is not
/// cached, so the next call tries again. Each port disposes only what was
/// created for it.
///
/// This is also the boundary where the adapters' errors become the
/// domain's: `ModelAssetsException` → [ModelsUnavailableError],
/// `OrtException` and `InferenceError` → [InferenceFailedError]. The reader's
/// `describeReaderError` imports only `domain/`, and the domain must not
/// know ONNX Runtime, so the mapping lives here rather than in the error
/// types (as `LazyDictionary` does for `DictionaryAssetError`).
class LazyInference {
  LazyInference({
    required PrepareModels prepare,
    required CreateDetector detector,
    required CreateOcr ocr,
  }) : _assets = _Once(prepare),
       _createDetector = detector,
       _createOcr = ocr;

  /// The app's wiring: the bundle's models copied to application support,
  /// the detector on CoreML (D0.10 + D0b.6), OCR on the CPU provider
  /// (D0b.6), ONNX Runtime from the process (D2.5).
  factory LazyInference.production({
    AssetBundle? bundle,
    bool coreMl = true,
    double confThreshold = 0.2,
  }) => LazyInference(
    prepare: () async => ModelAssets.prepare(
      bundle: bundle ?? rootBundle,
      directory: await ModelAssets.defaultDirectory(),
    ),
    detector: (assets) => OrtTextDetector.create(
      assets: assets,
      confThreshold: confThreshold,
      coreMl: coreMl,
    ),
    ocr: (assets) => OrtOcrEngine.create(assets: assets),
  );

  final _Once<ModelAssets> _assets;
  final CreateDetector _createDetector;
  final CreateOcr _createOcr;
  late final _Once<TextDetector> _detector = _Once(
    () async => _createDetector(await _assets()),
  );
  late final _Once<OcrEngine> _ocr = _Once(
    () async => _createOcr(await _assets()),
  );

  /// The [TextDetector] port; the real adapter is created on first [detect].
  late final TextDetector detector = _LazyTextDetector(this);

  /// The [OcrEngine] port; the real adapter is created on first [recognise].
  late final OcrEngine ocr = _LazyOcrEngine(this);

  /// Disposes whichever adapters were created (waiting for one still being
  /// created); nothing when none was.
  Future<void> dispose() async {
    await Future.wait([
      _detector.disposeCreated((d) => d.dispose()),
      _ocr.disposeCreated((o) => o.dispose()),
    ]);
  }
}

/// Runs [body] and maps the adapters' failures to the domain's.
Future<T> _mapped<T>(Future<T> Function() body) async {
  try {
    return await body();
  } on ModelAssetsException catch (e, s) {
    Error.throwWithStackTrace(ModelsUnavailableError(e.toString()), s);
  } on OrtException catch (e, s) {
    Error.throwWithStackTrace(InferenceFailedError(e.toString()), s);
  } on InferenceError catch (e, s) {
    Error.throwWithStackTrace(InferenceFailedError(e.toString()), s);
  }
}

class _LazyTextDetector implements TextDetector {
  _LazyTextDetector(this._owner);

  final LazyInference _owner;

  @override
  Future<List<TextBlock>> detect(BgraImage image) =>
      _mapped(() async => (await _owner._detector()).detect(image));

  @override
  Future<void> dispose() => _owner._detector.disposeCreated((d) => d.dispose());
}

class _LazyOcrEngine implements OcrEngine {
  _LazyOcrEngine(this._owner);

  final LazyInference _owner;

  @override
  Future<OcrResult> recognise(BgraImage crop) =>
      _mapped(() async => (await _owner._ocr()).recognise(crop));

  @override
  Future<void> dispose() => _owner._ocr.disposeCreated((o) => o.dispose());
}

/// A value created on first call, shared while in flight, forgotten when
/// the creation fails (so the next call retries) or after [disposeCreated].
class _Once<T> {
  _Once(this._create);

  final Future<T> Function() _create;
  Future<T>? _inFlight;

  Future<T> call() {
    final inFlight = _inFlight;
    if (inFlight != null) return inFlight;
    final creating = _create();
    _inFlight = creating;
    return creating.catchError((Object e, StackTrace s) {
      if (identical(_inFlight, creating)) _inFlight = null;
      return Future<T>.error(e, s);
    });
  }

  /// Disposes the value if one was (or is being) created; a creation that
  /// failed has nothing to dispose.
  Future<void> disposeCreated(Future<void> Function(T value) dispose) async {
    final inFlight = _inFlight;
    if (inFlight == null) return;
    _inFlight = null;
    final T value;
    try {
      value = await inFlight;
    } on Object {
      return;
    }
    await dispose(value);
  }
}
