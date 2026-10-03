#!/usr/bin/env python3
"""Minimal REST backend for the teamvks private network platform (Task C).

The same program runs twice, once per backend VM:

    vm3-backend-a:  python3 server.py --id A --port 3001
    vm4-backend-b:  python3 server.py --id B --port 3002

Only the Python standard library is used, so nothing has to be installed.
The application is deliberately tiny: the network is the project.
"""
import argparse
import html
import json
import socket
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer


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
        if path == "/":
            status, content_type, body = 200, "text/html; charset=utf-8", self.home_page()
        elif path == "/api/status":
            status, content_type, body = 200, "application/json", self.to_json(
                {"backend": self.backend_id, "status": "ok", "host": self.hostname}
            )
        else:
            status, content_type, body = 404, "application/json", self.to_json(
                {"error": "not found", "path": path}
            )

        self.send_response(status)  # also adds the Date and Server headers
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(body)))
        # Lets every client see which backend served the request (load balancing proof).
        self.send_header("X-Backend", self.backend_id)
        self.end_headers()
        if send_body:
            self.wfile.write(body)

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
            '<p>JSON status: <a href="/api/status">/api/status</a></p>'
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
