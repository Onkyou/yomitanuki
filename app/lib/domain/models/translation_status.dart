/// Whether the device can translate Japanese to English offline (WP6c).
enum TranslationStatus {
  /// Both languages are on the device; translating works.
  installed,

  /// Supported, but the reader has to download the language packs first.
  downloadNeeded,

  /// This device cannot translate the pair.
  unsupported,

  /// The platform's translation API is too new for this iOS version.
  requiresNewerOs,
}
