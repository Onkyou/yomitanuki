/// The ONNX Runtime wrapper as one library in parts: the parts share the
/// library-private `_OrtApi` (typed function pointers out of the OrtApi
/// struct) without a package-visible accessor on the public classes.
library;

import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import 'bindings/onnxruntime_c_api.g.dart' as b;

part 'ort_api.dart';
part 'ort_exception.dart';
part 'ort_runtime.dart';
part 'ort_session.dart';
part 'ort_session_options.dart';
part 'ort_value.dart';
