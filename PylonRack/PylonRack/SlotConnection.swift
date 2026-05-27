import Foundation

// MARK: - WebSocket delegate bridge

private final class WSDelegate: NSObject, URLSessionWebSocketDelegate {
    var onOpen:  (() -> Void)?
    var onClose: (() -> Void)?

    func urlSession(_ s: URLSession, webSocketTask t: URLSessionWebSocketTask,
                    didOpenWithProtocol p: String?) { onOpen?() }
    func urlSession(_ s: URLSession, webSocketTask t: URLSessionWebSocketTask,
                    didCloseWith code: URLSessionWebSocketTask.CloseCode,
                    reason: Data?) { onClose?() }
}

// MARK: - Incoming message

// Typed representation of every message the rack receives from a slot app.
// Decoding is centralised here — SlotConnection only dispatches on type.

enum IncomingMessage {
    case pong(status: String, message: String)
    case manifest(SlotManifest)
    case logResponse(lines: [String], total: Int)
    case controlData(controlId: String, items: [String])
    case controlsUpdate(updates: [[String: Any]])
    case reloadUI
    case actionResult   // acknowledged, no action needed
    case unknown

    static func decode(from raw: String) -> IncomingMessage {
        guard let data = raw.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = json["type"] as? String
        else { return .unknown }

        switch type {
        case "pong":
            return .pong(
                status:  json["status"]  as? String ?? "running",
                message: json["message"] as? String ?? ""
            )
        case "manifest":
            guard let m = try? JSONDecoder().decode(SlotManifest.self, from: data)
            else { return .unknown }
            return .manifest(m)
        case "log_response":
            return .logResponse(
                lines: json["lines"] as? [String] ?? [],
                total: json["total"] as? Int ?? 0
            )
        case "control_data":
            guard let id    = json["control_id"] as? String,
                  let items = json["items"]       as? [String]
            else { return .unknown }
            return .controlData(controlId: id, items: items)
        case "controls_update":
            return .controlsUpdate(updates: json["controls"] as? [[String: Any]] ?? [])
        case "reload_ui":
            return .reloadUI
        case "action_result":
            return .actionResult
        default:
            return .unknown
        }
    }
}

// MARK: - SlotConnection

@MainActor
final class SlotConnection: ObservableObject {
    let slot: Slot

    @Published var status:        SlotStatus    = .connecting
    @Published var statusMessage: String        = ""
    @Published var manifest:      SlotManifest?
    @Published var controls:      [SlotControl] = []
    @Published var showLog:       Bool          = false
    @Published var logLines:      [String]      = []
    @Published var logTotal:      Int           = 0
    @Published var processLog:    [String]      = []
    @Published var appMessage:    String        = ""
    @Published var reloadUIToken: UUID          = UUID()  // changes → WebView reloads

    private(set) var isActive:        Bool = false
    private(set) var connectionCount: Int  = 0

    // Injected settings — avoids singleton coupling, enables testing without globals.
    private let settings: AppConfig

    // Optional callback to report errors to the rack log
    var onRackLog: ((String) -> Void)?

    private var runtimePort:    Int?
    private var wsTask:         URLSessionWebSocketTask?
    private var urlSession:     URLSession?
    private var wsDelegate:     WSDelegate?
    private var heartbeatTimer: Timer?
    private var receiveTask:    Task<Void, Never>?
    private var reconnectTask:  Task<Void, Never>?
    private var pendingPong:    Bool = false
    private var missedBeats:    Int  = 0
    private var reconnectCount: Int  = 0
    private var isReconnecting: Bool = false

    init(slot: Slot, settings: AppConfig = SettingsStore().current) {
        self.slot     = slot
        self.settings = settings
    }

    // MARK: - Public API

    func activate(port: Int? = nil) {
        isActive       = true
        reconnectCount = 0
        runtimePort    = port
        status         = .connecting
        statusMessage  = "Connecting…"
        Task { await connect() }
    }

    func deactivate() {
        isActive      = false
        tearDown()
        status        = .missing
        statusMessage = "Inactive"
    }

    func reconnect() {
        guard isActive else { return }
        reconnectTask?.cancel(); reconnectTask = nil
        isReconnecting = false
        reconnectCount = 0
        status         = .connecting
        statusMessage  = "Connecting…"
        Task { await connect() }
    }

    func sendAction(_ controlId: String, value: String? = nil) {
        var dict: [String: Any] = ["type": "action", "control_id": controlId]
        if let v = value { dict["value"] = v }
        send(dict)
    }

    func requestControlData(_ controlId: String) {
        send(["type": "control_data", "control_id": controlId])
    }

    func sendShutdown() {
        send(["type": "shutdown"])
    }

    func requestLog(lines: Int? = nil, offset: Int = 0) {
        send(["type": "log_request",
              "lines":  lines ?? settings.logLinesPerRequest,
              "offset": offset])
    }

    func appendProcessLog(_ text: String) {
        let incoming = text.components(separatedBy: "\n").filter { !$0.isEmpty }
        processLog.append(contentsOf: incoming)
        let cap = settings.logLinesPerRequest * 10
        if processLog.count > cap { processLog.removeFirst(processLog.count - cap) }
    }

    // MARK: - Connection lifecycle

    private var effectiveURL: URL? {
        let port = runtimePort ?? slot.port
        let host = slot.isLocal ? "localhost" : slot.host
        return URL(string: "ws://\(host):\(port)")
    }

    private func connect() async {
        guard isActive, let url = effectiveURL else { return }
        tearDown()
        isReconnecting = false

        let del     = WSDelegate()
        wsDelegate  = del
        let session = URLSession(configuration: .default, delegate: del, delegateQueue: nil)
        urlSession  = session
        let task    = session.webSocketTask(with: url)
        wsTask      = task

        del.onOpen  = { [weak self] in Task { await self?.onConnected() } }
        del.onClose = { [weak self] in Task { await self?.onDropped()   } }

        task.resume()
        startReceiveLoop(task: task)
    }

    private func tearDown() {
        receiveTask?.cancel();   receiveTask   = nil
        reconnectTask?.cancel(); reconnectTask = nil
        heartbeatTimer?.invalidate(); heartbeatTimer = nil
        wsTask?.cancel(); wsTask = nil
        urlSession = nil; wsDelegate = nil
        pendingPong = false; missedBeats = 0
    }

    private func onConnected() async {
        reconnectCount  = 0
        isReconnecting  = false
        connectionCount += 1
        processLog      = []
        controls        = []
        send(["type": "manifest"])
    }

    private func onDropped() async {
        heartbeatTimer?.invalidate(); heartbeatTimer = nil
        guard isActive else { return }
        scheduleReconnect()
    }

    private func startReceiveLoop(task: URLSessionWebSocketTask) {
        receiveTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self, let t = await self.wsTask else { break }
                do {
                    let msg = try await t.receive()
                    await self.dispatch(IncomingMessage.decode(from: rawString(msg)))
                } catch {
                    if !Task.isCancelled { await self.scheduleReconnect() }
                    break
                }
            }
        }
    }

    // MARK: - Message dispatch

    private func dispatch(_ message: IncomingMessage) async {
        switch message {
        case .pong(let statusStr, let msg):
            handlePong(status: statusStr, message: msg)
        case .manifest(let m):
            handleManifest(m)
        case .logResponse(let lines, let total):
            if total == -1 {
                // Streaming append — live push from slot app
                logLines.append(contentsOf: lines)
                let cap = settings.logLinesPerRequest * 20
                if logLines.count > cap { logLines.removeFirst(logLines.count - cap) }
            } else {
                // Full fetch response
                logLines = lines
                logTotal = total
            }
        case .controlData(let id, let items):
            if let idx = controls.firstIndex(where: { $0.id == id }) {
                controls[idx].items = items
            }
        case .controlsUpdate(let updates):
            applyControlsUpdate(updates)
        case .reloadUI:
            reloadUIToken = UUID()
        case .actionResult, .unknown:
            break
        }
    }

    private func handlePong(status statusStr: String, message: String) {
        pendingPong    = false
        missedBeats    = 0
        reconnectCount = 0
        isReconnecting = false
        statusMessage  = message
        appMessage     = message
        switch statusStr {
        case "warning": status = .warning
        case "error":   status = .error
        default:        status = .connected
        }
    }

    private func handleManifest(_ m: SlotManifest) {
        manifest  = m
        controls  = m.controls
        status    = .connected
        if statusMessage.isEmpty { statusMessage = "Connected" }
        let interval = Double(m.heartbeatInterval ?? settings.heartbeatInterval)
        startHeartbeat(interval: interval)
        for ctrl in m.controls where ctrl.type == .dropdown {
            requestControlData(ctrl.id)
        }
    }

    private func applyControlsUpdate(_ updates: [[String: Any]]) {
        for update in updates {
            guard let id  = update["id"] as? String,
                  let idx = controls.firstIndex(where: { $0.id == id }) else { continue }
            if let label    = update["label"]  as? String { controls[idx].label = label }
            if let value    = update["value"]  as? String { controls[idx].value = value }
            if let badge    = update["badge"]  as? Bool   { controls[idx].badge = badge }
            if let styleStr = update["style"]  as? String,
               let style    = ControlStyle(rawValue: styleStr) { controls[idx].style = style }
            if let items    = update["items"]  as? [String] { controls[idx].items = items }
        }
    }

    // MARK: - Heartbeat

    private func startHeartbeat(interval: Double) {
        heartbeatTimer?.invalidate()
        heartbeatTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) {
            [weak self] _ in Task { @MainActor [weak self] in self?.tick() }
        }
    }

    private func tick() {
        if pendingPong {
            missedBeats += 1
            if missedBeats >= settings.reconnectAttempts { scheduleReconnect(); return }
            status        = .warning
            statusMessage = "No heartbeat (\(missedBeats) missed)"
        }
        pendingPong = true
        send(["type": "ping"])
    }

    // MARK: - Reconnect

    private func scheduleReconnect() {
        guard !isReconnecting else { return }
        isReconnecting = true
        tearDown()
        guard isActive else { return }

        reconnectCount += 1
        let max = settings.reconnectAttempts
        if reconnectCount > max {
            status         = .error
            statusMessage  = "Cannot connect after \(max) attempts"
            onRackLog?("[\(slot.name)] Cannot connect after \(max) attempts")
            isReconnecting = false
            return
        }

        status        = .connecting
        statusMessage = "Connecting… (\(reconnectCount)/\(max))"

        reconnectTask = Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            guard !Task.isCancelled else { return }
            isReconnecting = false
            await self.connect()
        }
    }

    // MARK: - Send

    private func send(_ dict: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: dict),
              let str  = String(data: data, encoding: .utf8) else { return }
        wsTask?.send(.string(str)) { _ in }
    }
}

// MARK: - Helpers

private func rawString(_ msg: URLSessionWebSocketTask.Message) -> String {
    switch msg {
    case .string(let s): return s
    case .data(let d):   return String(data: d, encoding: .utf8) ?? ""
    @unknown default:    return ""
    }
}
