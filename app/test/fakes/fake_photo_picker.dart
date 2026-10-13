import 'package:yomitanuki/data/services/photo/photo_picker.dart';
import 'package:yomitanuki/domain/models/bgra_image.dart';

/// Hands back [photo] (null = the user cancelled) or throws [error].
class FakePhotoPicker implements PhotoPicker {
  FakePhotoPicker({this.photo, this.error});

  BgraImage? photo;
  Object? error;
  int calls = 0;

  @override
  Future<BgraImage?> pickPhoto() async {
    calls++;
    final e = error;
    if (e != null) {
      Error.throwWithStackTrace(e, StackTrace.current);
    }
    return photo;
  }
}
