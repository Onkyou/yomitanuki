// `toHiragana` lives in the domain (`LineGlosser` and `furigana` need it and
// the domain must not import the data layer); this keeps the dictionary
// service's own imports unchanged.
export '../../../domain/text/kana.dart';
