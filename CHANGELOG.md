# Changelog

## 2.2.0

- New menu: choose what the Description column shows (2, 3 or 5 programs, or the next 2, 4, 8 or 12 hours). The choice is saved. In hours mode at most 10 programs are listed.
- Genre column: category of the running program. Album column: synopsis of the running program.
- On-screen message includes the category and a short synopsis.
- Program titles escaped twice by a guide (for example `&amp;#039;`) are decoded correctly.
- Safer channel matching: cleaned `tvg-id` comparison, quality words and tags ignored in names, ambiguous matches skipped. The status line shows matches by id and by name.
- The guide address from a playlist header is only used when it is an http or https address.
- Project renamed to VLC EPG (`vlc_epg.lua`). Settings and cache files were renamed, so enter your addresses again after updating.
- One-line installers for macOS, Linux and Windows (Windows untested), and an uninstall option.
- CI: syntax check, VLC scan-phase check, installer lint and tests.

## 2.1.0

- Improvements:
  - Changed separator from `|||` to ` || ` for better readability.
  - Separator in Description is now `   |||   ` (three spaces, pipe, three spaces).
  - Added a progress bar (progress bar starts from left to right for current program).
  - Added bold font for current running program.

## 2.0.0

- First public release.
- Loads an M3U playlist into VLC's own playlist and fills the Description column
  with XMLTV program info (current program plus the next ones).
- Author column shows the channel group, so the playlist can be sorted by group.
- Streaming XMLTV parser that keeps only the channels in your playlist.
- Matches channels by `tvg-id`, with a fallback on channel name.
- Local cache of the parsed guide (refreshed every 6 hours).
- Gzip-compressed guides and stubborn HTTPS sources are fetched with `curl` / `gzip`.
- On-screen display with the current and next program when you switch channel.
