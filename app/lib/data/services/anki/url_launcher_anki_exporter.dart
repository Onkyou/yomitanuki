import 'package:url_launcher/url_launcher.dart';

import '../../../domain/models/anki_note.dart';
import '../../../domain/ports/anki_exporter.dart';
import 'anki_url.dart';

/// Answers whether a URL can be opened, or opens it; `url_launcher`'s
/// `canLaunchUrl` / `launchUrl` in the app, closures in tests.
typedef UrlAction = Future<bool> Function(Uri url);

/// [AnkiExporter] over AnkiMobile's URL scheme via `url_launcher` (WP5).
///
/// Every add foregrounds AnkiMobile (WP0 C14); it returns to the app through
/// the `x-success` URL, which `ios/Runner/Info.plist` registers under the
/// `yomitanuki` scheme (D5.3). `canLaunchUrl` for `anki://` needs that
/// plist's `LSApplicationQueriesSchemes` entry.
class UrlLauncherAnkiExporter implements AnkiExporter {
  UrlLauncherAnkiExporter({
    bool allowDuplicates = false,
    Uri? returnUrl,
    this._canLaunch = canLaunchUrl,
    this._launch = _launchExternally,
  }) : _urls = AnkiUrlBuilder(
         returnUrl: returnUrl ?? defaultReturnUrl,
         allowDuplicates: allowDuplicates,
       );

  /// The URL AnkiMobile opens after adding (D5.3).
  static final Uri defaultReturnUrl = Uri.parse('yomitanuki://anki-return');

  final AnkiUrlBuilder _urls;
  final UrlAction _canLaunch;
  final UrlAction _launch;

  @override
  Future<AnkiExportOutcome> add(AnkiNote note) async {
    final url = _urls.addNote(note);
    if (!await _canLaunch(url)) return AnkiExportOutcome.ankiNotInstalled;
    // `launchUrl` answers false only when iOS could not open the URL, which
    // for a custom scheme means no app handles it (D5.4).
    if (!await _launch(url)) return AnkiExportOutcome.ankiNotInstalled;
    return AnkiExportOutcome.handedOver;
  }
}

Future<bool> _launchExternally(Uri url) =>
    launchUrl(url, mode: LaunchMode.externalApplication);
