import 'package:yomitanuki/domain/models/bgra_image.dart';
import 'package:yomitanuki/domain/ports/photo_picker.dart';

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
