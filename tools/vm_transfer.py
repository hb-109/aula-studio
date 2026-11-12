"""Tiny file exchange between this Mac and the Windows capture VM.

Usage: python3 -I tools/vm_transfer.py <folder to serve> <folder for uploads>

Listens only on UTM's private VM network (192.168.64.1), never on Wi-Fi.
GET  /<name>                   download a file from the serve folder
POST /upload?name=<file name>  save the request body into the uploads folder
"""
import http.server
import os
import sys
from urllib.parse import parse_qs, urlparse

HOST, PORT = "192.168.64.1", 8765
MAX_UPLOAD = 50 * 1024 * 1024

serve_dir = os.path.abspath(sys.argv[1])
upload_dir = os.path.abspath(sys.argv[2])
os.makedirs(upload_dir, exist_ok=True)


class Handler(http.server.SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=serve_dir, **kwargs)

    def do_POST(self):
        url = urlparse(self.path)
        name = os.path.basename(parse_qs(url.query).get("name", ["upload.bin"])[0]) or "upload.bin"
        length = int(self.headers.get("Content-Length", "0"))
        if url.path != "/upload" or not 0 < length <= MAX_UPLOAD:
            self.send_error(400, "POST /upload?name=<file> with a body of at most 50 MB")
            return
        dest = os.path.join(upload_dir, name)
        base, ext = os.path.splitext(dest)
        n = 2
        while os.path.exists(dest):
            dest = f"{base}-{n}{ext}"
            n += 1
        with open(dest, "wb") as f:
            remaining = length
            while remaining:
                chunk = self.rfile.read(min(remaining, 1 << 16))
                if not chunk:
                    break
                f.write(chunk)
                remaining -= len(chunk)
        print(f"saved {dest} ({length - remaining} bytes)", flush=True)
        self.send_response(200)
        self.end_headers()
        self.wfile.write(f"Saved on the Mac as {os.path.basename(dest)}\r\n".encode())


http.server.ThreadingHTTPServer((HOST, PORT), Handler).serve_forever()
