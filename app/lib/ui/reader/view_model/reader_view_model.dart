import 'dart:async';
import 'dart:developer' as developer;
import 'dart:ui';

import 'package:flutter/foundation.dart';

import '../../../domain/errors.dart';
import '../../../domain/models/anki_note.dart';
import '../../../domain/models/anki_settings.dart';
import '../../../domain/models/bgra_image.dart';
import '../../../domain/models/dictionary_entry.dart';
import '../../../domain/models/line_gloss.dart';
import '../../../domain/models/lookup_result.dart';
import '../../../domain/models/ocr_capture.dart';
import '../../../domain/models/text_block.dart';
import '../../../domain/models/translation_status.dart';
import '../../../domain/ports/anki_exporter.dart';
import '../../../domain/ports/dictionary.dart';
import '../../../domain/ports/frame_source.dart';
import '../../../domain/ports/ocr_capture_log.dart';
import '../../../domain/ports/ocr_engine.dart';
import '../../../domain/ports/photo_picker.dart';
import '../../../domain/ports/sentence_translator.dart';
import '../../../domain/ports/settings_repository.dart';
import '../../../domain/ports/text_detector.dart';
import '../../../domain/use_cases/anki_note_builder.dart';
import '../../../domain/use_cases/line_glosser.dart';
import 'reader_errors.dart';
import 'reader_state.dart';
import 'rect_iou.dart';

/// The live reader: samples the camera at ~1 Hz (D0.13), detects blocks on
/// the sampled frame, OCRs a block on tap from that same frame (D0.12), cuts
/// the read line into dictionary words (WP6b) and translates it (WP6c), looks a
/// tapped character up and hands a note to Anki.
///
/// Every port call is awaited inside a try/catch and surfaces as a state; the
/// view model never throws into the view. Nothing in here runs inference: the
/// adapters behind [TextDetector] and [OcrEngine] own their isolates.
///
/// A result is only committed to the state that asked for it (D4.16): a
/// detection carries the [_generation] it started in and is dropped when
/// `pickPhoto`, `backToCamera` or `stop` moved on; an OCR or lookup result is
/// dropped when its `OcrRunning`/`LookupLoading` state is no longer the
/// current one. A gloss or translation lands when the current state is still
/// an `OcrText` over the same crop (D6c.3), onto that state, so whichever of
/// the two comes second keeps the first.
class ReaderViewModel extends ChangeNotifier {
  ReaderViewModel({
    required FrameSource frameSource,
    required PhotoPicker photoPicker,
    required TextDetector detector,
    required OcrEngine ocr,
    required Dictionary dictionary,
    required AnkiExporter anki,
    required SettingsRepository settings,
    required OcrCaptureLog captureLog,
    required SentenceTranslator translator,
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
         captureLog,
         translator,
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
    this._captureLog,
    this._translator,
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
  final OcrCaptureLog _captureLog;
  final SentenceTranslator _translator;
  final DateTime Function() _clock;

  /// One detection per interval; frames in between are dropped (D0.13).
  final Duration detectionInterval;

  /// Margin added around a block before OCR, as a fraction of the block's
  /// own width and height on each side (WP0 D0.6 used 8 %).
  final double cropMargin;

  /// Overlap with the tapped box below which a current box is a different
  /// bubble (D6a.2).
  static const selectedMinIou = 0.5;

  /// Consecutive empty detections before the "no bubbles" hint shows.
  static const emptyRunsForHint = 3;

  StreamSubscription<BgraImage>? _subscription;
  DateTime? _lastSampleAt;
  int _inFlight = 0;
  int _generation = 0;
  int _emptyRuns = 0;
  bool _disposed = false;
  TranslationStatus? _translationStatus;
  bool _translationActive = false;

  ReaderSource _source = ReaderSource.camera;
  CameraState _cameraState = const CameraIdle();
  BgraImage? _frame;
  List<TextBlock> _blocks = const [];
  String? _notice;
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
  /// Unmodifiable.
  List<TextBlock> get blocks => _blocks;

  /// A detection is in flight.
  bool get scanning => _inFlight > 0;

  /// A detector or picker failure, shown as a banner until [dismissNotice]
  /// or the next source change.
  String? get notice => _notice;

  /// Three detections in a row found nothing: the page is probably too far
  /// away or moving (UX self-assessment, WP4 notes).
  bool get noBlocksHint => _emptyRuns >= emptyRunsForHint;
  OcrState get ocrState => _ocrState;

  /// While the OCR sheet is open: the current box that still is the tapped
  /// bubble (IoU >= [selectedMinIou] against the tapped box), so the overlay
  /// can highlight it as the live boxes move (D6a.2). `null` when the sheet
  /// is closed or the bubble is no longer in view.
  Rect? get selectedBox {
    final tapped = switch (_ocrState) {
      OcrIdle() => null,
      OcrRunning(:final block) ||
      OcrText(:final block) ||
      OcrFailed(:final block) => block.box,
    };
    if (tapped == null) {
      return null;
    }
    Rect? best;
    var bestIou = selectedMinIou;
    for (final candidate in _blocks) {
      final iou = rectIou(tapped, candidate.box);
      if (iou >= bestIou) {
        best = candidate.box;
        bestIou = iou;
      }
    }
    return best;
  }

  /// A translation is running for the read on screen, or has landed: the
  /// switch is on and the packs are installed (WP6c). The sheet shows its
  /// "Translating…" line while this holds and the translation is null.
  bool get translationActive => _translationActive;

  LookupState get lookupState => _lookupState;
  AnkiMessage? get ankiMessage => _ankiMessage;

  // --- camera ---------------------------------------------------------------

  Future<void> start() async {
    _subscription ??= _frameSource.frames.listen(
      _onFrame,
      onError: _onFrameError,
    );
    _source = ReaderSource.camera;
    // The reader may have installed the language packs while away.
    _translationStatus = null;
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
    _generation++;
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
    if (_source != ReaderSource.camera || _inFlight > 0) {
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
    final generation = _generation;
    _inFlight++;
    notifyListeners();
    try {
      final blocks = await _detector.detect(frame);
      if (generation != _generation) {
        return;
      }
      _frame = frame;
      _blocks = List.unmodifiable(blocks);
      _notice = null;
      _emptyRuns = blocks.isEmpty ? _emptyRuns + 1 : 0;
    } on Object catch (e) {
      _log('detection failed', e);
      if (generation != _generation) {
        return;
      }
      _frame = frame;
      _blocks = const [];
      _notice = describeReaderError(e);
    } finally {
      _inFlight--;
      _notify();
    }
  }

  void dismissNotice() {
    _notice = null;
    notifyListeners();
  }

  // --- photo fallback -------------------------------------------------------

  Future<void> pickPhoto() async {
    final BgraImage? photo;
    try {
      photo = await _photoPicker.pickPhoto();
    } on Object catch (e) {
      _log('photo pick failed', e);
      _notice = describeReaderError(e);
      _notify();
      return;
    }
    if (photo == null) {
      return;
    }
    _source = ReaderSource.photo;
    await stop();
    // Show the photo at once, not the last camera frame under the old boxes.
    _frame = photo;
    _blocks = const [];
    _notice = null;
    _emptyRuns = 0;
    _ocrState = const OcrIdle();
    _lookupState = const LookupIdle();
    await _detect(photo);
  }

  Future<void> backToCamera() async {
    _generation++;
    _frame = null;
    _blocks = const [];
    _notice = null;
    _emptyRuns = 0;
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
    final crop = _cropWithMargin(frame, block.box);
    final running = OcrRunning(block, crop);
    _ocrState = running;
    _lookupState = const LookupIdle();
    _translationActive = false;
    notifyListeners();
    OcrState next;
    var text = '';
    var elapsed = Duration.zero;
    try {
      final result = await _ocr.recognise(crop);
      text = result.text;
      elapsed = result.elapsed;
      next = OcrText(block, crop, text);
    } on Object catch (e) {
      _log('ocr failed', e);
      next = OcrFailed(block, crop, describeReaderError(e));
    }
    if (!identical(_ocrState, running)) {
      return; // dismissed while reading
    }
    _ocrState = next;
    _notify();
    // Concurrent: neither the translation nor the capture (diagnostics) may
    // wait for the walk, nor the walk for them.
    await Future.wait([
      if (next is OcrText) _addGloss(next),
      if (next is OcrText) _addTranslation(next),
      _capture(
        OcrCapture(
          crop: crop,
          frameWidth: frame.width,
          frameHeight: frame.height,
          text: text,
          elapsed: elapsed,
          at: _clock(),
        ),
      ),
    ]);
  }

  /// Cuts the read line into dictionary words (WP6b) and swaps the gloss into
  /// the state, if [read] still is the sheet on screen. A failure is logged
  /// and leaves the line without a gloss: it stays readable and every
  /// character stays tappable, so it is not worth a notice.
  Future<void> _addGloss(OcrText read) async {
    if (read.text.trim().isEmpty) {
      return;
    }
    // The dictionary is synchronous under its async signature (D3.6), so the
    // walk would otherwise run to the end before the text was ever drawn.
    await Future<void>.delayed(Duration.zero);
    if (!_isCurrent(read)) {
      return;
    }
    final LineGloss gloss;
    try {
      gloss = await LineGlosser(_dictionary).gloss(read.text);
    } on Object catch (e) {
      _log('gloss failed', e);
      return;
    }
    _land(read, (current) => current.copyWith(gloss: gloss));
  }

  /// Translates the read line (WP6c) when the switch is on and the packs are
  /// installed, and swaps the translation into the state. Never a notice: a
  /// line without a translation is the normal case on a device without the
  /// packs, so failures are only logged.
  Future<void> _addTranslation(OcrText read) async {
    if (read.text.trim().isEmpty) {
      return;
    }
    try {
      if (!await _settings.loadTranslateEnabled()) {
        return;
      }
      _translationStatus ??= await _translator.status();
      if (_translationStatus != TranslationStatus.installed) {
        return;
      }
    } on Object catch (e) {
      _log('translation status failed', e);
      return;
    }
    if (!_isCurrent(read)) {
      return;
    }
    _translationActive = true;
    _notify();
    try {
      final translation = await _translator.translate(read.text);
      _land(read, (current) => current.copyWith(translation: translation));
    } on Object catch (e) {
      _log('translation failed', e);
      if (e is TranslationUnavailableError) {
        // The packs went away since the status was cached: stop trying until
        // the next start() asks again.
        _translationStatus = e.status;
      }
      if (_isCurrent(read)) {
        // Nothing will land: the sheet stops saying it is translating.
        _translationActive = false;
        _notify();
      }
    }
  }

  /// [read] is still what the sheet shows: same crop, one per read and never
  /// shared (D6c.3). Not `identical(_ocrState, read)`: a gloss or translation
  /// that landed meanwhile replaced the instance.
  bool _isCurrent(OcrText read) => switch (_ocrState) {
    OcrText(:final crop) => identical(crop, read.crop),
    _ => false,
  };

  void _land(OcrText read, OcrText Function(OcrText current) update) {
    if (_isCurrent(read)) {
      _ocrState = update(_ocrState as OcrText);
      _notify();
    }
  }

  /// Diagnostics only: whatever goes wrong here is logged and must not touch
  /// the sheet the reader is already looking at.
  Future<void> _capture(OcrCapture capture) async {
    try {
      if (await _settings.loadSaveCrops()) {
        // The port promises not to throw; the guard keeps that promise local.
        unawaited(
          _captureLog.record(capture).catchError((Object e) {
            _log('capture failed', e);
          }),
        );
      }
    } on Object catch (e) {
      _log('capture settings failed', e);
    }
  }

  /// Detection ran behind the sheet (D6a.1), so there is nothing to catch up
  /// on and a detection in flight still lands.
  void dismissOcr() {
    _ocrState = const OcrIdle();
    _lookupState = const LookupIdle();
    _translationActive = false;
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
    final loading = LookupLoading(index);
    _lookupState = loading;
    notifyListeners();
    LookupState next;
    try {
      final results = await _dictionary.lookupAt(ocr.text, index);
      final kanji = await _kanjiIn(results);
      next = LookupResults(
        index: index,
        results: List.unmodifiable(results),
        kanji: Map.unmodifiable(kanji),
      );
    } on Object catch (e) {
      _log('lookup failed', e);
      next = LookupFailed(index, describeReaderError(e));
    }
    if (!identical(_lookupState, loading)) {
      return; // a later tap (or a dismiss) superseded this lookup
    }
    _lookupState = next;
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
    await _handOver(
      result.entry.headword,
      (settings) => const AnkiNoteBuilder().build(
        lookup: result,
        contextLine: example,
        contextTranslation: ocr is OcrText ? ocr.translation : null,
        settings: settings,
      ),
    );
  }

  /// The whole OCR line as one note (D6b.3). Does nothing until the gloss is
  /// there, or when it found no word: the button is disabled then, and a
  /// note without readings or glosses is not what was asked for.
  Future<void> addSentenceToAnki() async {
    if (_ocrState case OcrText(gloss: final gloss?, :final translation)
        when gloss.hasMatches) {
      await _handOver(
        gloss.line,
        (settings) => const AnkiNoteBuilder().buildSentence(
          gloss: gloss,
          contextTranslation: translation,
          settings: settings,
        ),
      );
    }
  }

  Future<void> _handOver(
    String label,
    AnkiNote Function(AnkiSettings settings) build,
  ) async {
    try {
      final settings = await _settings.loadAnkiSettings();
      final note = build(settings);
      _ankiMessage = switch (await _anki.add(note)) {
        AnkiExportOutcome.handedOver => AnkiHandedOver(label),
        AnkiExportOutcome.ankiNotInstalled => const AnkiNotInstalled(),
      };
    } on ArgumentError catch (e) {
      _log('anki settings invalid', e);
      _ankiMessage = AnkiFailed(
        'The Anki settings cannot make a note: ${e.message} '
        'Fix them under Settings.',
      );
    } on Object catch (e) {
      _log('anki add failed', e);
      _ankiMessage = AnkiFailed(describeReaderError(e));
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

  /// The only place the raw error text goes; the screen gets a sentence
  /// from [describeReaderError].
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
