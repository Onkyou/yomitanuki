// Keeps ONNX Runtime linked into the app (.claude/wp2/NOTES.md D2.5).
//
// onnxruntime-c is a STATIC xcframework and this plugin is a static
// framework, so the linker only keeps object files something references.
// Two things make the runtime reachable from dart:ffi:
//
//  1. ort_ffi_get_api_base references OrtGetApiBase, which drags the whole
//     runtime in (the OrtApi struct points at everything).
//  2. OrtFfiAnchor is an Objective-C class, so CocoaPods' -ObjC linker flag
//     forces THIS object file into the app; a plain C file would itself be
//     dropped as unreferenced.
//
// Dart looks up OrtGetApiBase through DynamicLibrary.process() and falls
// back to ort_ffi_get_api_base (same signature).
#import <Foundation/Foundation.h>

#include "onnxruntime_c_api.h"

@interface OrtFfiAnchor : NSObject
@end

@implementation OrtFfiAnchor
@end

__attribute__((visibility("default"))) __attribute__((used))
const OrtApiBase *ort_ffi_get_api_base(void) {
  return OrtGetApiBase();
}
