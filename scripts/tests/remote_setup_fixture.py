"""Local browser QA fixture; serves the app's exact embedded page, never real account data.
Run python3 scripts/tests/remote_setup_fixture.py, then open http://127.0.0.1:8766/?t=fixture.
Edit /tmp/nuvio-remote-fixture-mode to confirmed / failed / rejected / pending / applying / conflict / forbidden.
"""
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
import json

ROOT = Path(__file__).resolve().parents[2]
MODE = Path('/tmp/nuvio-remote-fixture-mode')
MODE.write_text('confirmed')
STATE = {'deviceName': 'Apple TV · Settings test', 'revision': '1',
         'addons': [{'url': 'https://catalog.example.invalid/manifest.json', 'name': 'Catalog', 'enabled': True},
                    {'url': 'https://series.example.invalid/manifest.json', 'name': 'Series', 'enabled': True}],
         'rows': [{'key': 'movies', 'title': 'Popular Movies', 'enabled': True, 'isCollection': False},
                  {'key': 'shows', 'title': 'Popular Shows', 'enabled': True, 'isCollection': False},
                  {'key': 'collection', 'title': 'Weekend Favorites', 'enabled': False, 'isCollection': True}],
         'badgePacks': [], 'tmdbKeySet': True, 'mdblistKeySet': False}
PENDING = None
FINISHED = False

class Handler(BaseHTTPRequestHandler):
    def send(self, body, status=200, html=False):
        data = body.encode() if html else json.dumps(body).encode()
        self.send_response(status)
        self.send_header('Content-Type', 'text/html' if html else 'application/json')
        self.send_header('Content-Length', str(len(data)))
        self.send_header('Cache-Control', 'no-store')
        self.end_headers()
        self.wfile.write(data)

    def do_GET(self):
        global FINISHED
        mode = MODE.read_text().strip()
        if self.path == '/phone':
            self.send('<!doctype html><meta name=viewport content="width=device-width"><body style="margin:0;background:#333"><iframe title="Phone settings" src="/?t=fixture" style="border:0;width:390px;height:844px"></iframe>', html=True)
        elif self.path.startswith('/?') or self.path == '/':
            swift = (ROOT / 'iosApp/NuvioTV/Screens/RemoteSetupWebPage.swift').read_text()
            self.send(swift.split('#"""\n', 1)[1].rsplit('"""#', 1)[0], html=True)
        elif mode == 'forbidden':
            self.send({'error': 'Forbidden'}, 403)
        elif self.path == '/api/state':
            self.send(STATE)
        elif self.path.startswith('/api/status/'):
            if mode == 'confirmed' and not FINISHED:
                p = PENDING or {}
                if 'addons' in p: STATE['addons'] = [dict(a, name=next((b['name'] for b in STATE['addons'] if b['url'] == a['url']), 'Added provider')) for a in p['addons']]
                if 'rowOrder' in p:
                    STATE['rows'] = [dict(next(r for r in STATE['rows'] if r['key'] == k), enabled=k not in p.get('disabledRowKeys', [])) for k in p['rowOrder']]
                STATE['badgePacks'] += p.get('badgeUrls', [])
                for key in ('tmdbKey', 'mdblistKey'):
                    if key in p: STATE[key+'Set'] = True
                STATE['revision'] = str(int(STATE['revision']) + 1)
                FINISHED = True
            self.send({'status': mode, 'started': mode in ('confirmed', 'failed', 'applying'), 'errors': ['Add-on: Could not install. Check the URL and try again.'] if mode == 'failed' else []})
        else: self.send({}, 404)

    def do_POST(self):
        global PENDING, FINISHED
        PENDING = json.loads(self.rfile.read(int(self.headers['Content-Length'])))
        # Fake keys only; useful for asserting omitted fields and ordering after browser actions.
        Path('/tmp/nuvio-remote-fixture-payload.json').write_text(json.dumps(PENDING))
        if MODE.read_text().strip() == 'conflict':
            self.send({'error': 'Settings changed on the TV. Reload before sending.'}, 409)
        else:
            FINISHED = False
            self.send({'id': 'fixture-request', 'status': 'pending_confirmation'})

ThreadingHTTPServer(('127.0.0.1', 8766), Handler).serve_forever()
