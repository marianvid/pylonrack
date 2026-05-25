# PylonRack

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
- An **action panel** with buttons defined by the application itself

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
- Top bar: slot name + current status
- Main area: either the application's HTML UI (in a WebView) or the log viewer (toggled per slot)
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
- **Heartbeat Interval** — how often the rack sends a ping to each connected slot (1–60 seconds, default 10s)
- **Reconnect Attempts** — how many times the rack retries before marking a slot as error (1–10, default 3)

**Logs**
- **Lines per Request** — how many log lines are fetched per scroll chunk (10–500, default 50)

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
- **Port:** For local apps, read from the `PARALLAX_PORT` environment variable (set by the rack at launch). Fall back to your preferred port if the variable is not set.

```python
# Python example
import os
port = int(os.environ.get("PARALLAX_PORT", 9001))
```

```javascript
// Node.js example
const port = parseInt(process.env.PARALLAX_PORT) || 9001
```

---

## Local Application Structure

A local application must have a `rack.json` file in its root folder. This file is read by the rack when you browse for the application.

### `rack.json`

```json
{
  "name": "My Application",
  "version": "1.0",
  "start": "conda run -n my-env python3 app.py",
  "stop": "python3 stop.py",
  "port": 9001
}
```

| Field | Required | Description |
|-------|----------|-------------|
| `name` | ✅ | Display name shown in the rack |
| `version` | ❌ | Application version (informational) |
| `start` | ✅ | Shell command to launch the application (run via `/bin/zsh -c`) |
| `stop` | ❌ | Optional graceful stop script, called before SIGTERM |
| `port` | ✅ | Preferred WebSocket port (1–65535). Rack may assign a different port if this one is occupied — always read `PARALLAX_PORT` |
| `startup_delay` | ❌ | Seconds to wait after launch before attempting the first WebSocket connection (default: 0). Use this for runtimes that take time to initialize, e.g. conda environments (`3`), JVM (`5`) |

**Important:** The rack sets the `PARALLAX_PORT` environment variable before launching the process. Your application **must** read this variable to know which port to bind on.

---


## The Protocol

### Message Direction
- **Rack → App:** requests and commands
- **App → Rack:** responses

All messages are JSON objects with a `type` field. Unknown message types must be silently ignored — future versions of the rack may introduce new message types.

---

### Connection Flow

This is the exact sequence of events from the moment the rack connects to your application. Implementing this correctly is critical.

```
Rack                              App
 |                                 |
 |--- WebSocket connect ---------->|  (rack connects to ws://localhost:PORT)
 |                                 |
 |--- { "type": "manifest" } ----->|  (FIRST message sent by rack, immediately after connect)
 |                                 |
 |<-- { "type": "manifest", ... } -|  (app responds with its manifest)
 |                                 |
 |        [ heartbeat loop ]       |
 |--- { "type": "ping" } --------->|  (rack starts heartbeat after manifest received)
 |<-- { "type": "pong", ... } -----|
 |--- { "type": "ping" } --------->|
 |<-- { "type": "pong", ... } -----|
 |                                 |
 |        [ user interaction ]     |
 |--- { "type": "action", ... } -->|  (user pressed a button)
 |<-- { "type": "action_result" } -|
 |                                 |
 |--- { "type": "log_request" } -->|  (user opened log panel)
 |<-- { "type": "log_response" } --|
 |                                 |
 |        [ deactivation ]         |
 |--- { "type": "shutdown" } ----->|  (user pressed deactivate)
 |                                 |  (app cleans up and exits)
 |--- WebSocket close ------------>|  (rack closes connection)
```

**Key rules:**
1. The rack sends `manifest` as its **first message** immediately after the WebSocket connection is established. Your application must be ready to respond before any ping arrives.
2. The heartbeat loop starts **after** the manifest is received successfully. If the manifest response is invalid JSON or missing required fields, the rack will not start heartbeats and the slot will remain in connecting state.
3. The rack may disconnect and reconnect at any time (e.g. after a network error). Your application must handle multiple sequential connections gracefully — each new connection starts the flow from the beginning (manifest request first).
4. There is only ever **one active connection** from the rack at a time per slot.

---

### Port Binding — Critical

For local applications, the rack sets `PARALLAX_PORT` in the environment **before** launching your process. The `port` field in `rack.json` is only a **preference** — the rack may assign a different port if that one is occupied.

Your application **must always** read `PARALLAX_PORT` to know which port to bind on:

```python
# Python
import os
port = int(os.environ.get("PARALLAX_PORT", 9001))  # 9001 is fallback for manual testing only
```

```javascript
// Node.js
const port = parseInt(process.env.PARALLAX_PORT) || 9001
```

```go
// Go
port := os.Getenv("PARALLAX_PORT")
if port == "" { port = "9001" }
```

If your application ignores `PARALLAX_PORT` and binds to a hardcoded port, it may conflict with other slots or system services, and the rack will fail to connect.

---

### Heartbeat

The rack sends a ping at the configured interval (default 10 seconds, configurable per-slot via `heartbeat_interval` in the manifest). The application must respond promptly.

**Rack → App**
```json
{ "type": "ping" }
```

**App → Rack**
```json
{
  "type": "pong",
  "status": "running",
  "message": "All systems nominal"
}
```

| Field | Required | Values | Description |
|-------|----------|--------|-------------|
| `status` | ✅ | `"running"` \| `"warning"` \| `"error"` | Maps to slot color: green / yellow / red |
| `message` | ✅ | Any short string | Shown in the rack status bar. Keep it concise |

If the rack does not receive a pong within the heartbeat interval, it marks the slot as **warning**. After the configured number of missed beats, it attempts to reconnect.

---

### Manifest

The rack sends this as its **first message** after connecting. Respond with the full manifest before any other interaction is possible.

**Rack → App**
```json
{ "type": "manifest" }
```

**App → Rack**
```json
{
  "type": "manifest",
  "name": "My Application",
  "version": "1.0",
  "heartbeat_interval": 10,
  "buttons": [
    { "id": "start",  "label": "Start",  "style": "primary"     },
    { "id": "stop",   "label": "Stop",   "style": "destructive" },
    { "id": "reload", "label": "Reload", "style": "secondary"   }
  ],
  "ui_url": "http://localhost:8080/index.html"
}
```

| Field | Required | Description |
|-------|----------|-------------|
| `name` | ✅ | Application name |
| `version` | ❌ | Version string (informational) |
| `heartbeat_interval` | ❌ | Overrides the rack setting for this slot (seconds). Useful if your app has a known response latency |
| `buttons` | ✅ | List of action buttons. Use `[]` if no buttons are needed |
| `ui_url` | ❌ | Full URL of the HTML interface. Omit entirely if your app has no UI |

**Button styles**

| Style | Appearance | Use for |
|-------|-----------|---------|
| `primary` | Prominent, accent color | Main action (Start, Run) |
| `secondary` | Subdued | Secondary actions (Reload, Reset) |
| `destructive` | Red | Dangerous actions (Stop, Delete) |
| `warning` | Orange | Caution actions (Force restart) |

**About `ui_url`:**
If provided, the rack loads this URL in a WebView in the right panel. Your application is responsible for serving the HTML content — typically via a lightweight HTTP server running on a separate port (not the WebSocket port). The URL must be reachable from localhost. If omitted, the rack shows a placeholder in the right panel.

```python
# Example: serve index.html on HTTP alongside the WebSocket server
from http.server import HTTPServer, SimpleHTTPRequestHandler
import threading

HTTP_PORT = int(os.environ.get("PARALLAX_PORT", 9001)) + 100  # e.g. WS=9001, HTTP=9101

def run_http():
    HTTPServer(("localhost", HTTP_PORT), SimpleHTTPRequestHandler).serve_forever()

threading.Thread(target=run_http, daemon=True).start()
```

Then in your manifest:
```json
"ui_url": "http://localhost:9101/index.html"
```

---

### Actions

When the user clicks a button in the rack, the rack sends an action message. You must respond with `action_result` for every action received.

**Rack → App**
```json
{
  "type": "action",
  "button_id": "start"
}
```

**App → Rack**
```json
{
  "type": "action_result",
  "button_id": "start",
  "success": true,
  "message": "Service started successfully"
}
```

| Field | Required | Description |
|-------|----------|-------------|
| `button_id` | ✅ | Matches the `id` from the manifest button |
| `success` | ✅ | `true` or `false` |
| `message` | ✅ | Result message shown in the rack |

---

### Log Streaming

The rack requests log lines on demand — when the user opens the log panel or scrolls up. The application must serve lines from its log file or internal buffer.

**Rack → App**
```json
{
  "type": "log_request",
  "lines": 50,
  "offset": 0
}
```

| Field | Description |
|-------|-------------|
| `lines` | How many lines to return |
| `offset` | How many lines to skip from the end. `0` = last N lines. `50` = the 50 lines before the last 50. Used for scrolling backwards through history |

**App → Rack**
```json
{
  "type": "log_response",
  "lines": [
    "2026-05-25 10:00:01 [INFO] Service started",
    "2026-05-25 10:00:02 [INFO] Listening on port 9001"
  ],
  "total": 1240
}
```

| Field | Description |
|-------|-------------|
| `lines` | The requested lines in chronological order (oldest first) |
| `total` | Total number of log lines currently available |

**Log format recommendations:**
- Use rolling file logs to avoid unbounded disk usage
- Include timestamp and level in every line
- Recommended format: `YYYY-MM-DD HH:MM:SS [LEVEL] message`
- The rack applies automatic color coding: `[ERROR]` → red, `[WARNING]` → orange, `[DEBUG]` → gray, `[INFO]` → default

---

### Shutdown

When the user deactivates a local slot, the rack sends a shutdown message and waits up to 3 seconds before escalating.

**Rack → App**
```json
{ "type": "shutdown" }
```

**Shutdown sequence (rack side):**
1. Rack sends `{ "type": "shutdown" }`
2. Waits up to 3 seconds
3. If a `stop` script is defined in `rack.json`, runs it
4. Sends SIGTERM to the process
5. Polls for up to 3 seconds
6. Sends SIGKILL if the process is still running

**Your application must:**
1. Receive the shutdown message
2. Finish any critical in-progress work
3. Flush all log buffers to disk
4. Close open connections and file handles
5. Call `sys.exit(0)` (or equivalent) to terminate the process

```python
elif t == "shutdown":
    logger.info("Shutdown requested by rack")
    # flush, cleanup...
    import sys
    sys.exit(0)
```

> **Important:** Simply breaking out of the message loop is not enough. The process must actually exit, otherwise the rack will proceed to SIGTERM after the timeout.

---

### Reconnection Handling

The rack may disconnect and reconnect at any time — on network errors, after a rack restart, or after a manual reconnect. Your application must handle this correctly:

- Keep the WebSocket server running at all times (do not shut it down on disconnect)
- Reset any per-connection state when a new connection arrives
- Be ready to respond to `manifest` immediately on each new connection
- Do not assume that a new connection is a continuation of the previous one

```python
async def handle(ws):
    # This function is called fresh for every new connection
    # Reset per-connection state here if needed
    logger.info("Rack connected")
    try:
        async for raw in ws:
            ...
    except websockets.exceptions.ConnectionClosed:
        logger.info("Rack disconnected — server keeps running, waiting for reconnect")
```

---

## Minimal Implementation Example (Python)

```python
import asyncio, json, logging, os, sys
from http.server import HTTPServer, SimpleHTTPRequestHandler
from logging.handlers import RotatingFileHandler
from threading import Thread
import websockets

# Always read PARALLAX_PORT — never hardcode
WS_PORT   = int(os.environ.get("PARALLAX_PORT", 9001))
HTTP_PORT = WS_PORT + 100   # serve HTML on a separate port
APP_DIR   = os.path.dirname(os.path.abspath(__file__))
LOG_FILE  = os.path.join(APP_DIR, "app.log")

# Logging setup
logger = logging.getLogger("myapp")
logger.setLevel(logging.DEBUG)
fh = RotatingFileHandler(LOG_FILE, maxBytes=5*1024*1024, backupCount=3)
fh.setFormatter(logging.Formatter("%(asctime)s [%(levelname)s] %(message)s"))
logger.addHandler(fh)
logger.addHandler(logging.StreamHandler())

def read_log(count, offset):
    try:
        with open(LOG_FILE) as f:
            lines = f.readlines()
        total = len(lines)
        end   = max(0, total - offset)
        start = max(0, end - count)
        return [l.rstrip() for l in lines[start:end]], total
    except Exception:
        return [], 0

def run_http():
    class Handler(SimpleHTTPRequestHandler):
        def __init__(self, *a, **kw):
            super().__init__(*a, directory=APP_DIR, **kw)
        def log_message(self, *a): pass
    HTTPServer(("localhost", HTTP_PORT), Handler).serve_forever()

async def handle(ws):
    # Called fresh for every new connection from the rack
    logger.info("Rack connected")
    try:
        async for raw in ws:
            msg = json.loads(raw)
            t   = msg.get("type")

            if t == "manifest":
                # Respond to manifest FIRST — rack sends this immediately on connect
                await ws.send(json.dumps({
                    "type": "manifest",
                    "name": "My App",
                    "version": "1.0",
                    "heartbeat_interval": 10,
                    "buttons": [
                        {"id": "start", "label": "Start", "style": "primary"},
                        {"id": "stop",  "label": "Stop",  "style": "destructive"}
                    ],
                    "ui_url": f"http://localhost:{HTTP_PORT}/index.html"
                }))

            elif t == "ping":
                await ws.send(json.dumps({
                    "type": "pong",
                    "status": "running",
                    "message": "All good"
                }))

            elif t == "action":
                btn = msg.get("button_id")
                logger.info(f"Action: {btn}")
                # Handle your buttons here
                await ws.send(json.dumps({
                    "type": "action_result",
                    "button_id": btn,
                    "success": True,
                    "message": f"Executed: {btn}"
                }))

            elif t == "log_request":
                lines, total = read_log(msg.get("lines", 50), msg.get("offset", 0))
                await ws.send(json.dumps({
                    "type": "log_response",
                    "lines": lines,
                    "total": total
                }))

            elif t == "shutdown":
                logger.info("Shutdown requested — exiting")
                sys.exit(0)  # Must actually exit, not just break

    except websockets.exceptions.ConnectionClosed:
        logger.info("Rack disconnected — waiting for reconnect")
        # Do NOT exit here — keep server running

async def main():
    Thread(target=run_http, daemon=True).start()
    logger.info(f"Started — WS port {WS_PORT}, HTTP port {HTTP_PORT}")
    async with websockets.serve(handle, "localhost", WS_PORT):
        await asyncio.Future()  # Run forever

asyncio.run(main())
```

---

## Message Reference Summary

| Direction | Type | Required Response | When |
|-----------|------|------------------|------|
| Rack → App | `manifest` | `manifest` | **First message after connect** |
| Rack → App | `ping` | `pong` | Every N seconds (after manifest received) |
| Rack → App | `action` | `action_result` | User pressed a button |
| Rack → App | `log_request` | `log_response` | User opened log panel or scrolled |
| Rack → App | `shutdown` | *(exit process)* | User pressed deactivate |

---

## Checklist for a New Slot Application

**Setup**
- [ ] Create `rack.json` in the application root folder
- [ ] Set `start` command in `rack.json` (use conda/venv activation if needed)
- [ ] Read port from `PARALLAX_PORT` environment variable — never hardcode

**WebSocket Server**
- [ ] Start WebSocket server on `PARALLAX_PORT` at application launch
- [ ] Keep server running even when the rack disconnects
- [ ] Handle multiple sequential connections (rack reconnects after errors)

**Protocol**
- [ ] Respond to `manifest` — first message from rack on every connection
- [ ] Respond to `ping` with `pong` including `status` and `message`
- [ ] Respond to each `action` with `action_result`
- [ ] Respond to `log_request` with `log_response` (lines + total)
- [ ] Handle `shutdown` by calling `sys.exit(0)` (not just breaking the loop)

**HTML UI (optional)**
- [ ] Serve HTML on a separate HTTP port (not the WebSocket port)
- [ ] Set `ui_url` in manifest pointing to your HTTP server
- [ ] Omit `ui_url` entirely if no UI is needed

**Logging**
- [ ] Use rotating file logs (max size + backup count)
- [ ] Format: `YYYY-MM-DD HH:MM:SS [LEVEL] message`
- [ ] Log to file (not only stdout — rack reads the file)
