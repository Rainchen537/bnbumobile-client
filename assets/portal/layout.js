(function installPortalLayout(config) {
  'use strict';
  // Presentation only: reflow the school's own Portal document for a phone
  // viewport. Every school node, handler and value is preserved; nothing is
  // created, cloned, serialized, navigated or submitted. No cookie, storage,
  // fetch or school control is ever read.
  const key = '__bnbuPortalLayoutV1';
  if (window[key]) return window[key].configure(config);

  const normalize = text =>
    text.replace(/[\s\u00a0:*：]+/g, ' ').trim().toLowerCase();
  // Section titles the adapter may re-label once it recognizes the shell.
  const sectionTitles = new Set([
    'My Application', 'My Favorites', 'Announcements', 'My To-do',
    'My Schedule', 'Quick Links',
  ].map(normalize));
  const interactive =
    'a,button,input:not([type="hidden"]),select,textarea,[role="button"],[onclick]';
  const wideTags = new Set(['table', 'pre', 'iframe']);
  const headingSelector = 'h1,h2,h3,h4,th,dt,legend,.title,.header,.caption';

  let options = config;
  let root = null;
  let style = null;
  let viewport = null;
  let createdViewport = false;
  let timer = null;
  let observing = false;
  const ownedClasses = new Map();
  const ownedLabels = new Set();

  function isPortalDocument() {
    let url;
    try {
      url = new URL(location.href);
    } catch (_) {
      return false;
    }
    return url.origin === options.origin && !url.username && !url.password &&
      url.protocol === 'https:';
  }

  function declaresFrameset() {
    return document.querySelector('frameset,frame') !== null;
  }

  /// Adds an owned class and remembers the attribute exactly as it was, so a
  /// restore can drop an empty `class=""` instead of leaving one behind.
  function mark(node, name) {
    let entry = ownedClasses.get(node);
    if (!entry) {
      entry = {
        names: new Set(),
        hadClassAttribute: node.hasAttribute('class'),
        originalValue: node.getAttribute('class'),
      };
      ownedClasses.set(node, entry);
    }
    if (!node.classList.contains(name)) {
      entry.names.add(name);
      node.classList.add(name);
    }
  }

  function unmark(node, name) {
    const entry = ownedClasses.get(node);
    if (!entry || !entry.names.has(name)) return;
    node.classList.remove(name);
    entry.names.delete(name);
    if (entry.names.size === 0) restoreClassAttribute(node, entry);
  }

  function restoreClassAttribute(node, entry) {
    ownedClasses.delete(node);
    if (!entry.hadClassAttribute) {
      if (node.classList.length === 0) node.removeAttribute('class');
      return;
    }
    // Restore original whitespace only if the school's own classes have not
    // changed while the adapter was active. Never undo school state changes.
    const original = (entry.originalValue || '').trim().split(/\s+/).filter(Boolean);
    if (original.length === node.classList.length &&
        original.every(name => node.classList.contains(name))) {
      node.setAttribute('class', entry.originalValue);
    }
  }

  function markWhen(node, name, condition) {
    if (condition) {
      mark(node, name);
      return;
    }
    unmark(node, name);
  }

  function undoLayout() {
    for (const [node, entry] of [...ownedClasses]) {
      for (const name of entry.names) node.classList.remove(name);
      restoreClassAttribute(node, entry);
    }
    ownedClasses.clear();
    for (const node of ownedLabels) node.removeAttribute('data-bnbu-portal-label');
    ownedLabels.clear();
    if (style) style.remove();
    style = null;
    if (viewport) {
      if (createdViewport) viewport.remove();
    }
    viewport = null;
    createdViewport = false;
    root = null;
  }

  /// A desktop Portal shell is a fixed-width wrapper around the interactive
  /// content. The widest direct child of body that still carries controls is
  /// the element worth constraining; a frameset shell owns no such layout.
  function findShell() {
    if (declaresFrameset() || !document.body) return null;
    const portalRoot = document.getElementById('container');
    if (portalRoot && portalRoot.querySelector('.layout-main-content') &&
        portalRoot.querySelector('.layout-top-header')) return portalRoot;
    let widest = null;
    let widestWidth = 0;
    for (const node of Array.from(document.body.children)) {
      const tag = node.tagName;
      if (tag === 'SCRIPT' || tag === 'STYLE' || tag === 'LINK') continue;
      if (!node.querySelector(interactive) && !node.textContent.trim()) continue;
      const width = node.getBoundingClientRect
        ? node.getBoundingClientRect().width
        : 0;
      if (width >= widestWidth) {
        widest = node;
        widestWidth = width;
      }
    }
    return widest;
  }

  function isWide(node) {
    const tag = node.tagName ? node.tagName.toLowerCase() : '';
    if (!wideTags.has(tag)) return false;
    if (tag !== 'table') return true;
    if (node.matches('.layouttable')) return false;
    return Array.from(node.rows || []).some(
      row => Array.from(row.cells).length >= 4,
    );
  }

  function isTinyControl(node) {
    if (!node.getBoundingClientRect) return false;
    const rect = node.getBoundingClientRect();
    if (!rect.width || !rect.height) return false;
    return rect.width < 40 || rect.height < 40;
  }

  function decorate(scope) {
    for (const node of scope.querySelectorAll('*')) {
      if (node.hasAttribute('data-bnbu-portal-owned')) continue;
      if (node.matches('img,svg,video,canvas')) mark(node, 'bnbu-portal-media');
      if (isWide(node)) {
        const tag = node.tagName.toLowerCase();
        mark(node, tag === 'table' ? 'bnbu-portal-table' : 'bnbu-portal-scroll');
        if (node.parentElement) mark(node.parentElement, 'bnbu-portal-scroll');
      }
      if (node.matches(interactive) && isTinyControl(node)) {
        mark(node, 'bnbu-portal-touch');
      }
    }
  }

  function relabel(scope, translated) {
    for (const node of scope.querySelectorAll(headingSelector)) {
      if (node.hasAttribute('data-bnbu-portal-owned')) continue;
      const text = (node.textContent || '').trim();
      if (text.length > 60) continue;
      const value = normalize(text);
      const title = sectionTitles.has(value) ? translated.get(value) : null;
      if (title) {
        node.setAttribute('data-bnbu-portal-label', title);
        ownedLabels.add(node);
      } else if (ownedLabels.has(node)) {
        node.removeAttribute('data-bnbu-portal-label');
        ownedLabels.delete(node);
      }
    }
  }

  function installPresentation() {
    style = document.createElement('style');
    style.id = 'bnbu-portal-layout-style';
    style.setAttribute('data-bnbu-portal-owned', 'true');
    style.textContent = options.css;
    document.head.appendChild(style);
    viewport = document.querySelector('meta[name="viewport"]');
    if (viewport) {
      // An existing school declaration is left exactly as written.
      return;
    }
    createdViewport = true;
    viewport = document.createElement('meta');
    viewport.name = 'viewport';
    viewport.setAttribute('data-bnbu-portal-owned', 'true');
    viewport.setAttribute('content', 'width=device-width, initial-scale=1');
    document.head.appendChild(viewport);
  }

  function apply() {
    timer = null;
    if (!options.enabled || !isPortalDocument()) {
      undoLayout();
      return 'original';
    }
    if (!document.body) {
      if (root) undoLayout();
      return 'unrecognized';
    }
    const shell = findShell();
    if (!shell) {
      undoLayout();
      return 'unrecognized';
    }
    if (root && root !== shell) undoLayout();
    root = shell;
    if (!style) installPresentation();
    mark(document.documentElement, 'bnbu-portal-document');
    markWhen(document.documentElement, 'bnbu-portal-dark', !!options.dark);
    if (root) {
      // Constrain only the shell's own ancestors, never a school dialog or
      // picker that is a sibling of the shell.
      for (let parent = root.parentElement;
        parent && parent !== document.body;
        parent = parent.parentElement) {
        mark(parent, 'bnbu-portal-shell');
      }
      mark(root, 'bnbu-portal-shell');
      // Recognize the observed E9 shell, not arbitrary school forms or dialogs.
      markWhen(document.documentElement, 'bnbu-portal-e9',
        !!root.querySelector('.layout-top-header') &&
        !!root.querySelector('.layout-main-content'));
      for (const label of root.querySelectorAll('.ecodeQuickApp .appName')) {
        if (label.parentElement) {
          mark(label.parentElement, 'bnbu-portal-app');
          if (label.parentElement.parentElement) {
            mark(label.parentElement.parentElement, 'bnbu-portal-app-grid');
          }
        }
      }
      decorate(root);
      relabel(root, new Map(
        Object.entries(options.labels || {})
          .map(([label, title]) => [normalize(label), title]),
      ));
    }
    return root ? 'adapted' : 'unrecognized';
  }

  const observer = new MutationObserver(() => {
    if (timer === null) timer = window.setTimeout(apply, 80);
  });

  function configure(next) {
    options = next;
    if (!options.enabled) {
      observer.disconnect();
      observing = false;
      if (timer !== null) window.clearTimeout(timer);
      timer = null;
      undoLayout();
      return 'original';
    }
    if (isPortalDocument() && !observing && document.body) {
      observer.observe(document.body, { childList: true, subtree: true });
      observing = true;
    } else if (!isPortalDocument()) {
      observer.disconnect();
      observing = false;
    }
    return apply();
  }
  window.addEventListener('hashchange', () => configure(options));
  window[key] = { configure, apply };
  return configure(config);
})
