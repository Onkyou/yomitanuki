#
# ort_ffi: links ONNX Runtime into the app so dart:ffi can reach it.
#
# The onnxruntime-c pod is a STATIC xcframework, so the linker only keeps the
# object files something references. Classes/ort_ffi.c references
# OrtGetApiBase, which drags the whole runtime (the OrtApi struct points at
# everything) into this plugin's framework, where DynamicLibrary.process()
# finds it. The version is pinned exactly: the Dart bindings are generated
# from a specific onnxruntime_c_api.h (tool/ffigen.dart) and request a
# specific ORT_API_VERSION (.claude/wp2/NOTES.md D2.4).
#
Pod::Spec.new do |s|
  s.name             = 'ort_ffi'
  s.version          = '0.1.0'
  s.summary          = 'ONNX Runtime for Yomitanuki via dart:ffi.'
  s.description      = <<-DESC
Links the onnxruntime-c pod into the app and keeps its C API entry point exported for dart:ffi.
                       DESC
  s.homepage         = 'https://github.com/mcmaffin/yomitanuki'
  s.license          = { :type => 'MIT' }
  s.author           = { 'Yomitanuki' => '5831176+Onkyou@users.noreply.github.com' }

  s.source           = { :path => '.' }
  s.source_files     = 'Classes/**/*'
  s.dependency 'onnxruntime-c', '1.30.0'

  # onnxruntime-c 1.30.0 requires iOS 15.1; the app's deployment target matches.
  s.platform = :ios, '15.1'
  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES',
    'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386',
  }
end
