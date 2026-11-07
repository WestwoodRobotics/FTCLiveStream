# Raspberry Pi cameras

Each camera is a Raspberry Pi 5 with a camera module and a PoE HAT. It streams 1080p30 H.264 over HTTP at `http://<address>:8000/live.ts`, with audio when a USB mic is plugged in. Any number of viewers can watch one camera.

## Set up a camera

Do this once per camera, at home or anywhere the Pi can reach the internet. Run `bun run setup` on the Mac first; see the main [README](../README.md).

1. **Flash the card** with [Raspberry Pi Imager](https://www.raspberrypi.com/software/). Choose Raspberry Pi 5 and Raspberry Pi OS (64-bit). In the customization settings, set the hostname (for example `live0`), create a username and password, and turn on SSH. Wi-Fi isn't needed.
2. **Boot it on a network with internet.** Plug it into the PoE switch, with the switch connected to a router. The first boot takes about 3 minutes.
3. **Run setup from the Mac**, in the repo folder, using the username you created:

   ```sh
   pi/push-setup.sh <user>@live0.local live0 10.0.100.20/24
   ```

   It asks for the Pi's password twice: once to log in and once for `sudo`. It reboots the Pi and waits until the stream comes up at its fixed address, then prints an OK line.

4. **Repeat for each camera** with the next name and address, such as `live1` and `10.0.100.21/24`.

You don't need to repeat this at events. The fixed address and settings stay on the card. Rerun it only after reflashing a card, or to install updated files from this folder. Once a Pi has its fixed address, point the command at that address instead:

```sh
pi/push-setup.sh <user>@10.0.100.20 live0 10.0.100.20/24
```

## What setup changes on the Pi

- Installs `rpicam-apps`, `python3`, and `alsa-utils` if they're missing.
- Sets the hostname and gives `eth0` a fixed address with no DHCP, so the camera never depends on the venue's router.
- Turns off Wi-Fi and Bluetooth, so the camera is only reachable over Ethernet.
- Lets the PoE HAT supply full USB power.
- Installs the `ftc-cam` service, which starts the stream on boot and restarts it if it stops.

If you're logged in to the Pi already, you can run the same setup directly with `sudo ./setup.sh <hostname> [static-ip/prefix] [gateway]`.

## Settings

Camera settings live in `/etc/ftc-cam.env` on each Pi. After editing, run `sudo systemctl restart ftc-cam`.

| Setting | Default | Meaning |
| --- | --- | --- |
| `WIDTH`, `HEIGHT`, `FPS` | 1920, 1080, 30 | Resolution and frame rate |
| `BITRATE` | 8000000 | Video bitrate in bits per second |
| `INTRA` | 30 | Frames between keyframes; a new viewer starts within this many frames |
| `ROTATION` | 0 | 0 or 180. Prefer the cam page's `rotate` parameter |
| `FOCUS_ARGS` | continuous autofocus | Camera Module 3 only; remove for the HQ or Global Shutter camera |
| `AUDIO` | `auto` | `auto` adds a USB mic's audio to the stream; `off` streams video only |
| `AUDIO_BITRATE` | 128000 | AAC audio bitrate in bits per second |
| `AV_SYNC` | 0 | Shifts audio against video, in microseconds; negative plays audio earlier. Usually easier to fix in OBS instead; see below |

## Audio

Plug a USB mic into one of the four rectangular USB ports before the Pi powers on. The USB-C port only takes power. At startup, the camera makes a one-second test recording. If it works, the mic's audio goes into the stream; otherwise the camera streams video only. To pick up a mic plugged in later, restart the Pi by unplugging its Ethernet for a few seconds.

A mic with a 3.5 mm or XLR plug needs a USB sound adapter or audio interface. To check whether the Pi sees a mic, run `lsusb` and `arecord -l` on it.

## Audio and video sync

With an Apple USB-C to 3.5 mm adapter as the mic input, audio and video drifted apart by only about 4 ms per hour, so a setting made at the start of an event holds all day. A fixed offset between them is normal, and `tools/av-sync.py` measures it:

1. Point the camera at the Mac's screen, with its mic near the Mac's speakers and the volume up.
2. Run `python3 tools/av-sync.py 10.0.100.20` from the repo folder. Click the page it opens, make it full screen, and press Enter in the terminal.
3. Apply what it prints. When audio is behind, add a Render Delay filter of that many milliseconds to the camera's source in OBS. When audio is ahead, set the source's Sync Offset in Advanced Audio Properties.

Restart the Pi and run it again to confirm the result holds. To include OBS's own delay, run it with `--page-only`, record 30 seconds in OBS, and pass the recording instead of an address. It needs `ffmpeg`.

In OBS, keep "Shutdown source when not visible" and "Refresh browser when scene becomes active" off on camera sources. Either one reconnects the camera and can change the offset.

## Troubleshooting

- **"Remote host identification has changed"** after reflashing a card: the card has a new SSH key. Remove the old one with `ssh-keygen -R live0.local`, then run the command again.
- **The Pi doesn't show up:** check that its PoE light is on and that the switch can power every camera at once. On some switches, an "Extend" mode limits ports to 10 Mbps and isolates them; turn it off.
- **The stream has no sound:** see the audio checks above. The log shows what the camera found at startup: `journalctl -u ftc-cam -b`.
