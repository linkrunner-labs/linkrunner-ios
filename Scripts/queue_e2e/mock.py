import json, sys, time, threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
LOG = sys.argv[2]; MODE = sys.argv[3]  # mode: 'events503' or 'ok'
lock = threading.Lock()
class H(BaseHTTPRequestHandler):
    def do_POST(self):
        n = int(self.headers.get('Content-Length', 0)); body = self.rfile.read(n)
        try: j = json.loads(body)
        except Exception: j = {}
        status = 200
        if MODE == 'events503' and self.path == '/api/client/capture-event': status = 503
        with lock, open(LOG, 'a') as f:
            f.write(json.dumps({"t": time.time(), "path": self.path, "status": status,
                                "token": j.get("token"), "i": (j.get("event_data") or {}).get("i") if isinstance(j.get("event_data"), dict) else None}) + "\n")
        out = json.dumps({"status": status, "msg": "ok", "data": {}}).encode()
        self.send_response(status); self.send_header('Content-Type', 'application/json')
        self.send_header('Content-Length', str(len(out))); self.end_headers(); self.wfile.write(out)
    def log_message(self, *a): pass
ThreadingHTTPServer(('127.0.0.1', int(sys.argv[1])), H).serve_forever()
