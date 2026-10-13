// Keeps ONNX Runtime linked into the app.
//
// onnxruntime-c ships a static xcframework; without a reference from compiled
// code the linker drops OrtGetApiBase and dart:ffi finds nothing to look up.
// This one exported function is that reference. Dart calls it (not
// OrtGetApiBase directly) so the lookup works whether the pod's own symbol is
// re-exported from this framework or not.
#include "onnxruntime_c_api.h"

__attribute__((visibility("default"))) __attribute__((used))
const OrtApiBase* ort_ffi_get_api_base(void) {
  return OrtGetApiBase();
}
