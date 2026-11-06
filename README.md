# 📹 FTCLiveStream 🔴

A **reimagined** live experience, designed by roboticists for **everyone**.  
presented by **20240 Slingshot**

> [!NOTE]
> 🚧 This project is in development. Please check back for more information.

> [!WARNING]
> This is the **BioBuzz** branch. Please ensure you are on the right branch.

## Setup

### Prerequisites

- A Mac running OBS, with [Bun](https://bun.sh) installed.
- FTC Live 8.0.3 or newer (BIOBUZZ).
- Raspberry Pi 5 cameras, a PoE switch, and a USB Ethernet adapter for the Mac. Camera setup is in [pi/README.md](pi/README.md).

### One-time setup

```sh
bun run setup
```

This installs each app's dependencies from its lockfile. It also gives each of the Mac's wired Ethernet adapters a fixed address on the camera network, 10.0.100.0/24, next to its normal address. The cameras then stay at the same addresses on any network. Run it again after plugging in a new Ethernet adapter.

Then set up each camera once, following [pi/README.md](pi/README.md).

### At the event

1. Plug the cameras and the Mac into the PoE switch, and the switch into the scoring router.
2. Join the venue Wi-Fi for internet, and keep Wi-Fi first in the Mac's network service order.
3. Get the FTC Live address and event code from the scoring computer, then run:

   ```sh
   bun run start <ftclive-host[:port]> <event-code> "<region>" "<level>"
   ```

4. Fix anything the checks mark FAIL, then paste the printed URLs into OBS browser sources. On camera sources with a mic, check "Control audio via OBS".
5. Leave the terminal open. It beeps when a camera or FTC Live drops.

OBS needs Local Network access to reach FTC Live, under System Settings, Privacy & Security, Local Network. The camera pages don't, because the `cam` app relays each stream through localhost.

### Apps

Each app (`overlays`, `cam`, `switcher`) is its own SvelteKit package. `bun run start` launches all three; `bun run dev` inside one launches just that app.

| App | Port | URL parameters |
| --- | --- | --- |
| `overlays` | 5173 | `host` (FTC Live `host:port`), `code` (event code), `region`, `level` |
| `cam` | 23456 | `url` (camera stream), `fps`, `rotate` (degrees, default `180`), `mm` |
| `switcher` | 17113 | `ws` (FTC Live display socket), `field1`, `field2`, `obs`, `obsUrl`, `obsPassword` |

### Security

- No passwords or keys live in this repo. Pi logins come from the user you create when flashing each card, and SSH asks for the password each time.
- The `cam` and `overlays` pages listen on localhost only. The `cam` relay only forwards `http://` camera streams ending in `.ts`, so it can't fetch other pages.
- The `switcher` listens on every network interface so a second device can control it. Pass an OBS WebSocket password with `obsPassword` and keep OBS WebSocket authentication on.
- Camera streams are unencrypted and unauthenticated on the camera network. Keep cameras on the PoE switch, not on public Wi-Fi.

## Design

Our custom overlays are designed with every viewer in mind. From the first-time parents to the seasoned FTC members, we aimed to maximize accessibility with our overlays.

Efficiency sits at the core of our design. Every icon has been crafted or selected to best represent their respective labels while maintaining simplicity. We didn't cheap out on features, however, as we also focused on information density. Our custom design is able to display significantly more critical game-related information while covering up less of the frame, providing for a superior viewing experience.

The result is a library of WebP images scaled for 4K resolution. Every asset, as well as mock-ups, are publicly available and viewable through [Sketch](https://sketch.com/s/18e172c0-7dc7-40a2-8038-ae110b2ddd0c). The designs are licensed under the same license and copyright as this repository.

## Legal

### Disclaimer

*FIRST*®, *FIRST*® Tech Challenge, FTC®, *FIRST*® CANOPY™, BIOBUZZ™, and all accompanying logos as they are created, are trademarks of For Inspiration and Recognition of Science and Technology (*FIRST*®) (www.firstinspires.org). These trademarks are used by special permission of _FIRST_ which is not overseeing, involved with, or responsible for this activity, product, or service. © 2026 *FIRST*®. Used by special permission. All rights reserved.

### Copyright

© 2026-2027 FRC Team 2583 Orange Dynamite and Contributors. [MIT License](LICENSE).
