import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import test from 'node:test';
import { Window } from 'happy-dom';

test('Tiptap mail document preserves formatting, editable tables and undo', async () => {
  const window = new Window({ url: 'file:///assets/mail_editor/index.html' });
  const events = [];
  window.flutter_inappwebview = {
    callHandler: async (_name, payload) => {
      events.push(payload);
      return null;
    },
  };
  const editorPage = readFileSync(
    new URL('../../../assets/mail_editor/index.html', import.meta.url),
    'utf8',
  );
  window.document.head.innerHTML = /<head>([\s\S]*?)<\/head>/.exec(editorPage)[1];
  window.document.body.innerHTML = '<div id="editor"></div>';
  window.bnbuMailEditorTheme = 'dark';
  Object.assign(globalThis, {
    window,
    document: window.document,
    DOMParser: window.DOMParser,
    HTMLElement: window.HTMLElement,
    MutationObserver: window.MutationObserver,
    Node: window.Node,
    Range: window.Range,
    getSelection: window.getSelection.bind(window),
    requestAnimationFrame: (callback) => setTimeout(callback, 0),
    cancelAnimationFrame: clearTimeout,
  });

  await import(new URL('../../../assets/mail_editor/editor.js', import.meta.url).href);
  const command = window.bnbuMailEditorCommand;
  assert.equal(typeof command, 'function');
  assert.equal(window.document.documentElement.dataset.theme, 'dark');
  assert.equal(window.getComputedStyle(window.document.documentElement).backgroundColor, '#1d2228');

  let payload = command({
    name: 'setContent',
    value:
      '<p><strong>课程</strong></p><p><a href="javascript:alert(1)">危险链接</a></p>',
  });
  assert.match(payload.html, /<strong>课程<\/strong>/);
  assert.doesNotMatch(payload.html, /javascript:/);

  command({ name: 'setContent', value: '<p>普通段落</p>' });
  payload = command({ name: 'bold' });
  assert.equal(payload.state.bold, true);
  payload = command({ name: 'insertText', value: '强调' });
  assert.match(payload.html, /<strong>强调<\/strong>/);
  payload = command({ name: 'setContent', value: '<p>普通段落</p>' });
  assert.equal(payload.state.bold, false);
  payload = command({ name: 'clearFormat' });
  assert.equal(payload.state.bold, false);
  payload = command({ name: 'insertText', value: '即时输入' });
  assert.match(payload.text, /普通段落即时输入/);

  payload = command({ name: 'insertTable', value: { rows: 2, cols: 2 } });
  assert.match(payload.html, /<table/);
  assert.match(payload.html, /<th/);
  assert.match(payload.html, /<td/);
  assert.equal(payload.state.table, true);
  payload = command({ name: 'undo' });
  assert.doesNotMatch(payload.html, /<table/);
  payload = command({ name: 'redo' });
  assert.match(payload.html, /<table/);
  payload = command({ name: 'addRowAfter' });
  assert.equal((payload.html.match(/<tr/g) || []).length, 3);
  payload = command({ name: 'toggleHeaderRow' });
  assert.doesNotMatch(payload.html, /<th/);
  payload = command({ name: 'toggleHeaderRow' });
  assert.match(payload.html, /<th/);

  command({ name: 'setContent', value: '<p>普通段落</p>' });
  payload = command({ name: 'sink' });
  assert.match(payload.html, /margin-left:\s*2em/);
  for (let index = 0; index < 8; index += 1) {
    payload = command({ name: 'sink' });
  }
  assert.match(payload.html, /margin-left:\s*12em/);
  payload = command({ name: 'lift' });
  assert.match(payload.html, /margin-left:\s*10em/);

  command({ name: 'setContent', value: '<p>行距</p>' });
  payload = command({ name: 'lineHeight', value: '1.6' });
  assert.match(payload.html, /line-height:\s*1.6/);
  assert.equal(payload.state.lineHeight, '1.6');

  command({ name: 'setContent', value: '<p>格式</p>' });
  command({ name: 'fontSize', value: 44 / 3 });
  command({ name: 'color', value: '#3187F4' });
  payload = command({ name: 'insertText', value: '正文' });
  assert.match(payload.html, /font-size:\s*14\.666667px/);
  assert.ok(Math.abs(Number.parseFloat(payload.state.fontSize) - 44 / 3) < 1e-6);
  const sizedHtml = payload.html;
  payload = command({ name: 'setContent', value: sizedHtml });
  assert.ok(Math.abs(Number.parseFloat(payload.state.fontSize) - 44 / 3) < 1e-6);
  assert.match(payload.html, /font-size:\s*14\.666667px/);
  assert.match(payload.html, /color: rgb\(49, 135, 244\)|color:#3187F4|color: #3187F4/);
  const beforeThemeChange = command({ name: 'snapshot' });
  const focusBeforeThemeChange = window.document.activeElement;
  const selectionBeforeThemeChange = window.getSelection();
  const selectionAnchorBeforeThemeChange = selectionBeforeThemeChange.anchorNode;
  const selectionAnchorOffsetBeforeThemeChange = selectionBeforeThemeChange.anchorOffset;
  const selectionFocusBeforeThemeChange = selectionBeforeThemeChange.focusNode;
  const selectionFocusOffsetBeforeThemeChange = selectionBeforeThemeChange.focusOffset;
  command({ name: 'setTheme', value: 'light' });
  assert.equal(window.getComputedStyle(window.document.documentElement).backgroundColor, '#ffffff');
  assert.equal(window.getComputedStyle(window.document.body).color, '#172235');
  command({ name: 'setTheme', value: 'dark' });
  assert.equal(window.getComputedStyle(window.document.documentElement).backgroundColor, '#1d2228');
  assert.equal(window.getComputedStyle(window.document.body).color, '#eceff3');
  assert.equal(window.document.activeElement, focusBeforeThemeChange);
  const selectionAfterThemeChange = window.getSelection();
  assert.equal(selectionAfterThemeChange.anchorNode, selectionAnchorBeforeThemeChange);
  assert.equal(selectionAfterThemeChange.anchorOffset, selectionAnchorOffsetBeforeThemeChange);
  assert.equal(selectionAfterThemeChange.focusNode, selectionFocusBeforeThemeChange);
  assert.equal(selectionAfterThemeChange.focusOffset, selectionFocusOffsetBeforeThemeChange);
  const afterThemeChange = command({ name: 'snapshot' });
  assert.deepEqual(afterThemeChange, beforeThemeChange);
  assert.doesNotMatch(afterThemeChange.html, /data-theme|color-scheme/);
  await new Promise((resolve) => setTimeout(resolve, 0));
  assert.ok(events.some((event) => event.type === 'editorReady'));
});
