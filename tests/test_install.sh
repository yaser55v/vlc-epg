#!/bin/sh
# Tests install.sh with a temporary HOME. Usage: sh tests/test_install.sh vlc_epg.lua
set -eu

SRC="$(cd "$(dirname "$1")" && pwd)/$(basename "$1")"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
pass() { printf 'ok: %s\n' "$*"; }

export HOME="$WORK/home"
mkdir -p "$HOME"
export VLC_EPG_URL="file://$SRC"
unset VLC_EPG_DIR XDG_DATA_HOME || true

# macOS target
VLC_EPG_OS=Darwin sh "$ROOT/install.sh" >/dev/null
MAC="$HOME/Library/Application Support/org.videolan.vlc/lua/extensions/vlc_epg.lua"
[ -f "$MAC" ] || fail "macOS install path"
cmp -s "$SRC" "$MAC" || fail "macOS file content differs"
pass "macOS install"

# update (second run overwrites)
VLC_EPG_OS=Darwin sh "$ROOT/install.sh" >/dev/null || fail "second run"
pass "re-run is idempotent"

# settings and cache are removed only with --purge
BASE="$HOME/Library/Application Support/org.videolan.vlc"
touch "$BASE/vlc_epg.cfg" "$BASE/vlc_epg_cache.txt"
VLC_EPG_OS=Darwin sh "$ROOT/install.sh" --uninstall >/dev/null
[ ! -f "$MAC" ] || fail "uninstall left the extension"
[ -f "$BASE/vlc_epg.cfg" ] || fail "uninstall without --purge removed settings"
pass "uninstall keeps settings"
VLC_EPG_OS=Darwin sh "$ROOT/install.sh" >/dev/null
VLC_EPG_OS=Darwin sh "$ROOT/install.sh" --uninstall --purge >/dev/null
if [ -f "$BASE/vlc_epg.cfg" ] || [ -f "$BASE/vlc_epg_cache.txt" ]; then fail "purge left files"; fi
pass "purge removes settings and cache"

# Linux default (no vlc binary needed when no flatpak/snap folders exist)
VLC_EPG_OS=Linux sh "$ROOT/install.sh" >/dev/null
[ -f "$HOME/.local/share/vlc/lua/extensions/vlc_epg.lua" ] || fail "Linux default path"
pass "Linux default path"

# Flatpak folder is used when present
mkdir -p "$HOME/.var/app/org.videolan.VLC"
VLC_EPG_OS=Linux sh "$ROOT/install.sh" >/dev/null
[ -f "$HOME/.var/app/org.videolan.VLC/data/vlc/lua/extensions/vlc_epg.lua" ] || fail "Flatpak path"
pass "Flatpak path"

# custom directory override with spaces in the name
VLC_EPG_DIR="$WORK/my folder/ext" sh "$ROOT/install.sh" >/dev/null
[ -f "$WORK/my folder/ext/vlc_epg.lua" ] || fail "VLC_EPG_DIR override"
pass "custom folder with spaces"

# refuses a file that is not an extension
printf '<html>404 Not Found</html>\n' > "$WORK/bad.html"
if VLC_EPG_URL="file://$WORK/bad.html" VLC_EPG_DIR="$WORK/x" sh "$ROOT/install.sh" >/dev/null 2>&1; then
  fail "installed an HTML page"
fi
[ ! -f "$WORK/x/vlc_epg.lua" ] || fail "HTML page was written"
pass "rejects non-extension download"

# refuses an unreachable address
if VLC_EPG_URL="file://$WORK/missing.lua" VLC_EPG_DIR="$WORK/y" sh "$ROOT/install.sh" >/dev/null 2>&1; then
  fail "installed from a missing file"
fi
pass "fails on download error"

# unknown option
if sh "$ROOT/install.sh" --nope >/dev/null 2>&1; then fail "accepted unknown option"; fi
pass "rejects unknown option"

echo "All installer tests passed."
