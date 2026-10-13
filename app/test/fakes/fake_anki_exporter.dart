import 'package:yomitanuki/domain/models/anki_note.dart';
import 'package:yomitanuki/domain/ports/anki_exporter.dart';

/// Records every note and answers [outcome], or throws [error].
class FakeAnkiExporter implements AnkiExporter {
  FakeAnkiExporter({this.outcome = AnkiExportOutcome.handedOver, this.error});

  AnkiExportOutcome outcome;
  Object? error;
  final List<AnkiNote> notes = [];

  @override
  Future<AnkiExportOutcome> add(AnkiNote note) async {
    notes.add(note);
    final e = error;
    if (e != null) {
      Error.throwWithStackTrace(e, StackTrace.current);
    }
    return outcome;
  }
}
