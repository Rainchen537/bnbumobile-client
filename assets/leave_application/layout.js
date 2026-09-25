(function installLeaveApplicationLayout(config) {
  'use strict';
  // Layout only: retain every school-owned node, event handler and form value.
  // No cookies, storage, fetch, cloned controls, form serialization or submission.
  const key = '__bnbuLeaveLayoutV1';
  if (window[key]) return window[key].configure(config);

  const normalize = text => text.replace(/[\s\u00a0:*：]+/g, ' ').trim().toLowerCase();
  const labels = new Set([
    'Semester', 'Application Opening Period', 'Chinese Name', 'English Name',
    'Student No.', 'School/Faculty', 'Programme', 'Application Time',
    'Mobile Phone No.', 'Family Contact No.', 'Last Begin Date of Leave',
    'Last Begin Time of Leave', 'Last End Date of Leave', 'Last End Time of Leave',
    'Begin Dates of Leave', 'Begin Date of Leave', 'Begin Time of Leave',
    'End Date of Leave', 'End Time of Leave', 'Total calendar day(s)', 'Reason',
    'Reason Details', 'Attachment',
  ].map(normalize));
  const headings = new Set([
    'Applicant', 'Details of leave application', 'Courses and teachers',
    'Comments of approval', 'Declaration',
  ].map(normalize));
  const controls = 'input:not([type="hidden"]),select,textarea,button,a,img,svg,[role="button"]';
  const ownedClasses = new Map();
  const ownedLabels = new Set();
  const ownedTitles = new Set();
  const ownedButtons = new Map();
  let profileExpanded = false;
  let options = config;
  let root = null;
  let style = null;
  let viewport = null;
  let oldViewport = null;
  let createdViewport = false;
  let timer = null;
  let observing = false;

  function isLeaveDocument() {
    const url = new URL(location.href);
    const [path, query = ''] = url.hash.slice(1).split('?');
    const params = new URLSearchParams(query);
    return url.origin === options.origin && !url.username && !url.password &&
      url.pathname === '/spa/workflow/static4form/index.html' &&
      path === '/main/workflow/req' &&
      params.getAll('workflowid').length === 1 && params.get('workflowid') === '57' &&
      params.getAll('iscreate').length === 1 && params.get('iscreate') === '1';
  }

  function mark(node, name) {
    if (!ownedClasses.has(node)) ownedClasses.set(node, new Set());
    if (!node.classList.contains(name)) {
      ownedClasses.get(node).add(name);
      node.classList.add(name);
    }
  }

  function markWhen(node, name, condition) {
    if (condition) mark(node, name);
    else if (ownedClasses.get(node)?.has(name)) {
      node.classList.remove(name);
      ownedClasses.get(node).delete(name);
    }
  }

  function undoLayout() {
    for (const [node, names] of ownedClasses) {
      for (const name of names) node.classList.remove(name);
    }
    ownedClasses.clear();
    for (const node of ownedLabels) node.removeAttribute('data-bnbu-leave-label');
    ownedLabels.clear();
    for (const node of ownedTitles) node.removeAttribute('data-bnbu-leave-title');
    ownedTitles.clear();
    for (const button of ownedButtons.values()) button.remove();
    ownedButtons.clear();
    style?.remove();
    style = null;
    if (viewport) {
      if (createdViewport) viewport.remove();
      else if (oldViewport === null) viewport.removeAttribute('content');
      else viewport.setAttribute('content', oldViewport);
    }
    viewport = null;
    createdViewport = false;
    root = null;
  }

  function cellText(cell) {
    // Only compare short labels; never publish text or collect input values.
    if (cell.querySelector('table') || cell.textContent.length > 120) return '';
    return normalize(Array.from(cell.childNodes)
      .filter(node => !node.matches?.('[data-bnbu-leave-owned]'))
      .map(node => node.textContent).join(''));
  }

  function findForm() {
    return Array.from(document.querySelectorAll('table')).slice(0, 100).find(table => {
      const seen = new Set(Array.from(table.rows).flatMap(row =>
        Array.from(row.cells, cellText)));
      return ['Applicant', 'Reason Details', 'Courses and teachers', 'Family Contact No.']
        .every(label => seen.has(normalize(label)));
    });
  }

  function isEmpty(cell) {
    return !cell.textContent.trim() && !cell.querySelector(controls);
  }

  function decorateCourses(table) {
    const rows = Array.from(table.rows);
    const header = rows.find(row => {
      const seen = new Set(Array.from(row.cells, cellText));
      return ['Code', 'Course', 'Teacher(s)', 'Time'].every(x => seen.has(normalize(x)));
    });
    if (!header) return;
    mark(table, 'bnbu-leave-courses');
    mark(header, 'bnbu-leave-course-header');
    // Weaver's Code header spans three cells (lookup + required marker + lookup).
    // Map logical columns, not the physical cell index, to preserve teacher labels.
    const columns = [];
    for (const cell of header.cells) {
      const text = cell.textContent.trim();
      for (let i = 0; i < cell.colSpan; i++) columns.push(text);
    }
    for (const row of rows.slice(rows.indexOf(header) + 1)) {
      const width = Array.from(row.cells).reduce((n, cell) => n + cell.colSpan, 0);
      if (width !== columns.length || row.cells.length < 6) continue;
      mark(row, 'bnbu-leave-course');
      let index = 0;
      let previous = null;
      for (const cell of row.cells) {
        const label = columns[index];
        mark(cell, 'bnbu-leave-course-cell');
        if (label && label !== previous) {
          cell.setAttribute('data-bnbu-leave-label', label);
          ownedLabels.add(cell);
        }
        if (normalize(label || '') === 'code') mark(cell, 'bnbu-leave-code');
        previous = label;
        index += cell.colSpan;
      }
    }
  }

  function apply() {
    timer = null;
    if (!options.enabled || !isLeaveDocument()) {
      undoLayout();
      return 'original';
    }
    const form = findForm();
    if (!form) {
      if (root) undoLayout();
      return 'unrecognized';
    }
    if (root && root !== form) undoLayout();
    root = form;
    if (!style) {
      style = document.createElement('style');
      style.id = 'bnbu-leave-layout-style';
      style.textContent = options.css;
      document.head.appendChild(style);
      viewport = document.querySelector('meta[name="viewport"]');
      createdViewport = !viewport;
      if (!viewport) {
        viewport = document.createElement('meta');
        viewport.name = 'viewport';
        document.head.appendChild(viewport);
      }
      oldViewport = viewport.getAttribute('content');
      viewport.setAttribute('content', 'width=device-width, initial-scale=1');
    }
    mark(document.documentElement, 'bnbu-leave-document');
    document.documentElement.classList.toggle('bnbu-leave-dark', !!options.dark);
    ownedClasses.get(document.documentElement).add('bnbu-leave-dark');
    mark(root, 'bnbu-leave-form');
    markWhen(root, 'bnbu-leave-show-profile', profileExpanded);
    const translated = new Map(Object.entries(options.labels || {})
      .map(([label, title]) => [normalize(label), title]));
    let applicantHeading = null;
    let profileRows = 0;
    // Constrain only the form's ancestors, never a school picker/dialog sibling.
    for (let parent = root.parentElement; parent && parent !== document.body;
      parent = parent.parentElement) mark(parent, 'bnbu-leave-shell');
    for (const row of root.rows) {
      mark(row, 'bnbu-leave-row');
      const cells = Array.from(row.cells);
      const personal = cells.some(cell => ['chinese name', 'student no.', 'programme'].includes(cellText(cell))) &&
        !row.querySelector('input,select,textarea,button,a,[contenteditable="true"]');
      markWhen(row, 'bnbu-leave-profile-row', personal);
      if (personal) profileRows++;
      const empty = cells.every(isEmpty);
      markWhen(row, 'bnbu-leave-spacer', empty);
      if (empty) continue;
      if (cells.some(cell => headings.has(cellText(cell)))) {
        mark(row, 'bnbu-leave-heading');
      }
      for (const cell of cells) {
        mark(cell, 'bnbu-leave-cell');
        const text = cellText(cell);
        if (text === 'applicant') applicantHeading = cell;
        const translatedTitle = translated.get(text);
        if (translatedTitle) {
          cell.setAttribute('data-bnbu-leave-title', translatedTitle);
          ownedTitles.add(cell);
        } else if (ownedTitles.has(cell)) {
          cell.removeAttribute('data-bnbu-leave-title');
          ownedTitles.delete(cell);
        }
        markWhen(cell, 'bnbu-leave-label', labels.has(cellText(cell)));
        markWhen(cell, 'bnbu-leave-empty', isEmpty(cell));
        markWhen(cell, 'bnbu-leave-value', !labels.has(cellText(cell)) && !isEmpty(cell));
        // A full-width note/declaration must stay readable and visible.
        if (cell.colSpan >= 6 && (cells.filter(c => !isEmpty(c)).length === 1 ||
            cell.querySelector('textarea,input[type="file"],table'))) {
          mark(cell, 'bnbu-leave-full');
        }
      }
      if (cells.filter(cell => labels.has(cellText(cell))).length > 1) {
        mark(row, 'bnbu-leave-double');
      }
    }
    if (applicantHeading && profileRows) {
      mark(applicantHeading, 'bnbu-leave-profile-heading');
      let button = ownedButtons.get(applicantHeading);
      if (!button) {
        button = document.createElement('button');
        button.type = 'button';
        button.setAttribute('data-bnbu-leave-owned', 'profile-toggle');
        button.addEventListener('click', () => {
          profileExpanded = !profileExpanded;
          markWhen(root, 'bnbu-leave-show-profile', profileExpanded);
          button.setAttribute('aria-expanded', String(profileExpanded));
          button.textContent = profileExpanded ? (options.collapse || 'Collapse') : (options.expand || 'Expand');
        });
        applicantHeading.appendChild(button);
        ownedButtons.set(applicantHeading, button);
      }
      button.setAttribute('aria-expanded', String(profileExpanded));
      const label = profileExpanded ? (options.collapse || 'Collapse') : (options.expand || 'Expand');
      if (button.textContent !== label) button.textContent = label;
    }
    for (const table of root.querySelectorAll('table')) {
      decorateCourses(table);
      if (table.querySelector('input[type="radio"]')) mark(table, 'bnbu-leave-choices');
    }
    return 'adapted';
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
    // Do not observe or inspect a login screen / another origin / another workflow.
    if (isLeaveDocument() && !observing) {
      observer.observe(document.body, { childList: true, subtree: true, characterData: true });
      observing = true;
    } else if (!isLeaveDocument()) {
      observer.disconnect();
      observing = false;
    }
    return apply();
  }
  window.addEventListener('hashchange', () => configure(options));
  window[key] = { configure };
  return configure(config);
})
