(function bnbuLeaveBridge(request) {
  'use strict';
  // A bounded device-only bridge to workflow 57. No HTTP, credentials, storage,
  // generic field access or automatic acknowledgement. Final actions require
  // fresh handles and explicit native user confirmation; never replay them.
  const reply = (status, data = {}) => JSON.stringify({status, ...data});
  // WebView evaluation may remain queued after Dart's timeout. Reject it before
  // touching any field/control; accepted school operations cannot be undone.
  if (!Number.isSafeInteger(request.expiresAt) || Date.now() >= request.expiresAt) {
    return reply('timeout');
  }
  const url = new URL(location.href);
  const lease = window.__bnbuNativeLeaveV1;
  // Read the result before consulting the form/loading flag: the school's
  // success handler can disable the form or replace its route immediately.
  if (request.operation === 'submit_status' && url.protocol === 'https:' &&
      url.origin === request.origin && !url.username && !url.password &&
      lease?.document === document && lease.nonce === request.nonce && lease.submission) {
    return lease.submissionStatus();
  }
  const [path, query = ''] = url.hash.slice(1).split('?');
  const params = new URLSearchParams(query);
  if (url.protocol !== 'https:' || url.origin !== request.origin || url.username ||
      url.password || url.pathname !== '/spa/workflow/static4form/index.html' ||
      path !== '/main/workflow/req' || params.getAll('workflowid').length !== 1 ||
      params.get('workflowid') !== '57' || params.getAll('iscreate').length !== 1 ||
      params.get('iscreate') !== '1') return reply('unsupported');
  const wf = window.WfForm;
  if (!wf || ['getFieldInfo', 'getFieldValue', 'getDetailAllRowIndexStr',
    'getFieldCurViewAttr', 'changeFieldValue'].some(k => typeof wf[k] !== 'function')) {
    return reply('loading');
  }
  // Numeric field IDs AND names verified against the school's live form.
  const schema = {
    semester: ['26476', 'semester'], openingStart: ['26477', 'starttime'],
    openingEnd: ['26478', 'endtime'], chineseName: ['26525', 'chinesename'],
    englishName: ['7090', 'englishname'], studentNo: ['7098', 'studentno'],
    faculty: ['26560', 'faculty'], programme: ['26567', 'programme'],
    applicationTime: ['7089', 'Apply_Date'], mobile: ['7101', 'mobilephoneno'],
    familyPhone: ['7102', 'familycontactno'], beginDate: ['26447', 'ksrq'],
    beginTime: ['26448', 'kssj'], endDate: ['26449', 'jsrq'],
    endTime: ['26450', 'jssj'], days: ['26451', 'qjsc'], reason: ['7108', 'reason'],
    details: ['7109', 'reasondetails'], attachment: ['7110', 'attachment'],
  };
  const editable = new Set(['mobile', 'familyPhone', 'beginDate', 'beginTime',
    'endDate', 'endTime', 'reason', 'details']);
  const courseFields = {code: ['27731', 'code2'], title: ['26483', 'title'],
    section: ['26484', 'section'], teacher: ['27248', 'teachername'],
    type: ['26487', 'type'], time: ['27720', 'time']};
  const text = (value, limit = 4000) => String(value ?? '').slice(0, limit);
  const node = id => document.querySelector('[data-fieldmark="field' + id + '"]');
  // Keep the exact baseline; a truncated editable value must never overwrite
  // a longer school value. Unsupported lengths fall back to the original form.
  const value = id => String(wf.getFieldValue('field' + id) ?? '');
  const options = id => (wf.getFieldInfo(id).selectattr?.selectitemlist || [])
    .filter(item => Number(item.cancel) === 0).slice(0, 50)
    .map(item => ({value: text(item.selectvalue, 50), label: text(item.selectname, 300)}));
  try {
    for (const [id, name] of Object.values(schema)) {
      const info = wf.getFieldInfo(id);
      if (Object.keys(info).length === 0 || !node(id)) return reply('loading');
      if (info.fieldname !== name || info.tableMark !== 'main') {
        return reply('unsupported');
      }
      if (value(id).length > 4000) return reply('unsupported');
    }
    for (const [id, name] of Object.values(courseFields)) {
      const info = wf.getFieldInfo(id);
      if (info.fieldname !== name || info.tableMark !== 'detail_1') return reply('unsupported');
    }
    const owner = value(schema.studentNo[0]);
    if (!owner) return reply('loading');
    const stateKey = '__bnbuNativeLeaveV1';
    if (request.operation === 'attach') {
      // Reattaching cannot clear pending upload/submission or replace a lease.
      if (!window[stateKey]) window[stateKey] = {nonce: request.nonce, owner, document};
    }
    const state = window[stateKey];
    if (!state || state.nonce !== request.nonce || state.owner !== owner ||
        state.document !== document) return reply('stale');
    const label = (id, fallback) => {
      const ec = window.ecCom || window.ecComSmall;
      return ec?.WeaLocaleProvider?.getLabel?.(id, fallback);
    };
    const plain = element => element?.textContent?.replace(/\s+/g, ' ').trim() || '';
    // Only the school's designated user-facing receipt, parsed in inert DOM.
    // Do not traverse errorInfo, submitParams or arbitrary response properties.
    const receiptText = message => {
      if (!message || typeof message !== 'object') return '';
      return ['title', 'detail'].map(key => {
        const raw = message[key];
        if (typeof raw !== 'string' || raw.length > 8000) return '';
        const template = document.createElement('template');
        template.innerHTML = raw;
        template.content.querySelectorAll('script,style,iframe,object,embed,svg,math,input,textarea')
          .forEach(e => e.remove());
        return plain(template.content).replace(/[\u0000-\u001f\u007f]/g, '').slice(0, 600);
      }).filter((s, i, a) => s && a.indexOf(s) === i).join('\n').slice(0, 1200);
    };
    const visible = element => {
      for (let e = element; e; e = e.parentElement) {
        const style = getComputedStyle(e);
        if (e.hidden || e.getAttribute('aria-hidden') === 'true' || style.display === 'none' ||
            ['hidden', 'collapse'].includes(style.visibility)) return false;
      }
      return true;
    };
    const confirmation = () => {
      const dialogs = [...document.querySelectorAll('.ant-confirm, .ant-modal-confirm')]
        .filter(e => !state.previousDialogs?.includes(e) && visible(e));
      if (dialogs.length !== 1) return null;
      const dialog = dialogs[0];
      const title = dialog.querySelector('.ant-confirm-title, .ant-modal-confirm-title');
      const content = dialog.querySelector('.ant-confirm-content, .ant-modal-confirm-content');
      let buttons = [...dialog.querySelectorAll('.ant-confirm-btns button, .ant-modal-confirm-btns button')];
      if (!title || !content || buttons.length !== 2 || buttons.some(b => b.disabled || !visible(b)) ||
          content.querySelector('a,button,input,select,textarea,iframe,script,style,object,embed,[role],[contenteditable]') ||
          !visible(title) || !visible(content)) return null;
      let kind = 'standard', message = plain(content);
      if (plain(title) === 'Submit Confirmation') {
        // Verified in the live workflow 57 DOM (2026-09-16): same ant-confirm
        // shell, but bilingual dynamic content and Confirm BEFORE Back.
        // Preserve the school's wording, BRs and course list, never HTML.
        const elements = [...content.querySelectorAll('*')];
        if (elements.length > 500 || elements.some(e =>
            !['DIV', 'SPAN', 'BR'].includes(e.tagName) || !visible(e))) return null;
        const spans = [...content.querySelectorAll('span')];
        const start = value('26447') + ' ' + value('26448');
        const end = value('26449') + ' ' + value('26450');
        const dateTime = /^\d{4}-\d{2}-\d{2} \d{2}:\d{2}$/;
        if (!dateTime.test(start) || !dateTime.test(end) || spans.length !== 4 ||
            plain(spans[0]) !== start + ' to ' + end ||
            plain(spans[2]) !== start + ' 至 ' + end || !plain(spans[1]) ||
            plain(spans[1]) !== plain(spans[3]) ||
            plain(buttons[0]) !== 'Confirm' || plain(buttons[1]) !== 'Back') return null;
        const copy = content.cloneNode(true);
        copy.querySelectorAll('br').forEach(e => e.replaceWith('\n'));
        message = copy.textContent.trim();
        const expected = 'The leave period you applied for is: ' + start + ' to ' + end +
          ' The courses you have chosen are: ' + plain(spans[1]) +
          ' Each person can only apply once a day. Are you sure you want to submit?' +
          ' 你申请的请假时间是： ' + start + ' 至 ' + end +
          ' 你选择的课程是： ' + plain(spans[3]) + ' 每人每天只能申请一次。你确定要提交吗？';
        if (message.length > 8000 || message.replace(/\s+/g, ' ') !== expected) return null;
        kind = 'leave';
        buttons = [buttons[1], buttons[0]]; // Internal order: cancel, confirm.
      } else if (plain(title) !== label(131329, '信息确认') ||
          message !== label(19990, '确认是否提交?') ||
          plain(buttons[0]) !== label(201, '取消') || plain(buttons[1]) !== label(826, '确定')) return null;
      if (state.consumedConfirmationKinds?.includes(kind)) return null;
      return {dialog, buttons, kind, title: plain(title), message,
        cancel: plain(buttons[0]), confirm: plain(buttons[1])};
    };
    state.submissionStatus = () => {
      if (state.owner !== value(schema.studentNo[0])) return reply('stale');
      if (state.outcome) return reply(state.outcome, state.receiptMessage
        ? {schoolMessage: state.receiptMessage} : {});
      const current = confirmation();
      if (current) {
        if (!state.decision || state.decision.dialog !== current.dialog) {
          state.decisionSerial = (state.decisionSerial || 0) + 1;
          state.decision = {...current, token: request.nonce + ':submit:' + state.decisionSerial, at: Date.now()};
        }
        const d = state.decision;
        return reply('submission_confirmation', {confirmation: {
          token: d.token, title: d.title, message: d.message, cancel: d.cancel, confirm: d.confirm,
        }});
      }
      return reply('submission_unconfirmed');
    };
    if (request.operation === 'submit_decision') {
      const d = state.decision, current = confirmation();
      if (!state.submission || state.outcome || !d || !current ||
          Date.now() - d.at > 300000 || request.token !== d.token ||
          typeof request.confirmed !== 'boolean' || d.dialog !== current.dialog ||
          state.submissionFingerprint !== state.submissionCurrent?.() ||
          d.buttons.some((button, i) => button !== current.buttons[i]) ||
          ['title', 'message', 'cancel', 'confirm'].some(k => d[k] !== current[k])) return reply('conflict');
      // This is the school's own pre-send confirmation, never doSubmit().
      // Consume the handle before clicking, including if its handler throws.
      state.consumedConfirmationKinds.push(d.kind);
      delete state.decision;
      d.buttons[request.confirmed ? 1 : 0].click();
      if (!request.confirmed && !state.outcome && (!d.dialog.isConnected || !visible(d.dialog))) {
        state.submission = false;
        return reply('submission_cancelled');
      }
      return state.submissionStatus();
    }
    if (!['upload_status', 'upload_abort'].includes(request.operation) &&
        typeof wf.judgeIsLoading === 'function' && wf.judgeIsLoading()) {
      return reply('busy');
    }
    const indices = String(wf.getDetailAllRowIndexStr('detail_1') || '').split(',').filter(Boolean);
    if (indices.length > 100 || new Set(indices).size !== indices.length ||
        indices.some(i => !/^\d+$/.test(i))) return reply('unsupported');
    const captureRow = index => ({index,
      values: Object.values(courseFields).map(([id]) => value(id + '_' + index)),
      nodes: Object.values(courseFields).map(([id]) => node(id + '_' + index))});
    const matchesRow = row => indices.includes(row.index) &&
      Object.values(courseFields).every(([id], i) =>
        value(id + '_' + row.index) === row.values[i] &&
        node(id + '_' + row.index) === row.nodes[i]);
    const writableRow = index => Number(wf.getFieldInfo('27731').isonlyshow) !== 1 &&
      [2, 3].includes(Number(wf.getFieldCurViewAttr('field27731_' + index)));
    const cleanText = e => e?.textContent?.replace(/\s+/g, ' ').trim() || '';
    const fieldFile = node('7110');
    const fileInfo = wf.getFieldInfo('7110');
    const maxBytes = Math.floor(Number(fileInfo.fileattr?.maxUploadSize) * 1024 * 1024);
    const inputs = [...fieldFile.querySelectorAll('input[type="file"]')];
    const input = inputs.length === 1 ? inputs[0] : null;
    const fileWritable = Number(fileInfo.htmltype) === 6 && Number(fileInfo.isonlyshow) !== 1 &&
      [2, 3].includes(Number(wf.getFieldCurViewAttr('field7110')));
    // The school's File component reads isautoupload from the FIELD metadata.
    const auto = fileInfo.isautoupload ?? fileInfo.fileattr?.isautoupload;
    const automaticUpload = auto == null || auto === true || Number(auto) === 1;
    const fileObject = typeof wf.getFieldValueObj === 'function' ? wf.getFieldValueObj('field7110') : null;
    // WfForm.valueObj exposes MobX 3 ObservableArray, for which Array.isArray
    // is false. Materialize only this bounded attachment list, never stores.
    const fileArray = raw => {
      if (raw == null) return [];
      if ((!Array.isArray(raw) && !(typeof window.mobx?.isObservableArray === 'function' &&
          window.mobx.isObservableArray(raw))) || !Number.isSafeInteger(raw.length) ||
          raw.length < 0 || raw.length > 30) return null;
      return Array.from(raw);
    };
    const fileData = fileArray(fileObject?.specialobj?.filedatas);
    const ids = value('7110').split(',').filter(v => v && v !== '-1');
    const normalizedFiles = fileData ? fileData.map(f => ({
      id: String(f.fileid ?? f.id ?? ''), name: String(f.filename ?? f.name ?? ''), original: f,
    })) : [];
    const filesKnown = fileData !== null && ids.length === normalizedFiles.length && ids.length <= 30 &&
      new Set(ids).size === ids.length && normalizedFiles.every(f =>
        ids.includes(f.id) && f.name.length > 0 && f.name.length <= 255) &&
      new Set(normalizedFiles.map(f => f.id)).size === ids.length;
    const attachmentRequired = Number(wf.getFieldCurViewAttr('field7110')) === 3;
    const requiredCourseFields = indices.flatMap(index => Object.values(courseFields)
      .map(([id]) => id + '_' + index)
      .filter(id => Number(wf.getFieldCurViewAttr('field' + id)) === 3));
    const missingCourses = requiredCourseFields.some(id => !value(id).trim());
    const requiredMissing = missingCourses || (attachmentRequired && (!filesKnown || ids.length === 0)) ||
      [...editable].some(key => Number(wf.getFieldCurViewAttr('field' + schema[key][0])) === 3 &&
        !value(schema[key][0]).trim());
    const fingerprint = () => JSON.stringify([
      Object.values(schema).map(([id]) => value(id)),
      indices.map(i => captureRow(i).values),
      normalizedFiles.map(f => [f.id, f.name]),
    ]);
    // Only the observed acknowledgement field and its exact public label. Do
    // not expose arbitrary checkboxes or write any inferred hidden field.
    const ackField = node('26469');
    const ackInfo = wf.getFieldInfo('26469');
    const ackOptions = options('26469');
    const acknowledgementValue = ackOptions.length === 1 ? ackOptions[0].value : null;
    const ackInputs = [...(ackField?.querySelectorAll('input[type="checkbox"]') || [])];
    const ack = ackInputs.length === 1 ? ackInputs[0] : null;
    const ackText = cleanText(ackField?.closest('td'));
    const cells = [...document.querySelectorAll('td')].filter(e => !e.querySelector('table'));
    const uniqueCell = prefix => {
      const hits = cells.filter(e => cleanText(e).startsWith(prefix));
      return hits.length === 1 && cleanText(hits[0]).length <= 6000 ? hits[0] : null;
    };
    const declaration = uniqueCell('I certify that the above information is true and correct.');
    const note = uniqueCell('* A student who has been absent without approval');
    const attachmentNote = uniqueCell('Name attachments with student number');
    const submitButtons = [...document.querySelectorAll('button')]
      .filter(b => cleanText(b) === 'Submit');
    const submit = submitButtons.length === 1 ? submitButtons[0] : null;
    const ackKnown = ack && ackInfo.tableMark === 'main' &&
      ackInfo.fieldname === 'pleaseticktoindicateyouracknow' && Number(ackInfo.htmltype) === 5 &&
      acknowledgementValue !== null && acknowledgementValue !== '' &&
      [2, 3].includes(Number(wf.getFieldCurViewAttr('field26469'))) &&
      ackText === 'Please tick to indicate your acknowledgement of the provisions. 请勾选已了解申请须知。';
    const reviewReady = !!(ackKnown && declaration && note && attachmentNote && submit &&
      !submit.disabled && !ack.disabled && filesKnown && !state.upload && !state.picker && !state.mutation);
    const controlsCurrent = snapshot => snapshot && Date.now() - snapshot.at < 300000 &&
      snapshot.fingerprint === fingerprint() && snapshot.input === input && snapshot.fileField === fieldFile &&
      snapshot.ack === ack && snapshot.submit === submit && snapshot.declaration === cleanText(declaration) &&
      snapshot.note === cleanText(note) && snapshot.attachmentNote === cleanText(attachmentNote) &&
      snapshot.ackText === ackText && snapshot.acknowledgementValue === acknowledgementValue;
    if (state.submission && !['read', 'attach', 'focus', 'submit_status'].includes(request.operation)) return reply('submission_locked');
    if (request.operation === 'submit_status') {
      // Only report a dispatched action, never infer school acceptance from a
      // click, elapsed time, an empty error list or a changed URL.
      return reply(state.submission ? 'submission_unconfirmed' : 'rejected');
    }
    if (request.operation === 'acknowledge') {
      if (requiredMissing) return reply('required_missing');
      if (!reviewReady || !controlsCurrent(state.completion) || request.token !== state.completion.token ||
          request.confirmed !== true) return reply('conflict');
      if (!ack.checked) ack.click();
      if (!ack.checked || value('26469') !== acknowledgementValue) return reply('write_failed');
      state.completion.acknowledged = true;
      return reply('acknowledged');
    }
    if (request.operation === 'submit_confirmed') {
      if (requiredMissing) return reply('required_missing');
      const snapshot = state.completion;
      if (request.confirmed !== true || !reviewReady || !controlsCurrent(snapshot) ||
          request.token !== snapshot.token || !snapshot.acknowledged || !ack.checked ||
          value('26469') !== acknowledgementValue) return reply('conflict');
      // Consume before invoking the SCHOOL submit button (not doSubmit, which
      // would bypass its wrapper). A timeout/throw cannot dispatch it twice.
      if (typeof wf.registerCheckEvent !== 'function' || wf.OPER_APIRETURN !== 'oper_apiReturn') {
        return reply('submission_unavailable');
      }
      if (!state.resultObserver) {
        state.resultObserver = true;
        wf.registerCheckEvent(wf.OPER_APIRETURN, (next, context) => {
          try {
            if (window[stateKey] !== state || state.document !== document || !state.submission ||
                state.owner !== value(schema.studentNo[0]) || state.outcome ||
                context?.src !== 'submit' || context.actiontype !== 'requestOperation') return;
            const data = context.result?.data, info = data?.resultInfo;
            const id = info?.requestid;
            const positiveId = (typeof id === 'number' && Number.isSafeInteger(id) && id > 0) ||
              (typeof id === 'string' && /^[1-9]\d{0,14}$/.test(id));
            const followUp = ['isaffirmance', 'selectNextFlow', 'isCAAuth', 'isNextNodeOperator', 'needRemind']
              .some(k => info?.[k] != null && ![0, '0', false, ''].includes(info[k]));
            const status = data?.type === 'SUCCESS' && positiveId && !followUp
              ? 'submission_succeeded' : data?.type === 'FAILD'
                ? 'submission_failed' : 'submission_pending';
            state.outcome = status;
            state.receiptMessage = receiptText(data?.messageInfo);
            // Copy only the lease and decision, never requestId, form contents,
            // submitParams, credentials, errors or response bodies.
            const event = {nonce: state.nonce, status};
            if (window.webkit?.messageHandlers?.bnbuLeaveSubmission) {
              window.webkit.messageHandlers.bnbuLeaveSubmission.postMessage(event);
            } else if (window.flutter_inappwebview?.callHandler) {
              Promise.resolve(window.flutter_inappwebview.callHandler('bnbuLeaveSubmission', event)).catch(() => {});
            }
          } catch (_) {
            // Observer errors must never block the school's result handler.
          } finally {
            next();
          }
        });
      }
      state.previousDialogs = [...document.querySelectorAll('.ant-confirm, .ant-modal-confirm')];
      state.submissionFingerprint = fingerprint();
      state.submissionCurrent = fingerprint;
      // At most one of each verified school confirmation per Submit. A second
      // stage receives its own native user decision, never an automatic click.
      state.consumedConfirmationKinds = [];
      delete state.decision;
      delete state.outcome;
      delete state.receiptMessage;
      state.submission = true;
      delete state.completion;
      submit.click();
      return state.submissionStatus();
    }
    if (request.operation === 'upload_begin') {
      if (!controlsCurrent(state.completion) || request.token !== state.completion.token ||
          state.upload || state.picker || state.mutation || !filesKnown || !fileWritable || !automaticUpload ||
          !input || input.disabled || typeof DataTransfer !== 'function' ||
          !Number.isSafeInteger(maxBytes) || maxBytes <= 0 ||
          !Number.isSafeInteger(request.size) || request.size <= 0 ||
          request.size > Math.min(maxBytes, 20 * 1024 * 1024) || ids.length >= 30 ||
          typeof request.name !== 'string' || !request.name.trim() || request.name.length > 255 ||
          /[\\/\u0000-\u001f\u007f]/.test(request.name)) return reply('rejected');
      state.upload = {input, fileField: fieldFile, before: value('7110'), ids: [...ids],
        name: request.name, size: request.size, chunks: [], received: 0, at: Date.now()};
      delete state.completion;
      return reply('upload_buffering');
    }
    if (request.operation === 'upload_abort') {
      if (state.upload?.dispatched) return reply('upload_unconfirmed');
      delete state.upload;
      return reply('cancelled');
    }
    if (['upload_chunk', 'upload_dispatch', 'upload_status'].includes(request.operation)) {
      const upload = state.upload;
      if (!upload && request.operation === 'upload_status') return reply('upload_idle');
      if (!upload || upload.fileField !== fieldFile) return reply('conflict');
      if (request.operation === 'upload_status') {
        if (!upload.dispatched) return reply('upload_buffering');
        const added = normalizedFiles.filter(f => !upload.ids.includes(f.id));
        if (filesKnown && upload.ids.every(id => ids.includes(id)) && added.length === 1 && added[0].name === upload.name) {
          delete state.upload;
          return reply('uploaded');
        }
        return reply('upload_unconfirmed');
      }
      if (upload.dispatched || upload.input !== input || input.disabled || !fileWritable || !automaticUpload ||
          upload.before !== value('7110') || Date.now() - upload.at > 300000) return reply('conflict');
      if (request.operation === 'upload_chunk') {
        if (request.offset !== upload.received || typeof request.data !== 'string' ||
            request.data.length > 87384 || !/^[A-Za-z0-9+/]*={0,2}$/.test(request.data)) return reply('rejected');
        const bytes = Uint8Array.from(atob(request.data), c => c.charCodeAt(0));
        if (!bytes.length || bytes.length > 65536 || upload.received + bytes.length > upload.size) return reply('rejected');
        upload.chunks.push(bytes);
        upload.received += bytes.length;
        return reply('upload_buffering');
      }
      if (upload.received !== upload.size) return reply('rejected');
      const transfer = new DataTransfer();
      transfer.items.add(new File(upload.chunks, upload.name, {type: 'application/octet-stream'}));
      upload.chunks = [];
      upload.dispatched = true;
      input.files = transfer.files;
      // The school input's own upload handler owns URL, auth and validation.
      input.dispatchEvent(new Event('change', {bubbles: true}));
      return reply('upload_unconfirmed');
    }
    if (request.operation === 'attachment_remove') {
      if (!controlsCurrent(state.completion) || request.token !== state.completion.token ||
          !fileWritable || !filesKnown || state.upload || request.confirmed !== true) return reply('conflict');
      const file = state.completion.files.find(f => f.key === request.key);
      if (!file) return reply('conflict');
      const remaining = normalizedFiles.filter(f => f.id !== file.id);
      delete state.completion;
      // Same public WfForm value/specialobj shape used by the school's
      // fileChangeEvent. Remove only this form reference, not the remote file.
      wf.changeFieldValue('field7110', {value: remaining.map(f => f.id).join(','),
        specialobj: {...fileObject.specialobj, filedatas: remaining.map(f => f.original)}});
      const echoed = fileArray(wf.getFieldValueObj('field7110')?.specialobj?.filedatas);
      return reply(value('7110') === remaining.map(f => f.id).join(',') &&
        Array.isArray(echoed) && JSON.stringify(echoed) === JSON.stringify(remaining.map(f => f.original))
        ? 'written' : 'write_failed');
    }
    if (state.upload && !['read', 'attach', 'focus'].includes(request.operation)) return reply('busy');
    if (request.operation.startsWith('course_')) {
      // Only the observed school browser is supported. Candidate handles are
      // short-lived DOM references, never fabricated school IDs or API calls.
      // Ant keeps closed browsers mounted below a hidden wrap. Inspect the
      // ancestor chain too; layout/offset checks are unsuitable for a WebView
      // deliberately covered by the native form.
      const visible = element => {
        if (!element?.isConnected) return false;
        for (let e = element; e; e = e.parentElement) {
          const style = window.getComputedStyle(e);
          if (e.hidden || e.getAttribute('aria-hidden') === 'true' ||
              style.display === 'none' || ['hidden', 'collapse'].includes(style.visibility)) return false;
        }
        return true;
      };
      const modals = () => [...document.querySelectorAll('.wea-browser-modal')].filter(visible);
      const startPicker = (index, created = false) => {
        if (!writableRow(index)) return reply('readonly');
        const field = node('27731_' + index);
        const button = field?.querySelector('button.ant-btn');
        if (!button || !button.querySelector('.anticon-search') || button.disabled) return reply('unsupported');
        state.courseSerial = (state.courseSerial || 0) + 1;
        state.picker = {index, before: value('27731_' + index), field, created,
          baseline: captureRow(index), serial: state.courseSerial, revision: 0};
        delete state.mutation;
        button.click();
        return reply('loading');
      };
      const removeRow = (row, outcome) => {
        if (!matchesRow(row)) return reply('conflict');
        if (!writableRow(row.index)) return reply('readonly');
        if (typeof wf.delDetailRow !== 'function' ||
            !document.querySelector('#oTable0 .icon-coms-form-delete-hot.detailBtn')) return reply('unsupported');
        // School API verified in the live form and its public workflow script:
        // preserves OPER_DELROW validation, school linkage and ACTION_DELROW.
        // Consume before invoking it; settle only reads, never resends deletion.
        state.mutation = {kind: 'remove', row, outcome,
          others: indices.filter(i => i !== row.index).map(captureRow)};
        state.courseRows = [];
        delete state.picker;
        wf.delDetailRow('detail_1', row.index);
        return reply('loading');
      };
      const settle = cancel => {
        const mutation = state.mutation;
        if (!mutation) return reply('cancelled');
        if (mutation.kind === 'remove') {
          if (!mutation.others.every(matchesRow) ||
              indices.some(i => i !== mutation.row.index &&
                !mutation.others.some(r => r.index === i))) return reply('conflict');
          if (indices.includes(mutation.row.index)) {
            return reply(matchesRow(mutation.row) ? 'loading' : 'conflict');
          }
          delete state.mutation;
          return reply(mutation.outcome);
        }
        if (cancel) mutation.cancel = true;
        if (!mutation.before.every(matchesRow)) return reply('conflict');
        const added = indices.filter(i => !mutation.before.some(r => r.index === i));
        if (!added.length) return reply('loading');
        if (added.length !== 1) return reply('conflict');
        const row = captureRow(added[0]);
        if (row.values.some(Boolean)) return reply('conflict');
        if (row.nodes.some(n => !n)) return reply('loading');
        if (mutation.cancel) return removeRow(row, 'cancelled');
        return startPicker(row.index, true);
      };
      if (request.operation === 'course_release') {
        // Only forget a handle after the user closed/completed the original
        // school dialog. Never dismiss an unknown school dialog automatically.
        if (modals().length || state.mutation || state.picker?.created) return reply('conflict');
        delete state.picker;
        return reply('released');
      }
      if (request.operation === 'course_open') {
        if (state.picker || state.mutation || modals().length) return reply('conflict');
        const index = request.rowIndex ?? indices.find(i => captureRow(i).values.every(v => v === ''));
        if (request.rowIndex == null && index == null) {
          const add = document.querySelector('#oTable0 .icon-coms-Add-to-hot.detailBtn');
          if (!add || typeof wf.addDetailRow !== 'function' ||
              typeof wf.delDetailRow !== 'function' || indices.length >= 100) return reply('unsupported');
          if (add.classList.contains('detailBtnDisabled') || Number(wf.getFieldInfo('27731').isonlyshow) === 1) return reply('readonly');
          state.mutation = {kind: 'add', before: indices.map(captureRow)};
          // No supplied defaults/IDs and no forbidLinkage options. School owns
          // row creation and all validation; asynchronous results are polled.
          wf.addDetailRow('detail_1');
          return reply('loading');
        }
        if (!indices.includes(index)) return reply('unsupported');
        return startPicker(index);
      }
      if (request.operation === 'course_remove') {
        if (state.picker || state.mutation || modals().length) return reply('conflict');
        const row = state.courseRows?.find(row => row.token === request.token);
        return row ? removeRow(row, 'removed') : reply('conflict');
      }
      if (state.mutation && ['course_read', 'course_settle', 'course_cancel'].includes(request.operation)) {
        return settle(request.operation !== 'course_read');
      }
      if (['course_cancel', 'course_settle'].includes(request.operation) && !state.picker) return reply(modals().length ? 'conflict' : 'cancelled');
      const picker = state.picker;
      if (!picker || !indices.includes(picker.index) ||
          node('27731_' + picker.index) !== picker.field ||
          value('27731_' + picker.index) !== picker.before) return reply('conflict');
      const available = modals();
      if (picker.cancelling && !available.length) {
        if (picker.created) return removeRow(picker.baseline, 'cancelled');
        delete state.picker;
        return reply('cancelled');
      }
      if (request.operation === 'course_cancel' && !available.length) {
        // The browser may have failed before opening; leave existing rows intact.
        if (picker.created) return removeRow(picker.baseline, 'cancelled');
        delete state.picker;
        return reply('cancelled');
      }
      if (available.length !== 1) return reply(available.length ? 'unsupported' : 'loading');
      const modal = available[0];
      if (picker.modal && picker.modal !== modal) return reply('stale');
      const pending = () => {
        picker.token = null; // Any incomplete refresh invalidates old choices.
        return reply('loading');
      };
      const title = modal.querySelector('.wea-browser-single-title')?.textContent.trim();
      if (!title) return pending();
      if (!modal.classList.contains('wea-browser-single') || title !== 'Student Course') {
        return reply('unsupported');
      }
      picker.modal = modal;
      if (request.operation === 'course_cancel') {
        const close = modal.querySelector('.ant-modal-close');
        if (!close) return reply('unsupported');
        picker.cancelling = true;
        close.click();
        if (modals().length) return reply('loading');
        if (picker.created) return removeRow(picker.baseline, 'cancelled');
        delete state.picker;
        return reply('cancelled');
      }
      if (picker.cancelling) return reply('loading');
      if ([...modal.querySelectorAll('.ant-spin-spinning, [aria-busy="true"]')].some(visible)) return pending();
      const headers = [...modal.querySelectorAll('th')].map(e => e.textContent.trim());
      if (!headers.length) return pending();
      if (JSON.stringify(headers) !== JSON.stringify(['Course', 'Teacher', 'Units', 'Type', 'Times'])) return reply('unsupported');
      const rows = [...modal.querySelectorAll('tbody tr.ant-table-row')];
      const cells = row => [...row.cells].map(c => c.textContent.trim());
      const data = rows.map(cells);
      if (rows.length > 100 || data.some(c => c.length !== 5 || !c[0] || c.some(s => s.length > 500))) return reply('unsupported');
      const pager = modal.querySelector('.ant-pagination-weaSimple-pager');
      const prev = modal.querySelector('.ant-pagination-prev');
      const next = modal.querySelector('.ant-pagination-next');
      if (!pager || !prev || !next) return pending();
      const page = pager.textContent.trim();
      if (!page) return pending();
      // A mounted empty tbody alone is not evidence of a successful empty
      // result. Wait for rows or the school's explicit empty-state element.
      if (!rows.length && ![...modal.querySelectorAll('.ant-table-placeholder, .ant-empty')].some(visible)) return pending();
      const signature = JSON.stringify([page, data]);
      const enabled = e => !e.classList.contains('ant-pagination-disabled');
      if (request.operation === 'course_page' || request.operation === 'course_choose') {
        if (!matchesRow(picker.baseline) || !writableRow(picker.index)) return reply('conflict');
        if (picker.token !== request.token || picker.signature !== signature || picker.waiting) return reply('conflict');
        if (request.operation === 'course_page') {
          const target = request.direction === 'next' ? next : request.direction === 'prev' ? prev : null;
          if (!target || !enabled(target)) return reply('rejected');
          picker.waiting = signature;
          picker.waitingRows = JSON.stringify(data);
          picker.token = null;
          target.click();
          return reply('loading');
        }
        const candidate = picker.candidates?.find(c => c.key === request.key);
        if (!candidate || !candidate.row.isConnected || !modal.contains(candidate.row) ||
            JSON.stringify(cells(candidate.row)) !== JSON.stringify(candidate.cells)) return reply('conflict');
        // Consume before school linkage: an uncertain response cannot repeat it.
        delete state.picker;
        candidate.row.click();
        return reply('written');
      }
      if (request.operation !== 'course_read') return reply('rejected');
      // The pager may update before its asynchronous row request finishes.
      // Never expose old rows under the new page's candidate handles.
      if (picker.waiting && (picker.waiting === signature ||
          picker.waitingRows === JSON.stringify(data))) return pending();
      picker.waiting = null;
      picker.waitingRows = null;
      picker.signature = signature;
      picker.token = picker.serial + ':' + (++picker.revision);
      picker.candidates = rows.map((row, i) => ({key: String(i), row, cells: data[i]}));
      return reply('course_ready', {picker: {
        token: picker.token, rowIndex: picker.index, page,
        hasPrevious: enabled(prev), hasNext: enabled(next),
        candidates: picker.candidates.map(c => ({key: c.key, code: c.cells[0],
          teacher: c.cells[1], units: c.cells[2], type: c.cells[3], time: c.cells[4]})),
      }});
    }
    if (['validate', 'write'].includes(request.operation)) {
      const updates = Object.entries(request.changes || {});
      if (updates.length > editable.size) return reply('rejected');
      // Validate the whole patch before any school field changes. A stale or
      // partially failed write must be reconciled by the user, never replayed.
      for (const [key, change] of updates) {
        if (!editable.has(key) || !change || typeof change.value !== 'string' ||
            typeof change.before !== 'string') return reply('rejected');
        const id = schema[key][0];
        const info = wf.getFieldInfo(id);
        const attr = Number(wf.getFieldCurViewAttr('field' + id));
        if (Number(info.isonlyshow) === 1 || ![2, 3].includes(attr)) return reply('readonly');
        if (value(id) !== change.before) return reply('conflict');
        if (attr === 3 && change.value.trim() === '') return reply('rejected');
        const limit = key === 'details' ? 4000 : 100;
        if (change.value.length > limit || /\u0000/.test(change.value)) return reply('rejected');
        if (['mobile', 'familyPhone'].includes(key) && /[\u0000-\u001f\u007f-\u009f]/.test(change.value)) return reply('rejected');
        const max = Number(info.length);
        if (max > 0 && change.value.length > max) return reply('rejected');
        if (key === 'reason' && change.value !== '' &&
            !options(id).some(o => o.value === change.value)) return reply('rejected');
        if (key.endsWith('Date') && change.value !== '') {
          if (!/^\d{4}-\d{2}-\d{2}$/.test(change.value)) return reply('rejected');
          const date = new Date(change.value + 'T12:00:00Z');
          if (!Number.isFinite(date.getTime()) || date.toISOString().slice(0, 10) !== change.value) {
            return reply('rejected');
          }
        }
        if (key.endsWith('Time') && change.value !== '' &&
            !/^(?:[01]\d|2[0-3]):[0-5]\d$/.test(change.value)) return reply('rejected');
      }
      if (request.operation === 'validate') return reply('validated');
      for (const [key, change] of updates) {
        wf.changeFieldValue('field' + schema[key][0], {value: change.value});
      }
      return reply('written');
    }
    if (request.operation === 'focus') {
      const targets = {courses: '27731', attachment: '7110', review: null};
      if (!Object.hasOwn(targets, request.section)) return reply('rejected');
      const target = request.section === 'courses'
        ? document.querySelector('[data-fieldmark^="field27731_"]')
        : targets[request.section] ? node(targets[request.section]) : null;
      if (target) target.scrollIntoView({block: 'center', behavior: 'auto'});
      else if (request.section === 'review') window.scrollTo(0, 0);
      return reply('focused');
    }
    if (!['read', 'attach'].includes(request.operation)) return reply('rejected');
    const fields = {};
    for (const [key, [id]] of Object.entries(schema)) {
      if (key === 'attachment') continue;
      const raw = value(id);
      const info = wf.getFieldInfo(id);
      const choices = options(id);
      const display = choices.find(o => o.value === raw)?.label ||
        (editable.has(key) ? raw : text(node(id).textContent).trim() || raw);
      fields[key] = {value: raw, display,
        editable: editable.has(key) && Number(info.isonlyshow) !== 1 &&
          [2, 3].includes(Number(wf.getFieldCurViewAttr('field' + id))),
        required: Number(wf.getFieldCurViewAttr('field' + id)) === 3,
        maxLength: Number(info.length) > 0 ? Math.min(Number(info.length), 4000) : 4000};
    }
    state.rowSerial = (state.rowSerial || 0) + 1;
    state.courseRows = indices.map(index => ({...captureRow(index), token: state.rowSerial + ':' + index}));
    const courses = indices.map(index => {
      const row = {index, token: state.courseRows.find(r => r.index === index).token};
      for (const [key, [id]] of Object.entries(courseFields)) {
        // Empty required browser fields can contain '*' and search glyphs.
        // Never expose those school decorations as a selected course.
        const raw = value(id + '_' + index);
        // Read the school's current field store, not a React label that may
        // still be painting the old selection behind the native dialog.
        // Getter behavior is verified in the school's public WfForm runtime.
        const kind = Number(wf.getFieldInfo(id).htmltype);
        const selectedLabel = options(id).find(o => o.value === raw)?.label;
        let display = selectedLabel || node(id + '_' + index)?.textContent || raw;
        if (kind === 3) {
          display = typeof wf.getBrowserShowName === 'function'
            ? wf.getBrowserShowName('field' + id + '_' + index)
            : node(id + '_' + index)?.textContent || '';
        } else if ([1, 2].includes(kind)) display = raw;
        else if (kind === 5) display = selectedLabel || '';
        row[key] = raw ? text(display, 500)
          .replace(/\s+/g, ' ').trim() : '';
      }
      return row;
    }).filter(row => row.code || row.title);
    const file = node('7110');
    state.completionSerial = (state.completionSerial || 0) + 1;
    const token = String(state.completionSerial);
    state.completion = {token, at: Date.now(), fingerprint: fingerprint(), input, fileField: fieldFile,
      ack, submit, declaration: cleanText(declaration), note: cleanText(note),
      attachmentNote: cleanText(attachmentNote), ackText, acknowledgementValue,
      files: normalizedFiles.map((f, i) => ({id: f.id, key: token + ':' + i, name: f.name}))};
    return reply('ready', {fields, reasons: options('7108'), courses,
      completion: {token, notices: [cleanText(note), cleanText(attachmentNote)].filter(Boolean),
        declaration: cleanText(declaration), acknowledgement: ackKnown ? ackText : '',
        canSubmit: reviewReady && !state.submission, maxBytes: Number.isFinite(maxBytes) ? Math.min(maxBytes, 20 * 1024 * 1024) : 0,
        attachmentRequired, filesKnown, coursesRequired: requiredCourseFields.length > 0, missingCourses,
        canUpload: !!(fileWritable && automaticUpload && filesKnown && input && !input.disabled && maxBytes > 0 &&
          typeof DataTransfer === 'function' && !state.upload && !state.submission),
        files: filesKnown ? state.completion.files.map(({key, name}) => ({key, name})) : []},
      attachmentSummary: text(file?.textContent, 2000).trim(),
      attachmentLimit: text(wf.getFieldInfo('7110').fileattr?.maxUploadSize, 20)});
  } catch (_) {
    // Never return exception messages or arbitrary page state to the client.
    return reply(['write', 'course_choose', 'course_open', 'course_remove', 'course_cancel', 'course_settle',
      'acknowledge', 'submit_confirmed', 'attachment_remove', 'upload_dispatch'].includes(request.operation)
      ? 'write_failed' : 'unsupported');
  }
})
