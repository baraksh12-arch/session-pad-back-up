# SessionPad Remote Script — Installation Guide

## Prerequisites

- Ableton Live 11 or 12 (Standard or Suite)
- macOS 12+
- **SessionPad Bridge** macOS app (menu bar companion) — must be running
- iPhone or iPad with the SessionPad app installed
- Both devices on the **same Wi-Fi network**

---

## Quick install (recommended)

From Terminal:

```bash
cd "/path/to/SessionPad 2/AbletonRemoteScript"
chmod +x install.sh
./install.sh
```

This copies the script to:

```
~/Music/Ableton/User Library/Remote Scripts/SessionPad/
```

This location survives Live updates (unlike copying into the app bundle).

---

## Step 1: Install SessionPad Bridge (Mac)

1. Build and run the **SessionPadBridge** target from Xcode.
2. Launch **SessionPad Bridge** — a colored dot appears in the menu bar.
3. Keep it running whenever you use SessionPad.

> Allow **incoming network connections** when macOS prompts.

---

## Step 2: Install the Remote Script

**Option A — install script (recommended):**

```bash
./install.sh
```

**Option B — manual copy:**

Copy the `SessionPad` folder to:

```
~/Music/Ableton/User Library/Remote Scripts/SessionPad/
```

The folder must contain at minimum:

```
SessionPad/
├── __init__.py
├── SessionPad.py
├── Protocol.py
├── CommandHandler.py
├── ClipListener.py
├── TrackListener.py
├── SceneListener.py
├── TransportListener.py
└── transport/
    ├── __init__.py
    └── LiveBridgeClient.py
```

> **Do not** install into the Ableton `.app` bundle unless you need a one-off test — app updates can wipe it. Use the User Library path above.

---

## Step 3: Configure Ableton Live

1. **Launch SessionPad Bridge first** (menu bar should show “Waiting for Ableton Live”).
2. Launch Ableton Live (or restart if already open).
3. Go to **Live → Preferences → Link, Tempo & MIDI**.
4. Under **Control Surfaces**, select **SessionPad** (Input/Output = None).
5. Use **only one** SessionPad entry if you see duplicates.
6. Bridge menu should show **Live connected** (yellow/green dot).

---

## Step 4: Connect from the iOS App

1. Same Wi-Fi as your Mac.
2. Open SessionPad — it discovers the bridge automatically.
3. Allow **Local Network** permission when prompted.

### Manual connect (if Bonjour fails)

After ~15 seconds, enter your Mac's IP and port **17346**.

---

## Verify in Ableton Log.txt

Open:

```
~/Library/Preferences/Ableton/Live 12.x/Log.txt
```

You should see lines like:

```
SessionPad: Remote Script loaded — connect SessionPad Bridge on this Mac
SessionPad: bridge connected on localhost:17345
SessionPad: state sent rev=1 tracks=... scenes=... clips=...
```

If you see `RemoteScriptError` or `TypeError`, re-run `./install.sh` and restart Live.

---

## Architecture

```
Ableton Live (Remote Script) ←→ SessionPad Bridge (Mac) ←→ SessionPad (iOS)
         localhost:17345              Wi-Fi :17346
```

---

## Troubleshooting

**Bridge shows red (waiting for Live):**
- Bridge must run **before** Live connects.
- Select SessionPad control surface in Live Preferences.
- Toggle control surface off/on or restart Live.

**App cannot find bridge:**
- SessionPad Bridge running? (menu bar dot)
- Same Wi-Fi, not guest network.
- macOS Firewall: allow SessionPad Bridge.
- Manual connect: Mac IP + port 17346.

**Connected but empty grid:**
- Check Log.txt for `SessionPad: state sent` — if missing, script crashed; re-run `install.sh`.
- Bridge must show “Live connected”.

---

## Supported Versions

| Platform | Version |
|---|---|
| Ableton Live | 11.x, 12.x |
| macOS | 12+ |
| iOS / iPadOS | 16.0+ |
