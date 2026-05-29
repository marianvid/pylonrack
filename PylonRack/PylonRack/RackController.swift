import Foundation

@MainActor
final class RackController: ObservableObject {
    @Published var slots:          [Slot] = []
    @Published var selectedSlotId: UUID?
    @Published var rackLog:        [RackLogEntry] = []

    var rackSummary: String {
        let total    = slots.count
        let running  = slots.filter { connections[$0.id]?.status == .connected }.count
        let inactive = slots.filter { !$0.isActive }.count
        if total == 0 { return "No slots" }
        var parts = ["\(total) slot\(total == 1 ? "" : "s")"]
        if running  > 0 { parts.append("\(running) running") }
        if inactive > 0 { parts.append("\(inactive) inactive") }
        return parts.joined(separator: " · ")
    }

    private var connections:  [UUID: SlotConnection]  = [:]
    private var processes:    [UUID: SlotProcess]     = [:]
    private var configs:      [UUID: LocalSlotConfig] = [:]
    private var runtimePorts: [UUID: Int]             = [:]

    private let slotsURL: URL
    private let settingsStore: SettingsStore

    convenience init() {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory,
                                           in: .userDomainMask).first!
            .appendingPathComponent("PylonRack")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        self.init(
            slotsURL:      dir.appendingPathComponent("slots.json"),
            settingsStore: SettingsStore()
        )
    }

    init(slotsURL: URL, settingsStore: SettingsStore = SettingsStore()) {
        self.slotsURL      = slotsURL
        self.settingsStore = settingsStore
        loadSlots()
        for slot in slots {
            let conn = makeConnection(for: slot)
            if slot.isActive {
                launchProcess(for: slot, conn: conn)
            } else {
                conn.deactivate()
            }
        }
    }

    // MARK: - Public

    func addSlot(_ slot: Slot, config: LocalSlotConfig? = nil) {
        var s = slot
        s.isActive = false
        if let c = config { configs[s.id] = c }
        slots.append(s)
        makeConnection(for: s).deactivate()
        if slots.count == 1 { selectedSlotId = s.id }
        saveSlots()
    }

    func removeSlot(_ slot: Slot) {
        Task {
            await deactivate(slot)
            // Clear selection and remove only after shutdown completes
            if selectedSlotId == slot.id { selectedSlotId = nil }
            connections.removeValue(forKey: slot.id)
            processes.removeValue(forKey: slot.id)
            configs.removeValue(forKey: slot.id)
            runtimePorts.removeValue(forKey: slot.id)
            slots.removeAll { $0.id == slot.id }
            saveSlots()
            log("Removed \(slot.name)")
        }
    }

    func toggleActive(_ slot: Slot) {
        if slot.isActive { Task { await deactivate(slot) } }
        else             { activate(slot) }
    }

    func reconnect(_ slot: Slot) {
        connections[slot.id]?.reconnect()
    }

    func restart(_ slot: Slot) async {
        log("Restarting \(slot.name)")
        await deactivate(slot)
        guard let idx = slots.firstIndex(where: { $0.id == slot.id }) else { return }
        slots[idx].isActive = true
        saveSlots()
        let conn = makeConnection(for: slots[idx])
        launchProcess(for: slots[idx], conn: conn)
    }

    func connection(for slot: Slot) -> SlotConnection? {
        connections[slot.id]
    }

    // MARK: - Activate

    func activate(_ slot: Slot) {
        guard let idx = slots.firstIndex(where: { $0.id == slot.id }) else { return }
        slots[idx].isActive = true
        selectedSlotId = slot.id   // auto-select on activate
        saveSlots()
        log("Activating \(slot.name)")
        let conn = connections[slot.id] ?? makeConnection(for: slots[idx])
        launchProcess(for: slots[idx], conn: conn)
    }

    // MARK: - Deactivate

    func deactivate(_ slot: Slot) async {
        guard let idx = slots.firstIndex(where: { $0.id == slot.id }) else { return }

        connections[slot.id]?.status        = .disconnecting
        connections[slot.id]?.statusMessage = "Disconnecting…"

        let connIsActive = connections[slot.id].map {
            $0.status == .connected || $0.status == .warning || $0.status == .connecting
        } ?? false
        if connIsActive {
            connections[slot.id]?.sendShutdown()
            try? await Task.sleep(nanoseconds: 3_000_000_000)
        }
        if let config = configs[slot.id], let stopCmd = config.stop {
            await processes[slot.id]?.runScript(stopCmd, workingDir: slots[idx].localPath)
        }
        processes[slot.id]?.sendSIGTERM()
        for _ in 0..<30 {
            if processes[slot.id]?.isRunning != true { break }
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        if processes[slot.id]?.isRunning == true { processes[slot.id]?.sendSIGKILL() }
        processes.removeValue(forKey: slot.id)
        runtimePorts.removeValue(forKey: slot.id)

        connections[slot.id]?.deactivate()
        slots[idx].isActive = false
        saveSlots()
    }

    // MARK: - Private

    @discardableResult
    private func makeConnection(for slot: Slot) -> SlotConnection {
        let conn = SlotConnection(slot: slot, settings: settingsStore.current)
        conn.onRackLog = { [weak self] message in self?.log(message) }
        connections[slot.id] = conn
        return conn
    }

    private func launchProcess(for slot: Slot, conn: SlotConnection) {
        let path = slot.localPath
        let folderURL = URL(fileURLWithPath: path)

        if configs[slot.id] == nil {
            configs[slot.id] = LocalSlotConfig.load(from: folderURL)
        }
        guard let config = configs[slot.id] else {
            conn.status        = .error
            conn.statusMessage = "rack.json not found"
            log("[\(slot.name)] Error: rack.json not found")
            return
        }

        let port = findFreePort(startingFrom: config.port)
        runtimePorts[slot.id] = port

        let proc = SlotProcess()
        proc.onOutput    = { [weak conn] text in conn?.appendProcessLog(text) }
        proc.onTerminate = { [weak self, weak conn] in
            guard let self, let conn else { return }
            if conn.status == .connected || conn.status == .warning {
                conn.status        = .error
                conn.statusMessage = "Process exited unexpectedly"
                self.log("[\(slot.name)] Process exited unexpectedly")
            }
            self.processes.removeValue(forKey: slot.id)
        }
        processes[slot.id] = proc

        do {
            try proc.launch(command: config.start, workingDir: path, port: port)
            log("[\(slot.name)] Launched on port \(port)")
            let delay = UInt64(config.startupDelay ?? 0) * 1_000_000_000
            if delay > 0 {
                Task {
                    try? await Task.sleep(nanoseconds: delay)
                    conn.activate(port: port)
                }
            } else {
                conn.activate(port: port)
            }
        } catch {
            conn.status        = .error
            conn.statusMessage = "Launch failed: \(error.localizedDescription)"
            log("[\(slot.name)] Launch failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Persistence

    private func loadSlots() {
        guard let data = try? Data(contentsOf: slotsURL),
              let list = try? JSONDecoder().decode([Slot].self, from: data) else { return }
        slots = list
        for slot in slots {
            configs[slot.id] = LocalSlotConfig.load(from: URL(fileURLWithPath: slot.localPath))
        }
    }

    private func saveSlots() {
        try? JSONEncoder().encode(slots).write(to: slotsURL)
    }

    // MARK: - Rack Log

    func log(_ message: String) {
        let entry = RackLogEntry(message: message)
        rackLog.append(entry)
        if rackLog.count > 500 { rackLog.removeFirst(rackLog.count - 500) }
    }
}
