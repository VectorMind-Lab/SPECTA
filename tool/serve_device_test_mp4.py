"""Minimal deterministic HTTP file server for the Phase 2G-C device transfer
verification (test artifact only — never shipped).

Serves one file at http://127.0.0.1:8712/test.mp4 with explicit
Content-Length and Range support (206 Partial Content) so the
background_downloader engine can resume. Log lines are machine-parsable so
the verification harness can assert WHICH requests the device actually made.
"""
from __future__ import annotations

import os
import re
import sys
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

FILE_PATH = sys.argv[1] if len(sys.argv) > 1 else None
PORT = 8712

_RANGE = re.compile(rb"bytes=(\d*)-(\d*)")


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, fmt: str, *args: object) -> None:  # noqa: D102
        print(f"REQ {self.command} {self.path} rc={args[0] if args else '?'}",
              flush=True)

    def do_GET(self) -> None:  # noqa: N802
        if self.path != "/test.mp4" or FILE_PATH is None:
            self.send_error(404)
            return
        size = os.path.getsize(FILE_PATH)
        rng = _RANGE.match(self.headers.get("Range", "").encode())
        start, end = 0, size - 1
        partial = False
        if rng:
            if rng.group(1):
                start = int(rng.group(1))
                partial = True
            if rng.group(2):
                end = int(rng.group(2))
        if start >= size or end >= size or start > end:
            self.send_response(416)
            self.send_header("Content-Range", f"bytes */{size}")
            self.send_header("Content-Length", "0")
            self.end_headers()
            return
        length = end - start + 1
        self.send_response(206 if partial else 200)
        self.send_header("Content-Type", "video/mp4")
        self.send_header("Content-Length", str(length))
        self.send_header("Accept-Ranges", "bytes")
        if partial:
            self.send_header("Content-Range", f"bytes {start}-{end}/{size}")
        self.end_headers()
        with open(FILE_PATH, "rb") as handle:
            handle.seek(start)
            remaining = length
            while remaining > 0:
                chunk = handle.read(min(64 * 1024, remaining))
                if not chunk:
                    break
                try:
                    self.wfile.write(chunk)
                except (BrokenPipeError, ConnectionResetError):
                    return
                remaining -= len(chunk)

    def do_HEAD(self) -> None:  # noqa: N802
        if self.path != "/test.mp4" or FILE_PATH is None:
            self.send_error(404)
            return
        size = os.path.getsize(FILE_PATH)
        self.send_response(200)
        self.send_header("Content-Type", "video/mp4")
        self.send_header("Content-Length", str(size))
        self.send_header("Accept-Ranges", "bytes")
        self.end_headers()


def main() -> None:
    if FILE_PATH is None or not os.path.isfile(FILE_PATH):
        print("usage: python serve_device_test_mp4.py <file>", flush=True)
        sys.exit(1)
    server = ThreadingHTTPServer(("127.0.0.1", PORT), Handler)
    print(f"SERVING http://127.0.0.1:{PORT}/test.mp4 file={FILE_PATH} "
          f"size={os.path.getsize(FILE_PATH)}", flush=True)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass


if __name__ == "__main__":
    threading.main_thread()  # no-op; keeps linters calm about threading import
    main()
