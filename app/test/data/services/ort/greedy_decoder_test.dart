import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:yomitanuki/data/services/ort/greedy_decoder.dart';
import 'package:yomitanuki/data/services/ort/inference_error.dart';

/// A logits source that answers from a script: call n returns a row whose
/// argmax is `script[n]`, and records every prefix it was given.
class ScriptedLogits {
  ScriptedLogits(this.script, {this.vocabSize = 8});

  final List<int> script;
  final int vocabSize;
  final List<List<int>> prefixes = [];

  Float32List call(Int64List inputIds) {
    prefixes.add(inputIds.toList());
    final row = Float32List(vocabSize);
    row[script[prefixes.length - 1]] = 1;
    return row;
  }
}

void main() {
  const decoder = GreedyDecoder();

  test('starts with [2], appends the argmax of each row, stops at 3', () {
    final logits = ScriptedLogits([2, 5, 7, 3, 6]);

    expect(decoder.decode(logits.call), [2, 2, 5, 7, 3]);
  });

  test('every step sees the whole prefix (no KV cache, D0.2)', () {
    final logits = ScriptedLogits([4, 5, 3]);

    decoder.decode(logits.call);

    expect(logits.prefixes, [
      [2],
      [2, 4],
      [2, 4, 5],
    ]);
  });

  test('stops after maxLength ids in all, like the reference loop', () {
    final logits = ScriptedLogits(List.filled(400, 5));

    final ids = const GreedyDecoder(maxLength: 300).decode(logits.call);

    expect(ids.length, 300);
    expect(ids.first, 2);
    expect(ids.where((id) => id == 5).length, 299);
    expect(logits.prefixes.length, 299);
  });

  test('argmax picks the first of equal maxima, as numpy does', () {
    Float32List tie(Int64List _) =>
        Float32List.fromList([0.5, 0.9, 0.9, 0.1, 0.9, 0.0]);

    final ids = const GreedyDecoder(stopId: 1).decode(tie);

    expect(ids, [2, 1]);
  });

  test('a stop id as the very first token ends the sequence', () {
    expect(decoder.decode(ScriptedLogits([3]).call), [2, 3]);
  });

  test('startId and stopId are configurable', () {
    final logits = ScriptedLogits([1, 0]);

    expect(const GreedyDecoder(startId: 7, stopId: 0).decode(logits.call), [
      7,
      1,
      0,
    ]);
  });

  test('a NaN in the logits row is an InferenceError, not a silent pick', () {
    Float32List nan(Int64List _) =>
        Float32List.fromList([0.1, double.nan, 0.9, 0.2]);

    expect(
      () => decoder.decode(nan),
      throwsA(
        isA<InferenceError>().having(
          (e) => e.message,
          'message',
          contains('NaN'),
        ),
      ),
    );
  });

  test('an empty logits row is a programming error', () {
    expect(
      () => decoder.decode((_) => Float32List(0)),
      throwsA(isA<StateError>()),
    );
  });
}
