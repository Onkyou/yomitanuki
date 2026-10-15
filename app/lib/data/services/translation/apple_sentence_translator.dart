import 'package:flutter/services.dart';
import 'package:translation_ios/translation_ios.dart';

import '../../../domain/errors.dart';
import '../../../domain/models/translation_status.dart';
import '../../../domain/ports/sentence_translator.dart';

/// [SentenceTranslator] on Apple's Translation framework through the
/// `translation_ios` plugin (WP6c, D6c.1). The plugin's channel codes become
/// the domain's typed errors here, so nothing above this file sees a
/// [PlatformException].
class AppleSentenceTranslator implements SentenceTranslator {
  AppleSentenceTranslator(this._plugin);

  /// The real plugin on its default channel, so the composition root does not
  /// import the plugin (like `LazyInference.production()`).
  factory AppleSentenceTranslator.production() =>
      AppleSentenceTranslator(TranslationIos());

  final TranslationIos _plugin;

  @override
  Future<TranslationStatus> status() async => switch (await _plugin.status()) {
    TranslationIosStatus.installed => TranslationStatus.installed,
    TranslationIosStatus.supported => TranslationStatus.downloadNeeded,
    TranslationIosStatus.unsupported => TranslationStatus.unsupported,
    TranslationIosStatus.requiresNewerOs => TranslationStatus.requiresNewerOs,
  };

  @override
  Future<String> translate(String line) async {
    if (line.trim().isEmpty) {
      return '';
    }
    final List<String?> out;
    try {
      out = await _plugin.translate([line]);
    } on PlatformException catch (e) {
      throw switch (e.code) {
        'notInstalled' => const TranslationUnavailableError(
          TranslationStatus.downloadNeeded,
        ),
        'requiresNewerOs' => const TranslationUnavailableError(
          TranslationStatus.requiresNewerOs,
        ),
        _ => TranslationFailedError('${e.code}: ${e.message}'),
      };
    }
    final text = out.isEmpty ? null : out.first;
    if (text == null) {
      throw const TranslationFailedError('the framework returned no text');
    }
    return text;
  }
}
