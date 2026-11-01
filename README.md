# 📹 FTCLiveStream 🔴

A **reimagined** live experience, designed by roboticists for **everyone**.  
presented by **20240 Slingshot**

> [!NOTE]
> 🚧 This project is in development. Please check back for more information.

> [!WARNING]
> This is the **development** branch. Please ensure you are on the right branch.

## Development

### Prerequisites

[Bun](https://bun.sh) and FTC Live 8.0.3 or newer (BIOBUZZ). Camera setup for Raspberry Pi 5 is in [pi/README.md](pi/README.md).

### Project Setup

Each app (`overlays`, `cam`, `switcher`) is its own package:

```sh
cd overlays
bun install
bun run dev
```

| App | URL parameters |
| --- | --- |
| `overlays` | `host` (FTC Live `host:port`), `code` (event code), `region`, `level` |
| `cam` | `url` (camera stream), `fps`, `rotate` (degrees, default `180`), `mm` |
| `switcher` | `ws` (FTC Live display socket), `field1`, `field2`, `obs`, `obsUrl`, `obsPassword` |


## Design

Our custom overlays are designed with every viewer in mind. From the first-time parents to the seasoned FTC members, we aimed to maximize accessibility with our overlays.

Efficiency sits at the core of our design. Every icon has been crafted or selected to best represent their respective labels while maintaining simplicity. We didn't cheap out on features, however, as we also focused on information density. Our custom design is able to display significantly more critical game-related information while covering up less of the frame, providing for a superior viewing experience.

The result is a library of WebP images scaled for 4K resolution. Every asset, as well as mock-ups, are publicly available and viewable through [Sketch](https://sketch.com/s/18e172c0-7dc7-40a2-8038-ae110b2ddd0c). The designs are licensed under the same license and copyright as this repository.

## Legal

### Disclaimer

*FIRST*®, *FIRST*® Tech Challenge, FTC®, *FIRST*® CANOPY™, BIOBUZZ™, and all accompanying logos as they are created, are trademarks of For Inspiration and Recognition of Science and Technology (*FIRST*®) (www.firstinspires.org). These trademarks are used by special permission of _FIRST_ which is not overseeing, involved with, or responsible for this activity, product, or service. © 2026 *FIRST*®. Used by special permission. All rights reserved.

### Copyright

© 2025-2026 FTC Team 20240 Slingshot and Contributors. [MIT License](LICENSE).
