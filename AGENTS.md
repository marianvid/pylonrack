# AGENTS.md — PylonRack

> Machine-readable implementation reference. Not human documentation.
> Audience: AI agents continuing implementation. Assumes full Swift/macOS/SwiftUI competence.
> Audit: append knowledge after each implementation session.

---

## SYSTEM_IDENTITY

```
name: PylonRack
type: macOS menu bar application
language: Swift 5.0
min_os: macOS 14
ui_framework: SwiftUI + AppKit (NSViewRepresentable for WKWebView)
architecture: MVVM + protocol-oriented composition
build: Xcode 15, project.pbxproj hand-maintained (no SPM)
bundle_id: com.marianvid.pylonrack
repo: github.com/marianvid/pylonrack
install_path: /Applications/PylonRack.app
source_root: /Volumes/Marian_Backup/work/pylonrack/PylonRack/PylonRack/
test_root: /Volumes/Marian_Backup/work/pylonrack/PylonRack/PylonRackTests/
```

---

## ARCHITECTURE

### Dependency graph (ownership, not import)

```
PylonRackApp
  └── RackController           @StateObject, root orchestrator
        ├── [Slot]              Codable value type, persisted to slots.json
        ├── [SlotConnection]    @MainActor ObservableObject per slot
        │     ├── SlotManifest  Decodable, received from slot app
        │     ├── [SlotControl] Mutable after controls_update
        │     └── IncomingMessage  enum, centralised decode
        ├── [SlotProcess]       Process lifecycle, killpg
        ├── [LocalSlotConfig]   rack.json decoder
        └── SettingsStore       @Published AppConfig, JSON persistence

PylonRackApp
  └── SettingsStore            @StateObject, injected into SettingsView
  └── MacSystemEnvironment     SystemEnvironment protocol impl (NSApp, SMAppService)

ContentView
  └── SlotDetailView
        ├── SlotControlsView   native controls from manifest
        └── WebViewPanel       WKWebView NSViewRepresentable
              └── .id(reloadUIToken)  → recreate on reload_ui message
```

### Key design decisions

```
DI: AppConfig injected into SlotConnection (not singleton) → testable without globals
SRP: AppConfig = pure data; MacSystemEnvironment = side effects; SettingsStore = persistence
IncomingMessage: centralised decode enum → adding protocol messages = add case + handle in dispatch()
killpg: SlotProcess uses setpgid + killpg(pgid, SIGTERM/SIGKILL) → kills zsh + all children
WebView reload: reloadUIToken UUID on SlotConnection; .id(token) on WebViewPanel → SwiftUI recreates WKWebView fresh
process detection: lsof -iTCP:<port> -sTCP:LISTEN -t (not psutil.net_connections — fails without root on macOS)
pbxproj: hand-maintained, generated via Python scripts when adding files. Pattern: AA=app sources, BB=test sources, BS=shared sources (app files compiled into test target)
```

---

## DATA MODELS

### Slot (value type, Codable)
```swift
struct Slot: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    var host: String
    var port: Int
    var localPath: String?   // nil = remote slot
    var isActive: Bool
    var isLocal: Bool { localPath != nil }
}
```
Persisted: `~/Library/Application Support/PylonRack/slots.json`

### AppConfig (pure data, Codable, Equatable)
```swift
struct AppConfig: Codable, Equatable {
    var defaultLocation: String
    var heartbeatInterval: Int   // default 10
    var reconnectAttempts: Int   // default 10
    var logLinesPerRequest: Int  // default 50
    var startAtLogin: Bool
    var showInDock: Bool
    static let defaults: AppConfig
}
```
Persisted: `~/Library/Application Support/PylonRack/settings.json`

### SlotManifest (Decodable)
```swift
struct SlotManifest: Decodable, Equatable {
    let name: String
    let version: String
    let heartbeatInterval: Int?
    let controls: [SlotControl]
    let uiURL: String?           // CodingKey: "ui_url"
}
```

### SlotControl (Codable, Identifiable, Equatable, mutable)
```swift
struct SlotControl: Codable, Identifiable, Equatable {
    let id: String
    let type: ControlType        // .button | .dropdown | .label
    var label: String?
    var style: ControlStyle?     // .primary|.secondary|.destructive|.warning|.success|.error|.default
    var value: String?           // dropdown: current selection; label: display text
    var badge: Bool?             // button: orange dot indicator
    var items: [String]?         // dropdown: populated via control_data exchange
}
```

### LocalSlotConfig (Decodable, from rack.json)
```swift
// Required: name, start, port(1-65535)
// Optional: stop, version, heartbeat_interval, startup_delay
// Validation: name non-empty, start non-empty, port 1-65535
```

### RackLogEntry
```swift
struct RackLogEntry: Identifiable {
    let id = UUID()
    let timestamp = Date()
    let message: String
    var formatted: String  // "[HH:mm:ss] message"
}
```

---

## PROTOCOL — COMPLETE SPECIFICATION

### Transport
- WebSocket RFC 6455, ws:// only (no wss in current impl)
- Rack = client, slot app = server
- Local slots: rack sets env var PYLON_PORT before launch; slot reads it
- All messages: JSON UTF-8

### Connection sequence
```
rack connects → sends manifest request → app responds with manifest
→ rack starts heartbeat timer (interval from manifest or settings)
→ rack sends control_data for each dropdown in manifest
→ rack renders controls in SlotControlsView
→ bidirectional until shutdown
```

### Message catalogue (rack→app)

| type | fields | purpose |
|------|--------|---------|
| manifest | — | request manifest on every connect |
| ping | — | heartbeat, sent every N seconds |
| control_data | control_id:String | request dropdown items |
| action | control_id:String, value?:String | user interacted with control |
| log_request | lines:Int, offset:Int | fetch log lines |
| shutdown | — | graceful stop; app must sys.exit(0) |

### Message catalogue (app→rack)

| type | fields | purpose |
|------|--------|---------|
| manifest | name, version, heartbeat_interval?, controls:[], ui_url? | app identity + controls |
| pong | status:String, message:String | heartbeat response |
| control_data | control_id:String, items:[String] | dropdown population |
| controls_update | controls:[{id, label?, value?, style?, badge?, items?}] | push state change |
| action_result | control_id:String, success:Bool, message?:String | action ack |
| log_response | lines:[String], total:Int | log lines |
| reload_ui | — | signal WebView to reload (e.g. after model change) |

### Heartbeat state machine
```
connected → pendingPong=true, send ping
  ↳ pong received → pendingPong=false, missedBeats=0, status=connected|warning|error
  ↳ no pong → missedBeats++ → if missedBeats >= reconnectAttempts → scheduleReconnect
```

### Reconnect logic
```
scheduleReconnect():
  isReconnecting=true, tearDown()
  reconnectCount++
  if reconnectCount > max: status=error, onRackLog(message), return
  sleep(2s), connect()
```

### controls_update partial update
```
Only fields present in update dict are applied.
Missing fields: unchanged.
Mutable fields: label, value, style, badge, items.
id and type are immutable after manifest.
```

---

## SLOTCONNECTION STATE

### Published properties (observed by UI)
```
status: SlotStatus          → .connecting|.connected|.warning|.error|.missing|.disconnecting
statusMessage: String       → human-readable status for display
manifest: SlotManifest?     → nil until first manifest received
controls: [SlotControl]     → mutable, updated by controls_update
showLog: Bool               → toggle log/webview in body
logLines: [String]          → last N log lines from app
logTotal: Int               → total log lines in app
processLog: [String]        → stdout from local process (capped at logLinesPerRequest*10)
appMessage: String          → last pong message (shown in status bar)
reloadUIToken: UUID         → changes → WebViewPanel recreated via .id()
```

### SlotStatus.color mapping
```swift
.connecting    → .orange
.connected     → .green
.warning       → .yellow
.error         → .red
.missing       → .gray (inactive or lost)
.disconnecting → .orange
```

---

## RACKCONTROLLER

### Responsibilities
```
- owns [Slot] array (persisted)
- owns [UUID: SlotConnection] map
- owns [UUID: SlotProcess] map
- owns [UUID: LocalSlotConfig] map
- owns [UUID: Int] runtimePorts map (findFreePort result)
- owns [RackLogEntry] rackLog (max 500, shown in RackLogView)
- activate/deactivate/restart/reconnect/removeSlot
- wires onRackLog callback from SlotConnection
- auto-selects slot on addSlot (if first) and activate
```

### Process lifecycle (local slots)
```
activate(slot):
  slots[idx].isActive = true
  selectedSlotId = slot.id          // auto-select
  conn = makeConnection(for: slot)  // sets onRackLog
  launchProcess(for: slot, conn: conn)

launchProcess:
  load LocalSlotConfig from rack.json
  port = findFreePort(startingFrom: config.port)
  SlotProcess.launch(command: config.start, workingDir: path, port: port)
  setpgid(pid, pid)                 // new process group
  wait startup_delay if set
  conn.activate(port: port)

deactivate(slot):
  conn.status = .disconnecting
  if connected: conn.sendShutdown(); wait 3s
  if stop script: run it
  proc.sendSIGTERM(); poll 3s
  if still running: proc.sendSIGKILL()
  conn.deactivate()

restart(slot):
  await deactivate(slot)
  slots[idx].isActive = true
  makeConnection + launchProcess
```

### removeSlot ordering (CRITICAL)
```
Task {
  await deactivate(slot)            // shutdown first — user sees Disconnecting state
  if selectedSlotId == slot.id: selectedSlotId = nil
  remove from all maps
  slots.removeAll { $0.id == slot.id }
  saveSlots()
}
// selectedSlotId NOT cleared before deactivate — keeps panel visible during shutdown
```

---

## UI STRUCTURE

### Window hierarchy
```
MenuBarExtra → MenuBarMenuView (per-slot status + Open PylonRack + Rack Log + Settings + Quit)
Window("main") → ContentView
Window("rack-log") → RackLogView
Settings → SettingsView
```

### ContentView layout
```
HSplitView:
  left (200-320px): slot list with List(selection: $rack.selectedSlotId)
    each row: SlotRowView(slot, conn, onToggleActive, onReconnect)
      onReconnect: if .error → Task { await rack.restart(slot) } else rack.reconnect(slot)
  right: SlotDetailView(slot, conn, onReconnect, onRestart, onToggleLog)
    IF connected|warning:
      SlotControlsView(slot, conn, showLog, onToggleLog)  // HStack, no ScrollView
      Divider
    body:
      .error → errorContent (shows statusMessage + "Check Rack Log")
      .connecting|.disconnecting → ProgressView + statusMessage
      .missing + isActive → ProgressView "Connecting…"
      .missing + !isActive → inactiveContent
      default:
        if showLog → LogView
        elif ui_url → WebViewPanel(url).id(reloadUIToken)
        else → connectedPlaceholder
StatusBar: rackSummary left, appMessage right
```

### SlotRowView
```
Row 1: slot.name
Row 2: status dot + statusText + [↺ refresh if active && !transitioning] + [▶/■ toggle]
↺ behavior: error → restart; else → reconnect
isTransitioning: .connecting || .disconnecting
```

### SlotControlsView
```
HStack (NOT ScrollView — ScrollView blocks clicks):
  ForEach(controls): button|dropdown|label
  if ui_url: Divider + log toggle button
All buttons use ControlButtonStyle(color:) with:
  hover: background opacity 0.18, border opacity 0.5
  press: background opacity 0.35, scale 0.96
  animation: easeOut 100ms/150ms
```

### WebViewPanel
```
NSViewRepresentable wrapping WKWebView
makeNSView: load URLRequest with .reloadIgnoringLocalAndRemoteCacheData
updateNSView: reload only if url changed (nsView.url?.absoluteString != url.absoluteString)
Reload trigger: .id(conn.reloadUIToken) on call site — SwiftUI recreates entire view
reload_ui message → reloadUIToken = UUID() → .id() changes → makeNSView called fresh
```

---

## SLOTPROCESS

### Process group management (CRITICAL)
```swift
// After proc.run():
setpgid(proc.processIdentifier, proc.processIdentifier)  // new pgid = pid

sendSIGTERM():
  pgid = getpgid(proc.processIdentifier)
  if pgid > 0: killpg(pgid, SIGTERM)  // kills zsh AND python3 AND all children
  else: proc.terminate()

sendSIGKILL():
  pgid = getpgid(proc.processIdentifier)
  if pgid > 0: killpg(pgid, SIGKILL)
```
WHY: `start: "zsh start.sh"` → zsh spawns python3; SIGTERM to zsh alone leaves python3 orphaned.

### Environment
```
PYLON_PORT = String(port)  // always set before launch
```

---

## SETTINGS

### SettingsStore
```
init(url: URL)  // testable init
convenience init()  // uses ~/Library/Application Support/PylonRack/settings.json
load: JSON → AppConfig, fallback to AppConfig.defaults on any error
save: encode AppConfig → write to url
```

### SystemEnvironment protocol
```swift
protocol SystemEnvironment {
    func setDockVisibility(_ visible: Bool)
    func setLaunchAtLogin(_ enabled: Bool)
}
// Production: MacSystemEnvironment (NSApp, SMAppService)
// Test: mock implementation
```
Side effects applied: in SettingsView onChange handlers (not in didSet — avoids NSApp nil crash in tests).
At startup: PylonRackApp.init() applies showInDock via DispatchQueue.main.asyncAfter(0.1) — delay needed because MenuBarExtra sets .accessory policy after App.init().

---

## PBXPROJ CONVENTIONS

```
Object ID prefixes:
  AA0001-AA0031: app PBXBuildFile entries
  AA1001-AA1031: app PBXFileReference entries
  AA0030-AA0031: resource build file entries (assets, icns)
  BB0001-BB0008: test-only PBXBuildFile entries (test source files)
  BB1001-BB1008: test PBXFileReference entries
  BS0001-BS0012: shared source PBXBuildFile entries (app sources compiled into test target)
  AA_TGT, BB_TGT: native targets
  AA_SRC, BB_SRC: sources build phases
  AA_FW, BB_FW: frameworks build phases
  AA_RES: resources build phase
  APP_GRP, TEST_GRP, FW_GRP, PROD_GRP, ROOT_GRP: groups

Adding a new Swift file to app:
  1. Add PBXBuildFile: AA00XX = {isa = PBXBuildFile; fileRef = AA10XX; };
  2. Add PBXFileReference: AA10XX = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = File.swift; sourceTree = "<group>"; };
  3. Add to APP_GRP children
  4. Add to AA_SRC files
  5. If needed in tests: add BS00XX = {isa = PBXBuildFile; fileRef = AA10XX; }; add to BB_SRC

Test target does NOT use @testable import — uses BUNDLE_LOADER pattern.
Shared sources (BS series) compile app types directly into test bundle.
```

---

## TEST SUITE

```
86 tests, 0 failures (as of last audit)

Files:
  PylonRackTests.swift      PortFinderTests(4), LocalSlotConfigTests(13), SlotTests(4)
  SettingsStoreTests.swift  SettingsStoreTests(4), SettingsTests(2)
  SlotManifestTests.swift   SlotManifestTests(5)
  IncomingMessageTests.swift IncomingMessageTests(13)
  SlotConnectionTests.swift  SlotConnectionTests(16) — uses MockWSServer
  RackControllerTests.swift  RackControllerTests(17)
  SlotProcessTests.swift     SlotProcessTests(8)

MockWSServer scenarios:
  .normal, .warning, .errorStatus, .noUI, .dropAfter, .badJSON
  .withControls — manifest with dropdown + button + label, control_data responds with 3 models
  .controlsUpdate — sends controls_update on first pong (toggle→Stop/destructive, status→Running/success)

SlotConnectionTests uses ports 19200-19215. RackControllerTests uses temp dirs.
SlotProcessTests: tests killpg (spawns "sleep 30 & sleep 30"), output capture, PYLON_PORT env.

Run tests:
  cd PylonRack
  DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodebuild test -scheme PylonRack -destination 'platform=macOS' \
  -derivedDataPath /tmp/pylonrack-test
```

---

## BUILD & INSTALL

```bash
# Build Debug
cd /Volumes/Marian_Backup/work/pylonrack/PylonRack
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
xcodebuild build -scheme PylonRack -destination 'platform=macOS' \
-derivedDataPath /tmp/pylonrack-build -configuration Debug

# Install to /Applications
python3 -c "
import shutil; from pathlib import Path
src = Path('/tmp/pylonrack-build/Build/Products/Debug/PylonRack.app')
dst = Path('/Applications/PylonRack.app')
if dst.exists(): shutil.rmtree(dst)
shutil.copytree(src, dst)
"

# Icon build tools (conda env: pylonrack)
# cairosvg, psutil, aiohttp, websockets, requests installed
conda run -n pylonrack python3 build_icons.py
```

---

## KNOWN ISSUES & CONSTRAINTS

```
[RESOLVED] psutil.net_connections() fails without root on macOS → replaced with lsof
[RESOLVED] orphan processes when slot uses start.sh → killpg on process group
[RESOLVED] WebView shows stale model name → reload_ui message + .id(reloadUIToken)
[RESOLVED] NSApp nil crash in tests from AppSettings.didSet → moved side effects to SettingsView
[RESOLVED] @testable import fails with BUNDLE_LOADER → shared sources (BS series) pattern
[ACTIVE] Rack log (RackLogView) does not persist across sessions — in-memory only
[ACTIVE] No test for deactivate→process actually dead (RackControllerTests verifies isActive flag but not OS-level process termination)
[ACTIVE] startup_delay in rack.json: if venv creation takes >delay, connection fails; start.sh echos to stdout which becomes process log
[ACTIVE] Warning status on heartbeat miss persists until next successful pong — no visual timeout indicator
[CONSTRAINT] pbxproj must be manually maintained — Xcode will regenerate and fix on open, but agent must keep in sync
[CONSTRAINT] Test ports 19200-19215 hardcoded — port conflicts possible if tests run concurrently with other services
```

---

## SLOT APP CONTRACT (for agent writing slot apps)

```
rack.json required fields: name(str), start(str), port(int 1-65535)
rack.json optional: stop(str), version(str), heartbeat_interval(int), startup_delay(int), controls([])
start command: run via /bin/zsh -c; reads PYLON_PORT env var
controls[].type: "button"|"dropdown"|"label"
controls[].style: "primary"|"secondary"|"destructive"|"warning"|"success"|"error"|"default"

Slot app MUST:
  - bind WebSocket server on PYLON_PORT (or fallback port)
  - respond to manifest with full manifest message on EVERY connect (not just first)
  - respond to ping with pong within heartbeat_interval seconds
  - respond to control_data for each dropdown (items array)
  - respond to action with action_result
  - respond to log_request with log_response
  - handle shutdown by calling sys.exit(0) — rack will SIGTERM after 3s if not exited
  - send controls_update when internal state changes (not just on request)
  - keep WebSocket server running when rack disconnects (rack may reconnect)

reload_ui: send when UI should be refreshed (e.g. after backend model/process change)
  → rack recreates WKWebView with .reloadIgnoringLocalAndRemoteCacheData

Reference implementation: /Volumes/Marian_Backup/work/pylonrack-slots/llama/
```

---

## AUDIT_LOG

```
2026-05-27 — Initial AGENTS.md
  Added: full protocol spec, architecture, data models, pbxproj conventions,
  known issues (psutil, orphan processes, WebView reload), slot app contract.
  Test count at audit: 86/86 passing.
  Active slot apps: pylonrack-slots/llama, pylonrack-slots/benchmark

2026-05-28 — Major audit after long implementation session
  Changes:
  - BodyMode enum: .webview | .log | .models (replaced showLog: Bool)
  - ModelManagerView: HF browse/download/delete, actionResultToken pattern
  - WebViewPanel: NSViewContainer subclass, load triggered from viewDidMoveToWindow+layout
    CRITICAL: WKWebView created in handleManifest WITHOUT load — load triggered only after
    non-zero frame from SwiftUI layout. Prevents blank WebView on startup.
  - WKWebView persistent: created once in SlotConnection.handleManifest, reset only on deactivate()
    NOT reset on reconnect — preserves session across heartbeat reconnects
  - ZStack body: WebViewPanel always in hierarchy during log/models toggle — prevents SPA reset
  - show_log protocol message: rack auto-switches to bodyMode=.log + requestLog()
  - Heartbeat suspend during update: tick() checks updateInProgress (status_label == Updating...)
    Prevents reconnect during cmake builds (minutes long)
    missedBeats reset when update finishes via applyControlsUpdate()
  - AppDelegate.applicationWillTerminate: pkill -TERM -f server.py → prevents orphan processes on quit
  - AddSlotView removed: + button opens NSOpenPanel directly
  - Remote slot type removed from UI
  - Tooltip delay: 0.5s via UserDefaults NSInitialToolTipDelay + NSToolTipDelay
  - SlotControlsView: update button filtered to right side, separated by Divider
  - ModeToggleButton: log + models toggles with .help() tooltips
  
  Protocol additions:
  - show_log (app→rack): rack sets bodyMode=.log
  - reload_ui now also calls wv.load() directly on persistent WKWebView instance
  - log_response total=-1: streaming append to logLines (not replace)
  - actionResultToken: UUID changes on each action_result → ModelManagerView observes
  
  ACTIVE BUG (in progress at audit):
  - During cmake build, log disappears from view at ~11% 
    Test confirmed: WebSocket protocol works correctly (268 lines received)
    Problem is in Swift: receive loop error causes reconnect despite heartbeat suspend
    NSLog added to onDropped() and receiveLoop error handler for diagnosis
    Status: NSLog logging added, waiting for user to report Console.app output
  
  Test count: 86/86 passing (Swift), 42/43 (Python — 1 expected fail: binary stale)
```
