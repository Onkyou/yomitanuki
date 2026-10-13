import 'dart:async';
import 'dart:developer' as developer;
import 'dart:ui';

import 'package:flutter/foundation.dart';

import '../../../data/services/photo/photo_picker.dart';
import '../../../domain/errors.dart';
import '../../../domain/models/anki_note.dart';
import '../../../domain/models/bgra_image.dart';
import '../../../domain/models/dictionary_entry.dart';
import '../../../domain/models/lookup_result.dart';
import '../../../domain/models/text_block.dart';
import '../../../domain/ports/anki_exporter.dart';
import '../../../domain/ports/dictionary.dart';
import '../../../domain/ports/frame_source.dart';
import '../../../domain/ports/ocr_engine.dart';
import '../../../domain/ports/settings_repository.dart';
import '../../../domain/ports/text_detector.dart';
import '../../../domain/use_cases/anki_note_builder.dart';
import 'reader_errors.dart';
import 'reader_state.dart';

/// The live reader: samples the camera at ~1 Hz (D0.13), detects blocks on
/// the sampled frame, OCRs a block on tap from that same frame (D0.12), looks
/// a tapped character up and hands a note to Anki.
///
/// Every port call is awaited inside a try/catch and surfaces as a state; the
/// view model never throws into the view. Nothing in here runs inference: the
/// adapters behind [TextDetector] and [OcrEngine] own their isolates.
class ReaderViewModel extends ChangeNotifier {
  ReaderViewModel({
    required FrameSource frameSource,
    required PhotoPicker photoPicker,
    required TextDetector detector,
    required OcrEngine ocr,
    required Dictionary dictionary,
    required AnkiExporter anki,
    required SettingsRepository settings,
    Duration detectionInterval = const Duration(seconds: 1),
    double cropMargin = 0.08,
    DateTime Function() clock = DateTime.now,
  }) : this._(
         frameSource,
         photoPicker,
         detector,
         ocr,
         dictionary,
         anki,
         settings,
         clock,
         detectionInterval,
         cropMargin,
       );

  // Private fields cannot be named initializing formals, hence the redirect.
  ReaderViewModel._(
    this._frameSource,
    this._photoPicker,
    this._detector,
    this._ocr,
    this._dictionary,
    this._anki,
    this._settings,
    this._clock,
    this.detectionInterval,
    this.cropMargin,
  );

  final FrameSource _frameSource;
  final PhotoPicker _photoPicker;
  final TextDetector _detector;
  final OcrEngine _ocr;
  final Dictionary _dictionary;
  final AnkiExporter _anki;
  final SettingsRepository _settings;
  final DateTime Function() _clock;

  /// One detection per interval; frames in between are dropped (D0.13).
  final Duration detectionInterval;

  /// Margin added around a block before OCR, as a fraction of the block's
  /// own width and height on each side (WP0 D0.6 used 8 %).
  final double cropMargin;

  StreamSubscription<BgraImage>? _subscription;
  DateTime? _lastSampleAt;
  bool _detecting = false;
  bool _disposed = false;

  ReaderSource _source = ReaderSource.camera;
  CameraState _cameraState = const CameraIdle();
  BgraImage? _frame;
  List<TextBlock> _blocks = const [];
  String? _detectionError;
  OcrState _ocrState = const OcrIdle();
  LookupState _lookupState = const LookupIdle();
  AnkiMessage? _ankiMessage;

  ReaderSource get source => _source;
  CameraState get cameraState => _cameraState;

  /// The frame the current [blocks] were detected on, and the frame a tapped
  /// block is cropped from. `null` until the first detection completes.
  BgraImage? get frame => _frame;
  Size? get frameSize {
    final f = _frame;
    return f == null ? null : Size(f.width.toDouble(), f.height.toDouble());
  }

  /// In [frame]'s pixel coordinates; the view maps them with `FrameMapping`.
  List<TextBlock> get blocks => _blocks;

  /// A detection is in flight.
  bool get scanning => _detecting;
  String? get detectionError => _detectionError;
  OcrState get ocrState => _ocrState;
  LookupState get lookupState => _lookupState;
  AnkiMessage? get ankiMessage => _ankiMessage;

  // --- camera ---------------------------------------------------------------

  Future<void> start() async {
    _subscription ??= _frameSource.frames.listen(
      _onFrame,
      onError: _onFrameError,
    );
    _source = ReaderSource.camera;
    _cameraState = const CameraStarting();
    notifyListeners();
    try {
      await _frameSource.start();
      _cameraState = const CameraLive();
    } on Object catch (e) {
      _cameraState = CameraFailed(
        describeReaderError(e),
        permissionDenied: e is CameraPermissionDeniedError,
      );
    }
    _notify();
  }

  Future<void> stop() async {
    try {
      await _frameSource.stop();
    } on Object catch (e) {
      _log('camera stop failed', e);
    }
    _cameraState = const CameraIdle();
    _notify();
  }

  /// The adapter reports a failed reopen (after AnkiMobile foregrounds) on
  /// the stream, since no `start()` call is waiting for it. Camera errors
  /// are logged once, by the adapter, with the plugin's own code; the view
  /// model only turns them into a state.
  void _onFrameError(Object error) {
    _cameraState = CameraFailed(
      describeReaderError(error),
      permissionDenied: error is CameraPermissionDeniedError,
    );
    _notify();
  }

  // --- detection ------------------------------------------------------------

  void _onFrame(BgraImage frame) {
    if (_source != ReaderSource.camera || _detecting || _ocrState is! OcrIdle) {
      return;
    }
    final now = _clock();
    final last = _lastSampleAt;
    if (last != null && now.difference(last) < detectionInterval) {
      return;
    }
    _lastSampleAt = now;
    unawaited(_detect(frame));
  }

  Future<void> _detect(BgraImage frame) async {
    _detecting = true;
    notifyListeners();
    try {
      final blocks = await _detector.detect(frame);
      _frame = frame;
      _blocks = blocks;
      _detectionError = null;
    } on Object catch (e) {
      _frame = frame;
      _blocks = const [];
      _detectionError = describeReaderError(e);
      _log('detection failed', e);
    } finally {
      _detecting = false;
      _notify();
    }
  }

  // --- photo fallback -------------------------------------------------------

  Future<void> pickPhoto() async {
    final BgraImage? photo;
    try {
      photo = await _photoPicker.pickPhoto();
    } on Object catch (e) {
      _detectionError = describeReaderError(e);
      _log('photo pick failed', e);
      _notify();
      return;
    }
    if (photo == null) {
      return;
    }
    _source = ReaderSource.photo;
    await stop();
    _ocrState = const OcrIdle();
    _lookupState = const LookupIdle();
    await _detect(photo);
  }

  Future<void> backToCamera() async {
    _frame = null;
    _blocks = const [];
    _detectionError = null;
    _ocrState = const OcrIdle();
    _lookupState = const LookupIdle();
    _lastSampleAt = null;
    await start();
  }

  // --- OCR ------------------------------------------------------------------

  Future<void> onTapBlock(TextBlock block) async {
    final frame = _frame;
    if (frame == null || _ocrState is OcrRunning) {
      return;
    }
    _ocrState = OcrRunning(block);
    _lookupState = const LookupIdle();
    notifyListeners();
    final crop = _cropWithMargin(frame, block.box);
    try {
      final result = await _ocr.recognise(crop);
      _ocrState = OcrText(block, result.text);
    } on Object catch (e) {
      _ocrState = OcrFailed(block, describeReaderError(e));
      _log('ocr failed', e);
    }
    _notify();
  }

  void dismissOcr() {
    _ocrState = const OcrIdle();
    _lookupState = const LookupIdle();
    // The boxes on screen are as old as the sheet; detect the very next
    // frame instead of waiting out the rest of the interval.
    _lastSampleAt = null;
    notifyListeners();
  }

  BgraImage _cropWithMargin(BgraImage frame, Rect box) {
    final mx = box.width * cropMargin;
    final my = box.height * cropMargin;
    return frame.crop(
      left: (box.left - mx).round(),
      top: (box.top - my).round(),
      width: (box.width + 2 * mx).round(),
      height: (box.height + 2 * my).round(),
    );
  }

  // --- lookup ---------------------------------------------------------------

  Future<void> onTapCharacter(int index) async {
    final ocr = _ocrState;
    if (ocr is! OcrText || index < 0 || index >= ocr.text.length) {
      return;
    }
    _lookupState = LookupLoading(index);
    notifyListeners();
    try {
      final results = await _dictionary.lookupAt(ocr.text, index);
      final kanji = await _kanjiIn(results);
      _lookupState = LookupResults(
        index: index,
        results: results,
        kanji: kanji,
      );
    } on Object catch (e) {
      _lookupState = LookupFailed(index, describeReaderError(e));
      _log('lookup failed', e);
    }
    _notify();
  }

  static final _kanji = RegExp(r'[㐀-䶿一-鿿]');

  Future<Map<String, KanjiEntry>> _kanjiIn(List<LookupResult> results) async {
    final out = <String, KanjiEntry>{};
    for (final result in results) {
      for (final m in _kanji.allMatches(result.surface)) {
        final literal = m.group(0)!;
        if (out.containsKey(literal)) {
          continue;
        }
        final entry = await _dictionary.kanji(literal);
        if (entry != null) {
          out[literal] = entry;
        }
      }
    }
    return out;
  }

  // --- Anki -----------------------------------------------------------------

  /// Settings are loaded for every note: the settings screen can change them
  /// while the reader is open (WP5 D5.7). The builder refuses settings with
  /// problems (D5.8); that becomes a message pointing at Settings.
  Future<void> addToAnki(LookupResult result) async {
    final ocr = _ocrState;
    final example = ocr is OcrText ? ocr.text : '';
    try {
      final settings = await _settings.loadAnkiSettings();
      final note = const AnkiNoteBuilder().build(
        lookup: result,
        contextLine: example,
        settings: settings,
      );
      _ankiMessage = switch (await _anki.add(note)) {
        AnkiExportOutcome.handedOver => AnkiHandedOver(result.entry.headword),
        AnkiExportOutcome.ankiNotInstalled => const AnkiNotInstalled(),
      };
    } on ArgumentError catch (e) {
      _ankiMessage = AnkiFailed(
        'The Anki settings cannot make a note: ${e.message} '
        'Fix them under Settings.',
      );
      _log('anki settings invalid', e);
    } on Object catch (e) {
      _ankiMessage = AnkiFailed(describeReaderError(e));
      _log('anki add failed', e);
    }
    _notify();
  }

  void consumeAnkiMessage() {
    _ankiMessage = null;
  }

  // --- plumbing -------------------------------------------------------------

  void _notify() {
    if (!_disposed) {
      notifyListeners();
    }
  }

  void _log(String what, Object error) {
    developer.log(what, name: 'reader', error: error, level: 900);
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(_subscription?.cancel());
    _subscription = null;
    super.dispose();
  }
}
