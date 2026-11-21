#!/usr/bin/env python3
"""Loopback-only static server for OTA builds (see the `ota` lane in Fastfile).

Tailscale Serve proxies tailnet-only HTTPS (:4443) to this server, because the
App Store build of Tailscale on macOS can't serve folders directly.

Usage: ota_server.py <directory> <port>
"""
import functools
import http.server
import sys

directory, port = sys.argv[1], int(sys.argv[2])


class Handler(http.server.SimpleHTTPRequestHandler):
    extensions_map = {
        **http.server.SimpleHTTPRequestHandler.extensions_map,
        ".plist": "text/xml",
        ".ipa": "application/octet-stream",
        ".html": "text/html; charset=utf-8",
    }

    def end_headers(self):
        self.send_header("Cache-Control", "no-store")
        super().end_headers()

    def list_directory(self, path):  # never list build folders
        self.send_error(404)
        return None


http.server.ThreadingHTTPServer(
    ("127.0.0.1", port), functools.partial(Handler, directory=directory)
).serve_forever()
