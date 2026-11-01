#!/bin/zsh
# Builds Peach.app from source and installs it in ~/Applications.
# Usage: ./build.sh [install-dir]    PEACH_NO_INSTALL=1 ./build.sh   (build only)
set -e

HERE="$(cd "$(dirname "$0")" && pwd)"
APP_NAME="Peach"
APP_NAME_HE="פיץ׳"
BUNDLE_ID="org.hameretz2.peach"
BUILD="$HERE/build"
APP="$BUILD/$APP_NAME.app"
# The per-user Applications folder by default.
DEST="${1:-$HOME/Applications}"

# --- Syntax gate for the page script ---
# The UI page lives in a Swift string, so a JS syntax error does not stop the
# compiler; it shows up as a blank window at run time. This checks the script
# after Swift's escapes are decoded, exactly as the page receives it.
if command -v node >/dev/null 2>&1; then
    python3 - "$HERE/Sources/Screen.swift" <<'PYEOF' > /tmp/peach-page-check.js
import re, sys
src = open(sys.argv[1], encoding='utf-8').read()
m = re.search(r'<script>(.*?)</script>', src, re.S)
js = m.group(1) if m else ""
out, i = [], 0
while i < len(js):
    c = js[i]
    if c == '\\' and i + 1 < len(js):
        n = js[i + 1]
        simple = {'n': '\n', 't': '\t', 'r': '\r', '"': '"', "'": "'", '\\': '\\', '0': '\0'}
        if n in simple:
            out.append(simple[n]); i += 2; continue
        if n == '(':                      # Swift interpolation: skip it, balancing parentheses
            depth, j = 1, i + 2
            while j < len(js) and depth:
                if js[j] == '(': depth += 1
                elif js[j] == ')': depth -= 1
                j += 1
            out.append('0'); i = j; continue
    out.append(c); i += 1
sys.stdout.write(''.join(out))
PYEOF
    if [[ ! -s /tmp/peach-page-check.js ]]; then
        echo "x no page script found in Screen.swift: build stopped"
        exit 1
    fi
    if ! node --check /tmp/peach-page-check.js 2>/tmp/peach-page-err; then
        echo "x the page script has a syntax error: build stopped:"
        head -4 /tmp/peach-page-err
        exit 1
    fi
    echo "✓ page script passed the syntax check"
fi

rm -rf "$BUILD"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

echo "→ compiling…"
# Universal binary: an arm64-only build does not launch on an Intel MacBook.
# Both slices compile in parallel; PEACH_ARCH=arm64 skips the second one.
ARCHS=(${=PEACH_ARCH:-arm64 x86_64})
for arch in $ARCHS; do
    swiftc -O -whole-module-optimization \
        -target $arch-apple-macos12.0 \
        -framework AppKit -framework WebKit -framework Carbon -framework UserNotifications \
        -o "$BUILD/Peach-$arch" \
        "$HERE"/Sources/*.swift &
done
wait
for arch in $ARCHS; do [[ -f "$BUILD/Peach-$arch" ]] || { echo "✗ build failed: $arch"; exit 1; }; done
lipo -create "$BUILD"/Peach-* -output "$APP/Contents/MacOS/Peach"
rm -f "$BUILD"/Peach-*

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>$APP_NAME</string>
    <key>CFBundleDisplayName</key><string>$APP_NAME</string>
    <key>CFBundleDevelopmentRegion</key><string>en</string>
    <key>CFBundleLocalizations</key><array><string>en</string><string>he</string></array>
    <key>CFBundleExecutable</key><string>Peach</string>
    <key>CFBundleDocumentTypes</key>
    <array>
        <dict>
            <key>CFBundleTypeName</key><string>Markdown</string>
            <key>CFBundleTypeRole</key><string>Editor</string>
            <key>LSHandlerRank</key><string>Default</string>
            <key>LSItemContentTypes</key>
            <array><string>net.daringfireball.markdown</string><string>public.markdown</string></array>
            <key>CFBundleTypeExtensions</key><array><string>md</string><string>markdown</string></array>
        </dict>
        <dict>
            <key>CFBundleTypeName</key><string>Plain text</string>
            <key>CFBundleTypeRole</key><string>Editor</string>
            <key>LSHandlerRank</key><string>Alternate</string>
            <key>LSItemContentTypes</key><array><string>public.plain-text</string></array>
        </dict>
    </array>
    <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>0.36.2</string>
    <key>CFBundleVersion</key><string>28</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>LSMinimumSystemVersion</key><string>12.0</string>
    <key>NSAppleEventsUsageDescription</key>
    <string>פיץ׳ מזהה את חלונות־המסוף ומקפיץ אותם לחזית לפי בקשתך.</string>
    <key>NSHumanReadableCopyright</key><string>פיץ׳ — מסך־המצב של המסופים</string>
    <key>NSSupportsAutomaticTermination</key><false/>
    <key>NSSupportsSuddenTermination</key><false/>
</dict>
</plist>
PLIST

# Hebrew display name. The file must be UTF-16: Finder silently ignores it
# in any other encoding.
mkdir -p "$APP/Contents/Resources/he.lproj" "$APP/Contents/Resources/en.lproj"
printf 'CFBundleDisplayName = "%s";\nCFBundleName = "%s";\n' "$APP_NAME_HE" "$APP_NAME_HE" \
    | iconv -f UTF-8 -t UTF-16 > "$APP/Contents/Resources/he.lproj/InfoPlist.strings"
printf 'CFBundleDisplayName = "%s";\nCFBundleName = "%s";\n' "$APP_NAME" "$APP_NAME" \
    | iconv -f UTF-8 -t UTF-16 > "$APP/Contents/Resources/en.lproj/InfoPlist.strings"

if [[ -f "$HERE/AppIcon.icns" ]]; then
    cp "$HERE/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
fi

# The Markdown editor bundle (tools/editor-bundle, built and committed).
# Missing = a silent fallback to the slow textarea, so it fails the build.
if [[ ! -f "$HERE/Resources/peach-editor.js" ]]; then
    echo "⛔ Resources/peach-editor.js missing — cd tools/editor-bundle && npm ci && npm run build"
    exit 1
fi
cp "$HERE/Resources/peach-editor.js" "$APP/Contents/Resources/peach-editor.js"

# Signing. With a "Developer ID Application" identity in the keychain, Peach
# is signed with it and the hardened runtime. Without one it falls back to an
# ad-hoc signature, which is fine for building from source.
#
# Why a real identity matters for daily use: macOS records the permission to
# control Terminal by signing team for a signed app, and by code hash for an
# ad-hoc one. The hash changes on every build, so an ad-hoc Peach is asked for
# that permission again after each rebuild, and until it is granted Peach
# cannot read the terminal screen and detects questions late.
#
# PEACH_KEYCHAIN / PEACH_KEYCHAIN_PASS_FILE (optional): unlock a dedicated
# signing keychain first.
if [[ -n "$PEACH_KEYCHAIN" && -n "$PEACH_KEYCHAIN_PASS_FILE" ]]; then
    security unlock-keychain -p "$(cat "$PEACH_KEYCHAIN_PASS_FILE" 2>/dev/null)" \
        "$PEACH_KEYCHAIN" 2>/dev/null || true
fi
# PEACH_ADHOC=1 skips the identity lookup and signs ad-hoc.
IDENTITY="${PEACH_SIGN_IDENTITY:-$([[ -n "$PEACH_ADHOC" ]] || security find-identity -v -p codesigning 2>/dev/null \
    | grep -o '"Developer ID Application: [^"]*"' | head -1 | tr -d '"')}"
if [[ -n "$IDENTITY" ]] && ! codesign --force --options runtime --timestamp \
        --entitlements "$HERE/Peach.entitlements" \
        --sign "$IDENTITY" "$APP"; then
    echo "! signing with \"$IDENTITY\" failed (locked keychain?)"
    IDENTITY=""
fi
if [[ -z "$IDENTITY" ]]; then
    echo "! no usable Developer ID identity: signing ad-hoc"
    echo "  (macOS will ask again for Terminal access after each rebuild)"
    IDENTITY="ad-hoc"
    find "$APP" -name '*.cstemp' -delete 2>/dev/null || true
    codesign --force --entitlements "$HERE/Peach.entitlements" --sign - "$APP"
fi
# "The command ran" is not "the app is signed": a locked keychain fails quietly.
codesign --verify "$APP" >/dev/null 2>&1 || {
    echo "x signature did not verify (locked keychain?)"
    exit 1
}
echo "✓ signed: $IDENTITY"

# PEACH_NO_INSTALL=1: stop at a signed build/Peach.app — no install, no quit,
# no relaunch, no login-agent rewrite. For preparing a build while the
# running Peach stays in use.
if [[ -n "$PEACH_NO_INSTALL" ]]; then
    echo "✓ built (not installed): $APP"
    exit 0
fi

mkdir -p "$DEST"
# Older builds were installed under the Hebrew name. Remove that copy so the
# Dock does not keep launching a stale one.
if [[ -d "$DEST/$APP_NAME_HE.app" ]]; then
    pkill -f "^$DEST/$APP_NAME_HE.app/Contents/MacOS/Peach" 2>/dev/null || true
    sleep 1
    rm -rf "$DEST/$APP_NAME_HE.app"
    echo "✓ removed the old install under the Hebrew name"
fi
# ⛔ Reported 3.10: a release run closed Peach to replace it and never
#    reopened it — the user saw the app "close and vanish". If Peach was running
#    before the install, it is opened again after.
WAS_RUNNING=0
pgrep -f "^$DEST/$APP_NAME.app/Contents/MacOS/Peach" >/dev/null 2>&1 && WAS_RUNNING=1
if [[ -d "$DEST/$APP_NAME.app" ]]; then
    # Anchored to the line start, so /Applications does not also match ~/Applications.
    pkill -f "^$DEST/$APP_NAME.app/Contents/MacOS/Peach" 2>/dev/null || true
    sleep 1
    rm -rf "$DEST/$APP_NAME.app"
fi
cp -R "$APP" "$DEST/"
xattr -dr com.apple.quarantine "$DEST/$APP_NAME.app" 2>/dev/null || true
# peach-q: a command-line client for Peach's control socket (see tools/peach-q).
mkdir -p "$HOME/.local/bin"
install -m 755 "$HERE/tools/peach-q" "$HOME/.local/bin/peach-q" && echo "✓ peach-q → ~/.local/bin/peach-q"

# The launch-at-login agent stores a full path; keep it pointing at this install.
AGENT="$HOME/Library/LaunchAgents/org.hameretz2.peach.login.plist"
if [[ -f "$AGENT" ]] && ! grep -q "$DEST/$APP_NAME.app/" "$AGENT"; then
    launchctl unload -w "$AGENT" 2>/dev/null || true
    /usr/bin/sed -i '' "s|<string>.*/Contents/MacOS/Peach</string>|<string>$DEST/$APP_NAME.app/Contents/MacOS/Peach</string>|" "$AGENT"
    launchctl load -w "$AGENT" 2>/dev/null || true
    echo "✓ launch-at-login now points at the new path"
fi

echo "✓ installed: $DEST/$APP_NAME.app"
if [[ $WAS_RUNNING == 1 ]]; then
    open "$DEST/$APP_NAME.app" && echo "✓ Peach reopened"
fi
