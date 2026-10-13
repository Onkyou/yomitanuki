import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'png.dart';

void main() {
  // A 4x5 RGB PNG whose five rows use filter types 0..4 and whose IDAT is
  // split in two; the expected bytes are what Pillow decodes it to.
  const fixture =
      'iVBORw0KGgoAAAANSUhEUgAAAAQAAAAFCAIAAADtz9qMAAAAB0lEQVR4nAFBAL7/tfnpAwAAAEVJ'
      'REFUAKVNyhglMLsdbRMs3gHWI3tYtqMRmQGMp1ICQSEZqHAeXuoVlaXAAxX8H4OnTiFNT/Ks5wRc'
      'CzD/1UWldldDL3MtVRnkHxtB3QAAAABJRU5ErkJggg==';
  const expected = [
    202, 77, 165, 255, 48, 37, 24, 255, 109, 29, 187, 255, 222, 44, 19, 255, //
    123, 35, 214, 255, 30, 217, 46, 255, 31, 114, 63, 255, 113, 25, 203, 255, //
    148, 68, 23, 255, 60, 73, 214, 255, 52, 92, 157, 255, 49, 190, 96, 255, //
    105,
    30,
    32,
    255,
    160,
    218,
    254,
    255,
    185,
    232,
    238,
    255,
    92,
    127,
    153,
    255, //
    153,
    41,
    124,
    255,
    229,
    175,
    253,
    255,
    60,
    37,
    147,
    255,
    175,
    84,
    214,
    255, //
  ];

  test('decodes every filter type and several IDAT chunks into BGRA', () {
    final image = decodePng(base64Decode(fixture));

    expect(image.width, 4);
    expect(image.height, 5);
    expect(image.bytesPerRow, 16);
    expect(image.bytes, expected);
  });

  test('rejects what is not a PNG', () {
    expect(() => decodePng(utf8.encode('hello')), throwsFormatException);
  });
}
