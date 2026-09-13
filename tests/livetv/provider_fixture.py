from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlparse, parse_qs
from datetime import datetime, timedelta, timezone
import json
import time
class Handler(BaseHTTPRequestHandler):
    def log_message(self, *args): pass
    def do_GET(self):
        path = urlparse(self.path)
        args = parse_qs(path.query)
        if path.path == '/player_api.php':
            if args.get('username') != ['fixture user'] or args.get('password') != ['p&ss']:
                body = json.dumps({'user_info': {'auth': 0}})
            elif args.get('action') == ['get_live_categories']:
                body = json.dumps([{'category_id': '7', 'category_name': 'Nature'}])
            elif args.get('action') == ['get_live_streams']:
                body = json.dumps([{'stream_id': 42, 'name': 'Fixture Nature', 'category_id': '7', 'epg_channel_id': 'nature'}])
            else: body = json.dumps({'user_info': {'auth': 1}})
        elif path.path in ['/xmltv.php', '/guide.xml', '/slow-guide.xml']:
            if path.path == '/slow-guide.xml': time.sleep(2)
            now = datetime.now(timezone.utc)
            start = (now - timedelta(minutes=15)).strftime('%Y%m%d%H%M%S +0000')
            end = (now + timedelta(minutes=45)).strftime('%Y%m%d%H%M%S +0000')
            body = f'<tv><programme channel="nature" start="{start}" stop="{end}"><title>Wild Places</title></programme></tv>'
        elif path.path == '/slow.m3u':
            body = '#EXTM3U x-tvg-url="/slow-guide.xml"\n#EXTINF:-1 tvg-id="nature",Ready first\nhttp://127.0.0.1:8766/live.m3u8\n'
        elif path.path == '/playlist.m3u':
            body = '#EXTM3U x-tvg-url="/guide.xml"\n#EXTINF:-1 tvg-id="nature" group-title="Nature",Fixture Nature\nhttp://127.0.0.1:8766/live.m3u8\n'
        elif path.path == '/no-guide.m3u':
            body = '#EXTM3U x-tvg-url="/missing.xml"\n#EXTINF:-1,Still playable\nhttp://127.0.0.1:8766/live.m3u8\n'
        else:
            self.send_response(404); self.end_headers(); return
        data = body.encode()
        self.send_response(200); self.send_header('Content-Length',str(len(data))); self.end_headers(); self.wfile.write(data)
ThreadingHTTPServer(('127.0.0.1',8766),Handler).serve_forever()
