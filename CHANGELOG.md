# Changelog

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
