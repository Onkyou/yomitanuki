import 'dart:convert';

import '../../../domain/models/anki_note.dart';

/// Builds AnkiMobile `addnote` URLs (`.claude/wp5/NOTES.md` D5.1, D5.2).
///
/// Shape, from https://docs.ankiweb.net/ankimobile/url-schemes:
///
///     anki://x-callback-url/addnote?type=NOTE_TYPE&deck=DECK
///         &fldFIELD=VALUE…&tags=TAG TAG[&dupes=1]&x-success=URL
///
/// "Fields are entered by prefixing their name with 'fld'", "Special
/// characters in the URL must be escaped", and `dupes=1` "allow[s] a note to
/// be added even if the same content is on an existing note".
///
/// Pure Dart, no Flutter: the exporter wraps it, the tests pin the exact
/// strings.
class AnkiUrlBuilder {
  const AnkiUrlBuilder({required this.returnUrl, this.allowDuplicates = false});

  /// Sent as `x-success`; AnkiMobile opens it after the note is added.
  final Uri returnUrl;

  /// `false` (the default) sends no `dupes` parameter, so AnkiMobile refuses
  /// a note whose first field already exists (D5.2). `true` sends `dupes=1`.
  final bool allowDuplicates;

  Uri addNote(AnkiNote note) {
    final params = StringBuffer()
      ..write('type=')
      ..write(percentEncode(note.noteType))
      ..write('&deck=')
      ..write(percentEncode(note.deck));
    for (final MapEntry(key: name, value: text) in note.fields.entries) {
      if (text.isEmpty) continue;
      params
        ..write('&fld')
        ..write(percentEncode(name))
        ..write('=')
        ..write(percentEncode(text));
    }
    if (note.tags.isNotEmpty) {
      params
        ..write('&tags=')
        ..write(percentEncode(note.tags.join(' ')));
    }
    if (allowDuplicates) params.write('&dupes=1');
    params
      ..write('&x-success=')
      ..write(percentEncode(returnUrl.toString()));
    return Uri.parse('anki://x-callback-url/addnote?$params');
  }
}

const _unreserved =
    'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~';

/// Percent-encodes [text] as UTF-8, leaving only RFC 3986 unreserved
/// characters bare. Stricter than [Uri.encodeComponent], which also keeps
/// `!*'()`; Anki's docs ask for every special character to be escaped and
/// this is what the Shortcuts "URL encode" action they recommend produces.
String percentEncode(String text) {
  final out = StringBuffer();
  for (final byte in utf8.encode(text)) {
    if (byte < 0x80 && _unreserved.contains(String.fromCharCode(byte))) {
      out.writeCharCode(byte);
    } else {
      out
        ..write('%')
        ..write(byte.toRadixString(16).toUpperCase().padLeft(2, '0'));
    }
  }
  return out.toString();
}
