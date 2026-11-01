#!/usr/bin/env python3
"""Fans an MPEG-TS stream on stdin out to any number of HTTP clients.

One camera encodes once, however many browsers watch. A slow client is dropped
from the queue instead of delaying the others.
"""
import argparse
import http.server
import queue
import socketserver
import sys
import threading

TS_PACKET = 188
CHUNK = TS_PACKET * 64
CLIENT_QUEUE = 256

clients = set()
clients_lock = threading.Lock()


def pump():
    while chunk := sys.stdin.buffer.read(CHUNK):
        with clients_lock:
            for client in clients:
                try:
                    client.put_nowait(chunk)
                except queue.Full:
                    # Empty it so the client resyncs on live video rather than falling behind
                    with client.mutex:
                        client.queue.clear()
    print('camera stream ended', file=sys.stderr)
    sys.exit(1)


class Handler(http.server.BaseHTTPRequestHandler):
    protocol_version = 'HTTP/1.1'

    def do_GET(self):
        if self.path.split('?')[0] != '/live.ts':
            self.send_error(404)
            return

        self.send_response(200)
        self.send_header('Content-Type', 'video/mp2t')
        self.send_header('Cache-Control', 'no-store')
        self.send_header('Access-Control-Allow-Origin', '*')
        self.send_header('Connection', 'close')
        self.end_headers()

        client = queue.Queue(CLIENT_QUEUE)
        with clients_lock:
            clients.add(client)
        try:
            while True:
                self.wfile.write(client.get(timeout=5))
                self.wfile.flush()
        except (queue.Empty, ConnectionError):
            pass
        finally:
            with clients_lock:
                clients.discard(client)
            self.close_connection = True

    def log_message(self, format, *args):
        pass


class Server(socketserver.ThreadingMixIn, http.server.HTTPServer):
    daemon_threads = True
    allow_reuse_address = True


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--port', type=int, default=8000)
    args = parser.parse_args()

    server = Server(('0.0.0.0', args.port), Handler)
    threading.Thread(target=server.serve_forever, daemon=True).start()
    try:
        pump()
    except KeyboardInterrupt:
        pass
