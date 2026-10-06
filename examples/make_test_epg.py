#!/usr/bin/env python3
"""Generate examples/test_epg.xml with programs around the current time.

Usage: python3 examples/make_test_epg.py
The file matches the channels in examples/test.m3u and is valid for ~45 hours.
"""
import datetime as dt
import os

now = dt.datetime.now(dt.timezone.utc).replace(minute=0, second=0, microsecond=0)
start = now - dt.timedelta(hours=3)
end_of_data = now + dt.timedelta(hours=45)


def stamp(t):
    return t.strftime("%Y%m%d%H%M%S") + " +0000"


shows = {
    "test.one": ["Morning News", "Cooking Time", "Nature Docs", "Quiz Night", "Late Movie", "Music Hits"],
    "test.two": ["Sports Update", "Kids Cartoon", "Tech Talk", "Travel Diary", "Crime Series", "Weather & Talk"],
}
names = {"test.one": "Test Channel 1", "test.two": "Test Channel 2"}

lines = ['<?xml version="1.0" encoding="UTF-8"?>', '<tv generator-info-name="iptv-guide-test">']
for cid, name in names.items():
    lines.append(f'  <channel id="{cid}"><display-name>{name}</display-name></channel>')

for cid, titles in shows.items():
    t, i = start, 0
    while t < end_of_data:
        e = t + dt.timedelta(minutes=45)
        title = titles[i % len(titles)].replace("&", "&amp;")
        lines.append(
            f'  <programme start="{stamp(t)}" stop="{stamp(e)}" channel="{cid}">'
            f'<title lang="en">{title}</title>'
            f'<desc lang="en">Test description for {title}.</desc></programme>'
        )
        t, i = e, i + 1

lines.append("</tv>")
out = os.path.join(os.path.dirname(os.path.abspath(__file__)), "test_epg.xml")
with open(out, "w", encoding="utf-8") as f:
    f.write("\n".join(lines) + "\n")
print("Wrote", out)
