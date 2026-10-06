# Security Policy

## Is This Safe to Install?

**Yes.** Here is exactly what this project is and what it does.

`vlc_epg.lua` is a **single plain-text Lua script** (~1 000 lines). There is no
installer, no binary, no compiled code, and no dependency to download. You can
open the file in any text editor and read every line before you copy it anywhere.

### What the script does

| Action | Detail |
| ------ | ------ |
| Reads the M3U and XMLTV URLs **you provide** | No URL is hardcoded. The script only contacts addresses you type in yourself. |
| Makes HTTP requests to those two addresses | To download your playlist and TV guide. Nothing else. |
| Writes two files to VLC's user-data folder | `vlc_epg.cfg` (your settings) and `vlc_epg_cache.txt` (parsed guide cache). |
| Runs entirely inside VLC's Lua sandbox | VLC's sandbox limits what a Lua extension can do. It cannot launch processes, read arbitrary files, or access the OS outside what VLC exposes. |

### What the script does NOT do

- ❌ No telemetry, analytics, or tracking of any kind
- ❌ No network requests to any server you did not configure
- ❌ No access to your files outside VLC's data folder
- ❌ No background processes, no auto-start, no system-level changes
- ❌ No binaries, no compiled code, no native extensions

### Where your data is stored

The two files written by the script live in VLC's own data folder:

| System  | Path |
| ------- | ---- |
| macOS   | `~/Library/Application Support/org.videolan.vlc/` |
| Windows | `%APPDATA%\vlc\` |
| Linux   | `~/.local/share/vlc/` |

These files may contain your M3U or XMLTV URLs. Do not share them publicly.
To remove all traces of the extension, delete `vlc_epg.cfg` and `vlc_epg_cache.txt`
from that folder, then delete `vlc_epg.lua` from the extensions subfolder.

### Verifying the download

Every [release](../../releases/latest) includes a `vlc_epg.lua.sha256` checksum file.
After downloading, you can verify the file has not been modified:

\`\`\`bash
# macOS / Linux
shasum -a 256 -c vlc_epg.lua.sha256

# Windows (PowerShell)
Get-FileHash vlc_epg.lua -Algorithm SHA256
\`\`\`

The hash should match the one published on the release page.

---

## Reporting a Security Issue

If you find something that looks like a security problem, please open a
[GitHub Issue](../../issues) and describe what you found.

This project is a small personal tool. There is no bug-bounty programme and
no SLA, but every report will be read and taken seriously.
