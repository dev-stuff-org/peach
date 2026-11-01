// Peach's Markdown editor: CodeMirror 6, bundled offline into
// Resources/peach-editor.js and injected into the page by AppDelegate.
//
// Why not the <textarea> it replaces: WebKit lays out a textarea's whole text
// on every keystroke. On a 2,677-line Hebrew file that cost ~300 ms per key
// (measured 30.10 with tools/md-bench). CodeMirror lays out only the lines on
// screen, resolves direction per line, and keeps its own undo history.
import { EditorState, EditorSelection } from '@codemirror/state';
import { EditorView, keymap, drawSelection, highlightActiveLine, ViewPlugin, Decoration } from '@codemirror/view';
import { RangeSetBuilder } from '@codemirror/state';
import { history, defaultKeymap, historyKeymap, indentMore, indentLess } from '@codemirror/commands';
import { markdown, markdownKeymap } from '@codemirror/lang-markdown';
import { syntaxHighlighting, HighlightStyle } from '@codemirror/language';
import { tags as t } from '@lezer/highlight';

const peachHighlight = HighlightStyle.define([
  { tag: t.heading, fontWeight: '700', color: '#f2f4ef' },
  { tag: t.strong, fontWeight: '700', color: '#f2f4ef' },
  { tag: t.emphasis, color: 'var(--peach)' },
  { tag: t.strikethrough, textDecoration: 'line-through', color: 'var(--faint)' },
  { tag: [t.link, t.url], color: 'var(--run)' },
  { tag: t.monospace, color: '#cfe8d8' },
  { tag: [t.processingInstruction, t.meta], color: 'var(--faint)' },
  { tag: t.quote, color: 'var(--dim)' },
  { tag: t.list, color: 'var(--peach)' },
]);

const peachTheme = EditorView.theme({
  '&': { height: '100%', background: 'var(--ground)', color: 'var(--text)', fontSize: '13px' },
  '&.cm-focused': { outline: 'none' },
  '.cm-scroller': { fontFamily: "'Cascadia Mono', Menlo, 'Courier New', monospace", lineHeight: '1.6' },
  '.cm-content': { padding: '16px 0', caretColor: 'var(--peach)' },
  '.cm-line': { padding: '0 18px' },
  '.cm-cursor': { borderLeftColor: 'var(--peach)', borderLeftWidth: '2px' },
  '.cm-activeLine': { background: 'rgba(255,255,255,0.025)' },
  '&.cm-focused .cm-selectionBackground, .cm-selectionBackground, ::selection': { background: 'rgba(242,163,101,0.28)' },
}, { dark: true });

// The first letter with a direction decides a line's direction, as in the
// reader (blockDirs in Screen.swift): Hebrew, Arabic and RLM are RTL; Latin,
// Greek, Cyrillic and LRM are LTR. A line with none follows the page.
function firstStrongDir(text) {
  for (let q = 0; q < text.length; q++) {
    const c = text.charCodeAt(q);
    if (c === 0x200F || (c >= 0x590 && c <= 0x8FF) || (c >= 0xFB1D && c <= 0xFDFF) || (c >= 0xFE70 && c <= 0xFEFE)) return 'rtl';
    if (c === 0x200E || (c >= 65 && c <= 90) || (c >= 97 && c <= 122) || (c >= 0xC0 && c <= 0x24F) || (c >= 0x370 && c <= 0x52F)) return 'ltr';
  }
  return '';
}

// perLineTextDirection makes CodeMirror read each line's direction from the
// DOM for caret motion; this plugin is what puts the direction there. Only
// visible lines are decorated, so a long file costs nothing extra.
const lineDirs = ViewPlugin.fromClass(class {
  constructor(view) { this.decorations = this.build(view); }
  update(u) { if (u.docChanged || u.viewportChanged) { this.decorations = this.build(u.view); } }
  build(view) {
    const b = new RangeSetBuilder();
    for (const { from, to } of view.visibleRanges) {
      for (let pos = from; pos <= to;) {
        const line = view.state.doc.lineAt(pos);
        const dir = firstStrongDir(line.text);
        if (dir) b.add(line.from, line.from, Decoration.line({ attributes: { dir } }));
        pos = line.to + 1;
      }
    }
    return b.finish();
  }
}, { decorations: (v) => v.decorations });

// ⌘B / ⌘I wrap the selection; with no selection the caret lands inside.
function wrapWith(mark) {
  return (view) => {
    view.dispatch(view.state.changeByRange((range) => ({
      changes: [{ from: range.from, insert: mark }, { from: range.to, insert: mark }],
      range: EditorSelection.range(range.from + mark.length, range.to + mark.length),
    })));
    return true;
  };
}

window.PeachEditor = {
  // opts.markdown (default true): Markdown highlighting and list keys.
  // Saving is not bound here: the page's own ⌘S handler does it, once.
  create(parent, text, onChange, opts = {}) {
    const md = opts.markdown !== false;
    const view = new EditorView({
      parent,
      state: EditorState.create({
        doc: text,
        extensions: [
          history(),
          drawSelection(),
          highlightActiveLine(),
          EditorView.lineWrapping,
          // Each line takes its direction from its own first strong letter.
          EditorView.perLineTextDirection.of(true),
          lineDirs,
          ...(md ? [markdown(), syntaxHighlighting(peachHighlight)] : []),
          peachTheme,
          keymap.of([
            { key: 'Mod-b', run: wrapWith('**') },
            { key: 'Mod-i', run: wrapWith('*') },
            { key: 'Tab', run: indentMore, shift: indentLess },
            ...(md ? markdownKeymap : []),
            ...historyKeymap,
            ...defaultKeymap,
          ]),
          EditorView.updateListener.of((u) => { if (u.docChanged) { onChange(); } }),
          EditorView.contentAttributes.of({ spellcheck: 'false', autocorrect: 'off', autocapitalize: 'off' }),
        ],
      }),
    });
    return {
      view,
      get value() { return view.state.doc.toString(); },
      focus() { view.focus(); },
      destroy() { view.destroy(); },
    };
  },
};
