#!/bin/sh
# VLC EPG installer for macOS and Linux.
#
# Install or update:   sh install.sh
# Remove:              sh install.sh --uninstall
# Remove everything:   sh install.sh --uninstall --purge   (also settings and cache)
#
# Environment variables:
#   VLC_EPG_DIR  install into this folder instead of the detected one
#   VLC_EPG_URL  download from this address instead of the latest release

set -eu

REPO="yaser55v/vlc-epg"
NAME="vlc_epg.lua"
URL="${VLC_EPG_URL:-https://github.com/$REPO/releases/latest/download/$NAME}"
OS="${VLC_EPG_OS:-$(uname -s)}"

say() { printf '%s\n' "$*"; }
die() { printf 'Error: %s\n' "$*" >&2; exit 1; }

usage() {
  cat <<'USAGE'
Usage: install.sh [--uninstall] [--purge]

  (no options)  install or update the VLC EPG extension
  --uninstall   remove the extension
  --purge       with --uninstall, also remove settings and the guide cache
USAGE
}

mode="install"
purge=0
for arg in "$@"; do
  case "$arg" in
    --uninstall) mode="uninstall" ;;
    --purge) purge=1 ;;
    -h|--help) usage; exit 0 ;;
    *) usage >&2; die "unknown option: $arg" ;;
  esac
done

targets=""
add_target() {
  if [ -z "$targets" ]; then targets="$1"; else targets="$targets
$1"; fi
}

find_targets() {
  if [ -n "${VLC_EPG_DIR:-}" ]; then
    add_target "$VLC_EPG_DIR"
    return
  fi
  case "$OS" in
    Darwin)
      add_target "$HOME/Library/Application Support/org.videolan.vlc/lua/extensions"
      ;;
    Linux)
      found=0
      if [ -d "$HOME/.var/app/org.videolan.VLC" ]; then
        add_target "$HOME/.var/app/org.videolan.VLC/data/vlc/lua/extensions"
        found=1
      fi
      if [ -d "$HOME/snap/vlc" ]; then
        add_target "$HOME/snap/vlc/current/.local/share/vlc/lua/extensions"
        found=1
      fi
      if [ "$found" -eq 0 ] || command -v vlc >/dev/null 2>&1; then
        add_target "${XDG_DATA_HOME:-$HOME/.local/share}/vlc/lua/extensions"
      fi
      ;;
    *)
      die "unsupported system '$OS'. Set VLC_EPG_DIR to your VLC extensions folder."
      ;;
  esac
}

TMP_FILE=""
cleanup() {
  if [ -n "$TMP_FILE" ] && [ -f "$TMP_FILE" ]; then rm -f "$TMP_FILE"; fi
}
trap cleanup EXIT

download() {
  TMP_FILE="$(mktemp)"
  if command -v curl >/dev/null 2>&1; then
    curl -fsSL --retry 2 -o "$TMP_FILE" "$URL" || die "download failed: $URL"
  elif command -v wget >/dev/null 2>&1; then
    wget -q -O "$TMP_FILE" "$URL" || die "download failed: $URL"
  else
    die "curl or wget is required"
  fi
  [ -s "$TMP_FILE" ] || die "the downloaded file is empty"
  grep -q "function descriptor" "$TMP_FILE" || die "the downloaded file is not a VLC extension"
}

find_targets
OLD_IFS="$IFS"
NL='
'

if [ "$mode" = "install" ]; then
  download
  version="$(grep -o 'version = "[0-9.]*"' "$TMP_FILE" | head -n 1 | grep -o '[0-9][0-9.]*' || true)"
  IFS="$NL"
  for dir in $targets; do
    IFS="$OLD_IFS"
    mkdir -p "$dir" || die "cannot create $dir"
    cp "$TMP_FILE" "$dir/$NAME" || die "cannot write to $dir"
    chmod 644 "$dir/$NAME"
    say "Installed VLC EPG ${version:-} to: $dir/$NAME"
    IFS="$NL"
  done
  IFS="$OLD_IFS"
  say ""
  say "Next: quit VLC completely (Cmd+Q on macOS) and open it again."
  case "$OS" in
    Darwin) say "Then open it from the menu: VLC > Extensions > VLC EPG" ;;
    *) say "Then open it from the menu: View > VLC EPG" ;;
  esac
else
  IFS="$NL"
  for dir in $targets; do
    IFS="$OLD_IFS"
    if [ -f "$dir/$NAME" ]; then
      rm -f "$dir/$NAME"
      say "Removed: $dir/$NAME"
    else
      say "Not installed in: $dir"
    fi
    if [ "$purge" -eq 1 ]; then
      base="$(dirname "$(dirname "$dir")")"
      for f in vlc_epg.cfg vlc_epg_cache.txt vlc_epg_download.tmp vlc_epg_download.xml; do
        if [ -f "$base/$f" ]; then
          rm -f "$base/$f"
          say "Removed: $base/$f"
        fi
      done
    fi
    IFS="$NL"
  done
  IFS="$OLD_IFS"
fi
