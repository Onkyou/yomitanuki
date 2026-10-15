import 'package:flutter/services.dart';

/// What the platform says about translating Japanese to English offline.
enum TranslationIosStatus {
  /// Both languages are on the device; [TranslationIos.translate] works.
  installed,

  /// The pair is supported but a language pack still has to be downloaded.
  supported,

  /// This device cannot translate the pair.
  unsupported,

  /// The Translation framework session API needs iOS 26.
  requiresNewerOs,
}

/// A thin wrapper over the `yomitanuki/translation` method channel that
/// `TranslationIosPlugin.swift` answers. Japanese to English only; the plugin
/// reports failures as [PlatformException]s with the code the Swift side
/// sets (`notInstalled`, `requiresNewerOs`, `translationFailed`) and leaves
/// their meaning to the caller.
class TranslationIos {
  TranslationIos({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel('yomitanuki/translation');

  final MethodChannel _channel;

  Future<TranslationIosStatus> status() async {
    final wire = await _channel.invokeMethod<String>('status');
    return switch (wire) {
      'installed' => TranslationIosStatus.installed,
      'supported' => TranslationIosStatus.supported,
      'requiresNewerOs' => TranslationIosStatus.requiresNewerOs,
      // Anything else, including a status a newer plugin might add: this
      // build cannot translate with it.
      _ => TranslationIosStatus.unsupported,
    };
  }

  /// One entry per input line, in order; `null` where the platform returned
  /// no translation for that line.
  Future<List<String?>> translate(List<String> lines) async {
    final out = await _channel.invokeListMethod<String?>('translate', {
      'lines': lines,
    });
    return out ?? List<String?>.filled(lines.length, null);
  }
}
