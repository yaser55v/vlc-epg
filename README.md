# VLC EPG

[![Check](https://github.com/yassermahmoud/vlc-epg/actions/workflows/check.yml/badge.svg)](../../actions/workflows/check.yml)
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

## 🔒 Is This Safe?

`vlc_epg.lua` is a **single plain-text Lua script**. You can open it in any text editor and read every line before installing. There is no installer, no binary, and no compiled code.

**What it does:**
- Makes HTTP requests **only** to the M3U and XMLTV URLs that **you** type in
- Writes two files to VLC's own data folder (settings + guide cache)
- Runs inside **VLC's Lua sandbox** — the sandbox prevents it from touching the rest of your system

**What it does NOT do:**
- ❌ No telemetry or tracking
- ❌ No requests to any hardcoded server
- ❌ No access to your files outside VLC's data folder
- ❌ No background processes, no auto-start, no system changes

Every release includes a `vlc_epg.lua.sha256` file so you can verify your download has not been tampered with. See [SECURITY.md](SECURITY.md) for full details.

---

## Features

- Works with local files or URLs for both the M3U playlist and the XMLTV guide
- Handles large guides: the XMLTV file is streamed and only the channels in your playlist are kept
- Matches channels by `tvg-id`, with a fallback on channel name
- Understands compressed guides (`.xml.gz`) on macOS and Linux
- Caches the parsed guide locally and refreshes it every 6 hours
- Channel group goes into the **Author** column, so you can sort the playlist by group
- Shows an on-screen message with the current and next program when you switch channel
- Single Lua file, nothing else to install

## Installation

1. Download `vlc_epg.lua` from the [latest release](../../releases/latest).
2. Copy it into VLC's extensions folder (create the folder if it does not exist):

   | System  | Folder |
   | ------- | ------ |
   | macOS   | `~/Library/Application Support/org.videolan.vlc/lua/extensions/` |
   | Windows | `%APPDATA%\vlc\lua\extensions\` |
   | Linux   | `~/.local/share/vlc/lua/extensions/` |

3. Restart VLC.
4. Open it from **VLC > Extensions > VLC EPG** (macOS) or **View > VLC EPG** (Windows and Linux).

## Usage

1. Enter the **M3U** address (file path or URL).
2. Enter the **XMLTV guide** address (file path or URL). Leave it empty to use the address declared in the playlist header, if there is one.
3. Press **Load into playlist**.
4. In VLC's playlist, right-click the column header and enable **Description** (and **Author** if you want the group).
5. Drag the edge of the Description column to make it as wide as you like. VLC remembers the width.

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
| `225 channels added to the playlist. guide: 8326 programs, 224 of 225 channels matched` | Everything worked. |
| `guide: no programs found for your channels` | The guide loaded but none of its channel IDs match your playlist. Check the `tvg-id` values. |
| `guide failed: ...` | The guide could not be downloaded or read. The text after the colon says why. |
| `The playlist source returned no data` | Wrong path or URL, or the server returned nothing. |
| `No channels found. Read N lines, first line: "..."` | The source was read but is not an M3U playlist. The first line shows what it actually contains. |

## Notes

- **The Description is a snapshot.** VLC does not allow changing an item's metadata after it is added, so the guide text reflects the moment you pressed Load. The times stay correct, but the "current" program becomes outdated after it ends. Press **Load into playlist** again to refresh. This clears the playlist and rebuilds it (the cached guide makes this quick).
- **Loading replaces your current VLC playlist.**
- **Bold text** is done with Unicode bold characters because VLC columns are plain text. It only affects the English letters and digits of the running program, and searching for that text may not match. To turn it off, set `BOLD_CURRENT = false` at the top of the script.
- The number of programs per channel can be changed with `UPCOMING` at the top of the script.
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

Before sending a pull request, check the script compiles:

```
luac5.1 -p vlc_epg.lua
```

## Releasing (maintainers)

1. Update `version` in the script's `descriptor()` and add a section to `CHANGELOG.md`.
2. Generate and attach a checksum:
   ```bash
   shasum -a 256 vlc_epg.lua > vlc_epg.lua.sha256
   ```
3. Commit, then tag and push:
   ```
   git tag v2.2.0
   git push origin v2.2.0
   ```

The release workflow checks that the tag matches the script version and publishes `vlc_epg.lua`, `vlc_epg.lua.sha256`, and a zip on the Releases page.

## License

[MIT](LICENSE)
