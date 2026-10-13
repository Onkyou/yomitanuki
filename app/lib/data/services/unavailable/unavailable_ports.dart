/// Stand-ins for the ports whose real adapters are built on other branches.
/// Each call throws [NotWiredError], which the reader shows as a message.
/// At merge: WP2b replaces [UnavailableTextDetector] and [UnavailableOcrEngine],
/// WP3 replaces [UnavailableDictionary], WP5 replaces [UnavailableAnkiExporter],
/// all in `AppDependencies.production()` and nowhere else.
library;

import '../../../domain/errors.dart';
import '../../../domain/models/anki_note.dart';
import '../../../domain/models/bgra_image.dart';
import '../../../domain/models/dictionary_entry.dart';
import '../../../domain/models/lookup_result.dart';
import '../../../domain/models/ocr_result.dart';
import '../../../domain/models/text_block.dart';
import '../../../domain/ports/anki_exporter.dart';
import '../../../domain/ports/dictionary.dart';
import '../../../domain/ports/ocr_engine.dart';
import '../../../domain/ports/text_detector.dart';

class UnavailableTextDetector implements TextDetector {
  const UnavailableTextDetector();

  @override
  Future<List<TextBlock>> detect(BgraImage image) async =>
      throw NotWiredError('TextDetector');

  @override
  Future<void> dispose() async {}
}

class UnavailableOcrEngine implements OcrEngine {
  const UnavailableOcrEngine();

  @override
  Future<OcrResult> recognise(BgraImage crop) async =>
      throw NotWiredError('OcrEngine');

  @override
  Future<void> dispose() async {}
}

class UnavailableDictionary implements Dictionary {
  const UnavailableDictionary();

  @override
  Future<List<LookupResult>> lookupAt(String text, int index) async =>
      throw NotWiredError('Dictionary');

  @override
  Future<KanjiEntry?> kanji(String literal) async =>
      throw NotWiredError('Dictionary');
}

class UnavailableAnkiExporter implements AnkiExporter {
  const UnavailableAnkiExporter();

  @override
  Future<AnkiExportOutcome> add(AnkiNote note) async =>
      throw NotWiredError('AnkiExporter');
}
