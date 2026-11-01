// Bench probe. window.__DOC (text) and window.__MODE ('read'|'edit') are set by run.sh.
window.__probe = async function () {
  var R = {};
  // reader layout without the rest of the app
  document.querySelectorAll('.view').forEach(function (v) { v.className = 'view'; });
  document.getElementById('chatview').className = 'view on reader';
  var text = window.__DOC; var view0 = document.getElementById("docview");
  var t0 = performance.now();
  var frag = md(text, []);
  R.mdMs = +(performance.now() - t0).toFixed(1);
  t0 = performance.now();
  paintDoc({ path: window.__PATH, name: window.__NAME, text: text, stamp: 's1', paths: [], editing: window.__MODE === 'edit' });
  void document.getElementById('docscroll').scrollHeight;
  R.firstPaintMs = +(performance.now() - t0).toFixed(1);  // synchronous: parse + first slice laid out
  void view0.offsetHeight; await new Promise(function (r) { setTimeout(r, 30); });
  R.paintMs = +(performance.now() - t0).toFixed(1);
  // whole document in place (sliced rendering)
  for (var w8 = performance.now(); performance.now() - w8 < 3000 && window.__MODE !== 'edit' && document.getElementById('docview').dataset.done !== 's1'; w8++) { await new Promise(function (r) { setTimeout(r, 5); }); }
  void view0.offsetHeight;
  R.fullMs = +(performance.now() - t0).toFixed(1);
  var view = document.getElementById('docview');
  // stand in for Swift: answer image asset requests with the file next to the page
  window.__sent.filter(function (m) { return m.act === 'asset'; }).forEach(function (m) {
    setAsset({ path: m.path, kind: 'image', src: m.path.split('/').pop() });
  });
  await new Promise(function (r) { setTimeout(r, 100); });
  R.lines = text.split('\n').length;

  // 1. bidi per block: expected direction from the first strong letter
  function firstStrong(s) { for (var q = 0; q < s.length; q++) { var c = s.charCodeAt(q); if (c === 0x200F || (c >= 0x590 && c <= 0x6FF)) return 'rtl'; if (c === 0x200E || (c >= 65 && c <= 90) || (c >= 97 && c <= 122) || (c >= 0xC0 && c <= 0x24F)) return 'ltr'; } return null; }
  var bad = [];
  view.querySelectorAll('p, li, h1, h2, h3, h4, h5, h6, blockquote, th, td').forEach(function (n) {
    var want = firstStrong(n.textContent); if (!want) return;
    var cs = getComputedStyle(n);
    if (n.tagName === 'LI') {
      // an item follows its list; its text orders itself (plaintext)
      var w = n.querySelector('span.lit'); if (!w || getComputedStyle(w).direction !== want || cs.direction !== getComputedStyle(n.parentNode).direction) bad.push('LI-side:' + n.textContent.slice(0, 40));
      return;
    }
    var got = cs.direction;
    if (got !== want) bad.push(n.tagName + ':' + n.textContent.slice(0, 40));
  });
  R.blockDirMismatch = bad.length; R.blockDirMismatchSample = bad.slice(0, 6);
  R.preNotLtr = Array.prototype.filter.call(view.querySelectorAll('pre'), function (n) { return getComputedStyle(n).direction !== 'ltr'; }).length;
  R.rtlCellsNotRight = Array.prototype.filter.call(view.querySelectorAll('td, th'), function (n) {
    return !n.style.textAlign && getComputedStyle(n).direction === 'rtl' && ['right', 'start'].indexOf(getComputedStyle(n).textAlign) < 0 && getComputedStyle(n).textAlign !== '-webkit-right'; }).length;

  // 3. feature parity
  function has(sel) { return view.querySelectorAll(sel).length; }
  R.features = {
    h5: has('h5'), h6: has('h6'), strike: has('del, s'), italic: has('i, em'),
    link: has('a[data-href^="http"]'), relLink: has('a[data-href="notes.md"]'),
    img: has('img'), checkbox: has('input[type=checkbox], .task, .done'),
    nested: has('li li, li.sub'), olStart5: has('ol[start="5"]'),
    codeHighlight: has('pre span'), tableAlign: Array.prototype.filter.call(view.querySelectorAll('td'), function (n) { return n.style.textAlign; }).length,
    rawHtmlEscaped: view.textContent.indexOf('<b>') >= 0
  };

  // fonts
  var p = view.querySelector('p');
  R.fontProse = p ? getComputedStyle(p).fontFamily : null;
  var pre = view.querySelector('pre');
  R.fontCode = pre ? getComputedStyle(pre).fontFamily : null;

  // 2. editor
  var ta = document.getElementById('docedit');
  R.editor = { unicodeBidi: getComputedStyle(ta).unicodeBidi, dir: ta.dir, font: getComputedStyle(ta).fontFamily };
  ta.value = 'a\r\nb'; R.editor.crlfKept = ta.value === 'a\r\nb';
  if (window.__MODE === 'edit' && cm) {
    R.engine = 'codemirror';
    R.editor.roundTrip = cm.value === text;
    R.editorBehaviour = await window.__cmProbe(text);
    R.cardBehaviour = await window.__cardProbe(text);
    return R;
  }
  if (window.__MODE === 'edit') {
    R.engine = 'textarea';
    ta.value = text; R.editor.roundTrip = ta.value === text;
    ta.focus(); ta.setSelectionRange(0, 0);
    R.editorBehaviour = await window.__editProbe();
    var ed = freshEditor(); ed.className = 'on'; ed.value = text;
    var mid = Math.floor(text.length / 2); ed.focus(); ed.setSelectionRange(mid, mid);
    var lat = [];
    for (var z = 0; z < 40; z++) { var t1 = performance.now(); document.execCommand('insertText', false, 'ש'); void ed.scrollHeight; lat.push(performance.now() - t1); }
    lat.sort(function (a, b) { return a - b; });
    R.inputLatencyMs = { median: +lat[20].toFixed(2), p95: +lat[38].toFixed(2) };
    ed.value = text; ed.setSelectionRange(0, 0); ed.scrollTop = 0;
  }
  return R;
};

// Editor behaviour, driven with synthetic keys in real WebKit.
window.__editProbe = async function () {
  var ta = document.getElementById('docedit'), R = {};
  function key(k, o) { var e = new KeyboardEvent('keydown', Object.assign({ key: k, bubbles: true, cancelable: true }, o || {})); ta.dispatchEvent(e); return e.defaultPrevented; }
  function caretEnd() { ta.focus(); ta.setSelectionRange(ta.value.length, ta.value.length); }
  ta.value = '- פריט ראשון'; caretEnd(); key('Enter'); R.bulletContinues = ta.value === '- פריט ראשון\n- ';
  document.execCommand('insertText', false, 'second'); key('Enter'); key('Enter'); R.emptyItemEnds = ta.value === '- פריט ראשון\n- second\n';
  ta.value = '9. תשע'; caretEnd(); key('Enter'); R.numberIncrements = ta.value === '9. תשע\n10. ';
  ta.value = '- [x] בוצע'; caretEnd(); key('Enter'); R.taskResets = ta.value === '- [x] בוצע\n- [ ] ';
  ta = freshEditor(); ta.className = 'on'; ta.value = 'שלום עולם'; ta.focus(); ta.setSelectionRange(0, 4); key('b', { metaKey: true }); R.boldWraps = ta.value === '**שלום** עולם';
  document.execCommand('undo'); R.undoAfterBold = ta.value === 'שלום עולם';
  document.execCommand('redo'); R.redo = ta.value === '**שלום** עולם'; R.redoValue = ta.value;
  ta.value = '- a\n- b'; ta.focus(); ta.setSelectionRange(0, ta.value.length); key('Tab'); R.tabIndents = ta.value === '  - a\n  - b';
  key('Tab', { shiftKey: true }); R.shiftTabOutdents = ta.value === '- a\n- b';
  // dirty mark + close guard
  docDirty = false; ta.dispatchEvent(new Event('input')); R.dirtyMark = document.getElementById('docnote').textContent.indexOf('●') === 0;
  window.__sent.length = 0; closeDocAsked(); R.firstCloseHeld = window.__sent.filter(function (m) { return m.act === 'closeDoc'; }).length === 0;
  closeDocAsked(); R.secondCloseCloses = window.__sent.filter(function (m) { return m.act === 'closeDoc'; }).length === 1;
  docDirty = true; window.__sent.length = 0; saveAnything(); var sv = window.__sent.filter(function (m) { return m.act === 'saveDoc'; })[0];
  R.cmdSStays = !!(sv && sv.stay === true) && !docDirty;
  return R;
};


// The same behaviour checks against the CodeMirror editor, through real keymaps.
window.__cmProbe = async function (text) {
  var v = cm.view, R = {};
  function set(str, at) { v.dispatch({ changes: { from: 0, to: v.state.doc.length, insert: str }, selection: { anchor: at == null ? str.length : at } }); }
  function key(k, o) { var e = new KeyboardEvent('keydown', Object.assign({ key: k, bubbles: true, cancelable: true }, o || {})); v.contentDOM.dispatchEvent(e); return e.defaultPrevented; }
  function val() { return v.state.doc.toString(); }
  v.focus();
  set('- פריט ראשון'); key('Enter'); R.bulletContinues = val() === '- פריט ראשון\n- ';
  v.dispatch(v.state.replaceSelection('second')); key('Enter'); key('Enter'); R.emptyItemEnds = /- second\n?$/.test(val()) && val().split('\n').pop().trim() === '';
  set('9. תשע'); key('Enter'); R.numberIncrements = val() === '9. תשע\n10. ';
  set('- [x] בוצע'); key('Enter'); R.taskResets = val() === '- [x] בוצע\n- [ ] ';
  set('שלום עולם'); v.dispatch({ selection: { anchor: 0, head: 4 } }); key('b', { metaKey: true }); R.boldWraps = val() === '**שלום** עולם';
  key('z', { metaKey: true }); R.undoAfterBold = val() === 'שלום עולם';
  (function () { var e = new KeyboardEvent('keydown', { key: 'Z', metaKey: true, shiftKey: true, bubbles: true, cancelable: true }); Object.defineProperty(e, 'keyCode', { get: function () { return 90; } }); v.contentDOM.dispatchEvent(e); })(); R.redo = val() === '**שלום** עולם';
  set('- a\n- b'); v.dispatch({ selection: { anchor: 0, head: v.state.doc.length } }); key('Tab'); R.tabIndents = /^\s+- a\n\s+- b$/.test(val());
  key('Tab', { shiftKey: true }); R.shiftTabOutdents = val() === '- a\n- b';
  // per-line direction
  set('שורה בעברית עם config.json\nEnglish line with עברית\n## ‏Q-ID · כותרת');
  await new Promise(function (r) { setTimeout(r, 50); }); v.requestMeasure(); 
  var lines = v.contentDOM.querySelectorAll('.cm-line');
  R.lineDirs = Array.prototype.map.call(lines, function (l) { return getComputedStyle(l).direction; });
  R.lineAttrs = Array.prototype.map.call(lines, function (l) { return l.getAttribute('dir') + '|' + l.getAttribute('style'); }); R.contentDir = getComputedStyle(v.contentDOM).direction + '|' + v.contentDOM.getAttribute('dir');
  docDirty = false; set('x'); R.dirtyMark = docDirty && document.getElementById('docnote').textContent.indexOf('●') === 0;
  window.__sent.length = 0; closeDocAsked(); R.firstCloseHeld = !window.__sent.some(function (m) { return m.act === 'closeDoc'; });
  closeDocAsked(); R.secondCloseCloses = window.__sent.filter(function (m) { return m.act === 'closeDoc'; }).length === 1;
  // ⌘S through the editor's keymap
  docDirty = true; window.__sent.length = 0; key('s', { metaKey: true });
  var sv = window.__sent.filter(function (m) { return m.act === 'saveDoc'; })[0];
  R.cmdSStays = !!(sv && sv.stay === true && sv.text === val()) && !docDirty;
  // typing latency on the real document
  set(text, Math.floor(text.length / 2));
  var lat = [];
  for (var z = 0; z < 40; z++) {
    var t1 = performance.now();
    v.dispatch(v.state.replaceSelection('ש'));
    v.measure && v.measure(); void v.contentDOM.offsetHeight;
    lat.push(performance.now() - t1);
  }
  lat.sort(function (a, b) { return a - b; });
  R.inputLatencyMs = { median: +lat[20].toFixed(2), p95: +lat[38].toFixed(2) };
  set(text, 0);
  return R;
};


// File-card editing in the chat, through the same editor.
window.__cardProbe = async function (text) {
  var R = {}, path = '/tmp/peach-bench/card.md';
  document.querySelectorAll('.view').forEach(function (v) { v.className = 'view'; });
  document.getElementById('chatview').className = 'view on';
  var card = el('div', 'card'); card.appendChild(el('div', 'cardbar')); card.appendChild(el('div', 'cardbody'));
  document.getElementById('docpane').parentNode.appendChild(card);
  cardNodes[path] = card;
  assets[path] = { path: path, kind: 'md', text: text, size: text.length };
  var st = stateOf(path); st.open = true; st.edit = true; editingPath = path;
  renderCard(path);
  var ce = cardEds[path];
  R.engine = ce ? 'codemirror' : 'textarea';
  if (!ce) { return R; }
  var v = ce.ed.view;
  R.loaded = ce.ed.value === text;
  v.dispatch({ changes: { from: 0, insert: 'שורה חדשה\n' } });
  R.dirtyMark = st.dirty === true && card.querySelector('.cardnote').textContent.indexOf('●') === 0;
  renderCard(path);                       // a repaint must not lose the draft
  R.draftSurvivesRepaint = cardEds[path] === ce && ce.ed.value.indexOf('שורה חדשה') === 0 && card.contains(ce.host);
  window.__sent.length = 0;
  v.contentDOM.dispatchEvent(new KeyboardEvent('keydown', { key: 's', metaKey: true, bubbles: true, cancelable: true }));
  var sv = window.__sent.filter(function (m) { return m.act === 'saveAsset'; });
  R.cmdSSendsOnce = sv.length === 1 && sv[0].stay === true && sv[0].text === ce.ed.value;
  setAsset({ path: path, kind: 'md', text: ce.ed.value, size: 1, note: 'saved', warn: false, stay: true });
  R.cmdSStays = st.edit === true && cardEds[path] === ce;
  v.dispatch({ changes: { from: 0, insert: 'x' } });
  setAsset({ path: path, kind: 'md', text: '', size: 1, note: 'Save failed', warn: true });
  R.failedSaveKeepsDraft = st.edit === true && cardEds[path] && cardEds[path].ed.value.charAt(0) === 'x';
  var btn = function (label) { return Array.prototype.filter.call(card.querySelectorAll('.cardbtn'), function (b) { return b.textContent === label; })[0]; };
  st.dirty = true; btn('ביטול').click();
  R.firstCancelHeld = st.edit === true;
  btn('ביטול').click();
  R.secondCancelDiscards = st.edit === false && !cardEds[path];
  R.textareaGone = !card.querySelector('textarea');
  card.remove(); delete cardNodes[path]; editingPath = null;
  return R;
};
