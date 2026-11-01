<script lang="ts">
	import { onMount } from 'svelte';
	import OBSWebSocket from 'obs-websocket-js';

	// config
	let obsMode: boolean = true;
	const RESULTS_DELAY_MS = 20_000;
	const TRANSITION_DURATION_MS = 1000;
	let WS_URL: string = '';
	let OBS_URL: string = '';
	let OBS_PASSWORD: string = '';
	
	// obs ws
	let obs: OBSWebSocket;

	// camera urls - editable via UI or preset via URL params
	let field1Url = $state('');
	let field2Url = $state('');

	// derived: are we in test mode (no urls) or live mode (urls provided)
	let isLive = $derived(field1Url.trim() !== '' && field2Url.trim() !== '');

	// cameras config
	const CAMERA_COLORS: Record<string, { color: string; label: string }> = {
		field1: { color: '#e74c3c', label: 'Current Division Field 1' },
		field2: { color: '#3498db', label: 'Current Division Field 2' }
	};

	// state
	let activeCamera = $state<string>('field1');
	let resultsShownAt: number | null = $state(null);
	let pendingSwitchTimeout: ReturnType<typeof setTimeout> | null = null;
	let timerDisplay = $state<number>(0);
	let logs = $state<string[]>([]);
	let cameraRefs: Record<string, HTMLElement | null> = {};
	let showPanel = $state(!obsMode);

	function addLog(msg: string) {
		const time = new Date().toLocaleTimeString();
		logs = [`[${time}] ${msg}`, ...logs.slice(0, 19)];
	}

	function msUntilResultsDelayExpires(): number {
		if (resultsShownAt === null) return 0;
		return Math.max(0, RESULTS_DELAY_MS - (Date.now() - resultsShownAt));
	}

	function updateTimerDisplay() {
		timerDisplay = Math.ceil(msUntilResultsDelayExpires() / 1000);
	}

	// does the actual camera switch with fade transition
	function switchTo(targetField: string) {
		addLog(`switchTo called: target=${targetField}, active=${activeCamera}`);

		obs.call('SetCurrentProgramScene', {sceneName: CAMERA_COLORS[targetField].label});

		if (targetField === activeCamera) {
			addLog(`Already on ${targetField}, skipping`);
			return;
		}
		if (!CAMERA_COLORS[targetField]) {
			addLog(`Unknown camera field: ${targetField}`);
			return;
		}

		addLog(`Switching: ${activeCamera} → ${targetField}`);

		const targetEl = cameraRefs[targetField];
		const currentEl = cameraRefs[activeCamera];

		// reset all to base z
		for (const key of Object.keys(CAMERA_COLORS)) {
			const el = cameraRefs[key];
			if (el) el.style.zIndex = '0';
		}

		// show new one underneath
		if (targetEl) {
			targetEl.style.transition = 'none';
			targetEl.style.zIndex = '1';
			targetEl.style.opacity = '1';
			void targetEl.offsetWidth;
		}

		// fade out current
		if (currentEl) {
			currentEl.style.zIndex = '2';
			currentEl.style.transition = `opacity ${TRANSITION_DURATION_MS}ms ease`;
			currentEl.style.opacity = '0';
		}

		// cleanup after fade
		setTimeout(() => {
			activeCamera = targetField;
			if (currentEl) currentEl.style.zIndex = '0';
			if (targetEl) targetEl.style.zIndex = '2';
		}, TRANSITION_DURATION_MS);
	}

	function handleSwitchWithDelay(targetField: string) {
		addLog(`handleSwitchWithDelay: target=${targetField}`);

		if (pendingSwitchTimeout !== null) {
			clearTimeout(pendingSwitchTimeout);
			pendingSwitchTimeout = null;
			addLog('Cleared pending switch');
		}

		const delay = msUntilResultsDelayExpires();
		addLog(`Delay remaining: ${delay}ms`);

		if (delay === 0) {
			switchTo(targetField);
		} else {
			addLog(`Waiting ${Math.ceil(delay / 1000)}s before switching to ${targetField}`);
			pendingSwitchTimeout = setTimeout(() => {
				addLog(`Delayed switch executing now to ${targetField}`);
				switchTo(targetField);
				pendingSwitchTimeout = null;
			}, delay);
		}
	}

	// for test panel - broadcast to all tabs so they stay in sync
	let wsRef: WebSocket | null = null;
	let broadcastChannel: BroadcastChannel | null = null;

	function sendMessage(type: string) {
		// // send via websocket if connected (server will broadcast to all WS clients)
		// if (wsRef && wsRef.readyState === WebSocket.OPEN) {
		// 	wsRef.send(JSON.stringify({ type, field: getOtherField().replace('field', '') }));
		// 	addLog(`Sent via WS: ${type}`);
		// } else {
		// 	// no websocket - broadcast to other tabs and handle locally
		broadcastChannel?.postMessage({ type, source: 'local' });
		addLog(`Broadcast: ${type}`);
		handleMessageType(type, getOtherField());
		// }
	}

	// get the other field (not currently active)
	function getOtherField(): string {
		const fields = Object.keys(CAMERA_COLORS);
		return fields.find((f) => f !== activeCamera) ?? fields[0];
	}

	// core message handling logic
	function handleMessageType(msgType: string, field?: string) {
		switch (msgType) {
			case 'SHOW_RESULTS':
				resultsShownAt = Date.now();
				addLog('Timer started (20s)');
				break;

			case 'SHOW_PREVIEW':
			case 'SHOW_RANDOM':
				handleSwitchWithDelay(isLive ? field || getOtherField() : getOtherField());
				break;

			case 'SHOW_MATCH':
			case 'START_MATCH':
				if (pendingSwitchTimeout !== null) {
					clearTimeout(pendingSwitchTimeout);
					pendingSwitchTimeout = null;
					addLog('Cancelled pending switch');
				}
				resultsShownAt = null;
				switchTo(isLive ? field || getOtherField() : getOtherField());
				break;

			default:
				break;
		}
	}

	// handle WebSocket message - parse and broadcast to other tabs
	function handleWsMessage(event: MessageEvent) {
		let data: { type?: string; field?: string };
		try {
			data = typeof event.data === 'string' ? JSON.parse(event.data) : event.data;
		} catch {
			return;
		}
		if (!data.type) return;

		// broadcast to other tabs
		broadcastChannel?.postMessage({ type: data.type, source: 'ws' });
		handleMessageType(data.type, `field${data.field}`);
	}

	// handle BroadcastChannel message from another tab
	function handleBroadcastMessage(event: MessageEvent) {
		const data = event.data as { type?: string; source?: string };
		if (!data.type) return;
		addLog(`From other tab: ${data.type}`);
		handleMessageType(data.type);
	}

	function connectWs() {
		try {
			wsRef = new WebSocket(WS_URL);
		} catch (e) {
			addLog('WebSocket connection failed');
			console.warn('WebSocket connection failed', e);
			return;
		}

		wsRef.addEventListener('open', () => {
			addLog('WebSocket connected to ' + WS_URL);
		});
		wsRef.addEventListener('message', (e) => {
			addLog('WS message: ' + e.data);
			handleWsMessage(e);
		});
		wsRef.addEventListener('error', (e) => {
			addLog('WebSocket error');
			console.error('WebSocket error', e);
		});
		wsRef.addEventListener('close', () => {
			addLog('WebSocket closed, reconnecting...');
			wsRef = null;
			setTimeout(connectWs, 1000);
		});
	}

	function initCameras() {
		for (const key of Object.keys(CAMERA_COLORS)) {
			const el = cameraRefs[key];
			if (el) {
				el.style.opacity = key === activeCamera ? '1' : '0';
				el.style.zIndex = key === activeCamera ? '2' : '0';
			}
		}
	}

	onMount(async () => {
		const urlParams = new URLSearchParams(location.search);
		obsMode = urlParams.get('obs') === 'true';
		field1Url = decodeURIComponent(urlParams.get('field1') ?? 'about:blank');
		field2Url = decodeURIComponent(urlParams.get('field2') ?? 'about:blank');
		WS_URL = urlParams.get('ws') ?? '';
		OBS_URL = urlParams.get('obsUrl') ?? 'ws://localhost:4455';
		OBS_PASSWORD = urlParams.get('obsPassword') ?? '';
		CAMERA_COLORS['field1'].label = urlParams.get('field1') ?? CAMERA_COLORS['field1'].label;
		CAMERA_COLORS['field2'].label = urlParams.get('field2') ?? CAMERA_COLORS['field2'].label;

		obs = new OBSWebSocket();
		
		try {
			const { obsWebSocketVersion, negotiatedRpcVersion } = await obs.connect(
				OBS_URL,
				OBS_PASSWORD,
				{
					rpcVersion: 1
				}
			);
			console.log(`Connected to server ${obsWebSocketVersion} (using RPC ${negotiatedRpcVersion})`);
		} catch (error: any) {
			console.error('Failed to connect', error.code, error.message);
		}

		// init cameras after a short delay to ensure refs are bound
		setTimeout(initCameras, 100);

		setInterval(updateTimerDisplay, 100);

		// broadcast channel for syncing across tabs
		broadcastChannel = new BroadcastChannel('ftc-switcher');
		broadcastChannel.addEventListener('message', handleBroadcastMessage);

		// keyboard shortcut to toggle panel
		function handleKeydown(e: KeyboardEvent) {
			if (e.key === '.') {
				e.preventDefault();
				showPanel = !showPanel;
			}
		}
		window.addEventListener('keydown', handleKeydown);

		// websocket connection - only if ws param is provided
		if (WS_URL) connectWs();

		addLog(
			'Switcher initialized' + (isLive ? '' : ' (TEST MODE)') + (WS_URL ? '' : ' - no WebSocket')
		);

		// return () => {
		// 	wsRef?.close();
		// 	broadcastChannel?.close();
		// 	clearInterval(timerInterval);
		// 	window.removeEventListener('keydown', handleKeydown);
		// 	if (pendingSwitchTimeout !== null) clearTimeout(pendingSwitchTimeout);
		// };
	});
</script>

<div class="camera-container">
	<!-- field1 (starts visible) -->
	{#if isLive}
		<iframe
			bind:this={cameraRefs['field1']}
			class="camera-iframe"
			style="opacity: 1; z-index: 2;"
			src={field1Url}
			title="Camera field1"
			allow="autoplay; fullscreen"
			frameborder="0"
		></iframe>
	{:else}
		<div
			bind:this={cameraRefs['field1']}
			class="camera-placeholder"
			style="opacity: 1; z-index: 2;"
			style:background-color={CAMERA_COLORS['field1'].color}
		>
			<span class="camera-label">{CAMERA_COLORS['field1'].label}</span>
		</div>
	{/if}

	<!-- field2 (starts hidden) -->
	{#if isLive}
		<iframe
			bind:this={cameraRefs['field2']}
			class="camera-iframe"
			style="opacity: 0; z-index: 0;"
			src={field2Url}
			title="Camera field2"
			allow="autoplay; fullscreen"
			frameborder="0"
		></iframe>
	{:else}
		<div
			bind:this={cameraRefs['field2']}
			class="camera-placeholder"
			style="opacity: 0; z-index: 0;"
			style:background-color={CAMERA_COLORS['field2'].color}
		>
			<span class="camera-label">{CAMERA_COLORS['field2'].label}</span>
		</div>
	{/if}
</div>

{#if showPanel}
	<div class="control-panel">
		<b>Camera Switcher</b> <small style="color: #888">(Tab to hide)</small>
		<hr />
		<div>
			<label
				>Field 1 URL:<br />
				<input type="text" bind:value={field1Url} placeholder="https://..." style="width: 250px" />
			</label>
		</div>
		<div>
			<label
				>Field 2 URL:<br />
				<input type="text" bind:value={field2Url} placeholder="https://..." style="width: 250px" />
			</label>
		</div>
		<div style="margin-top: 5px; color: {isLive ? 'green' : 'gray'}">
			{isLive ? '● Live mode' : '○ Test mode (add URLs to go live)'}
		</div>
		<hr />
		<div>
			Active: {activeCamera} | Timer: {timerDisplay > 0 ? `${timerDisplay}s` : 'Off'}
		</div>
		<hr />
		<div>
			<button onclick={() => sendMessage('SHOW_RESULTS')}>SHOW_RESULTS</button>
			<button onclick={() => sendMessage('SHOW_PREVIEW')}>SHOW_PREVIEW</button>
			<button onclick={() => sendMessage('SHOW_RANDOM')}>SHOW_RANDOM</button>
			<button onclick={() => sendMessage('SHOW_MATCH')}>SHOW_MATCH</button>
			<button onclick={() => sendMessage('START_MATCH')}>START_MATCH</button>
		</div>
		<hr />
		<div>Log:</div>
		<pre class="log-box">{logs.join('\n')}</pre>
	</div>
{/if}

<style>
	:global(:root, body) {
		margin: 0;
		padding: 0;
		background: #0000;
	}

	.camera-container {
		position: relative;
		width: 100vw;
		height: 100vh;
		overflow: hidden;
		background: #000;
	}

	.camera-iframe,
	.camera-placeholder {
		position: absolute;
		inset: 0;
		width: 100%;
		height: 100%;
		border: none;
		opacity: 0;
	}

	.camera-placeholder {
		display: flex;
		align-items: center;
		justify-content: center;
	}

	.camera-label {
		font-size: 4rem;
		font-weight: bold;
		color: white;
		text-shadow: 0 2px 10px rgba(0, 0, 0, 0.5);
	}

	.control-panel {
		position: fixed;
		top: 10px;
		right: 10px;
		background: white;
		border: 1px solid #ccc;
		padding: 10px;
		font-family: sans-serif;
		font-size: 12px;
		z-index: 9999;
		max-width: 320px;
	}

	.control-panel button {
		margin: 2px;
	}

	.control-panel input {
		margin: 3px 0;
	}

	.log-box {
		background: #f0f0f0;
		border: 1px solid #ccc;
		padding: 5px;
		font-size: 10px;
		max-height: 150px;
		overflow-y: auto;
		white-space: pre-wrap;
		word-break: break-all;
	}
</style>
