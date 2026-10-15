import 'package:flutter_test/flutter_test.dart';
import 'package:yomitanuki/domain/text/html.dart';

void main() {
  test('& < > are escaped, quotes are left alone', () {
    expect(escapeHtml('R&D <b> "x" \'y\''), 'R&amp;D &lt;b&gt; "x" \'y\'');
  });

  test('newlines become <br> after escaping', () {
    expect(escapeHtml('a<\nb'), 'a&lt;<br>b');
  });
}
