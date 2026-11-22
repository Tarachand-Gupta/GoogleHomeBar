# GoogleHomeBar

A native macOS menu bar utility for controlling Google Home devices whenever you're on Wi-Fi.

## What It Combines

- **Google Home tab (`home.google.com`):** Persistent Google sign-in inside a long-lived `WKWebView` (zero reload on popover reopen) with quick jump buttons for **Devices**, **Cameras**, and **Automations**, zoom controls, and a detachable full-size window.
- **Speakers & TVs tab (Native Local Wi-Fi CastV2):** Automatic Bonjour/mDNS (`_googlecast._tcp`) discovery on your Wi-Fi with direct TLS CastV2 control over Nest speakers, Nest Hubs, Chromecasts, Google TVs, and speaker groups — live volume sliders, mute, play/pause/skip, album artwork, stop casting, and master Mute All / Stop All actions.
- **Wi-Fi Gating:** Automatically activates on Wi-Fi and pauses offline, with an optional **Home Wi-Fi Only** mode supporting both SSID matching (with optional Location access) and zero-permission Home Cast device / LAN subnet matching, plus a one-click session override.

## Build & Run

```bash
cd GoogleHomeBar
chmod +x scripts/build-app.sh
./scripts/build-app.sh
open dist/GoogleHomeBar.app
```

Install into `/Applications`:

```bash
./scripts/build-app.sh --install
```

Run tests:

```bash
swift test
```
