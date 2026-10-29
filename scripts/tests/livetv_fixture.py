#!/usr/bin/env python3
"""Live TV fixture for the simulator and the Live TV UI tests.

Run python3 scripts/tests/livetv_fixture.py, then launch the app with --live-tv-ui-test
(port 8766) or --live-player-ui-test (port 8767). Both ports serve an M3U playlist whose
header points at an XMLTV guide generated around the current time. Channel streams are
Apple's public HLS sample, so playback needs internet access.

--large N replaces the 8766 playlist with N channels in categories of about 25, each with a
local logo, to reproduce the load and scrolling of a big IPTV provider.
"""
import struct
import sys
import zlib
from datetime import datetime, timedelta, timezone
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from threading import Thread

STREAM = "https://devstreaming-cdn.apple.com/videos/streaming/examples/bipbop_16x9/bipbop_16x9_variant.m3u8"
CHANNELS = {
    8766: [
        ("fixture.nature", "Fixture Nature", "Documentary"),
        ("fixture.news", "Fixture News 24", "News"),
        ("fixture.sports", "Fixture Sports", "Sports"),
        ("fixture.kids", "Fixture Kids", "Kids"),
        ("fixture.movies", "Fixture Movies", "Movies"),
        ("fixture.music", "Fixture Music", "Music"),
    ],
    8767: [
        ("focus.one", "Focus Test One", "Focus"),
        ("focus.two", "Focus Test Two", "Focus"),
    ],
}
SHOWS = ["Morning Edition", "Wild Coasts", "Match Day Live", "The Late Movie", "Cartoon Hour",
         "World Report", "Studio Sessions", "Deep Ocean", "Highlights", "Night Desk"]


if "--large" in sys.argv:
    count = int(sys.argv[sys.argv.index("--large") + 1])
    CHANNELS[8766] = [(f"large.{n}", f"Channel {n} HD", f"Category {n // 25:03d}") for n in range(count)]


def png(width=600, height=300, rgb=(40, 90, 160)):
    row = b"\x00" + bytes(rgb) * width
    chunk = lambda kind, data: struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data))
    return (b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0))
            + chunk(b"IDAT", zlib.compress(row * height)) + chunk(b"IEND", b""))


LOGO = png()


def playlist(port):
    lines = [f'#EXTM3U x-tvg-url="http://127.0.0.1:{port}/guide.xml"']
    for guide_id, name, group in CHANNELS[port]:
        logo = f' tvg-logo="http://127.0.0.1:{port}/logo/{guide_id}.png"' if guide_id.startswith("large.") else ""
        lines.append(f'#EXTINF:-1 tvg-id="{guide_id}"{logo} group-title="{group}",{name}')
        lines.append(f"{STREAM}?channel={guide_id}")
    return "\n".join(lines) + "\n"


def guide(port):
    fmt = "%Y%m%d%H%M%S +0000"
    now = datetime.now(timezone.utc).replace(minute=0, second=0, microsecond=0)
    rows = ['<?xml version="1.0" encoding="UTF-8"?>', "<tv>"]
    for index, (guide_id, name, _) in enumerate(CHANNELS[port]):
        rows.append(f'<channel id="{guide_id}"><display-name>{name}</display-name></channel>')
        start = now - timedelta(hours=2)
        slot = 0
        while start < now + timedelta(hours=24):
            minutes = 30 if (slot + index) % 3 else 60
            end = start + timedelta(minutes=minutes)
            title = SHOWS[(slot + index) % len(SHOWS)]
            rows.append(f'<programme channel="{guide_id}" start="{start.strftime(fmt)}" stop="{end.strftime(fmt)}">'
                        f"<title>{title}</title><desc>{title} on {name}.</desc></programme>")
            start, slot = end, slot + 1
    rows.append("</tv>")
    return "\n".join(rows)


def handler(port):
    class Handler(BaseHTTPRequestHandler):
        def do_GET(self):
            if self.path.startswith("/logo/"):
                self.send_response(200)
                self.send_header("Content-Type", "image/png")
                self.send_header("Content-Length", str(len(LOGO)))
                self.end_headers()
                self.wfile.write(LOGO)
                return
            if self.path.startswith("/playlist.m3u"):
                body, kind = playlist(port), "audio/x-mpegurl"
            elif self.path.startswith("/guide.xml"):
                body, kind = guide(port), "application/xml"
            else:
                self.send_response(404); self.end_headers(); return
            data = body.encode()
            self.send_response(200)
            self.send_header("Content-Type", kind)
            self.send_header("Content-Length", str(len(data)))
            self.end_headers()
            self.wfile.write(data)

        def log_message(self, *args):
            pass
    return Handler


servers = [ThreadingHTTPServer(("127.0.0.1", port), handler(port)) for port in CHANNELS]
for server in servers[1:]:
    Thread(target=server.serve_forever, daemon=True).start()
print("Live TV fixture on 127.0.0.1:" + ", ".join(str(port) for port in CHANNELS))
servers[0].serve_forever()
