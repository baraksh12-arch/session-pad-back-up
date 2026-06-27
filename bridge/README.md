# SessionPad Bridge (Python)

Cross-platform relay between **Ableton Live** (Remote Script over localhost TCP) and **SessionPad** on iPhone/iPad (WebSocket + mDNS). Use this bridge on **Windows** (or anywhere you prefer Python over the macOS Swift menu-bar app).

## Architecture

```
Ableton Live (Remote Script) ←→ SessionPad Bridge (Python) ←→ SessionPad (iOS)
         localhost:17345              Wi-Fi :17346 + mDNS
```

The macOS Swift bridge (`SessionPadBridge` Xcode target) is unchanged and remains the recommended option on Mac.

## Requirements

- Python 3.10+
- Ableton Live 11 or 12 with the SessionPad Remote Script installed
- iPhone/iPad with SessionPad on the **same Wi-Fi network**

## Quick start

```bash
cd bridge
python3 -m venv .venv

# macOS / Linux
source .venv/bin/activate

# Windows (PowerShell)
# .\.venv\Scripts\Activate.ps1

pip install -r requirements.txt
python -m sessionpad_bridge
```

Keep the bridge running, then:

1. Launch Ableton Live and select **SessionPad** as a Control Surface (Preferences → Link, Tempo & MIDI).
2. Open SessionPad on iOS — it discovers the bridge via Bonjour/mDNS, or use manual connect with your PC’s IP and port **17346**.

### Options

```
python -m sessionpad_bridge --help

  --port PORT         iOS WebSocket port (default: 17346)
  --live-port PORT    Ableton TCP port (default: 17345)
  --name NAME         Session name shown to iOS (default: Ableton Live)
  --no-mdns           Disable mDNS advertisement (use manual IP connect)
  --tray              System-tray icon (requires pystray + Pillow)
  -v, --verbose       Debug logging
```

## Windows Remote Script install

From PowerShell in the repo:

```powershell
cd AbletonRemoteScript
.\install.ps1
```

Then in Live: **Preferences → Link, Tempo & MIDI → Control Surface: SessionPad**.

Allow **SessionPad Bridge** through Windows Defender Firewall when prompted (private network).

## Build standalone Windows .exe

On a Windows machine with Python 3.10+:

```powershell
cd bridge
python -m venv .venv
.\.venv\Scripts\Activate.ps1
pip install -r requirements.txt
pip install pyinstaller
pyinstaller SessionPadBridge.spec
```

The executable is written to `bridge/dist/SessionPadBridge.exe`. Copy it anywhere convenient and run before opening Ableton Live.

## Troubleshooting

| Symptom | Fix |
|--------|-----|
| Bridge shows “Waiting for Ableton Live” | Start bridge **before** Live; select SessionPad control surface; restart Live if needed |
| iOS cannot find bridge | Same Wi-Fi; allow firewall; try manual connect: `<PC-IP>:17346` |
| Connected but empty grid | Re-run Remote Script install; check Live Log.txt for `SessionPad: state sent` |

## Status indicator (console)

- **Red** — waiting for Ableton Live
- **Yellow** — Live connected, no iOS client yet
- **Green** — Live + iOS connected
