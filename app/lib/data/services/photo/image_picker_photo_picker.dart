import 'dart:typed_data';

import 'package:image_picker/image_picker.dart';

import '../../../domain/models/bgra_image.dart';
import '../../../domain/ports/photo_picker.dart';
import 'photo_decoder.dart';

/// `image_picker`-backed [PhotoPicker]: the photo library, full resolution,
/// decoded with [decodePhoto]. [pickBytes] is the plugin call, swapped in
/// tests.
class ImagePickerPhotoPicker implements PhotoPicker {
  ImagePickerPhotoPicker({Future<Uint8List?> Function()? pickBytes})
    : _pickBytes = pickBytes ?? _pickFromLibrary;

  final Future<Uint8List?> Function() _pickBytes;

  @override
  Future<BgraImage?> pickPhoto() async {
    final bytes = await _pickBytes();
    return bytes == null ? null : decodePhoto(bytes);
  }

  static Future<Uint8List?> _pickFromLibrary() async {
    final file = await ImagePicker().pickImage(source: ImageSource.gallery);
    return file?.readAsBytes();
  }
}
