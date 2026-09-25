import 'package:flutter_test/flutter_test.dart';
import 'package:bnbu_me/models/assistant_text.dart';

void main() {
  test('repairs double escaped paragraphs and list separators', () {
    expect(
      normalizeAssistantProse(
        r'部门信息。\n\n联系方式：\n- 邮箱：office@example.org\n- 地点：T8\n\n需要打开吗？',
      ),
      '部门信息。\n\n联系方式：\n- 邮箱：office@example.org\n- 地点：T8\n\n需要打开吗？',
    );
  });
  test('preserves code formulas paths and ordinary Markdown', () {
    const source = r'`print("\n\n")` 路径 C:\new\notes $\nu + \nabla$';
    expect(normalizeAssistantProse(source), source);
    expect(
      normalizeAssistantProse(
        '```text\n'
        r'\n\n\n- literal'
        '\n```',
      ),
      '```text\n'
      r'\n\n\n- literal'
      '\n```',
    );
    expect(normalizeAssistantProse('正常\n\n- 列表'), '正常\n\n- 列表');
  });
  test('normalization is idempotent and keeps literal inline escapes', () {
    const source = r'正文\n\n- 正文\n- `\n- code`';
    final result = normalizeAssistantProse(source);
    expect(normalizeAssistantProse(result), result);
    expect(result, contains(r'`\n- code`'));
  });
}
