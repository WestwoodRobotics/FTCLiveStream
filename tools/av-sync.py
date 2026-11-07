#!/usr/bin/env python3
"""Measures how far a camera's audio is ahead of or behind its video, and how steady that is.

Point the camera at this Mac's screen, put its mic near the Mac's speakers, turn the volume up, then:
  python3 tools/av-sync.py 10.0.100.20          # the camera stream itself
  python3 tools/av-sync.py ~/Movies/clip.mkv    # an OBS recording, which includes OBS's own delay

For an address, it opens a page that flashes white and beeps at the same moment, records the camera,
and compares when each flash and beep land in the stream. For a file, record 30 seconds in OBS while
the page runs (open it with --page-only) and pass the recording. Needs ffmpeg.
"""
import argparse
import http.server
import os
import re
import statistics
import subprocess
import sys
import tempfile
import threading
import time
import urllib.request
import webbrowser

PAGE = b"""<!doctype html>
<html><head><meta charset="utf-8"><title>AV sync test</title>
<style>html,body{margin:0;height:100%;background:#000;color:#888;font:24px system-ui;cursor:none}
#msg{position:fixed;inset:0;display:grid;place-items:center;text-align:center;padding:2em}</style></head>
<body><div id="msg">Click anywhere to start.<br>Then press Ctrl+Cmd+F for full screen.<br><br>
Point the camera at this screen and put its mic near the speakers.</div>
<script>
let ctx, next = 0, frame = 1000 / 60, last = 0, count = 0;
const msg = document.getElementById('msg');
function beep(at) {
  const osc = ctx.createOscillator(), gain = ctx.createGain();
  osc.frequency.value = 1000;
  gain.gain.setValueAtTime(1, at);
  gain.gain.setValueAtTime(0, at + 0.06);
  osc.connect(gain).connect(ctx.destination);
  osc.start(at);
  osc.stop(at + 0.07);
}
function tick(now) {
  if (last) frame = 0.9 * frame + 0.1 * (now - last);
  last = now;
  if (now >= next) {
    // The white frame appears on screen about one refresh from now, so the beep leaves the
    // speaker at that moment instead of right away
    const audioDelay = (ctx.baseLatency || 0) + (ctx.outputLatency || 0);
    beep(ctx.currentTime + Math.max(0, frame / 1000 - audioDelay));
    document.body.style.background = '#fff';
    msg.textContent = '';
    setTimeout(() => (document.body.style.background = '#000'), 150);
    // Random spacing so flashes land at different points between camera frames
    next = now + 1400 + Math.random() * 1200;
    count++;
  }
  requestAnimationFrame(tick);
}
addEventListener('click', () => {
  if (ctx) return;
  ctx = new AudioContext();
  next = performance.now() + 1000;
  requestAnimationFrame(tick);
}, { once: true });
</script></body></html>"""


class PageHandler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        self.send_response(200)
        self.send_header('Content-Type', 'text/html')
        self.end_headers()
        self.wfile.write(PAGE)

    def log_message(self, *args):
        pass


def open_page():
    server = http.server.ThreadingHTTPServer(('127.0.0.1', 0), PageHandler)
    threading.Thread(target=server.serve_forever, daemon=True).start()
    url = f'http://127.0.0.1:{server.server_port}/'
    webbrowser.open(url)
    return url


def record(address, seconds, path):
    url = address if '://' in address else f'http://{address}:8000/live.ts'
    deadline = time.monotonic() + seconds
    with urllib.request.urlopen(url, timeout=10) as stream, open(path, 'wb') as out:
        while time.monotonic() < deadline:
            out.write(stream.read(188 * 64))


def metadata(path, stream, filters, key):
    """Runs ffmpeg and returns (pts_time, value) for every frame, read from its metadata printout."""
    cmd = ['ffmpeg', '-v', 'error', '-i', path, '-map', f'0:{stream}:0', '-filter:' + stream,
           f'{filters},{"a" if stream == "a" else ""}metadata=print:key={key}:file=-', '-f', 'null', '-']
    out = subprocess.run(cmd, capture_output=True, text=True, check=True).stdout
    rows, pts = [], None
    for line in out.splitlines():
        if m := re.search(r'pts_time:(-?[\d.]+)', line):
            pts = float(m.group(1))
        elif key in line and pts is not None:
            value = line.split('=', 1)[1]
            rows.append((pts, float(value) if value not in ('-inf', 'inf', 'nan') else -120.0))
    return rows


def rising_edges(rows, threshold, refractory=1.0):
    """Times where the value crosses the threshold upward, interpolated between samples."""
    edges, last = [], -1e9
    for (t0, v0), (t1, v1) in zip(rows, rows[1:]):
        if v0 < threshold <= v1 and t1 - last > refractory:
            t = t0 + (threshold - v0) / (v1 - v0) * (t1 - t0)
            edges.append(t)
            last = t
    return edges


def flashes(path):
    rows = metadata(path, 'v', 'scale=160:-2,signalstats', 'lavfi.signalstats.YAVG')
    values = sorted(v for _, v in rows)
    low, high = values[len(values) // 20], values[-len(values) // 50 - 1]
    if high - low < 10:
        sys.exit('No flashes found in the video. Is the camera pointed at the flashing screen?')
    # Halfway between dark and lit screen marks the moment the flash appeared
    return rising_edges(rows, (low + high) / 2)


def beeps(path):
    # 2 ms windows at 48 kHz
    rows = metadata(path, 'a', 'aresample=48000,asetnsamples=n=96:p=0,astats=metadata=1:reset=1',
                    'lavfi.astats.Overall.RMS_level')
    floor = statistics.median(v for _, v in rows)
    if max(v for _, v in rows) - floor < 15:
        sys.exit('No beeps found in the audio. Is the mic near the speakers with the volume up?')
    return rising_edges(rows, floor + 15)


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('source', nargs='?', help='camera address (10.0.100.20) or a recording')
    parser.add_argument('--seconds', type=float, default=30, help='how long to record a camera')
    parser.add_argument('--page-only', action='store_true', help='just open the flash page')
    args = parser.parse_args()

    if args.page_only or not args.source:
        print('Flash page:', open_page())
        print('Leave this running while you record. Ctrl+C to stop.')
        try:
            threading.Event().wait()
        except KeyboardInterrupt:
            return

    if not os.path.exists(os.path.expanduser(args.source)):
        print('Opening the flash page. Click it, make it full screen, and point the camera at it.')
        open_page()
        input('Press Enter here once the screen is flashing and the camera can see it... ')
        path = tempfile.mktemp(suffix='.ts')
        print(f'Recording {args.seconds:.0f} seconds from {args.source}...')
        record(args.source, args.seconds, path)
    else:
        path = os.path.expanduser(args.source)

    v, a = flashes(path), beeps(path)
    offsets = []
    for t in v:
        nearest = min(a, key=lambda x: abs(x - t), default=None)
        if nearest is not None and abs(nearest - t) < 0.5:
            offsets.append((nearest - t) * 1000)
    if len(offsets) < 3:
        sys.exit(f'Only matched {len(offsets)} flash/beep pairs ({len(v)} flashes, {len(a)} beeps). Record longer or move the mic closer.')

    median = statistics.median(offsets)
    spread = statistics.pstdev(offsets)
    print(f'\nMatched {len(offsets)} flashes with beeps.')
    print(f'Audio is {abs(median):.0f} ms {"behind" if median > 0 else "ahead of"} the video '
          f'(steadiness: ±{spread:.0f} ms, range {min(offsets):.0f} to {max(offsets):.0f} ms).')
    print('Measurement precision is about ±20 ms, from screen and speaker latency on this Mac.\n')
    fix = round(abs(median) / 5) * 5
    if fix < 20:
        print('That is within what viewers can notice. No change needed.')
    elif median > 0:
        print(f'Fix in OBS: add a "Render Delay" filter of {fix} ms to this camera\'s source, which holds the video back.')
        print(f'Or on the Pi: set AV_SYNC=-{fix * 1000} in /etc/ftc-cam.env, then sudo systemctl restart ftc-cam.')
    else:
        print(f'Fix in OBS: set this camera\'s Sync Offset to {fix} ms in Advanced Audio Properties.')
        print(f'Or on the Pi: set AV_SYNC={fix * 1000} in /etc/ftc-cam.env, then sudo systemctl restart ftc-cam.')
    if spread > 25:
        print('The offset varies more than usual between flashes; check that the Mac is not overloaded and run it again.')


if __name__ == '__main__':
    main()
