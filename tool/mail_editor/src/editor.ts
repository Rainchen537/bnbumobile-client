import { Editor, Extension } from '@tiptap/core';
import Blockquote from '@tiptap/extension-blockquote';
import Bold from '@tiptap/extension-bold';
import BulletList from '@tiptap/extension-bullet-list';
import Document from '@tiptap/extension-document';
import HardBreak from '@tiptap/extension-hard-break';
import Highlight from '@tiptap/extension-highlight';
import HorizontalRule from '@tiptap/extension-horizontal-rule';
import Image from '@tiptap/extension-image';
import Italic from '@tiptap/extension-italic';
import Link from '@tiptap/extension-link';
import ListItem from '@tiptap/extension-list-item';
import OrderedList from '@tiptap/extension-ordered-list';
import Paragraph from '@tiptap/extension-paragraph';
import Placeholder from '@tiptap/extension-placeholder';
import Strike from '@tiptap/extension-strike';
import {
  Table,
  TableCell,
  TableHeader,
  TableRow,
} from '@tiptap/extension-table';
import TextAlign from '@tiptap/extension-text-align';
import {
  BackgroundColor,
  Color,
  FontFamily,
  FontSize,
  TextStyle,
} from '@tiptap/extension-text-style';
import Underline from '@tiptap/extension-underline';
import Text from '@tiptap/extension-text';
import { UndoRedo } from '@tiptap/extensions';

type EditorCommand = {
  name: string;
  value?: unknown;
};

type EditorPayload = {
  html?: string;
  json?: object;
  text?: string;
  state: Record<string, unknown>;
  type: 'documentChanged' | 'editorReady' | 'requestImage' | 'selectionChanged';
};

const safeUrl = /^(https?:|mailto:|tel:)/i;
const safeImage = /^data:image\/(png|jpe?g|gif|webp);base64,/i;
const allowedStyle = new Set([
  'background-color',
  'color',
  'font-family',
  'font-size',
  'font-style',
  'font-weight',
  'height',
  'line-height',
  'margin-left',
  'min-width',
  'text-align',
  'text-decoration',
  'width',
]);

function safeStyleValue(property: string, value: string): boolean {
  if (['width', 'min-width', 'height'].includes(property)) {
    return /^\d+(?:\.\d+)?(?:px|%|em|rem)?$/.test(value);
  }
  if (property === 'margin-left') {
    const match = /^(\d+(?:\.\d+)?)(?:px|em|rem)$/.exec(value);
    return match !== null && Number(match[1]) <= 12;
  }
  return true;
}

function sanitizeHtml(source: unknown): string {
  const template = document.createElement('template');
  template.innerHTML = typeof source === 'string' ? source : '';
  for (const node of template.content.querySelectorAll(
    'base,embed,form,iframe,link,meta,object,script,style,svg',
  )) {
    node.remove();
  }
  for (const node of template.content.querySelectorAll('*')) {
    for (const attribute of [...node.attributes]) {
      const name = attribute.name.toLowerCase();
      const value = attribute.value.trim();
      if (name.startsWith('on')) {
        node.removeAttribute(attribute.name);
        continue;
      }
      if (name === 'src') {
        if (node.tagName !== 'IMG' || !safeImage.test(value)) {
          node.removeAttribute(attribute.name);
        }
        continue;
      }
      if (name === 'href') {
        if (!safeUrl.test(value)) {
          node.removeAttribute(attribute.name);
        }
        continue;
      }
      if (name === 'style') {
        const styles = value
          .split(';')
          .map((entry) => entry.split(':', 2))
          .filter(
            ([property, styleValue]) =>
              property &&
              styleValue &&
              allowedStyle.has(property.trim().toLowerCase()) &&
              !/expression|url\s*\(/i.test(styleValue) &&
              safeStyleValue(property.trim().toLowerCase(), styleValue.trim()),
          )
          .map(([property, styleValue]) =>
            `${property.trim().toLowerCase()}:${styleValue.trim()}`,
          );
        if (styles.length === 0) {
          node.removeAttribute(attribute.name);
        } else {
          node.setAttribute('style', styles.join(';'));
        }
        continue;
      }
      if (
        (name === 'colwidth' || name === 'data-colwidth') &&
        /^[0-9, ]+$/.test(value)
      ) {
        continue;
      }
      if (!['align', 'colspan', 'rowspan'].includes(name)) {
        node.removeAttribute(attribute.name);
      }
    }
  }
  return template.innerHTML;
}

let sendTimer: number | undefined;
let editor: Editor;

const ParagraphIndent = Extension.create({
  name: 'paragraphIndent',
  addGlobalAttributes() {
    return [
      {
        types: ['paragraph', 'heading'],
        attributes: {
          indent: {
            default: 0,
            parseHTML: (element) => {
              const value = element.style.marginLeft;
              const match = /^(\d+(?:\.\d+)?)em$/.exec(value);
              return match === null ? 0 : Math.min(6, Math.floor(Number(match[1]) / 2));
            },
            renderHTML: (attributes) => {
              const indent = Math.max(0, Math.min(6, Number(attributes.indent) || 0));
              return indent === 0 ? {} : { style: `margin-left:${indent * 2}em` };
            },
          },
        },
      },
    ];
  },
});

const ParagraphLineHeight = Extension.create({
  name: 'paragraphLineHeight',
  addGlobalAttributes() {
    return [
      {
        types: ['paragraph', 'heading'],
        attributes: {
          lineHeight: {
            default: null,
            parseHTML: (element) => {
              const value = element.style.lineHeight;
              return /^\d(?:\.\d+)?$/.test(value) ? value : null;
            },
            renderHTML: (attributes) => {
              const value = String(attributes.lineHeight ?? '');
              return /^\d(?:\.\d+)?$/.test(value) ? { style: `line-height:${value}` } : {};
            },
          },
        },
      },
    ];
  },
});

function activeIndentNode(): 'paragraph' | 'heading' {
  return editor.isActive('heading') ? 'heading' : 'paragraph';
}

function toolbarState(): Record<string, unknown> {
  const paragraph = editor.getAttributes('paragraph');
  const heading = editor.getAttributes('heading');
  const textStyle = editor.getAttributes('textStyle');
  return {
    alignment: paragraph.textAlign || heading.textAlign || 'left',
    blockquote: editor.isActive('blockquote'),
    bold: editor.isActive('bold'),
    bulletList: editor.isActive('bulletList'),
    color: textStyle.color || null,
    fontFamily: textStyle.fontFamily || null,
    fontSize: textStyle.fontSize || null,
    italic: editor.isActive('italic'),
    lineHeight: paragraph.lineHeight || heading.lineHeight || textStyle.lineHeight || null,
    orderedList: editor.isActive('orderedList'),
    strike: editor.isActive('strike'),
    table: editor.isActive('table'),
    underline: editor.isActive('underline'),
  };
}

function documentPayload(type: EditorPayload['type']): EditorPayload {
  return {
    type,
    html: sanitizeHtml(editor.getHTML()),
    json: editor.getJSON(),
    text: editor.getText({ blockSeparator: '\n' }),
    state: toolbarState(),
  };
}

function selectionPayload(): EditorPayload {
  return { type: 'selectionChanged', state: toolbarState() };
}

function post(payload: EditorPayload): void {
  const bridge = window.flutter_inappwebview;
  if (!bridge?.callHandler) {
    return;
  }
  void bridge.callHandler('bnbuMailEditor', payload);
}

function scheduleDocumentChanged(): void {
  window.clearTimeout(sendTimer);
  sendTimer = window.setTimeout(() => post(documentPayload('documentChanged')), 90);
}

function command(command: EditorCommand): EditorPayload {
  if (command.name === 'setTheme') {
    // Appearance belongs to the host, not to the draft. Do not touch the
    // editor document, undo history, selection or keyboard focus here.
    window.bnbuMailEditorTheme = command.value === 'dark' ? 'dark' : 'light';
    document.documentElement.dataset.theme = window.bnbuMailEditorTheme;
    return documentPayload('selectionChanged');
  }
  const chain = editor.chain().focus();
  switch (command.name) {
    case 'focus':
      editor.commands.focus();
      break;
    case 'snapshot':
      break;
    case 'insertText':
      chain.insertContent(String(command.value ?? '')).run();
      break;
    case 'undo':
      chain.undo().run();
      break;
    case 'redo':
      chain.redo().run();
      break;
    case 'clearFormat':
      chain.unsetAllMarks().clearNodes().run();
      break;
    case 'bold':
      chain.toggleBold().run();
      break;
    case 'italic':
      chain.toggleItalic().run();
      break;
    case 'underline':
      chain.toggleUnderline().run();
      break;
    case 'strike':
      chain.toggleStrike().run();
      break;
    case 'bulletList':
      chain.toggleBulletList().run();
      break;
    case 'orderedList':
      chain.toggleOrderedList().run();
      break;
    case 'blockquote':
      chain.toggleBlockquote().run();
      break;
    case 'horizontalRule':
      chain.setHorizontalRule().run();
      break;
    case 'sink':
      if (editor.isActive('listItem')) {
        chain.sinkListItem('listItem').run();
      } else {
        const node = activeIndentNode();
        const indent = Number(editor.getAttributes(node).indent) || 0;
        chain.updateAttributes(node, { indent: Math.min(6, indent + 1) }).run();
      }
      break;
    case 'lift':
      if (editor.isActive('listItem')) {
        chain.liftListItem('listItem').run();
      } else {
        const node = activeIndentNode();
        const indent = Number(editor.getAttributes(node).indent) || 0;
        chain.updateAttributes(node, { indent: Math.max(0, indent - 1) }).run();
      }
      break;
    case 'align':
      chain.setTextAlign(String(command.value ?? 'left')).run();
      break;
    case 'fontFamily':
      chain.setFontFamily(String(command.value ?? '')).run();
      break;
    case 'fontSize':
      chain.setFontSize(`${Number(command.value) || 44 / 3}px`).run();
      break;
    case 'lineHeight': {
      const value = String(command.value ?? '1.6');
      const node = activeIndentNode();
      if (/^\d(?:\.\d+)?$/.test(value)) {
        chain.updateAttributes(node, { lineHeight: value }).run();
      }
      break;
    }
    case 'color':
      chain.setColor(String(command.value ?? '#172235')).run();
      break;
    case 'highlight':
      chain.setHighlight({ color: String(command.value ?? '#FFF0A6') }).run();
      break;
    case 'clearHighlight':
      chain.unsetHighlight().run();
      break;
    case 'setLink': {
      const href = String(command.value ?? '').trim();
      if (safeUrl.test(href)) {
        chain.extendMarkRange('link').setLink({ href }).run();
      }
      break;
    }
    case 'unsetLink':
      chain.extendMarkRange('link').unsetLink().run();
      break;
    case 'insertTable': {
      const requested = command.value as { cols?: unknown; rows?: unknown } | undefined;
      const rows = Math.min(12, Math.max(1, Number(requested?.rows) || 2));
      const cols = Math.min(8, Math.max(1, Number(requested?.cols) || 2));
      chain.insertTable({ rows, cols, withHeaderRow: true }).run();
      break;
    }
    case 'addRowBefore':
      chain.addRowBefore().run();
      break;
    case 'addRowAfter':
      chain.addRowAfter().run();
      break;
    case 'addColumnBefore':
      chain.addColumnBefore().run();
      break;
    case 'addColumnAfter':
      chain.addColumnAfter().run();
      break;
    case 'deleteRow':
      chain.deleteRow().run();
      break;
    case 'deleteColumn':
      chain.deleteColumn().run();
      break;
    case 'deleteTable':
      chain.deleteTable().run();
      break;
    case 'mergeOrSplit':
      chain.mergeOrSplit().run();
      break;
    case 'toggleHeaderRow':
      chain.toggleHeaderRow().run();
      break;
    case 'addImage': {
      const src = String(command.value ?? '');
      if (safeImage.test(src)) {
        chain.setImage({ src }).run();
      }
      break;
    }
    case 'setContent':
      editor.commands.setContent(sanitizeHtml(command.value), {
        emitUpdate: false,
      });
      break;
    case 'requestImage':
      post(documentPayload('requestImage'));
      break;
  }
  return documentPayload('documentChanged');
}

window.bnbuMailEditorCommand = command;
document.documentElement.dataset.theme =
  window.bnbuMailEditorTheme === 'dark' ? 'dark' : 'light';

editor = new Editor({
  element: document.querySelector('#editor') as HTMLElement,
  extensions: [
    Document,
    Paragraph,
    ParagraphIndent,
    ParagraphLineHeight,
    Text,
    Bold,
    Italic,
    BulletList,
    OrderedList,
    ListItem,
    Blockquote,
    HardBreak,
    UndoRedo,
    Underline,
    Strike,
    HorizontalRule,
    Link.configure({
      autolink: false,
      linkOnPaste: false,
      openOnClick: false,
      protocols: ['http', 'https', 'mailto', 'tel'],
    }),
    Image.configure({ allowBase64: true }),
    TextStyle,
    FontFamily.configure({ types: ['textStyle'] }),
    FontSize.configure({ types: ['textStyle'] }),
    Color.configure({ types: ['textStyle'] }),
    BackgroundColor.configure({ types: ['textStyle'] }),
    Highlight.configure({ multicolor: true }),
    TextAlign.configure({ types: ['heading', 'paragraph'] }),
    Table.configure({
      resizable: true,
      HTMLAttributes: { class: 'bnbu-mail-table' },
    }),
    TableRow,
    TableHeader,
    TableCell,
    Placeholder.configure({ placeholder: '' }),
  ],
  editorProps: {
    attributes: {
      autocapitalize: 'sentences',
      autocomplete: 'off',
      autocorrect: 'on',
      class: 'bnbu-mail-editor',
      spellcheck: 'true',
    },
    handleClick: (_view, _position, event) => {
      if ((event.target as HTMLElement).closest('a')) {
        event.preventDefault();
        return true;
      }
      return false;
    },
  },
  onUpdate: scheduleDocumentChanged,
  onSelectionUpdate: () => post(selectionPayload()),
});

window.addEventListener('flutterInAppWebViewPlatformReady', () => {
  post(documentPayload('editorReady'));
});
setTimeout(() => post(documentPayload('editorReady')), 0);
