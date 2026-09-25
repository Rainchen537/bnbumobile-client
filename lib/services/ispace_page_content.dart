import 'package:html/dom.dart';
import 'package:html/parser.dart' show parseFragment;

import 'courseware_download_plan.dart' show normalizeCoursewareFileUrl;

class IspacePageLink {
  const IspacePageLink({
    required this.url,
    required this.title,
    required this.group,
    required this.isFile,
  });
  final String url;
  final String title;
  final String group;
  final bool isFile;
  String get fileName => Uri.parse(url).pathSegments.last;
}

/// A conservative presentation decision. Rich or unrecognised content stays on
/// the school's page; this model never executes HTML or guesses activity types.
class IspacePageContent {
  const IspacePageContent({
    required this.links,
    required this.isFileDirectory,
    this.notes = '',
  });
  final String notes;
  final List<IspacePageLink> links;
  final bool isFileDirectory;

  factory IspacePageContent.parse(String html, String baseUrl) {
    final fragment = parseFragment(html);
    final links = <IspacePageLink>[];
    var heading = '';
    var unsupported =
        fragment.querySelector(
          'img,svg,canvas,table,form,input,button,select,textarea,iframe,object,embed,video,audio,script,math',
        ) !=
        null;
    final looseText = StringBuffer();
    String ownText(Element element) {
      final copy = element.clone(true);
      for (final nested in copy.querySelectorAll('ul,ol')) {
        nested.remove();
      }
      return copy.text.replaceAll(RegExp(r'\s+'), ' ').trim();
    }

    void visit(Node node, List<String> parents) {
      if (node is Text) {
        final text = node.text.trim();
        // Moodle editors often encode directory headings as styled spans, not
        // semantic h1-h6 nodes. Retain common numbered teaching sections.
        if (text.length <= 80 &&
            RegExp(
              r'^(?:week|lab|lecture|chapter|topic|unit)\s*\d+\b',
              caseSensitive: false,
            ).hasMatch(text)) {
          heading = text;
        } else {
          looseText.write(node.text);
        }
        return;
      }
      if (node is! Element) return;
      final tag = node.localName ?? '';
      if (RegExp(r'^h[1-6]$').hasMatch(tag) ||
          ((tag == 'p' || tag == 'div') &&
              node.querySelector('strong,b') != null &&
              node.querySelector('a,ul,ol') == null &&
              node.text.trim().length < 100)) {
        heading = ownText(node);
        return;
      }
      if (const {'a', 'object', 'embed', 'iframe'}.contains(tag)) {
        final raw =
            node.attributes['href'] ??
            node.attributes['data'] ??
            node.attributes['src'] ??
            '';
        final file = normalizeCoursewareFileUrl(raw, baseUrl);
        final resolved = Uri.tryParse(baseUrl)?.resolve(raw);
        if (resolved == null ||
            !{'http', 'https'}.contains(resolved.scheme) ||
            resolved.userInfo.isNotEmpty) {
          unsupported = true;
          return;
        }
        final label = ownText(node);
        links.add(
          IspacePageLink(
            url: (file ?? resolved).toString(),
            title: label.isEmpty
                ? (resolved.pathSegments.lastOrNull ?? '文件')
                : label,
            group: {if (heading.isNotEmpty) heading, ...parents}.join(' / '),
            isFile:
                file != null &&
                !RegExp(r'/mod_page/content/index\.html?$').hasMatch(file.path),
          ),
        );
        return;
      }
      var nextParents = parents;
      if (tag == 'li') {
        final label = ownText(node);
        if (node.querySelector('ul,ol') != null && label.isNotEmpty) {
          nextParents = [...parents, label];
        }
      }
      for (final child in node.nodes) {
        visit(
          child,
          (child is Element && {'ul', 'ol'}.contains(child.localName))
              ? nextParents
              : parents,
        );
      }
    }

    for (final node in fragment.nodes) {
      visit(node, const []);
    }
    // A short directory label may sit outside headings. Long prose or layout
    // must remain available in HTML, even if it also contains attachments.
    final remainder = looseText
        .toString()
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    return IspacePageContent(
      links: List.unmodifiable(links),
      notes: remainder,
      isFileDirectory:
          !unsupported && links.any((l) => l.isFile) && remainder.length <= 160,
    );
  }
}
