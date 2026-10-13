import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:yomitanuki/data/services/photo/image_picker_photo_picker.dart';

void main() {
  test('a cancelled pick is null', () async {
    final picker = ImagePickerPhotoPicker(pickBytes: () async => null);

    expect(await picker.pickPhoto(), isNull);
  });

  test('picked bytes are decoded into a frame', () async {
    final bytes = await File('test/data/services/photo/fixtures/rgbw_2x2.png')
        .readAsBytes();
    final picker = ImagePickerPhotoPicker(pickBytes: () async => bytes);

    final img = await picker.pickPhoto();

    expect((img!.width, img.height), (2, 2));
  });
}
