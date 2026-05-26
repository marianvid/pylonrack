# PylonRack

A macOS menu bar application that acts as a universal launcher and monitor for independent services and applications — each slot holds one application, and the rack provides a unified interface to manage, monitor, and interact with all of them.

---

## Installation

PylonRack is distributed as source code. There is no App Store release and no signed certificate — build it yourself with Xcode.

### Requirements

- macOS 14 (Sonoma) or later
- Xcode 15 or later

### Build and Install

```
git clone https://github.com/marianvid/pylonrack
cd pylonrack/PylonRack
open PylonRack.xcodeproj
```

In Xcode:
1. Select the **PylonRack** scheme and **My Mac** as destination
2. **Product → Build** (`⌘B`)
3. **Product → Archive** for a release build, or just run directly with `⌘R`

To install to `/Applications` from the command line after building:

```
xcodebuild build \
  -scheme PylonRack \
  -destination 'platform=macOS' \
  -derivedDataPath /tmp/pylonrack-build \
  -configuration Release

cp -R /tmp/pylonrack-build/Build/Products/Release/PylonRack.app /Applications/
```

### First Launch — Gatekeeper

Because the app is not notarized, macOS will block the first launch:

1. Open `/Applications` in Finder
2. Right-click `PylonRack.app` → **Open**
3. Click **Open** in the dialog

After the first launch, double-clicking works normally.

Alternatively, from the terminal:

```
xattr -dr com.apple.quarantine /Applications/PylonRack.app
```

---

## What is PylonRack?

PylonRack is a macOS menu bar application that acts as a universal launcher and monitor for independent services and applications. Think of it as a physical server rack — each slot holds one application, each application runs independently, and the rack provides a unified interface to manage, monitor, and interact with all of them from a single place.

The rack does not care what technology your application uses. It can be a Python script, a Node.js server, a native macOS app, a remote cloud service, or anything else — as long as it speaks the PylonRack protocol over a WebSocket connection.

---

## Core Concepts

### Slots
A slot is a placeholder in the rack for one application. Each slot has:
- A **name** (from the application's own manifest)
- A **status** (connecting, connected, warning, error, inactive)
- An **activate/deactivate toggle**
- A **log viewer**
- A **controls header** with native controls defined by the application itself

Slots are persistent — they survive rack restarts. Their active/inactive state is also persistent: if a slot was active when you quit the rack, it will be automatically reactivated on the next launch.

### Local vs Remote Applications
**Local applications** live on disk. The rack launches them as child processes and manages their lifecycle. You add them by browsing to their folder — the rack reads a `rack.json` configuration file to understand how to start them.

**Remote applications** are already running somewhere (locally on another port, on a LAN machine, or in the cloud). You add them by providing a host and port manually. The rack connects to them but never starts or stops them.

### The Protocol
All communication between the rack and an application happens over a **WebSocket connection** using **JSON messages**. The rack is always the client — it connects to the application's WebSocket server. This makes the protocol universally implementable in any language or runtime.

---

## User Interface

### Menu Bar Icon
The rack lives in the macOS menu bar. Clicking the icon shows:
- A list of all slots with their current status (colored emoji + name + state)
- Clicking a slot opens the main window with that slot selected
- Settings and Quit

### Main Window
The main window is split into two panels:

**Left panel — Slot list**
- Title "PylonRack" at the top
- Toolbar with `+` (add slot), `−` (remove slot with confirmation), `↺` (reconnect)
- Each slot row shows:
  - Row 1: application name
  - Row 2: status dot (color-coded) + status message + log toggle + activate/deactivate button

**Right panel — Slot detail**
- **Top bar:** slot name + current status + log toggle button
- **Controls header:** native macOS controls (buttons, dropdowns, labels) defined by the application manifest — visible only when the application provides controls
- **Body:** either the application's HTML UI (in a WebView) or the log viewer, toggled via the log button in the top bar
- When no slot is selected: empty state with instructions

**Status bar** (bottom of window, full width)
- Left: rack summary — `3 slots · 2 running · 1 inactive`
- Right: application message from the last heartbeat response (only when a slot is selected and active)

### Slot Status Colors
| Color | Status | Meaning |
|-------|--------|---------|
| 🟠 Orange | Connecting / Disconnecting | Transition in progress |
| 🟢 Green | Connected | Heartbeat OK, application running |
| 🟡 Yellow | Warning | Heartbeat delayed (missed beats) |
| 🔴 Red | Error | Cannot connect after max attempts |
| ⚫ Gray | Inactive | Slot exists but not activated |

---

## Settings

Accessible via the menu bar icon → Settings…

**General**
- **Default Location** — folder opened by default when browsing for a local application
- **Start at login** — launch PylonRack automatically when you log in
- **Show in Dock** — show PylonRack in the Dock in addition to the menu bar
- **Heartbeat Interval** — how often the rack sends a ping to each connected slot (1–60 seconds, default 10s)
- **Reconnect Attempts** — how many times the rack retries before marking a slot as error (1–10, default 10)

**Logs**
- **Lines per Request** — how many log lines are fetched per request (10–500, default 50)

Settings are stored in `~/Library/Application Support/PylonRack/settings.json`.

---

## Adding a Slot

### Local Application
1. Click `+` in the slot list
2. The dialog opens in **Local** mode by default
3. Click **Browse…** — a file picker opens at your Default Location
4. Navigate to your application folder and click **Open**
5. The rack validates the folder — it must contain a valid `rack.json` file
6. If valid, the application name and address are shown with a green checkmark
7. Click **Add**

The slot is added in **inactive** state. Press ▶ to activate it.

### Remote Application
1. Click `+`
2. Switch to the **Remote** tab
3. Enter a name, host, and port
4. Click **Add**

---

## Activating and Deactivating

**Activate (▶):** For local apps, the rack launches the process and connects. For remote apps, the rack connects to the existing service.

**Deactivate (■):** For local apps, the rack sends a graceful shutdown message, waits, then sends SIGTERM, then SIGKILL if necessary. For remote apps, the rack simply disconnects — the remote service is left running.

---

## Data Storage

```
~/Library/Application Support/PylonRack/
├── settings.json    ← user preferences
└── slots.json       ← slot list (configuration only, no runtime state)
```

`slots.json` stores only static configuration (name, host, port, local path, active flag). Runtime state (status, manifest, log) is always fetched live.

---

---

# PylonRack Slot Application Specification

## Overview

A slot application is any service that implements the PylonRack WebSocket protocol. The application acts as a **WebSocket server**; the rack connects as a client. Once connected, the rack requests a manifest, starts sending heartbeats, and the application responds accordingly.

---

## Transport

- **Protocol:** WebSocket (RFC 6455)
- **Format:** JSON, UTF-8
- **Address:** `ws://<host>:<port>` — for local apps, host is always `localhost`
- **Port:** For local apps, read from the `PYLON_PORT` environment variable (set by the rack at launch). Fall back to your preferred port if the variable is not set.

```python
# Python example
import os
port = int(os.environ.get("PYLON_PORT", 9001))
```

```javascript
// Node.js example
const port = parseInt(process.env.PYLON_PORT) || 9001
```

---

## Local Application Structure

A local application must have a `rack.json` file in its root folder.

### `rack.json`

```json
{
  "name": "My Application",
  "version": "1.0",
  "start": "conda run -n my-env python3 app.py",
  "stop": "python3 stop.py",
  "port": 9001,
  "heartbeat_interval": 5,
  "controls": [
    { "id": "model_select", "type": "dropdown", "label": "Model" },
    { "id": "toggle",       "type": "button",   "label": "Start", "style": "primary" },
    { "id": "status_label", "type": "label",    "value": "Idle",  "style": "default" }
  ]
}
```

| Field | Required | Description |
|-------|----------|-------------|
| `name` | ✅ | Display name shown in the rack |
| `version` | ❌ | Application version (informational) |
| `start` | ✅ | Shell command to launch the application (run via `/bin/zsh -c`) |
| `stop` | ❌ | Optional graceful stop script, called before SIGTERM |
| `port` | ✅ | Preferred WebSocket port (1–65535) |
| `heartbeat_interval` | ❌ | Heartbeat interval in seconds (overrides rack setting for this slot) |
| `controls` | ❌ | Native controls rendered in the rack header (see Controls section) |
| `startup_delay` | ❌ | Seconds to wait after launch before connecting (default: 0) |

**Important:** The rack sets the `PYLON_PORT` environment variable before launching the process. Always read this variable.

---

## The Protocol

### Connection Flow

```
Rack                              App
 |                                 |
 |--- WebSocket connect ---------->|
 |--- { "type": "manifest" } ----->|  (first message after connect)
 |<-- { "type": "manifest", ... } -|
 |                                 |
 |        [ heartbeat loop ]       |
 |--- { "type": "ping" } --------->|
 |<-- { "type": "pong", ... } -----|
 |                                 |
 |        [ control data ]         |
 |--- { "type": "control_data" } ->|  (rack requests dropdown items)
 |<-- { "type": "control_data" } --|
 |                                 |
 |        [ user interaction ]     |
 |--- { "type": "action", ... } -->|  (user interacted with a control)
 |<-- { "type": "action_result" } -|
 |                                 |
 |   [ app pushes control update ] |
 |<-- { "type": "controls_update"} |  (app updates control state)
 |                                 |
 |--- { "type": "log_request" } -->|
 |<-- { "type": "log_response" } --|
 |                                 |
 |--- { "type": "shutdown" } ----->|
```

---

### Port Binding

Always read `PYLON_PORT`:

```python
import os
port = int(os.environ.get("PYLON_PORT", 9001))
```

---

### Heartbeat

**Rack → App**
```json
{ "type": "ping" }
```

**App → Rack**
```json
{ "type": "pong", "status": "running", "message": "All systems nominal" }
```

| `status` value | Slot color |
|----------------|------------|
| `"running"` | 🟢 Green |
| `"warning"` | 🟡 Yellow |
| `"error"` | 🔴 Red |

---

### Manifest

**Rack → App:** `{ "type": "manifest" }`

**App → Rack:**
```json
{
  "type": "manifest",
  "name": "My Application",
  "version": "1.0",
  "heartbeat_interval": 10,
  "controls": [
    { "id": "model_select", "type": "dropdown", "label": "Model" },
    { "id": "toggle",       "type": "button",   "label": "Start", "style": "primary" },
    { "id": "status_label", "type": "label",    "value": "Idle",  "style": "default" }
  ],
  "ui_url": "http://localhost:9101/index.html"
}
```

---

### Controls

Controls are native macOS UI elements rendered in the rack header. The rack requests data for dropdowns automatically after the manifest is received.

#### Control types

**`button`**
```json
{ "id": "toggle", "type": "button", "label": "Start", "style": "primary", "badge": false }
```

| Style | Appearance |
|-------|-----------|
| `primary` | Accent color |
| `secondary` | Subdued |
| `destructive` | Red |
| `warning` | Orange |
| `success` | Green |

Set `badge: true` to show an orange dot indicator (e.g. update available).

**`dropdown`**
```json
{ "id": "model_select", "type": "dropdown", "label": "Model" }
```

Items are populated via `control_data` exchange (see below).

**`label`**
```json
{ "id": "status_label", "type": "label", "value": "Idle", "style": "default" }
```

| Style | Color |
|-------|-------|
| `default` | Secondary text |
| `success` | Green |
| `warning` | Orange |
| `error` | Red |
| `primary` | Accent |

---

### Control Data (dropdown population)

After receiving the manifest, the rack sends a `control_data` request for each dropdown control. The app responds with the available items.

**Rack → App**
```json
{ "type": "control_data", "control_id": "model_select" }
```

**App → Rack**
```json
{
  "type": "control_data",
  "control_id": "model_select",
  "items": ["Model A", "Model B", "Model C"]
}
```

---

### Controls Update (push from app)

The app can push control state changes to the rack at any time — e.g. after starting a process, update the button label and status label.

**App → Rack**
```json
{
  "type": "controls_update",
  "controls": [
    { "id": "toggle",       "label": "Stop",    "style": "destructive" },
    { "id": "status_label", "value": "Running", "style": "success" },
    { "id": "update",       "badge": true }
  ]
}
```

Each entry in `controls` can update any subset of fields: `label`, `value`, `style`, `badge`, `items`.

---

### Actions

When the user interacts with a control, the rack sends an action message.

**Rack → App**
```json
{
  "type": "action",
  "control_id": "toggle"
}
```

For dropdowns, the selected value is included:
```json
{
  "type": "action",
  "control_id": "model_select",
  "value": "Model B"
}
```

**App → Rack**
```json
{
  "type": "action_result",
  "control_id": "toggle",
  "success": true,
  "message": "Started"
}
```

---

### Log Streaming

**Rack → App**
```json
{ "type": "log_request", "lines": 50, "offset": 0 }
```

**App → Rack**
```json
{
  "type": "log_response",
  "lines": ["2026-05-26 10:00:01 [INFO] Started", "..."],
  "total": 1240
}
```

---

### Shutdown

**Rack → App:** `{ "type": "shutdown" }`

The app must actually exit (`sys.exit(0)`), not just break the loop. Rack escalates to SIGTERM after 3 seconds, then SIGKILL.

---

## Minimal Python Implementation

```python
import asyncio, json, os, sys
from logging.handlers import RotatingFileHandler
import logging, websockets

WS_PORT  = int(os.environ.get("PYLON_PORT", 9001))
LOG_FILE = os.path.join(os.path.dirname(__file__), "app.log")

logger = logging.getLogger("myapp")
logger.setLevel(logging.DEBUG)
fh = RotatingFileHandler(LOG_FILE, maxBytes=5*1024*1024, backupCount=3)
fh.setFormatter(logging.Formatter("%(asctime)s [%(levelname)s] %(message)s"))
logger.addHandler(fh)

def read_log(n, offset):
    try:
        lines = open(LOG_FILE).readlines()
        total = len(lines)
        end   = max(0, total - offset)
        return [l.rstrip() for l in lines[max(0, end-n):end]], total
    except Exception:
        return [], 0

async def handle(ws):
    async for raw in ws:
        msg = json.loads(raw)
        t   = msg.get("type")

        if t == "manifest":
            await ws.send(json.dumps({
                "type": "manifest", "name": "My App", "version": "1.0",
                "heartbeat_interval": 10,
                "controls": [
                    {"id": "run",    "type": "button", "label": "Run",  "style": "primary"},
                    {"id": "status", "type": "label",  "value": "Idle", "style": "default"},
                ]
            }))

        elif t == "ping":
            await ws.send(json.dumps({"type": "pong", "status": "running", "message": "OK"}))

        elif t == "action":
            cid = msg.get("control_id")
            await ws.send(json.dumps({"type": "action_result", "control_id": cid, "success": True, "message": "Done"}))

        elif t == "log_request":
            lines, total = read_log(msg.get("lines", 50), msg.get("offset", 0))
            await ws.send(json.dumps({"type": "log_response", "lines": lines, "total": total}))

        elif t == "shutdown":
            sys.exit(0)

async def main():
    async with websockets.serve(handle, "localhost", WS_PORT):
        await asyncio.Future()

asyncio.run(main())
```

---

## Message Reference

| Direction | Type | When |
|-----------|------|------|
| Rack → App | `manifest` | First message after connect |
| Rack → App | `ping` | Every N seconds |
| Rack → App | `control_data` | After manifest, for each dropdown |
| Rack → App | `action` | User interacted with a control |
| Rack → App | `log_request` | User opened log panel |
| Rack → App | `shutdown` | User deactivated slot |
| App → Rack | `manifest` | Response to manifest request |
| App → Rack | `pong` | Response to ping |
| App → Rack | `control_data` | Response to control_data request |
| App → Rack | `action_result` | Response to action |
| App → Rack | `log_response` | Response to log_request |
| App → Rack | `controls_update` | Any time app wants to update control state |

---

## Checklist

- [ ] `rack.json` with `name`, `start`, `port`
- [ ] Read port from `PYLON_PORT` environment variable
- [ ] Respond to `manifest` (first message on every connection)
- [ ] Respond to `ping` with `pong`
- [ ] Respond to `action` with `action_result`
- [ ] Respond to `log_request` with `log_response`
- [ ] Respond to `control_data` for each dropdown
- [ ] Push `controls_update` when app state changes
- [ ] Handle `shutdown` by calling `sys.exit(0)`
- [ ] Keep WebSocket server running when rack disconnects
