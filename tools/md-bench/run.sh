#!/bin/bash
# Usage: run.sh <file.md> <read|edit> <out.png> [width] [height]
# Builds the page from Sources/Screen.swift, injects the document, renders in WebKit.
set -e
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$HERE/../.."
F="$1"; MODE="$2"; OUT="$3"; W="${4:-1100}"; H="${5:-1400}"
WORK="$(mktemp -d)"
python3 "$HERE/extract.py" "$ROOT/Sources/Screen.swift" he > "$WORK/page.html"
python3 - "$F" "$MODE" "$WORK/page.html" <<'PY'
import json, sys, os
f, mode, page = sys.argv[1:4]
doc = open(f, encoding='utf-8', newline='').read()
inj = ('<script src="peach-editor.js"></script>' if os.environ.get('PEACH_CM', '1') == '1' else '') + '<script>window.__DOC=%s;window.__MODE=%s;window.__PATH=%s;window.__NAME=%s;</script>' % (
    json.dumps(doc), json.dumps(mode), json.dumps(f), json.dumps(os.path.basename(f)))
s = open(page, encoding='utf-8').read().replace('</head>', inj + '</head>', 1)
open(page, 'w', encoding='utf-8').write(s)
PY
# relative assets (images) resolve next to the page
cp -R "$(dirname "$F")"/. "$WORK/" 2>/dev/null || true
cp "$ROOT/Resources/peach-editor.js" "$WORK/" 2>/dev/null || true
swift "$HERE/shoot.swift" "$WORK/page.html" "$HERE/probe.js" "$OUT" "$W" "$H"
