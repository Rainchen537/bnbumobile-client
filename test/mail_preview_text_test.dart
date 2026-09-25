import 'package:bnbu_me/utils/mail_preview_text.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('named, numeric and repeated entities become readable preview text', () {
    expect(
      normalizeMailPreviewText('各位同学： &nbsp; 近日，\n A&amp;B &#160; &#x1F600;'),
      '各位同学： 近日， A&B 😀',
    );
    expect(
      normalizeMailPreviewText(
        '&amp;nbsp; A &amp;amp; B &quot;C&quot; &apos;D&apos;',
      ),
      'A & B "C" \'D\'',
    );
    expect(
      normalizeMailPreviewText('one&nbsp two\u202fthree&ensp;four&emsp;five'),
      'one two three four five',
    );
    expect(
      normalizeMailPreviewText('&copy; &euro; &#x4E2D;&#25991;'),
      '© € 中文',
    );
  });
  test('plain prose, URLs and unknown names are preserved as text', () {
    const plain =
        'A < B & C > D; https://example.test/?a=1&b=2 &notables; &unknown;';
    expect(normalizeMailPreviewText(plain), plain);
    expect(
      normalizeMailPreviewText('&lt;script&gt;literal&lt;/script&gt;'),
      '<script>literal</script>',
    );
    expect(
      normalizeMailPreviewText('Contact <a@example.test>'),
      'Contact <a@example.test>',
    );
  });
  test('ordinary normalized previews remain stable on repeated reads', () {
    for (final raw in [
      'A&amp;nbsp;B',
      'A &amp;amp; B',
      '中文 &#x1F600;',
      '&notables;',
    ]) {
      final once = normalizeMailPreviewText(raw);
      expect(normalizeMailPreviewText(once), once);
    }
  });
}
