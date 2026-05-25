#!/usr/bin/env python3
"""
Mock WebSocket server for PylonRack tests.
Usage: python3 mock_ws_server.py <port> <scenario>

Scenarios:
  normal       - responds correctly to all messages
  warning      - pong returns status=warning
  error_status - pong returns status=error
  no_ui        - manifest without ui_url
  drop_after   - drops connection after first pong
  slow_pong    - delays pong by 2s
  bad_json     - sends invalid JSON on manifest request
"""
import asyncio, json, sys, logging
import websockets

logging.basicConfig(level=logging.WARNING)

PORT     = int(sys.argv[1]) if len(sys.argv) > 1 else 9999
SCENARIO = sys.argv[2] if len(sys.argv) > 2 else "normal"

MANIFEST_NORMAL = {
    "type": "manifest",
    "name": "MockApp",
    "version": "1.0",
    "heartbeat_interval": 1,
    "buttons": [
        {"id": "start", "label": "Start", "style": "primary"},
        {"id": "stop",  "label": "Stop",  "style": "destructive"}
    ],
    "ui_url": "http://localhost:9999/index.html"
}

MANIFEST_NO_UI = {
    "type": "manifest",
    "name": "MockApp",
    "version": "1.0",
    "heartbeat_interval": 1,
    "buttons": [{"id": "run", "label": "Run", "style": "primary"}]
}

pong_count = 0

async def handle(ws):
    global pong_count
    try:
        async for raw in ws:
            msg = json.loads(raw)
            t   = msg.get("type")

            if t == "ping":
                pong_count += 1
                if SCENARIO == "warning":
                    await ws.send(json.dumps({"type":"pong","status":"warning","message":"High load"}))
                elif SCENARIO == "error_status":
                    await ws.send(json.dumps({"type":"pong","status":"error","message":"Critical failure"}))
                elif SCENARIO == "drop_after" and pong_count >= 1:
                    await ws.close()
                    return
                elif SCENARIO == "slow_pong":
                    await asyncio.sleep(2)
                    await ws.send(json.dumps({"type":"pong","status":"running","message":"Slow response"}))
                else:
                    await ws.send(json.dumps({"type":"pong","status":"running","message":"All good"}))

            elif t == "manifest":
                if SCENARIO == "bad_json":
                    await ws.send("NOT VALID JSON {{{{")
                elif SCENARIO == "no_ui":
                    await ws.send(json.dumps(MANIFEST_NO_UI))
                else:
                    await ws.send(json.dumps(MANIFEST_NORMAL))

            elif t == "action":
                await ws.send(json.dumps({
                    "type": "action_result",
                    "button_id": msg.get("button_id"),
                    "success": True,
                    "message": f"Executed {msg.get('button_id')}"
                }))

            elif t == "log_request":
                lines = [f"Log line {i}" for i in range(msg.get("lines", 10))]
                await ws.send(json.dumps({
                    "type": "log_response",
                    "lines": lines,
                    "total": 100
                }))

    except websockets.exceptions.ConnectionClosed:
        pass

async def main():
    async with websockets.serve(handle, "localhost", PORT):
        await asyncio.Future()

asyncio.run(main())
