# VLC EPG

[![Check](https://github.com/yaser55v/vlc-epg/actions/workflows/check.yml/badge.svg)](../../actions/workflows/check.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)

A small VLC extension that puts **EPG (TV guide) information into VLC's own playlist**.

VLC can play IPTV playlists but has no support for XMLTV program guides. This extension loads your M3U playlist and your XMLTV guide, then fills VLC's native playlist so each channel shows what is on now and what comes next, right in the **Description** column.

There is no custom window to learn. You keep using VLC's playlist, search and sorting.

```
Title            Author     Description
BBC One          UK         18:30-19:00 Evening News  ||  19:00 The One Show  ||  19:30 EastEnders
Sky News         News       18:00-19:00 Sky News Tonight  ||  19:00 Politics Hub  ||  20:00 The Late Show
```

The program that is running now is shown in bold (Unicode bold letters, see [Notes](#notes)).

---

## Is this safe?

`vlc_epg.lua` is a single plain-text Lua script. You can read every line before installing.
There is no binary, no compiled code and no telemetry.

What it does:

- Requests the M3U and XMLTV addresses you enter. If the guide field is empty it uses the guide
  address declared in your playlist header (only http and https addresses are accepted).
- Reads the local files you point it at.
- For compressed guides and some HTTPS sources it runs `curl` and `gzip` (and `cp` for local files)
  on your computer.
- Writes its settings, a guide cache and temporary download files to VLC's user data folder.
- Replaces VLC's current playlist when you press Load.

What it does not do: send your data anywhere, contact any hardcoded server, run in the
background, or start by itself.

Important: VLC does not sandbox Lua extensions. Like any program, an extension runs with your
user's permissions, so install extensions only from sources you trust or have read.

Each release includes `vlc_epg.lua.sha256` so you can verify your download.

---

## Features

- Works with local files or URLs for both the M3U playlist and the XMLTV guide
- Handles large guides: the XMLTV file is streamed and only the channels in your playlist are kept
- **Show in Description** menu: choose 2, 3 or 5 programs, or the next 2, 4, 8 or 12 hours (in hours mode at most 10 programs are listed and `...` means there are more)
- Playlist columns:
  - **Description**: running program (bold) and upcoming ones
  - **Genre**: category of the running program
  - **Album**: synopsis of the running program
  - **Author**: channel group
  - *(Genre and Album stay empty when the guide has no category or synopsis)*
- Shows an on-screen message with the category and a short synopsis when you switch channel
- Matching: by `tvg-id` (cleaned, so `ATV.tr@SD` equals `ATV.HD.tr`), then by channel name with quality words and tags ignored; ambiguous matches are skipped; the status line reports how many channels matched by id and by name
- Understands compressed guides (`.xml.gz`) on macOS and Linux
- Caches the parsed guide locally and refreshes it every 6 hours
- Single Lua file, with optional one-line installer scripts

## Installation

### Quick install

**macOS and Linux** (Terminal):

```sh
curl -fsSL https://github.com/yaser55v/vlc-epg/releases/latest/download/install.sh | sh
```

**Windows** (PowerShell):

```powershell
irm https://github.com/yaser55v/vlc-epg/releases/latest/download/install.ps1 | iex
```

Then **quit VLC completely** (Cmd+Q on macOS) and open it again. Start the extension from
**VLC > Extensions > VLC EPG** (macOS) or **View > VLC EPG** (Windows and Linux).

The installer downloads the latest release, checks that it is a VLC extension, and copies it
to your user folder for VLC. It does not need administrator rights. Updating is the same
command. If you prefer to read it first, the scripts are `install.sh` and `install.ps1` in
this repository.

### Manual install

1. Download `vlc_epg.lua` from the [latest release](../../releases/latest).
2. Copy it into VLC's extensions folder (create the folders if they do not exist):

   | System  | Folder |
   | ------- | ------ |
   | macOS   | `~/Library/Application Support/org.videolan.vlc/lua/extensions/` |
   | Windows | `%APPDATA%\\vlc\\lua\\extensions\\` |
   | Linux   | `~/.local/share/vlc/lua/extensions/` |

   Do **not** use the folder inside `VLC.app`: VLC does not load user extensions from there
   and updates wipe it.
3. Quit VLC completely and open it again.

### Uninstall

macOS and Linux:

```sh
curl -fsSL https://github.com/yaser55v/vlc-epg/releases/latest/download/install.sh | sh -s -- --uninstall
```

Add `--purge` to also delete your saved addresses and the guide cache.

Windows: download `install.ps1`, then run `.\install.ps1 -Uninstall` (add `-Purge` for the same).

### Notes

- Tested on macOS (VLC 3.0.x, Apple Silicon). The Windows installer, and the Flatpak and Snap
  folders on Linux, have not been tested yet. If one does not work, use the manual install and
  open an issue with your system and the installer's output.
- You can point the installer at another folder with the `VLC_EPG_DIR` environment variable.

## Usage

1. Enter the **M3U** address (file path or URL).
2. Enter the **XMLTV guide** address (file path or URL). Leave it empty to use the address declared in the playlist header, if there is one (only http and https addresses are accepted).
3. Select what to show in the Description column (**2, 3 or 5 programs**, or the next **2, 4, 8 or 12 hours**).
4. Press **Load into playlist**.
5. In VLC's playlist, right-click the column header and enable **Description**, **Genre**, **Album**, and **Author**.
6. Drag the edges of the columns to make them as wide as you like. VLC remembers the widths.

The settings are saved, so next time you only press **Load into playlist**.

**Re-download guide** ignores the cache and fetches the guide again.

### Try it with the sample files

The `examples` folder has a small playlist and a generator for a matching guide:

```
python3 examples/make_test_epg.py
```

Then load `examples/test.m3u` and `examples/test_epg.xml` as described above.

## Status messages

The line at the top of the window tells you what happened.

| Message | Meaning |
| ------- | ------- |
| `225 channels added to the playlist. guide: 8326 programs, 224 of 225 channels matched (200 by id, 24 by name)` | Everything worked. |
| `guide: no programs found for your channels` | The guide loaded but none of its channel IDs match your playlist. Check the `tvg-id` values. |
| `guide failed: ...` | The guide could not be downloaded or read. The text after the colon says why. |
| `The playlist source returned no data` | Wrong path or URL, or the server returned nothing. |
| `No channels found. Read N lines, first line: "..."` | The source was read but is not an M3U playlist. The first line shows what it actually contains. |

## Notes

- **The Description is a snapshot.** VLC does not allow changing an item's metadata after it is added, so the guide text reflects the moment you pressed Load. The times stay correct, but the "current" program becomes outdated after it ends. Press **Load into playlist** again to refresh. This clears the playlist and rebuilds it (the cached guide makes this quick).
- **Loading replaces your current VLC playlist.**
- **Bold text** is done with Unicode bold characters because VLC columns are plain text. It only affects the English letters and digits of the running program, and searching for that text may not match. To turn it off, set `BOLD_CURRENT = false` at the top of the script.
- **Channel matching:** Use a guide from the same country as your channels. Name matching can be wrong if you mix countries.
- **Installers status:** Tested on macOS only. The Windows installer (`install.ps1`), and the Flatpak and Snap folders on Linux, are untested.
- Row height and column width are controlled by VLC, not by extensions.
- Compressed guides and some HTTPS sources are fetched with `curl` and `gzip`. These ship with macOS and most Linux systems. On Windows, `.gz` guides may not work, so use an uncompressed XMLTV URL.
- The cache and settings are stored in VLC's user data folder as `vlc_epg.cfg` and `vlc_epg_cache.txt`. Delete them to reset. They may contain your private playlist or guide URLs, so do not publish them.

## Compatibility

Developed and tested on **VLC 3.0.x for macOS (Apple Silicon)**. Windows and Linux have not been tested yet, and VLC 4 has not been tested. Reports are welcome, see below.

## Contributing

Bug reports and pull requests are welcome. When you open an issue, please include:

- your VLC version and operating system
- the status line shown at the top of the extension window
- the first lines of your M3U and of your XMLTV guide, with private URLs removed

Before sending a pull request, run the test suite:

```bash
luac5.1 -p vlc_epg.lua
lua5.1 tests/scan_phase.lua vlc_epg.lua
shellcheck -s sh install.sh tests/test_install.sh
sh tests/test_install.sh vlc_epg.lua
```

## Releasing (maintainers)

1. Update `version` in the script's `descriptor()` and add a section to `CHANGELOG.md`.
2. Commit, then tag and push:
   ```bash
   git tag v2.2.0
   git push origin v2.2.0
   ```

The release workflow validates the script syntax and scan-phase, lints and tests the installer, verifies that the tag matches the script version, generates `vlc_epg.lua.sha256`, packages the zip archive, and publishes all release assets on GitHub.

## License

[MIT](LICENSE)
