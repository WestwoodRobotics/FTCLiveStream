import { sveltekit } from '@sveltejs/kit/vite';
import { defineConfig, type Plugin } from 'vite';
import http, { type IncomingMessage, type ServerResponse } from 'node:http';

// macOS blocks Brave and OBS from reaching devices on the local network unless each app has been
// granted Local Network access. Relaying the camera stream through this server means the page only
// ever talks to localhost, so the feed works whether or not that permission is on.
function relayCamera(req: IncomingMessage, res: ServerResponse) {
	let target: URL;
	try {
		target = new URL(new URL(req.url ?? '', 'http://localhost').searchParams.get('url') ?? '');
	} catch {
		res.statusCode = 400;
		res.end('Expected ?url=http://<camera>:8000/live.ts');
		return;
	}
	// Only camera streams, so this cannot be used to fetch arbitrary pages
	if (target.protocol !== 'http:' || !target.pathname.endsWith('.ts')) {
		res.statusCode = 400;
		res.end('Only http:// camera streams ending in .ts can be relayed');
		return;
	}

	const upstream = http.get(target, (camera) => {
		res.writeHead(camera.statusCode ?? 502, {
			'Content-Type': camera.headers['content-type'] ?? 'video/mp2t',
			'Cache-Control': 'no-store'
		});
		camera.pipe(res);
	});
	// The camera sends constantly, so a silent connection means it is gone; the page then reconnects
	upstream.setTimeout(5000, () => upstream.destroy());
	upstream.on('error', () => {
		if (!res.headersSent) res.statusCode = 502;
		res.end();
	});
	res.on('close', () => upstream.destroy());
}

const cameraRelay: Plugin = {
	name: 'camera-relay',
	configureServer(server) {
		server.middlewares.use('/relay', relayCamera);
	},
	configurePreviewServer(server) {
		server.middlewares.use('/relay', relayCamera);
	}
};

export default defineConfig({
	plugins: [cameraRelay, sveltekit()]
});
