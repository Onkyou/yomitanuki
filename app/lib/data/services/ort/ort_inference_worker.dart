import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:ort_ffi/ort_ffi.dart';

import '../../../domain/models/bgra_image.dart';
import 'greedy_decoder.dart';
import 'inference_error.dart';
import 'manga_ocr_text.dart';
import 'model_assets.dart';

/// Which graphs a worker loads. The detector adapter and the OCR adapter
/// each spawn their own worker (`.claude/wp2/NOTES.md` D2.13), so a
/// detection pass never queues behind an OCR pass and either adapter can be
/// disposed alone.
enum WorkerGraphs { detector, ocr }

/// What [OrtInferenceWorker.spawn] loads and how.
class OrtWorkerConfig {
  const OrtWorkerConfig({
    required this.assets,
    required this.graphs,
    this.ortLibraryPath,
    this.detectorCoreMl,
  });

  final ModelAssets assets;
  final Set<WorkerGraphs> graphs;

  /// The ONNX Runtime dylib to open; `null` looks the C API up in the
  /// process itself (the iOS app, where the runtime is linked statically,
  /// D2.5).
  final String? ortLibraryPath;

  /// When set, the detector session gets the CoreML execution provider with
  /// these options (D0.10 + D0b.6); `null` keeps it on the CPU provider. The
  /// OCR graphs are int8 and always run on the CPU provider (D0b.6).
  final CoreMlOptions? detectorCoreMl;
}

/// One OCR pass: the greedy loop's ids, the text, and where the time went.
class RecognisedCrop {
  const RecognisedCrop({
    required this.ids,
    required this.text,
    required this.encoder,
    required this.decoder,
    required this.total,
  });

  /// The full id sequence, start token included (WP0b golden `ids`).
  final List<int> ids;

  /// `postProcess(detokenise(ids))`.
  final String text;

  /// Encoder run, every decoder run, and the whole request inside the
  /// worker (tensor creation included).
  final Duration encoder;
  final Duration decoder;
  final Duration total;

  /// Decoder runs: one per generated token.
  int get steps => ids.length - 1;
}

/// One long-lived isolate that owns an `OrtRuntime`, the sessions it was
/// asked for and the vocabulary; the adapters hold one each and never touch
/// ORT on the UI isolate (`.claude/wp2/NOTES.md` D2.11, D2.13).
///
/// Frames cross the isolate boundary as [TransferableTypedData] (one copy
/// into the transfer buffer, none on receipt); row-padded images are
/// repacked once inside the worker before they become a tensor (the graphs
/// want a tight `[1,H,W,4]`). Requests carry an id and are answered in
/// order; a late answer for a request that is no longer pending (disposed
/// meanwhile) is dropped. Failures inside the worker come back as the
/// `OrtException` ORT raised or as an [InferenceError], never as a dead
/// isolate.
class OrtInferenceWorker {
  OrtInferenceWorker._(this._replies, this._exit, this._errors) {
    // Each ReceivePort is listened to exactly once: cancelling the
    // subscription would close the port.
    _replies.listen(_onReply);
    _exit.listen((_) => _onGone('the inference isolate exited'));
    _errors.listen((e) => _onGone('the inference isolate failed', cause: '$e'));
  }

  /// Loads the graphs of [config] in a new isolate. Throws what loading
  /// threw (`OrtException` for a missing or unreadable model file).
  static Future<OrtInferenceWorker> spawn(OrtWorkerConfig config) async {
    final worker = OrtInferenceWorker._(
      ReceivePort('ort worker replies'),
      ReceivePort('ort worker exit'),
      ReceivePort('ort worker errors'),
    );
    final Isolate isolate;
    try {
      isolate = await Isolate.spawn(
        _workerMain,
        _Bootstrap(config, worker._replies.sendPort),
        onExit: worker._exit.sendPort,
        onError: worker._errors.sendPort,
        debugName: 'ort ${config.graphs.map((g) => g.name).join('+')}',
      );
    } on Object {
      worker._closePorts();
      rethrow;
    }
    worker._isolate = isolate;
    try {
      await worker._ready.future;
    } on Object {
      worker._closePorts();
      isolate.kill(priority: Isolate.immediate);
      rethrow;
    }
    return worker;
  }

  final ReceivePort _replies;
  final ReceivePort _exit;
  final ReceivePort _errors;
  final Map<int, Completer<Object?>> _pending = {};

  /// Completes with the worker's inbox, or with the load failure.
  final Completer<SendPort> _ready = Completer<SendPort>();
  final Completer<void> _gone = Completer<void>();
  late final Isolate _isolate;
  late final SendPort _requests;
  int _nextId = 1;
  bool _disposed = false;

  /// `blocks [N,5]` of the detector graph, flattened: x0, y0, x1, y1, score
  /// per block in [image]'s pixels, score descending, unclipped; empty when
  /// nothing scored above [confThreshold].
  Future<Float32List> detect(
    BgraImage image, {
    required double confThreshold,
  }) => _send<Float32List>(
    (id) => _DetectRequest(id, _Frame.of(image), confThreshold),
  );

  /// Encoder once, then the greedy loop (D0.2) over [crop].
  Future<RecognisedCrop> recognise(BgraImage crop, {int maxLength = 300}) =>
      _send<RecognisedCrop>(
        (id) => _RecogniseRequest(id, _Frame.of(crop), maxLength),
      );

  /// Fails every request still in flight with an [InferenceError], releases
  /// the sessions and the runtime in the worker and ends the isolate.
  /// Safe to call twice.
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _failPending(InferenceError('disposed while the request was in flight'));
    if (!_gone.isCompleted) {
      _requests.send(const _DisposeRequest());
      await _gone.future.timeout(
        const Duration(seconds: 10),
        onTimeout: () => _isolate.kill(priority: Isolate.immediate),
      );
    }
    _closePorts();
  }

  Future<T> _send<T>(_Request Function(int id) build) {
    if (_disposed) {
      throw StateError('OrtInferenceWorker has been disposed');
    }
    final id = _nextId++;
    // Build first: a throwing build (e.g. the transfer copy failing) must
    // not leave a completer nobody will ever answer.
    final request = build(id);
    final completer = Completer<Object?>();
    _pending[id] = completer;
    _requests.send(request);
    return completer.future.then((value) => value as T);
  }

  void _onReply(Object? message) {
    switch (message) {
      case _Ready(:final inbox):
        _requests = inbox;
        _ready.complete(inbox);
      case _Failed(id: 0, :final error, :final stackTrace)
          when !_ready.isCompleted:
        _ready.completeError(error, StackTrace.fromString(stackTrace));
      case _Done(:final id, :final result):
        _pending.remove(id)?.complete(result);
      case _Failed(:final id, :final error, :final stackTrace):
        _pending
            .remove(id)
            ?.completeError(error, StackTrace.fromString(stackTrace));
    }
  }

  void _onGone(String message, {String? cause}) {
    if (!_gone.isCompleted) _gone.complete();
    final error = InferenceError(message, cause: cause);
    if (!_ready.isCompleted) _ready.completeError(error, StackTrace.current);
    _failPending(error);
  }

  void _failPending(InferenceError error) {
    final pending = _pending.values.toList();
    _pending.clear();
    for (final c in pending) {
      c.completeError(error, StackTrace.current);
    }
  }

  void _closePorts() {
    _replies.close();
    _exit.close();
    _errors.close();
  }
}

// --- the isolate boundary ---------------------------------------------------

/// A [BgraImage] packed for transfer. [TransferableTypedData.fromList]
/// copies the bytes once; `materialize()` on the other side does not.
class _Frame {
  _Frame(this.width, this.height, this.bytesPerRow, this.bytes);

  factory _Frame.of(BgraImage image) => _Frame(
    image.width,
    image.height,
    image.bytesPerRow,
    TransferableTypedData.fromList([image.bytes]),
  );

  final int width;
  final int height;
  final int bytesPerRow;
  final TransferableTypedData bytes;

  /// The pixels as the graphs want them: `[1,H,W,4]`, no row padding.
  /// Throws [InferenceError] when the geometry does not add up.
  Uint8List tight() {
    final data = bytes.materialize().asUint8List();
    final rowBytes = width * 4;
    if (width < 1 || height < 1 || bytesPerRow < rowBytes) {
      throw InferenceError(
        'frame geometry ${width}x$height with $bytesPerRow bytes per row',
      );
    }
    final needed = (height - 1) * bytesPerRow + rowBytes;
    if (data.length < needed) {
      throw InferenceError(
        'frame holds ${data.length} bytes, ${width}x$height rows of '
        '$bytesPerRow need $needed',
      );
    }
    if (bytesPerRow == rowBytes && data.length == needed) return data;
    final out = Uint8List(height * rowBytes);
    for (var y = 0; y < height; y++) {
      out.setRange(y * rowBytes, (y + 1) * rowBytes, data, y * bytesPerRow);
    }
    return out;
  }
}

class _Bootstrap {
  const _Bootstrap(this.config, this.replies);

  final OrtWorkerConfig config;
  final SendPort replies;
}

sealed class _Request {
  const _Request(this.id);

  final int id;
}

class _DetectRequest extends _Request {
  const _DetectRequest(super.id, this.frame, this.confThreshold);

  final _Frame frame;
  final double confThreshold;
}

class _RecogniseRequest extends _Request {
  const _RecogniseRequest(super.id, this.frame, this.maxLength);

  final _Frame frame;
  final int maxLength;
}

class _DisposeRequest extends _Request {
  const _DisposeRequest() : super(0);
}

class _Ready {
  const _Ready(this.inbox);

  final SendPort inbox;
}

class _Done {
  const _Done(this.id, this.result);

  final int id;
  final Object result;
}

class _Failed {
  const _Failed(this.id, this.error, this.stackTrace);

  final int id;

  /// An `OrtException` or an [InferenceError]: both are plain data.
  final Object error;
  final String stackTrace;
}

/// What the worker sends back for an error: ORT's and ours as they are,
/// anything else (a Dart error, a `List` from an uncaught-error port)
/// summarised in an [InferenceError].
Object _portable(Object error) => switch (error) {
  OrtException() || InferenceError() => error,
  _ => InferenceError(
    'unexpected failure in the inference isolate',
    cause: '$error',
  ),
};

// --- inside the worker isolate ----------------------------------------------

Future<void> _workerMain(_Bootstrap boot) async {
  final inbox = ReceivePort('ort worker inbox');
  final _Graphs graphs;
  try {
    graphs = _Graphs.load(boot.config);
  } on Object catch (e, s) {
    inbox.close();
    boot.replies.send(_Failed(0, _portable(e), '$s'));
    return;
  }
  boot.replies.send(_Ready(inbox.sendPort));
  await for (final message in inbox) {
    switch (message) {
      case _DetectRequest(:final id, :final frame, :final confThreshold):
        boot.replies.send(
          _serve(id, () => graphs.detect(frame, confThreshold)),
        );
      case _RecogniseRequest(:final id, :final frame, :final maxLength):
        boot.replies.send(_serve(id, () => graphs.recognise(frame, maxLength)));
      case _DisposeRequest():
        graphs.dispose();
        inbox.close();
    }
  }
}

Object _serve(int id, Object Function() body) {
  try {
    return _Done(id, body());
  } on Object catch (e, s) {
    return _Failed(id, _portable(e), '$s');
  }
}

/// The runtime and the sessions, owned by the worker isolate.
class _Graphs {
  _Graphs._(
    this._runtime,
    this._detector,
    this._encoder,
    this._decoder,
    this._vocab,
  );

  factory _Graphs.load(OrtWorkerConfig config) {
    final runtime = config.ortLibraryPath == null
        ? OrtRuntime.process()
        : OrtRuntime.open(config.ortLibraryPath!);
    OrtSession? detector;
    OrtSession? encoder;
    OrtSession? decoder;
    MangaOcrVocab? vocab;
    try {
      if (config.graphs.contains(WorkerGraphs.detector)) {
        detector = _open(
          runtime,
          config.assets.detectorPath,
          coreMl: config.detectorCoreMl,
        );
      }
      if (config.graphs.contains(WorkerGraphs.ocr)) {
        encoder = _open(runtime, config.assets.encoderPath);
        decoder = _open(runtime, config.assets.decoderPath);
        vocab = MangaOcrVocab.parse(
          File(config.assets.vocabPath).readAsStringSync(),
        );
      }
    } on Object {
      detector?.dispose();
      encoder?.dispose();
      decoder?.dispose();
      runtime.dispose();
      rethrow;
    }
    return _Graphs._(runtime, detector, encoder, decoder, vocab);
  }

  static OrtSession _open(
    OrtRuntime runtime,
    String path, {
    CoreMlOptions? coreMl,
  }) {
    final options = OrtSessionOptions(runtime);
    try {
      if (coreMl != null) options.appendCoreML(coreMl);
      return OrtSession.fromFile(path, options);
    } finally {
      options.dispose();
    }
  }

  final OrtRuntime _runtime;
  final OrtSession? _detector;
  final OrtSession? _encoder;
  final OrtSession? _decoder;
  final MangaOcrVocab? _vocab;

  Float32List detect(_Frame frame, double confThreshold) {
    final session = _detector;
    if (session == null) {
      throw StateError('this worker did not load the detector graph');
    }
    final pixels = frame.tight();
    final image = OrtValue.fromUint8(_runtime, pixels, [
      1,
      frame.height,
      frame.width,
      4,
    ]);
    // Everything after the 8 MB image value is created inside the try, so a
    // failure on the way cannot leak it.
    OrtValue? threshold;
    Map<String, OrtValue>? outputs;
    try {
      threshold = OrtValue.fromFloat32(
        _runtime,
        Float32List.fromList([confThreshold]),
        [1],
      );
      outputs = session.run({'image': image, 'conf_threshold': threshold});
      final blocks = outputs['blocks']!;
      // A `[0,5]` tensor has no data pointer worth reading.
      if (blocks.shape.first == 0) return Float32List(0);
      return blocks.toFloat32List();
    } finally {
      outputs?.values.forEach((v) => v.dispose());
      threshold?.dispose();
      image.dispose();
    }
  }

  RecognisedCrop recognise(_Frame frame, int maxLength) {
    final encoder = _encoder;
    final decoder = _decoder;
    final vocab = _vocab;
    if (encoder == null || decoder == null || vocab == null) {
      throw StateError('this worker did not load the OCR graphs');
    }
    final total = Stopwatch()..start();
    final pixels = frame.tight();
    final image = OrtValue.fromUint8(_runtime, pixels, [
      1,
      frame.height,
      frame.width,
      4,
    ]);
    Map<String, OrtValue>? encoded;
    try {
      final encoderTime = Stopwatch()..start();
      encoded = encoder.run({'image': image});
      encoderTime.stop();
      final hidden = encoded['encoder_hidden_states']!;
      final decoderTime = Stopwatch()..start();
      final ids = GreedyDecoder(maxLength: maxLength)
          .decode((inputIds) => _lastLogits(decoder, inputIds, hidden));
      decoderTime.stop();
      return RecognisedCrop(
        ids: ids,
        text: postProcess(vocab.detokenise(ids)),
        encoder: encoderTime.elapsed,
        decoder: decoderTime.elapsed,
        total: total.elapsed,
      );
    } finally {
      encoded?.values.forEach((v) => v.dispose());
      image.dispose();
    }
  }

  Float32List _lastLogits(
    OrtSession decoder,
    Int64List inputIds,
    OrtValue hidden,
  ) {
    final ids = OrtValue.fromInt64(_runtime, inputIds, [1, inputIds.length]);
    Map<String, OrtValue>? outputs;
    try {
      outputs = decoder.run({
        'input_ids': ids,
        'encoder_hidden_states': hidden,
      });
      final logits = outputs['logits']!;
      final shape = logits.shape; // [1, L, V]
      final vocabSize = shape[2];
      // Only the last row: the tensor grows with the prefix (up to
      // 300 x 6144 floats), the loop needs logits[0, -1].
      return logits.readFloat32(
        offset: (shape[1] - 1) * vocabSize,
        count: vocabSize,
      );
    } finally {
      outputs?.values.forEach((v) => v.dispose());
      ids.dispose();
    }
  }

  void dispose() {
    _detector?.dispose();
    _encoder?.dispose();
    _decoder?.dispose();
    _runtime.dispose();
  }
}
