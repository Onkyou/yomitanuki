import 'dart:io';
import 'dart:typed_data';

import 'package:yomitanuki/domain/models/bgra_image.dart';

/// Decodes the PNG files under `test/goldens/` into [BgraImage]s.
///
/// Deliberately not the engine's codec (`dart:ui`), whose colour management
/// is not part of the WP0b contract: the goldens record the graphs' outputs on
/// exact pixels, so the test must feed exact pixels. This covers what
/// `make_goldens.py` writes (8-bit, non-interlaced grey / RGB / RGBA, any
/// filter type, any number of IDAT chunks) and rejects everything else.
BgraImage decodePng(Uint8List png) {
  const signature = [137, 80, 78, 71, 13, 10, 26, 10];
  if (png.length < 8 || !_startsWith(png, signature)) {
    throw const FormatException('not a PNG file');
  }
  final data = ByteData.sublistView(png);
  var offset = 8;
  int? width;
  int? height;
  int? channels;
  final idat = BytesBuilder(copy: false);
  while (offset + 8 <= png.length) {
    final length = data.getUint32(offset);
    final type = String.fromCharCodes(png, offset + 4, offset + 8);
    final body = Uint8List.sublistView(png, offset + 8, offset + 8 + length);
    switch (type) {
      case 'IHDR':
        width = data.getUint32(offset + 8);
        height = data.getUint32(offset + 12);
        final bitDepth = png[offset + 16];
        final colourType = png[offset + 17];
        final interlace = png[offset + 20];
        channels = switch (colourType) {
          0 => 1,
          2 => 3,
          6 => 4,
          _ => null,
        };
        if (bitDepth != 8 || channels == null || interlace != 0) {
          throw FormatException(
            'unsupported PNG: bit depth $bitDepth, colour type $colourType, '
            'interlace $interlace (only 8-bit grey/RGB/RGBA, non-interlaced)',
          );
        }
      case 'IDAT':
        idat.add(body);
      case 'IEND':
        offset = png.length;
        continue;
    }
    offset += 12 + length;
  }
  if (width == null || height == null || channels == null) {
    throw const FormatException('PNG without IHDR');
  }
  final raw = Uint8List.fromList(ZLibDecoder().convert(idat.takeBytes()));
  return _unfilter(raw, width, height, channels);
}

/// [decodePng] over a file.
BgraImage readPng(String path) => decodePng(File(path).readAsBytesSync());

bool _startsWith(Uint8List bytes, List<int> prefix) {
  for (var i = 0; i < prefix.length; i++) {
    if (bytes[i] != prefix[i]) return false;
  }
  return true;
}

/// Reverses the per-row filters (PNG spec 9.2) and converts to BGRA.
BgraImage _unfilter(Uint8List raw, int width, int height, int channels) {
  final stride = width * channels;
  if (raw.length != height * (stride + 1)) {
    throw FormatException(
      'PNG data is ${raw.length} bytes, expected ${height * (stride + 1)}',
    );
  }
  final out = Uint8List(width * height * 4);
  var previous = Uint8List(stride);
  for (var y = 0; y < height; y++) {
    final filter = raw[y * (stride + 1)];
    final row = Uint8List.sublistView(
      raw,
      y * (stride + 1) + 1,
      (y + 1) * (stride + 1),
    );
    for (var i = 0; i < stride; i++) {
      final a = i >= channels ? row[i - channels] : 0;
      final b = previous[i];
      final c = i >= channels ? previous[i - channels] : 0;
      final predictor = switch (filter) {
        0 => 0,
        1 => a,
        2 => b,
        3 => (a + b) >> 1,
        4 => _paeth(a, b, c),
        _ => throw FormatException('PNG filter type $filter in row $y'),
      };
      row[i] = (row[i] + predictor) & 0xff;
    }
    for (var x = 0; x < width; x++) {
      final src = x * channels;
      final dst = (y * width + x) * 4;
      final (r, g, b, alpha) = switch (channels) {
        1 => (row[src], row[src], row[src], 255),
        3 => (row[src], row[src + 1], row[src + 2], 255),
        _ => (row[src], row[src + 1], row[src + 2], row[src + 3]),
      };
      out[dst] = b;
      out[dst + 1] = g;
      out[dst + 2] = r;
      out[dst + 3] = alpha;
    }
    previous = row;
  }
  return BgraImage(width: width, height: height, bytes: out);
}

int _paeth(int a, int b, int c) {
  final p = a + b - c;
  final pa = (p - a).abs();
  final pb = (p - b).abs();
  final pc = (p - c).abs();
  if (pa <= pb && pa <= pc) return a;
  return pb <= pc ? b : c;
}
