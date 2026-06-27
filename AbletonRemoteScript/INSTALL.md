# SessionPad Remote Script — Installation Guide

## Prerequisites

- Ableton Live 11 or 12 (Standard or Suite)
- **SessionPad Bridge** — must be running on the computer hosting Ableton Live
  - **macOS:** Swift menu-bar app (SessionPadBridge Xcode target)
  - **Windows:** Python bridge or `SessionPadBridge.exe` (see [Windows setup](#windows-setup))
- iPhone or iPad with the SessionPad app installed
- Both devices on the **same Wi-Fi network**

---

## Architecture

```
Ableton Live (Remote Script) ←→ SessionPad Bridge ←→ SessionPad (iOS)
         localhost:17345              Wi-Fi :17346 + mDNS
```

---

## macOS setup

### Quick install (Remote Script)

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

### Step 1: Install SessionPad Bridge (Mac)

1. Build and run the **SessionPadBridge** target from Xcode.
2. Launch **SessionPad Bridge** — a colored dot appears in the menu bar.
3. Keep it running whenever you use SessionPad.

> Allow **incoming network connections** when macOS prompts.

### Step 2: Install the Remote Script

**Option A — install script (recommended):**

```bash
./install.sh
```

**Option B — manual copy:**

Copy the `SessionPad` folder to:

```
~/Music/Ableton/User Library/Remote Scripts/SessionPad/
```

### Step 3: Configure Ableton Live

1. **Launch SessionPad Bridge first** (menu bar should show “Waiting for Ableton Live”).
2. Launch Ableton Live (or restart if already open).
3. Go to **Live → Preferences → Link, Tempo & MIDI**.
4. Under **Control Surfaces**, select **SessionPad** (Input/Output = None).
5. Use **only one** SessionPad entry if you see duplicates.
6. Bridge menu should show **Live connected** (yellow/green dot).

### Step 4: Connect from the iOS App

1. Same Wi-Fi as your Mac.
2. Open SessionPad — it discovers the bridge automatically.
3. Allow **Local Network** permission when prompted.

**Manual connect (if Bonjour fails):** After ~15 seconds, enter your Mac's IP and port **17346**.

---

## Windows setup

### Step 1: Install SessionPad Bridge (Windows)

**Option A — Python (development / from source):**

```powershell
cd "path\to\SessionPad 2\bridge"
python -m venv .venv
.\.venv\Scripts\Activate.ps1
pip install -r requirements.txt
python -m sessionpad_bridge
```

**Option B — standalone executable:**

Build or download `SessionPadBridge.exe` (see [bridge/README.md](../bridge/README.md)) and run it before opening Ableton Live.

> Allow **SessionPad Bridge** through Windows Defender Firewall on your **private** network when prompted.

### Step 2: Install the Remote Script

From PowerShell:

```powershell
cd "path\to\SessionPad 2\AbletonRemoteScript"
.\install.ps1
```

This copies the script to:

```
%USERPROFILE%\Documents\Ableton\User Library\Remote Scripts\SessionPad\
```

### Step 3: Configure Ableton Live

1. **Launch SessionPad Bridge first** (console should show “Waiting for Ableton Live”).
2. Launch Ableton Live (or restart if already open).
3. Go to **Options → Preferences → Link, Tempo & MIDI**.
4. Under **Control Surfaces**, select **SessionPad** (Input/Output = None).
5. Use **only one** SessionPad entry if you see duplicates.
6. Bridge console should show **Live connected** (yellow/green status).

### Step 4: Connect from the iOS App

1. Same Wi-Fi as your Windows PC.
2. Open SessionPad — it discovers the bridge via mDNS/Bonjour.
3. Allow **Local Network** permission when prompted.

**Manual connect (if mDNS fails):** After ~15 seconds, enter your PC's IP address and port **17346**.

To find your PC's IP: **Settings → Network & Internet → Wi-Fi → your network → IPv4 address**.

---

## Remote Script folder contents

The installed folder must contain at minimum:

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

> **Do not** install into the Ableton application folder unless you need a one-off test — app updates can wipe it. Use the User Library path above.

---

## Verify in Ableton Log.txt

**macOS:**

```
~/Library/Preferences/Ableton/Live 12.x/Log.txt
```

**Windows:**

```
%APPDATA%\Ableton\Live 12.x\Preferences\Log.txt
```

You should see lines like:

```
SessionPad: Remote Script loaded — connect SessionPad Bridge on this Mac
SessionPad: bridge connected on localhost:17345
SessionPad: state sent rev=1 tracks=... scenes=... clips=...
```

If you see `RemoteScriptError` or `TypeError`, re-run the install script and restart Live.

---

## Troubleshooting

**Bridge shows red / waiting for Live:**
- Bridge must run **before** Live connects.
- Select SessionPad control surface in Live Preferences.
- Toggle control surface off/on or restart Live.

**App cannot find bridge:**
- SessionPad Bridge running?
- Same Wi-Fi, not guest network.
- Firewall: allow SessionPad Bridge (macOS or Windows).
- Manual connect: host IP + port **17346**.

**Connected but empty grid:**
- Check Log.txt for `SessionPad: state sent` — if missing, script crashed; re-run install script.
- Bridge must show “Live connected”.

---

## Supported Versions

| Platform | Version |
|---|---|
| Ableton Live | 11.x, 12.x |
| macOS (Swift bridge) | 12+ |
| Windows (Python bridge) | 10+ |
| iOS / iPadOS | 16.0+ |
