"""Extract Peach's page (Screen.html) from Screen.swift as the WKWebView receives it.

Swift escapes are decoded, \\(Lang.t("he", "en")) becomes the Hebrew string,
\\(Lang.dir) -> rtl, \\(Lang.code) -> he. A stub for webkit.messageHandlers is
injected so the page runs in a plain browser; posted messages land in
window.__sent for the bench to inspect.
"""
import re, sys

def swift_string_arg(s, i):
    # s[i] == '"'; returns (value, index after closing quote)
    assert s[i] == '"'
    out, i = [], i + 1
    while s[i] != '"':
        if s[i] == '\\':
            n = s[i + 1]
            out.append({'n': '\n', 't': '\t', '"': '"', "'": "'", '\\': '\\'}.get(n, n)); i += 2; continue
        out.append(s[i]); i += 1
    return ''.join(out), i + 1

def decode(body, lang):
    out, i = [], 0
    while i < len(body):
        c = body[i]
        if c == '\\' and i + 1 < len(body):
            n = body[i + 1]
            if n == '(':
                depth, j = 1, i + 2
                while depth:
                    if body[j] == '"':
                        _, j = swift_string_arg(body, j); continue
                    if body[j] == '(': depth += 1
                    elif body[j] == ')': depth -= 1
                    j += 1
                expr = body[i + 2:j - 1].strip()
                if expr.startswith('Lang.t('):
                    k = expr.index('"')
                    he, k = swift_string_arg(expr, k)
                    k = expr.index('"', k)
                    en, _ = swift_string_arg(expr, k)
                    out.append(he if lang == 'he' else en)
                elif expr == 'Lang.dir': out.append('rtl' if lang == 'he' else 'ltr')
                elif expr == 'Lang.code': out.append(lang)
                else: raise SystemExit('unknown interpolation: ' + expr)
                i = j; continue
            simple = {'n': '\n', 't': '\t', 'r': '\r', '"': '"', "'": "'", '\\': '\\', '0': '\0'}
            if n in simple: out.append(simple[n]); i += 2; continue
        out.append(c); i += 1
    return ''.join(out)

src = open(sys.argv[1], encoding='utf-8').read()
lang = sys.argv[2] if len(sys.argv) > 2 else 'he'
body = src.split('static let html = """\n', 1)[1].rsplit('\n"""', 1)[0]
html = decode(body, lang)
stub = '<script>window.__sent=[];window.webkit={messageHandlers:{peach:{postMessage:function(m){window.__sent.push(m)}}}};</script>'
html = html.replace('<head>', '<head>' + stub, 1)
sys.stdout.write(html)
