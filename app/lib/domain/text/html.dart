import 'dart:convert';

const _escape = HtmlEscape(HtmlEscapeMode.element);

/// [text] as HTML element content: `&`, `<`, `>` escaped, newlines as `<br>`.
/// Anki renders field text as HTML (D5.5), so every value goes through here
/// before any markup is composed around it.
String escapeHtml(String text) =>
    _escape.convert(text).replaceAll('\n', '<br>');
