import 'dart:typed_data';

import 'package:image/image.dart' as image;

import '../models/assistant_models.dart';

class StudyPageImageUnavailableException implements Exception {
  const StudyPageImageUnavailableException(this.pageNumber);

  final int pageNumber;

  String get message => '第 $pageNumber 页图像尚未准备好，请稍后重试。';

  @override
  String toString() => message;
}

class StudyPageSnapshot {
  const StudyPageSnapshot({
    required this.documentTitle,
    required this.pageNumber,
    required this.pageCount,
    required this.text,
    this.captureImage,
  });

  final String documentTitle;
  final int pageNumber;
  final int pageCount;
  final String text;
  final Future<Uint8List?> Function()? captureImage;

  String get pageLabel => '第 $pageNumber 页 / 共 $pageCount 页';
}

class StudySkillRequest {
  const StudySkillRequest({required this.prompt, required this.attachments});

  final String prompt;
  final List<AssistantInputAttachment> attachments;
}

enum StudyQuestionScope { currentPage, selectedPages, wholeDocument }

/// 学业模式的精简能力编排层。所有能力都以单页快照为边界。
class StudyModeSkill {
  const StudyModeSkill();

  static const maxVisualPages = 8;
  static const defaultOrganizationInstruction =
      '按页面原有顺序生成随页注释。题目页逐题解释题干和每个选项涉及的概念，不直接列出答案；普通课件保留标题层级、术语、公式、图表关系和必要原文。以整理为主，语言转换只优化表达。';
  static const _maxImageEdge = 1600;
  // Eight prepared pages must stay below the server's decoded 8 MiB request
  // budget. Keeping a little headroom also avoids provider/proxy body limits.
  static const _maxPreparedImageBytes = 960 * 1024;
  static const _pageCaptureTimeout = Duration(seconds: 8);

  Future<StudySkillRequest> organize({
    required StudyPageSnapshot page,
    required String outputLanguage,
    String customInstruction = '',
  }) async {
    return _request(
      page: page,
      task:
          '''
你正在调用“本页内容整理”技能。请只处理提供的这一页，不得混入文档其他页面。
本功能的角色是“随页注释”，不是答案页。恢复本页结构，解释主题、术语、条件、论据、数据、公式、图示和流程，并保留重要术语的原文。
如果本页是题目、测验或练习：按题目顺序逐题注释，逐个解释每一个选项在说什么、涉及什么概念或规则；不得设置“答案”“正确选项”“参考答案”等栏目，不得直接点名、加粗或暗示正确选项，也不得把页面颜色、高亮、勾选或其他答案标记抄成结论。即使页面已经显示答案，也只解释各选项。只有用户在右侧问答中明确索要答案时，才由问答功能回答。
如果本页不是题目：按原有内容层次进行整理和少量必要注释，不套用固定模板。
输出语言优先采用 $outputLanguage。翻译只是表达优化：仅在原文语言与输出语言不一致时自然转换，不要为了翻译破坏原结构。
只在理解确有必要时加入少量注释，并明确标注“注”。看不清或无法从本页确认的内容直接说明，禁止补写。
${customInstruction.trim().isEmpty ? '' : '用户附加要求：${customInstruction.trim()}'}
''',
    );
  }

  Future<StudySkillRequest> answer({
    required StudyPageSnapshot page,
    required String question,
    required String outputLanguage,
  }) async {
    return answerPages(
      pages: [page],
      question: question,
      outputLanguage: outputLanguage,
      scope: StudyQuestionScope.currentPage,
    );
  }

  Future<StudySkillRequest> answerPages({
    required List<StudyPageSnapshot> pages,
    required String question,
    required String outputLanguage,
    required StudyQuestionScope scope,
  }) async {
    if (pages.isEmpty) {
      throw ArgumentError.value(pages, 'pages', '页范围不能为空');
    }
    final scopeText = switch (scope) {
      StudyQuestionScope.currentPage => '本页',
      StudyQuestionScope.selectedPages => '所选页面',
      StudyQuestionScope.wholeDocument => '全文件',
    };
    return _pagesRequest(
      pages: pages,
      task:
          '''
你正在调用“本页教学问答”技能。问题：${question.trim()}
问答范围：$scopeText。只依据提供的页面回答，使用 $outputLanguage。先给直接答案，再按需要解释页面中的概念、图表、公式或因果关系，并在跨页引用时标注页码。
可以进行有助于教学的推理，但必须标为“推断”；页面没有答案时应明确说明，不得借用其他页面或虚构细节。
''',
    );
  }

  Future<StudySkillRequest> _request({
    required StudyPageSnapshot page,
    required String task,
  }) async {
    return _pagesRequest(pages: [page], task: task);
  }

  Future<StudySkillRequest> _pagesRequest({
    required List<StudyPageSnapshot> pages,
    required String task,
  }) async {
    var remainingText = 12000;
    final pageBlocks = <String>[];
    for (final page in pages) {
      final normalized = page.text.trim();
      final take = normalized.length < remainingText
          ? normalized.length
          : remainingText;
      final text = take <= 0 ? '' : normalized.substring(0, take);
      remainingText -= take;
      pageBlocks.add(
        '${page.pageLabel}\n${text.isEmpty ? '（本页没有可提取文字，请读取随附页面图像。）' : text}',
      );
    }
    final attachments = <AssistantInputAttachment>[];
    final capturablePages = pages
        .where((page) => page.captureImage != null)
        .toList(growable: false);
    final visualPages = _representativeVisualPages(capturablePages);
    if (visualPages.isEmpty) {
      throw StudyPageImageUnavailableException(pages.first.pageNumber);
    }
    for (final page in visualPages) {
      Uint8List? captured;
      try {
        captured = await page.captureImage!.call().timeout(_pageCaptureTimeout);
      } catch (_) {
        throw StudyPageImageUnavailableException(page.pageNumber);
      }
      final prepared = captured == null ? null : _preparePageImage(captured);
      if (prepared == null) {
        throw StudyPageImageUnavailableException(page.pageNumber);
      }
      attachments.add(
        AssistantInputAttachment(
          name: 'study-page-${page.pageNumber}.jpg',
          mimeType: 'image/jpeg',
          bytes: prepared,
        ),
      );
    }
    final first = pages.first;
    final imageIndex = attachments
        .map((attachment) => attachment.name)
        .join('、');
    return StudySkillRequest(
      prompt:
          '''$task\n文档：${first.documentTitle}\n提供页数：${pages.length}\n页面图像附件：$imageIndex。必须实际读取这些图像，并与对应页文字共同完成任务。\n页面内容：\n${pageBlocks.join('\n\n')}''',
      attachments: attachments,
    );
  }

  List<StudyPageSnapshot> _representativeVisualPages(
    List<StudyPageSnapshot> pages,
  ) {
    if (pages.length <= maxVisualPages) return pages;
    return [
      for (var index = 0; index < maxVisualPages; index++)
        pages[((pages.length - 1) * index / (maxVisualPages - 1)).round()],
    ];
  }

  Uint8List? _preparePageImage(Uint8List bytes) {
    image.Image? decoded;
    try {
      decoded = image.decodeImage(bytes);
    } catch (_) {
      return null;
    }
    if (decoded == null || decoded.width <= 0 || decoded.height <= 0) {
      return null;
    }
    var prepared = image.bakeOrientation(decoded);
    final longestEdge = prepared.width > prepared.height
        ? prepared.width
        : prepared.height;
    if (longestEdge > _maxImageEdge) {
      final ratio = _maxImageEdge / longestEdge;
      prepared = image.copyResize(
        prepared,
        width: (prepared.width * ratio).round(),
        height: (prepared.height * ratio).round(),
        interpolation: image.Interpolation.average,
      );
    }
    for (final quality in const [92, 84, 76]) {
      final encoded = Uint8List.fromList(
        image.encodeJpg(prepared, quality: quality),
      );
      if (encoded.isNotEmpty && encoded.length <= _maxPreparedImageBytes) {
        return encoded;
      }
    }
    return null;
  }
}
