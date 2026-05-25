import Foundation

private class WSDelegate: NSObject, URLSessionWebSocketDelegate {
    var onOpen:  (() -> Void)?
    var onClose: (() -> Void)?
    func urlSession(_ s: URLSession, webSocketTask: URLSessionWebSocketTask,
                    didOpenWithProtocol p: String?) { onOpen?() }
    func urlSession(_ s: URLSession, webSocketTask: URLSessionWebSocketTask,
                    didCloseWith code: URLSessionWebSocketTask.CloseCode,
                    reason: Data?) { onClose?() }
}

@MainActor
final class SlotConnection: ObservableObject {
    let slot: Slot

    @Published var status:        SlotStatus   = .connecting
    @Published var statusMessage: String       = ""
    @Published var manifest:      SlotManifest?
    @Published var showLog:       Bool         = false
    @Published var logLines:      [String]     = []
    @Published var logTotal:      Int          = 0
    @Published var processLog:    [String]     = []
    @Published var appMessage:    String       = ""

    private(set) var isActive: Bool = false
    private(set) var connectionCount: Int = 0  // for testing duplicate connection detection

    private var runtimePort:     Int?
    private var wsTask:          URLSessionWebSocketTask?
    private var urlSession:      URLSession?
    private var wsDelegate:      WSDelegate?
    private var heartbeatTimer:  Timer?
    private var receiveTask:     Task<Void, Never>?
    private var reconnectTask:    Task<Void, Never>?
    private var pendingPong:     Bool  = false
    private var missedBeats:     Int   = 0
    private var reconnectCount:  Int   = 0
    private var isReconnecting:  Bool  = false

    init(slot: Slot) { self.slot = slot }

    // MARK: - Public

    func activate(port: Int? = nil) {
        isActive       = true
        reconnectCount = 0
        runtimePort    = port
        status         = .connecting
        statusMessage  = "Connecting…"
        Task { await connect() }
    }

    func deactivate() {
        isActive = false
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

    func sendAction(_ buttonId: String) {
        send(["type": "action", "button_id": buttonId])
    }

    func sendShutdown() {
        send(["type": "shutdown"])
    }

    func requestLog(lines: Int = AppSettings.shared.logLinesPerRequest, offset: Int = 0) {
        send(["type": "log_request", "lines": lines, "offset": offset])
    }

    func appendProcessLog(_ text: String) {
        let lines = text.components(separatedBy: "\n").filter { !$0.isEmpty }
        processLog.append(contentsOf: lines)
        let maxLines = AppSettings.shared.logLinesPerRequest * 10
        if processLog.count > maxLines { processLog.removeFirst(processLog.count - maxLines) }
    }

    // MARK: - Private

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
        receiveTask?.cancel();  receiveTask  = nil
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
                    await self.handle(msg)
                } catch {
                    if !Task.isCancelled { await self.scheduleReconnect() }
                    break
                }
            }
        }
    }

    private func handle(_ msg: URLSessionWebSocketTask.Message) async {
        let raw: String
        switch msg {
        case .string(let s): raw = s
        case .data(let d):   raw = String(data: d, encoding: .utf8) ?? ""
        @unknown default:    return
        }
        guard let data = raw.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = json["type"] as? String else { return }

        switch type {
        case "pong":         handlePong(json)
        case "manifest":     handleManifest(raw)
        case "log_response": handleLogResponse(json)
        default: break
        }
    }

    private func handlePong(_ json: [String: Any]) {
        pendingPong    = false
        missedBeats    = 0
        reconnectCount = 0
        isReconnecting = false
        let msg        = json["message"] as? String ?? ""
        statusMessage  = msg
        appMessage     = msg
        switch json["status"] as? String ?? "running" {
        case "warning": status = .warning
        case "error":   status = .error
        default:        status = .connected
        }
    }

    private func handleManifest(_ raw: String) {
        guard let data = raw.data(using: .utf8),
              let m = try? JSONDecoder().decode(SlotManifest.self, from: data) else { return }
        manifest      = m
        status        = .connected
        if statusMessage.isEmpty { statusMessage = "Connected" }
        let interval  = Double(m.heartbeatInterval ?? AppSettings.shared.heartbeatInterval)
        startHeartbeat(interval: interval)
    }

    private func handleLogResponse(_ json: [String: Any]) {
        logLines = json["lines"] as? [String] ?? []
        logTotal = json["total"] as? Int ?? 0
    }

    private func startHeartbeat(interval: Double) {
        heartbeatTimer?.invalidate()
        heartbeatTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) {
            [weak self] _ in Task { @MainActor [weak self] in self?.tick() }
        }
    }

    private func tick() {
        if pendingPong {
            missedBeats += 1
            let max = AppSettings.shared.reconnectAttempts
            if missedBeats >= max { scheduleReconnect(); return }
            status        = .warning
            statusMessage = "No heartbeat (\(missedBeats) missed)"
        }
        pendingPong = true
        send(["type": "ping"])
    }

    private func scheduleReconnect() {
        guard !isReconnecting else { return }
        isReconnecting = true

        tearDown()
        guard isActive else { return }

        reconnectCount += 1
        let max = AppSettings.shared.reconnectAttempts
        if reconnectCount > max {
            status        = .error
            statusMessage = "Cannot connect after \(max) attempts"
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

    private func send(_ dict: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: dict),
              let str  = String(data: data, encoding: .utf8) else { return }
        wsTask?.send(.string(str)) { _ in }
    }
}
