#!/usr/bin/env python3
"""Minimal REST backend for the teamvks private network platform (Tasks C and F).

The same program runs twice, once per backend VM:

    vm3-backend-a:  python3 server.py --id A --port 3001
    vm4-backend-b:  python3 server.py --id B --port 3002

Only the Python standard library is used, so nothing has to be installed.
The application is deliberately tiny: the network is the project.
"""
import argparse
import hashlib
import html
import json
import socket
from email.utils import parsedate_to_datetime
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

# /api/info (Task F) is the cacheable endpoint. Its body is the same on every
# backend, so its ETag (a fingerprint of the body) is the same on A and B too:
# a client can revalidate with whichever backend round-robin picks next.
INFO = {
    "service": "teamvks private network platform",
    "endpoints": ["/", "/api/status", "/api/info"],
    "note": "this document is cacheable for 60 seconds",
}
INFO_BODY = (json.dumps(INFO) + "\n").encode()
INFO_ETAG = '"' + hashlib.sha256(INFO_BODY).hexdigest()[:16] + '"'
# When the content of INFO last changed (fixed, so it's identical on A and B).
INFO_LAST_MODIFIED = "Sat, 03 Oct 2026 18:00:00 GMT"


class BackendHandler(BaseHTTPRequestHandler):
    # HTTP/1.1 keeps connections open between requests, so every response
    # must carry an exact Content-Length.
    protocol_version = "HTTP/1.1"

    # Filled in by main() before the server starts.
    backend_id = "?"
    port = 0
    hostname = socket.gethostname()

    def do_GET(self):
        self.respond(send_body=True)

    def do_HEAD(self):
        # Same status and headers as GET, without the body (used by curl -I).
        self.respond(send_body=False)

    def respond(self, send_body):
        path = self.path.split("?", 1)[0]
        cache_headers = {}
        if path == "/":
            status, content_type, body = 200, "text/html; charset=utf-8", self.home_page()
            # Live per-backend data: never store it, always ask again.
            cache_headers["Cache-Control"] = "no-store"
        elif path == "/api/status":
            status, content_type, body = 200, "application/json", self.to_json(
                {"backend": self.backend_id, "status": "ok", "host": self.hostname}
            )
            cache_headers["Cache-Control"] = "no-store"
        elif path == "/api/info":
            content_type, body = "application/json", INFO_BODY
            # Fresh for 60 s in any cache (browser or edge); after that, revalidate
            # with the ETag / Last-Modified validators.
            cache_headers = {
                "Cache-Control": "public, max-age=60",
                "ETag": INFO_ETAG,
                "Last-Modified": INFO_LAST_MODIFIED,
            }
            status = 304 if self.not_modified() else 200
        else:
            status, content_type, body = 404, "application/json", self.to_json(
                {"error": "not found", "path": path}
            )

        self.send_response(status)  # also adds the Date and Server headers
        if status != 304:
            # A 304 has no body, so no Content-Type / Content-Length.
            self.send_header("Content-Type", content_type)
            self.send_header("Content-Length", str(len(body)))
        for name, value in cache_headers.items():
            self.send_header(name, value)
        # Lets every client see which backend served the request (load balancing proof).
        self.send_header("X-Backend", self.backend_id)
        self.end_headers()
        if send_body and status != 304:
            self.wfile.write(body)

    def not_modified(self):
        """True if the client's cached copy of /api/info is still current (-> 304)."""
        # If-None-Match: "is your ETag still one of these?" It wins over the date check.
        if_none_match = self.headers.get("If-None-Match")
        if if_none_match is not None:
            tags = [tag.strip().removeprefix("W/") for tag in if_none_match.split(",")]
            return "*" in tags or INFO_ETAG in tags
        # If-Modified-Since: "has it changed since this date?"
        if_modified_since = self.headers.get("If-Modified-Since")
        if if_modified_since:
            try:
                since = parsedate_to_datetime(if_modified_since)
                return since >= parsedate_to_datetime(INFO_LAST_MODIFIED)
            except (TypeError, ValueError):
                return False
        return False

    def home_page(self):
        # client_address is the TCP peer. Behind nginx that's the edge, while the
        # original client arrives in the X-Forwarded-For header that nginx adds.
        peer = self.client_address[0]
        forwarded = self.headers.get("X-Forwarded-For", "not set (direct connection)")
        rows = [
            ("Backend", self.backend_id),
            ("Host", f"{self.hostname}, port {self.port}"),
            ("TCP connection from", peer),
            ("Original client (X-Forwarded-For)", forwarded),
        ]
        cells = "".join(
            f"<tr><th>{html.escape(k)}</th><td>{html.escape(v)}</td></tr>" for k, v in rows
        )
        page = (
            "<!doctype html><meta charset=utf-8>"
            f"<title>teamvks - Backend {html.escape(self.backend_id)}</title>"
            f"<h1>Backend {html.escape(self.backend_id)} is running</h1>"
            f"<table>{cells}</table>"
            '<p>JSON status: <a href="/api/status">/api/status</a> · '
            'cacheable document: <a href="/api/info">/api/info</a></p>'
        )
        return page.encode()

    @staticmethod
    def to_json(data):
        return (json.dumps(data) + "\n").encode()

    def version_string(self):
        return f"teamvks-backend/{self.backend_id}"

    def log_message(self, fmt, *args):
        # One line per request in the journal: who connected (TCP peer), who the
        # original client was (X-Forwarded-For), and what was asked.
        headers = getattr(self, "headers", None)
        forwarded = headers.get("X-Forwarded-For", "-") if headers else "-"
        peer_ip, peer_port = self.client_address
        print(
            f"backend={self.backend_id} peer={peer_ip}:{peer_port} xff={forwarded} {fmt % args}",
            flush=True,
        )


def main():
    parser = argparse.ArgumentParser(description="teamvks REST backend")
    parser.add_argument("--id", required=True, help="backend identifier, e.g. A or B")
    parser.add_argument("--port", type=int, required=True, help="TCP port to listen on")
    parser.add_argument(
        "--host",
        default="0.0.0.0",
        help="address to bind: 0.0.0.0 = every interface (needed so the edge can connect)",
    )
    args = parser.parse_args()

    BackendHandler.backend_id = args.id
    BackendHandler.port = args.port

    server = ThreadingHTTPServer((args.host, args.port), BackendHandler)
    print(f"Backend {args.id} listening on {args.host}:{args.port}", flush=True)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()


if __name__ == "__main__":
    main()
