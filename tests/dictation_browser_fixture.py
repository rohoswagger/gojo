#!/usr/bin/env python3
import json
import sys
import time
import uuid
from http.server import BaseHTTPRequestHandler, HTTPServer
from pathlib import Path


def read_state(path, url, title):
    try:
        state = json.loads(Path(path).read_text())
        if (
            state["href"] == url
            and state["title"] == title
            and state["fieldID"] == "dictation"
            and isinstance(state["value"], str)
            and 0 <= time.time() - state["receivedAt"] < 1
        ):
            return state
    except (OSError, ValueError, KeyError, TypeError):
        pass
    return None


def verify(path, url, title, expected):
    deadline = time.monotonic() + 5
    state = None
    while time.monotonic() < deadline:
        state = read_state(path, url, title)
        if state and state["value"] == expected:
            print(
                "browser-fixture verified=true field=dictation actual="
                + json.dumps(state["value"], ensure_ascii=False)
            )
            return
        time.sleep(0.05)
    actual = state["value"] if state else None
    raise SystemExit(
        "Browser fixture exact text verification failed. actual="
        + json.dumps(actual, ensure_ascii=False)
        + " expected="
        + json.dumps(expected, ensure_ascii=False)
    )


def serve(fixture, directory):
    directory = Path(directory)
    run = uuid.uuid4().hex
    page_path = f"/dictation-e2e.html?run={run}"
    state_path = f"/state?run={run}"
    title = f"Gojo Dictation E2E {run}"
    page = Path(fixture).read_bytes()
    sequence = 0

    class Handler(BaseHTTPRequestHandler):
        def do_GET(self):
            if self.path != page_path:
                self.send_error(404)
                return
            self.send_response(200)
            self.send_header("Content-Type", "text/html; charset=utf-8")
            self.send_header("Cache-Control", "no-store")
            self.send_header(
                "Content-Security-Policy",
                "default-src 'none'; script-src 'unsafe-inline'; connect-src 'self'",
            )
            self.end_headers()
            self.wfile.write(page)

        def do_POST(self):
            nonlocal sequence
            if self.path != state_path or self.headers.get("Origin") != origin:
                self.send_error(403)
                return
            try:
                length = int(self.headers.get("Content-Length", "0"))
                if not 0 < length <= 65536:
                    raise ValueError("Invalid state size")
                state = json.loads(self.rfile.read(length))
                if not (
                    state["href"] == url
                    and state["title"] == title
                    and state["fieldID"] == "dictation"
                    and isinstance(state["value"], str)
                    and type(state["sequence"]) is int
                    and type(state["focused"]) is bool
                    and type(state["visible"]) is bool
                ):
                    raise ValueError("Invalid fixture state")
            except (ValueError, KeyError, TypeError):
                self.send_error(400)
                return
            if state["sequence"] > sequence:
                sequence = state["sequence"]
                state["receivedAt"] = time.time()
                temporary = directory / "state.pending"
                temporary.write_text(json.dumps(state))
                temporary.replace(directory / "state.json")
            self.send_response(204)
            self.end_headers()

        def log_message(self, *_):
            pass

    server = HTTPServer(("127.0.0.1", 0), Handler)
    origin = f"http://127.0.0.1:{server.server_port}"
    url = origin + page_path
    (directory / "ready.json").write_text(json.dumps({"url": url, "title": title}))
    server.serve_forever()


if __name__ == "__main__":
    if len(sys.argv) == 4 and sys.argv[1] == "serve":
        serve(*sys.argv[2:])
    elif len(sys.argv) == 6 and sys.argv[1] == "verify":
        verify(*sys.argv[2:])
    else:
        raise SystemExit("Usage: dictation_browser_fixture.py serve HTML DIRECTORY | verify STATE URL TITLE EXPECTED")
