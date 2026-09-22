"""Minimal deterministic HTTP file server for the Phase 2G-C device transfer
verification (test artifact only — never shipped).

Serves one file at http://127.0.0.1:8712/test.mp4 with explicit
Content-Length and Range support (206 Partial Content) so the
background_downloader engine can resume. Log lines are machine-parsable so
the verification harness can assert WHICH requests the device actually made.

Optional --slow flag: sends bytes at a controlled rate to keep the
transfer active long enough for restart-recovery and pause/resume
device tests (2MB in ~90 seconds at ~23 KB/s).

Direct-transport follow-up (2026-09-22): the previous device validation
reached this server through `adb reverse tcp:8712 tcp:8712`, which turned out
to be an unreliable transport. The server can now bind a specific interface
and port (`--host <addr> --port <n>`) so the device can reach it DIRECTLY over
the shared LAN, with no adb forwarding anywhere in the path. The defaults are
unchanged (127.0.0.1:8712), so the historical adb-reverse invocation still
behaves exactly as before.
"""
from __future__ import annotations

import os
import re
import sys
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

DEFAULT_HOST = "127.0.0.1"
DEFAULT_PORT = 8712


def _flag_value(flag: str, default: str) -> str:
    """Reads `--flag value` from argv, falling back to [default]."""
    if flag in sys.argv:
        index = sys.argv.index(flag)
        if index + 1 < len(sys.argv):
            return sys.argv[index + 1]
    return default


FILE_PATH = next(
    (arg for arg in sys.argv[1:] if not arg.startswith("--")), None
)
HOST = _flag_value("--host", DEFAULT_HOST)
PORT = int(_flag_value("--port", str(DEFAULT_PORT)))
SLOW = "--slow" in sys.argv
# Target: 2MB in ~90 seconds.
SLOW_BPS = 23000

_RANGE = re.compile(rb"bytes=(\d*)-(\d*)")


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, fmt: str, *args: object) -> None:
        # parse_request() may fail before self.path is set; the log line must
        # never crash the server, or a malformed probe would take the whole
        # controlled transfer path down with it.
        path = getattr(self, "path", "?")
        print(f"REQ {self.command} {path} rc={args[0] if args else '?'}",
              flush=True)

    def _send_body_slow(self, size: int, start: int) -> int:
        chunk_size = 8192
        sleep_per_chunk = chunk_size / SLOW_BPS
        remaining = size
        sent = 0
        with open(FILE_PATH, "rb") as handle:
            handle.seek(start)
            while remaining > 0:
                chunk = handle.read(min(chunk_size, remaining))
                if not chunk:
                    break
                try:
                    self.wfile.write(chunk)
                    self.wfile.flush()
                except (BrokenPipeError, ConnectionResetError):
                    return sent
                sent += len(chunk)
                time.sleep(sleep_per_chunk)
                remaining -= len(chunk)
        return sent

    def _send_body_normal(self, size: int, start: int) -> int:
        remaining = size
        sent = 0
        with open(FILE_PATH, "rb") as handle:
            handle.seek(start)
            while remaining > 0:
                chunk = handle.read(min(64 * 1024, remaining))
                if not chunk:
                    break
                try:
                    self.wfile.write(chunk)
                except (BrokenPipeError, ConnectionResetError):
                    return sent
                sent += len(chunk)
                remaining -= len(chunk)
        return sent

    def do_HEAD(self) -> None:
        if self.path != "/test.mp4" or FILE_PATH is None:
            self.send_error(404)
            return
        size = os.path.getsize(FILE_PATH)
        self.send_response(200)
        self.send_header("Content-Type", "video/mp4")
        self.send_header("Content-Length", str(size))
        self.send_header("Accept-Ranges", "bytes")
        self.end_headers()

    def do_GET(self) -> None:
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
        range_header = self.headers.get("Range", "-")
        agent = self.headers.get("User-Agent", "-")
        print(f"HDR range={range_header} ua={agent}", flush=True)
        self.send_response(206 if partial else 200)
        self.send_header("Content-Type", "video/mp4")
        self.send_header("Content-Length", str(length))
        self.send_header("Accept-Ranges", "bytes")
        if partial:
            self.send_header("Content-Range", f"bytes {start}-{end}/{size}")
        self.end_headers()
        if SLOW:
            sent = self._send_body_slow(length, start)
        else:
            sent = self._send_body_normal(length, start)
        # Decisive evidence: how much the server actually pushed before the
        # client closed. A SENT far below EXPECTED on a healthy host path
        # means the CLIENT stopped reading, not that the server truncated.
        print(f"SENT bytes={sent} expected={length} "
              f"complete={sent == length}", flush=True)


def main() -> None:
    if FILE_PATH is None or not os.path.isfile(FILE_PATH):
        print("usage: python serve_device_test_mp4.py <file> [--slow] "
              "[--host <addr>] [--port <port>]", flush=True)
        sys.exit(1)
    mode = "SLOW" if SLOW else "NORMAL"
    server = ThreadingHTTPServer((HOST, PORT), Handler)
    bps_info = f" rate={SLOW_BPS}B/s" if SLOW else ""
    print(f"SERVING http://{HOST}:{PORT}/test.mp4 file={FILE_PATH} "
          f"size={os.path.getsize(FILE_PATH)} mode={mode}{bps_info}",
          flush=True)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass


if __name__ == "__main__":
    threading.main_thread()
    main()
