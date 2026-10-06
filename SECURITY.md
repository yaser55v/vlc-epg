# Security Policy

## Is This Safe to Install?

`vlc_epg.lua` is a single plain-text Lua script. You can read every line before installing.
There is no binary, no compiled code and no telemetry.

### What it does

- Requests the M3U and XMLTV addresses you enter. If the guide field is empty it uses the guide
  address declared in your playlist header (only http and https addresses are accepted).
- Reads the local files you point it at.
- For compressed guides and some HTTPS sources it runs `curl` and `gzip` (and `cp` for local files)
  on your computer.
- Writes its settings, a guide cache and temporary download files to VLC's user data folder.
- Replaces VLC's current playlist when you press Load.

### What it does NOT do

- ❌ No telemetry, tracking, or analytics of any kind
- ❌ No contact with any hardcoded server
- ❌ No background processes, no auto-start, and no starting by itself
- ❌ Does not send your data anywhere

### Important note on VLC extensions

VLC does not sandbox Lua extensions. Like any program, an extension runs with your
user's permissions, so install extensions only from sources you trust or have read.

### Where your data is stored

The files written by the script live in VLC's own user data folder:

| System  | Path |
| ------- | ---- |
| macOS   | `~/Library/Application Support/org.videolan.vlc/` |
| Windows | `%APPDATA%\\vlc\\` |
| Linux   | `~/.local/share/vlc/` |

Files created:
- `vlc_epg.cfg` (your saved addresses and display preferences)
- `vlc_epg_cache.txt` (local parsed guide cache)
- `vlc_epg_download.tmp` / `vlc_epg_download.xml` (temporary files during download)

These files may contain your private M3U or XMLTV URLs. Do not share them publicly.
To remove all traces of the extension, delete these files or use `install.sh --uninstall --purge` (on Windows, `.\install.ps1 -Uninstall -Purge`).

### Verifying the download

Each release includes `vlc_epg.lua.sha256` so you can verify your download has not been modified:

```bash
# macOS / Linux
shasum -a 256 -c vlc_epg.lua.sha256

# Windows (PowerShell)
Get-FileHash vlc_epg.lua -Algorithm SHA256
```

---

## Reporting a Security Issue

If you find something that looks like a security problem, please open a
[GitHub Issue](../../issues) and describe what you found.

This project is a small personal tool. There is no bug-bounty programme and
no SLA, but every report will be read and taken seriously.
