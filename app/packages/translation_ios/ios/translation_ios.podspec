#
# translation_ios: Apple's Translation framework for Yomitanuki, over a method
# channel (Classes/TranslationIosPlugin.swift).
#
# The framework is iOS 18+ and the session API this plugin uses iOS 26+, but the
# app's deployment target stays 15.1 (onnxruntime-c needs it), so Translation is
# weak-linked and every use in the Swift file sits behind #available.
#
Pod::Spec.new do |s|
  s.name             = 'translation_ios'
  s.version          = '0.1.0'
  s.summary          = 'On-device Japanese to English translation for Yomitanuki.'
  s.description      = <<-DESC
A method-channel plugin over Apple's Translation framework (iOS 26+), weak-linked so the app still runs on older systems.
                       DESC
  s.homepage         = 'https://github.com/mcmaffin/yomitanuki'
  s.license          = { :type => 'MIT' }
  s.author           = { 'Yomitanuki' => '5831176+Onkyou@users.noreply.github.com' }

  s.source           = { :path => '.' }
  s.source_files     = 'Classes/**/*'
  s.dependency 'Flutter'
  s.platform = :ios, '15.1'
  s.swift_version = '5.0'
  s.weak_frameworks = 'Translation'

  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES',
    'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386',
  }
end
