import 'dart:typed_data';

/// The logits for the last position of [inputIds] (`logits[0, -1]`, one
/// float per vocabulary entry). The ORT decoder graph in the worker, a
/// scripted list in tests.
typedef LastLogits = Float32List Function(Int64List inputIds);

/// manga-ocr's greedy decode loop (WP0 D0.2: no beam search, no KV cache, no
/// n-gram rule), the reference being `OrtMangaOcr.generate_ids` in
/// `wp0/ocr_ort.py`: ids start as `[startId]`, every step runs the decoder on
/// the whole prefix and appends the argmax of the last row, until [stopId]
/// is appended or the sequence holds [maxLength] ids in all.
///
/// Pure: the caller supplies the step, so the loop is tested without ORT.
class GreedyDecoder {
  const GreedyDecoder({
    this.startId = 2,
    this.stopId = 3,
    this.maxLength = 300,
  });

  /// `[CLS]`.
  final int startId;

  /// `[SEP]`.
  final int stopId;

  /// `MAX_LEN` in the reference: the longest id sequence returned, start id
  /// included, so at most `maxLength - 1` decoder runs.
  final int maxLength;

  /// The id sequence including [startId] (and [stopId] when it was reached).
  /// The first generated token is usually [startId] again (WP0b); that is
  /// what the model does, not a bug.
  List<int> decode(LastLogits step) {
    final ids = <int>[startId];
    while (ids.length < maxLength) {
      final next = _argmax(step(Int64List.fromList(ids)));
      ids.add(next);
      if (next == stopId) break;
    }
    return ids;
  }

  /// numpy's argmax: the first index of the maximum.
  static int _argmax(Float32List row) {
    if (row.isEmpty) {
      throw StateError('the decoder produced an empty logits row');
    }
    var best = 0;
    for (var i = 1; i < row.length; i++) {
      if (row[i] > row[best]) best = i;
    }
    return best;
  }
}
