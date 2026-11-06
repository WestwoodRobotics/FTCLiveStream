<script lang="ts">
	import type Mpegts from 'mpegts.js';
	import { onMount } from 'svelte';

	let video: HTMLVideoElement;
	let player: Mpegts.Player;

	let interval: NodeJS.Timeout;
	let reconnectTimeout: NodeJS.Timeout;
	let fps = 30;

	let massiveMargin = false;
	let videoRotation = 180;

	onMount(async () => {
		const params = new URLSearchParams(location.search);
		const url = params.get('url');
		fps = +(params.get('fps') || fps);
		massiveMargin = params.get('mm') === 'true';
		videoRotation = +(params.get('rotate') ?? videoRotation);

		if (!url) {
			alert(`Please enter a URL in the "url" query parameter, e.g. "?url=http://ftc-cam1.local:8000/live.ts"`);
			window.close();
			return;
		}

		const mpegts = (await import('mpegts.js')).default;

		if (mpegts.isSupported()) {
			connect(mpegts, url);
			playPause();
		}
	});

	function connect(mpegts: typeof Mpegts, url: string) {
		player = mpegts.createPlayer(
			{
				type: 'mpegts',
				// Fetched through this page's server so the browser only talks to localhost (see vite.config.ts)
				url: new URL(`/relay?url=${encodeURIComponent(url)}`, location.origin).href,
				// hasAudio is left out so a camera with a mic plays sound and one without plays video only
				isLive: true
			},
			{
				enableStashBuffer: false
			}
		);

		// A camera reboot or dropped cable ends the stream, so keep retrying until it returns
		const reconnect = () => {
			clearTimeout(reconnectTimeout);
			reconnectTimeout = setTimeout(() => {
				player.destroy();
				connect(mpegts, url);
			}, 1000);
		};
		player.on(mpegts.Events.ERROR, reconnect);
		player.on(mpegts.Events.LOADING_COMPLETE, reconnect);

		player.attachMediaElement(video);
		player.load();
	}

	function playPause() {
		if (video.paused) {
			interval = setInterval(() => {
				// OBS plays sound automatically; a normal browser blocks unmuted autoplay, so fall back to muted
				player.play()?.catch((error: DOMException) => {
					if (error.name === 'NotAllowedError') video.muted = true;
				});
			}, 1);
		} else {
			clearInterval(interval);
			player.pause();
		}
	}

	function offset(frames: number) {
		video.requestVideoFrameCallback(() => {
			video.currentTime += (frames + 2) / fps;
		});
	}
</script>

<div id="frame">
	<div id="content">
		<!-- Browsers start the video muted until someone clicks, so a click on the video turns the sound on -->
		<!-- svelte-ignore a11y_click_events_have_key_events, a11y_media_has_caption -->
		<video
			bind:this={video}
			playsinline
			style:rotate="{videoRotation}deg"
			on:click={() => (video.muted = false)}
		></video>
		<button on:click={playPause} class:massive-margin={massiveMargin}>Play / Pause</button>
		<div>
			<button on:click={() => offset(-fps / 6)}>← {fps / 6} F</button>
			<button on:click={() => offset(-1)}>← 1 F</button>
			<button on:click={() => offset(1)}>1 F →</button>
			<button on:click={() => offset(fps / 6)}>{fps / 6} F →</button>
		</div>
		<div>
			<button on:click={() => offset(-fps)}>← {fps} F</button>
			<button on:click={() => offset(-fps / 3)}>← {fps / 3} F</button>
			<button on:click={() => offset(fps / 3)}>{fps / 3} F →</button>
			<button on:click={() => offset(fps)}>{fps} F →</button>
		</div>
	</div>
</div>

<style>
	:global(:root, body, *) {
		margin: 0;
	}

	:global(:root, body) {
		background-color: #0000;
	}

	#frame {
		width: 100vw;
		height: 100vh;
		display: flex;
		justify-content: left;
		align-items: top;

		#content {
			width: 100vw;
			display: flex;
			flex-direction: column;
			gap: 2vw;
			overflow: hidden;

			video {
				width: 100vw;
				height: calc(100vw / 16 * 9);
			}

			div {
				display: flex;
				gap: 2vw;
			}

			button {
				width: 100%;
				font-size: 2vw;
			}

			.massive-margin {
				margin-top: 12vw;
			}
		}
	}
</style>
