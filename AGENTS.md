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
        └── body panel (one of): WebViewPanel | LogView | ModelManagerView | SettingsPanelView
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
URLSession for WebSocket: timeoutIntervalForRequest=.infinity, timeoutIntervalForResource=.infinity
  REASON: default 60s kills WebSocket during long cmake builds where server sends nothing
receiveLoop: does NOT call scheduleReconnect() when updateInProgress
  REASON: cmake builds take minutes; reconnect would break live log streaming
```

---

## DATA MODELS

### Slot (value type, Codable)
```swift
struct Slot: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    var port: Int
    var localPath: String     // required; remote slots no longer supported
    var isActive: Bool
    // Custom init(from:) tolerates legacy slots.json with `host` field;
    // rejects entries without localPath (legacy remote slots).
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
- Rack always connects to `ws://localhost:<port>`
- Rack sets env var PYLON_PORT before launch; slot reads it
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
| action | control_id:String, value?:String, settings?:Dict | user interacted with control |
| log_request | lines:Int, skip:Int | fetch log lines (skip=0: tail, skip=N: load older) |
| shutdown | — | graceful stop; app must sys.exit(0) |

### Message catalogue (app→rack)

| type | fields | purpose |
|------|--------|---------|
| manifest | name, version, heartbeat_interval?, controls:[], ui_url? | app identity + controls |
| pong | status:String, message:String | heartbeat response |
| control_data | control_id:String, items:[String] | dropdown population |
| controls_update | controls:[{id, label?, value?, style?, badge?, items?}] | push state change |
| action_result | action:String, data:{type,...} | action response, routed via actionResultToken |
| log_response | lines:[String], total:Int, prepend:Bool | log lines |
| reload_ui | — | signal WebView to reload (e.g. after model change) |
| show_log | — | rack auto-switches to bodyMode=.log |

### log_response semantics
```
total >= 0, prepend=false  → initial fetch, replace logLines
total == -1, prepend=false → streaming append (file watcher push)
prepend=true               → load earlier lines, prepend to logLines (load more)
```

### Heartbeat state machine
```
connected → pendingPong=true, send ping
  ↳ pong received → pendingPong=false, missedBeats=0, status=connected|warning|error
  ↳ no pong → missedBeats++ → if missedBeats >= reconnectAttempts → scheduleReconnect
  ↳ updateInProgress=true → tick() returns early, NO heartbeat sent, NO reconnect
```

### updateInProgress detection
```swift
// In SlotConnection:
private var updateInProgress: Bool {
    controls.first(where: { $0.id == "status_label" })?.value == "Updating…"
}
// Heartbeat suspended when true
// receiveLoop does NOT call scheduleReconnect() when true
// missedBeats reset when update finishes (applyControlsUpdate detects transition)
```

---

## SLOTCONNECTION STATE

### Published properties (observed by UI)
```
status: SlotStatus          → .connecting|.connected|.warning|.error|.missing|.disconnecting
statusMessage: String       → human-readable status for display
manifest: SlotManifest?     → nil until first manifest received
controls: [SlotControl]     → mutable, updated by controls_update
bodyMode: BodyMode          → .webview | .log | .models | .settings
logLines: [String]          → log lines (appended from file watcher, replaced on initial fetch)
logTotal: Int               → total log lines reported
processLog: [String]        → stdout from local process (capped at logLinesPerRequest*10)
appMessage: String          → last pong message (shown in status bar)
reloadUIToken: UUID         → changes → WebViewPanel recreated via .id()
actionResultToken: UUID     → changes on each action_result → ModelManagerView + SettingsPanelView observe
lastActionResult: [String:Any]? → last action_result data payload
webView: WKWebView?         → persistent, created once in handleManifest, reset only on deactivate()
onRackLog: ((String)->Void)?→ callback to RackController for diagnostic messages
```

### BodyMode enum
```swift
enum BodyMode: Equatable {
    case webview    // default, show WKWebView
    case log        // LogView overlay
    case models     // ModelManagerView overlay
    case settings   // SettingsPanelView overlay
}
// toggleMode(.x): if bodyMode==.x → .webview; else → .x
// show_log message → bodyMode = .log (always, ignores current)
```

---

## BODY PANEL ROUTING (ContentView)

```swift
let isLive = conn.status == .connected || conn.status == .warning

if let wv = conn.webView, conn.status == .connected,
   let uiURL = conn.manifest?.uiURL {
    ZStack {
        WebViewPanel(webView: wv, url: url)
        if bodyMode == .log      { LogView(conn:) }
        if bodyMode == .models   { ModelManagerView(conn:) }
        if bodyMode == .settings { SettingsPanelView(conn:) }
    }
} else if isLive && bodyMode == .log      { LogView(conn:) }
  else if isLive && bodyMode == .models   { ModelManagerView(conn:) }
  else if isLive && bodyMode == .settings { SettingsPanelView(conn:) }
  else { connectedPlaceholder }

// CRITICAL: isLive includes .warning (server idle) — panels must be visible when idle
// WKWebView only shown when .connected (server running, ui_url present)
```

---

## LOG VIEW

```
LogView: shows logLines (from file watcher) or processLog fallback
- Single Text block (joined lines) with .textSelection(.enabled) — allows copy
- "Load earlier lines" button at top → requestLog(skip: displayLines.count) → prepend=true response
- Auto-scroll to bottom on new appended lines (unless userScrolled=true)
- userScrolled: set true on DragGesture up, false on drag down
- onAppear → requestLog() (initial tail from file)
- File watcher in Python pushes new lines via log_response total=-1
```

### requestLog parameters
```swift
func requestLog(lines: Int? = nil, skip: Int = 0)
// skip=0   → last N lines (initial/refresh)
// skip=N   → N lines before the last N (load more / prepend)
```

---

## MODEL MANAGER VIEW

```
Two tabs: Local Models | Browse HuggingFace
Local Models tab:
  - List of GGUFModel with selection highlight (selectedLocalModel state)
  - Each row: icon + "repo/name / filename" + size + delete button
  - Padding: 15px horizontal on LazyVStack
  - No refresh during active download (downloadingFile != nil guard)
  - download_complete → list refreshes + dropdown items update via control_data

Browse HuggingFace tab:
  - Left panel: search field + model list with selection highlight (selectedModel state)
  - Right panel: file list for selected model with selection highlight (selectedFile state)
  - File row: name + quant badge + size + download button (checkmark if downloaded)
  - Search: does NOT clear searchResults on new query (avoids blank panel during search)
  - searchResults only replaced if new response is non-empty

Download flow:
  - Python streams progress via requests (1MB chunks) → action_result download_progress
  - progress bar shown during download
  - download does NOT block Python event loop (asyncio.create_task)
  - ping/pong continues during download
  - After complete: local_models + control_data(model_select items) pushed automatically
```

### action_result routing (via actionResultToken)
```
"hf_search_results"  → searchResults, isSearching=false
"hf_model_files_result" → modelFiles, isLoadingFiles=false
"download_progress"  → downloadProgress (0.0-1.0)
"download_complete"  → downloadingFile=nil, loadLocalModels()
"download_error"     → error message
"local_models"       → localModels list
"delete_complete"    → loadLocalModels()
```

---

## SETTINGS PANEL VIEW

```
SettingsPanelView: gear icon toggle in SlotControlsView
Sections: Model & Context | Sampling | Hardware | Speculative Decoding
Footer: "Changes take effect after restart." + "Save & Restart" button

Save & Restart button:
  - DISABLED unless isDirty (current values ≠ loaded baseline)
  - isDirty computed from all 12 fields including draftModelPath
  - On save: sends save_settings action with settings dict
  - On settings_saved response: closes panel (toggleMode(.settings) → .webview)

Per-model settings:
  - Python maintains settings_map: {model_path: {ctx_size, temp, ...}} in settings.json
  - On model switch: Python pushes get_settings automatically → SettingsPanelView updates
  - New model: defaults from GGUF metadata (ctx_size from context_length field) + ServerConfig defaults
  - Known model: restored from settings_map
  - On save: settings_map[current_model] updated

Speculative Decoding section:
  - TextField showing filename + folder browse button (NSOpenPanel) + clear button
  - NSOpenPanel: starts in hf_cache dir, allowsOtherFileTypes=true (no UTType filter — .gguf not in system registry)
  - After selection: validates .gguf extension, then sends check_draft_compat action
  - Tokenizer compatibility check: Python reads vocab_size from both models via gguf package (~3-5s for 2 files)
  - Warning shown if vocab_size mismatch (orange Label with triangle icon)
  - "Checking tokenizer compatibility…" spinner while check runs
  - draft_model persisted per-model in draft_map: {model_path: draft_path}
  - On model switch: draft restored from draft_map automatically

Per-model persistence in settings.json:
  selected_model: str         — full_path of last selected model
  draft_model: str | null     — current model's draft (redundant with draft_map, kept for compat)
  draft_map: {path: path}     — per-model draft associations
  settings_map: {path: dict}  — per-model server settings
```

### save_settings action payload
```json
{
  "type": "action",
  "control_id": "save_settings",
  "settings": {
    "ctx_size": 131072, "n_gpu_layers": 99, "threads": 8,
    "batch_size": 512, "ubatch_size": 256,
    "temperature": 0.8, "top_p": 0.95, "top_k": 40, "repeat_penalty": 1.1,
    "flash_attn": true, "mlock": false,
    "draft_model": "/path/to/draft.gguf"
  }
}
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
```

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

---

## PBXPROJ CONVENTIONS

```
Object ID prefixes:
  AA0001-AA0025: app PBXBuildFile entries (AA0015 removed — AddSlotView deleted)
  AA1001-AA1025: app PBXFileReference entries
  AA0030-AA0031: resource build file entries (assets, icns)
  BB0001-BB0008: test-only PBXBuildFile entries
  BB1001-BB1008: test PBXFileReference entries
  BS0001-BS0012: shared source PBXBuildFile entries
  Current max app file: AA1025 = SettingsPanelView.swift

Adding a new Swift file to app:
  1. Add PBXBuildFile: AA00XX = {isa = PBXBuildFile; fileRef = AA10XX; };
  2. Add PBXFileReference: AA10XX = {...; path = File.swift; ...};
  3. Add to APP_GRP children
  4. Add to AA_SRC files
  5. If needed in tests: add BS00XX, add to BB_SRC
```

---

## BUILD & INSTALL

```bash
cd /Volumes/Marian_Backup/work/pylonrack/PylonRack
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
xcodebuild build -scheme PylonRack -destination 'platform=macOS' \
-derivedDataPath /tmp/pylonrack-build -configuration Debug

python3 -c "
import shutil; from pathlib import Path
src = Path('/tmp/pylonrack-build/Build/Products/Debug/PylonRack.app')
dst = Path('/Applications/PylonRack.app')
if dst.exists(): shutil.rmtree(dst)
shutil.copytree(src, dst)
"
```

---

## KNOWN ISSUES & CONSTRAINTS

```
[RESOLVED] psutil.net_connections() fails without root on macOS → lsof
[RESOLVED] orphan processes → killpg
[RESOLVED] WebView stale model → reload_ui + .id(reloadUIToken)
[RESOLVED] NSApp nil crash in tests → side effects in SettingsView
[RESOLVED] @testable import fails → shared sources BS series
[RESOLVED] WebSocket disconnect during cmake build → URLSession timeout=.infinity
[RESOLVED] receiveLoop reconnect during update → guard updateInProgress
[RESOLVED] AddSlotView dead code → deleted
[RESOLVED] Download blocks Python event loop → asyncio.create_task
[RESOLVED] Log unavailable when server stopped → file watcher reads from disk
[RESOLVED] Log text not selectable → single Text block + .textSelection(.enabled)
[ACTIVE] Rack log (RackLogView) does not persist across sessions — in-memory only
[ACTIVE] No test for deactivate→process actually dead
[ACTIVE] startup_delay: if venv creation > delay, connection fails
[ACTIVE] Warning status on heartbeat miss persists until next successful pong
[CONSTRAINT] pbxproj must be manually maintained
[CONSTRAINT] Test ports 19200-19215 hardcoded
```

---

## SLOT APP CONTRACT (for agent writing slot apps)

```
rack.json required fields: name(str), start(str), port(int 1-65535)
rack.json optional: stop(str), version(str), heartbeat_interval(int), startup_delay(int)
start command: run via /bin/zsh -c; reads PYLON_PORT env var

Slot app MUST:
  - bind WebSocket server on PYLON_PORT
  - respond to manifest with full manifest on EVERY connect
  - respond to ping with pong within heartbeat_interval seconds
  - respond to control_data for each dropdown
  - respond to action with action_result
  - respond to log_request with log_response (supports skip param for load more)
  - handle shutdown by sys.exit(0)
  - send controls_update when internal state changes
  - keep WebSocket server running when rack disconnects

action payload may include settings dict (for save_settings handler)
log_request includes skip:Int for "load earlier lines" feature

Reference implementation: /Volumes/Marian_Backup/work/pylonrack-slots/llama/
```

---

## AUDIT_LOG

```
2026-05-27 — Initial AGENTS.md

2026-05-28 — Major audit after debugging session
  Added: cmake PATH fix, correct build commands, binary_stale 3-state,
  show_log protocol, log streaming (total=-1), background check sequence,
  model manager handlers, anti-flicker controls_update, stop() wait semantics.

2026-05-29 — Major feature session audit
  FIXED:
  - WebSocket disconnect during cmake build: URLSession timeout=.infinity +
    receiveLoop guard updateInProgress + onRackLog diagnostics
  - Download progress: streaming via requests 1MB chunks, asyncio.create_task
  - Browse HuggingFace blank panel: searchResults not cleared on new query
  - Model/file list selection: highlight on click (selectedLocalModel, selectedFile)
  - Log from disk: file watcher (_watch_log_file) replaces on_log_line callback;
    log available even when server stopped; initial tail from file on log_request
  - Log text selection: single Text block + .textSelection(.enabled)
  - Log "load earlier lines": skip param in log_request, prepend=true response
  - Body panels visible when status==.warning (server idle, no ui_url)
  - save_settings closes panel on success (toggleMode → .webview)
  - selected_model persisted in settings.json (restored on slot restart)
  - draft_model persisted per-model in draft_map
  - Per-model settings via settings_map; ctx_size from GGUF metadata
  - Settings panel pushed automatically on model switch
  - Save & Restart disabled unless isDirty
  - Draft model: NSOpenPanel file picker (allowsOtherFileTypes=true),
    tokenizer compatibility check via gguf package (vocab_size comparison),
    warning displayed after dialog closes
  - llama-server start failure → auto show_log
  - Speculative decoding: -md flag for draft model

  ADDED FILES: SettingsPanelView.swift (AA1025)
  REMOVED FILES: AddSlotView.swift (AA1015/AA0015 — dead code)

  NEW PROTOCOL MESSAGES:
  - log_request: added skip:Int param
  - log_response: added prepend:Bool field
  - action: added settings:Dict field (save_settings)
  - get_settings / save_settings / check_draft_compat (action control_ids)

  NEW PYTHON DEPS: gguf>=0.9 (in requirements.txt)
  
  SLOT settings.json additions:
  - selected_model: str
  - draft_model: str|null
  - draft_map: {model_path: draft_path}
  - settings_map: {model_path: {server_settings}}
  - server.temperature, server.top_p, server.top_k, server.repeat_penalty
  - server.flash_attn, server.mlock

2026-05-30 — Remote slot removal refactor
  REMOVED:
  - Slot.host: String field (was always "localhost" in practice)
  - Slot.localPath: now non-optional String (was Optional with nil=remote)
  - Slot.isLocal computed property
  - All `if slot.isLocal { launch } else { connect }` branches in RackController
  - SlotConnection.effectiveURL host selection (now always localhost)
  - Documentation references to remote/host across DOCUMENTATION.md and AGENTS.md

  ADDED:
  - Slot.init(from:) custom decoder: tolerates legacy slots.json with `host`
    field; rejects entries without localPath (legacy remote slots throw
    DecodingError so they're skipped at load time)

  TESTS:
  - Removed test_remoteSlot_isNotLocal
  - Added test_decodesLegacySlotsJsonWithHost (backward compat verified)
  - Added test_rejectsLegacyRemoteSlot (legacy remote entries rejected)
  - Updated all Slot(name:, host:, port:[, isActive:]) -> Slot(name:, port:,
    localPath: "/tmp"[, isActive:]) across RackControllerTests and
    SlotConnectionTests via sed
  - Fixed IncomingMessageTests log_response case to match 3-param enum

  RESULT: 87 tests pass, BUILD SUCCEEDED. Simpler model surface; one
  fewer code path to maintain.
```
