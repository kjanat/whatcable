# WhatCable on Linux

WhatCable started as a macOS menu bar app built on IOKit. This document covers
the **Linux port**: a CLI (`whatcable`) and a browser-based GUI
(`whatcable-gui`) that read the equivalent data from the Linux kernel's USB
Type-C, USB Power Delivery, USB, power-supply, and Thunderbolt sysfs trees.

The platform-agnostic engine (`WhatCableCore`) is shared with macOS; only the
data source differs. On macOS the data comes from IOKit
(`WhatCableDarwinBackend`); on Linux it comes from sysfs
(`WhatCableLinuxBackend`). Both produce the same `CableSnapshot`, so the CLI's
text/JSON output and the diagnostics are identical across platforms.

## What works on Linux

| Capability | Source | Notes |
|---|---|---|
| Per-port headline (connected / data / display / Thunderbolt) | `/sys/class/typec/portN` | Derived from partner presence + active alt modes |
| Cable & partner e-marker (VID/PID, VDOs, PD revision) | `/sys/class/typec/portN-{cable,partner}/identity/` | sysfs VDO files map 1:1 onto WhatCable's Discover Identity model |
| Charger power profiles (PDO list) | `…/usb_power_delivery/source-capabilities/` | Fixed / variable / battery / PPS supplies |
| Charger summary (watts, voltage, current) | `/sys/class/power_supply/*` | Non-battery supply that is `online` |
| Attached USB devices + negotiated speed | `/sys/bus/usb/devices/*` | `speed` (Mbps) mapped to USB-IF speed tiers |
| Thunderbolt / USB4 routers | `/sys/bus/thunderbolt/devices/*` | Router identity + generation; per-adapter lane detail not exposed by sysfs |

### Known limitations vs macOS

These reflect what the Linux kernel exposes through stable sysfs, not gaps in
the engine:

- **Negotiated PDO ("winning" contract)** is not in sysfs (only `tcpm`
  debugfs, which is root-only and unstable), so the charger's *advertised*
  profiles are shown but not the live-selected one.
- **Thunderbolt per-lane/credit/bandwidth** detail isn't in sysfs, so the TB
  fabric view is router-level only.
- **DisplayPort EDID / link rate, USB3 transport, TRM, PHY** are not surfaced
  through the Type-C class; those `CableSnapshot` fields are left empty.
- **Per-port USB-device association**: Linux doesn't tie a USB device back to
  its Type-C port the way IOKit's `UsbIOPort` does, so the device list is
  global rather than nested under each port.

## Requirements

- **Swift 6.0 or newer.** The engine uses `String(localized:bundle:)`, which is
  available in the Swift 6 Foundation on Linux. Older toolchains
  (swift-corelibs-foundation) may not have it.
- **SQLite development headers** for the bundled cable database:
  - Debian/Ubuntu: `sudo apt-get install libsqlite3-dev`
  - Fedora: `sudo dnf install sqlite-devel`
  - Alpine: `sudo apk add sqlite-dev`
- A kernel with the **USB Type-C class** (`CONFIG_TYPEC`) exposing
  `/sys/class/typec`. Most modern laptops/boards with USB-C PD controllers do.

## Build

```bash
swift build -c release
```

This produces two executables under `.build/release/`:

- `whatcable-cli` — the command-line tool
- `whatcable-gui` — the local browser dashboard

Install them onto your `PATH`, e.g.:

```bash
sudo install -m 0755 .build/release/whatcable-cli /usr/local/bin/whatcable
sudo install -m 0755 .build/release/whatcable-gui /usr/local/bin/whatcable-gui
```

(The macOS product is named `whatcable-cli` and symlinked to `whatcable` by
Homebrew; the same convention is used here.)

## Usage

```bash
whatcable              # one-shot, human-readable
whatcable --json       # machine-readable JSON (same schema as macOS)
whatcable --watch      # live view, redraws on change (Ctrl+C to exit)
whatcable --raw        # include raw sysfs attributes per port
whatcable --report     # cable e-marker report (markdown + GitHub URL)
```

### GUI

```bash
whatcable-gui              # starts a local server and opens your browser
whatcable-gui --port 9000  # use a different port (default 8787)
whatcable-gui --no-open    # just print the URL (headless / SSH)
```

The GUI binds to `127.0.0.1` only and serves a page that auto-refreshes every
couple of seconds, showing the same per-port cards as the macOS popover. The
underlying JSON is available at `/snapshot.json`.

## Permissions

Reading sysfs generally needs no special privileges. A few attributes (some PD
capability nodes on certain drivers) are root-readable only; run with `sudo` if
a value you expect shows as missing. The GUI never needs root for the network
side — it only binds loopback.

## Architecture note

```
WhatCableCore  (shared engine: models, PortSummary, formatters, cable DB)
   ├── WhatCableDarwinBackend   (macOS: IOKit)        → CableSnapshot
   └── WhatCableLinuxBackend    (Linux: sysfs)        → CableSnapshot
          ↑ both conform to CableSnapshotProvider
WhatCableCLI       (both platforms; backend chosen at compile time)
WhatCableLinuxGUI  (Linux only; local web dashboard)
WhatCable / WhatCableAppKit / WidgetKit  (macOS only)
```

`Package.swift` selects the macOS or Linux target set with `#if os(macOS)`, so
`swift build` produces the right products on each platform with no extra flags.
