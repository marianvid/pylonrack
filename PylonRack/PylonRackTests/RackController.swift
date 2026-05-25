import Foundation

@MainActor
final class RackController: ObservableObject {
    @Published var slots: [Slot] = []
    @Published var selectedSlotId: UUID?

    private var connections:  [UUID: SlotConnection]  = [:]
    private var processes:    [UUID: SlotProcess]     = [:]
    private var configs:      [UUID: LocalSlotConfig] = [:]
    private var runtimePorts: [UUID: Int]             = [:]

    private let slotsURL: URL

    // Production init
    convenience init() {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory,
                                           in: .userDomainMask).first!
            .appendingPathComponent("PylonRack")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        self.init(slotsURL: dir.appendingPathComponent("slots.json"))
    }

    // Testable init
    init(slotsURL: URL) {
        self.slotsURL = slotsURL
        loadSlots()
        for slot in slots {
            let conn = makeConnection(for: slot)
            if slot.isActive {
                if slot.isLocal {
                    launchProcess(for: slot, conn: conn)
                } else {
                    conn.activate()
                }
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
        let conn = makeConnection(for: s)
        conn.deactivate()
        saveSlots()
    }

    func removeSlot(_ slot: Slot) {
        Task {
            await deactivate(slot)
            connections.removeValue(forKey: slot.id)
            processes.removeValue(forKey: slot.id)
            configs.removeValue(forKey: slot.id)
            runtimePorts.removeValue(forKey: slot.id)
            slots.removeAll { $0.id == slot.id }
            saveSlots()
        }
    }

    func toggleActive(_ slot: Slot) {
        if slot.isActive {
            Task { await deactivate(slot) }
        } else {
            activate(slot)
        }
    }

    func reconnect(_ slot: Slot) {
        connections[slot.id]?.reconnect()
    }

    func connection(for slot: Slot) -> SlotConnection? {
        connections[slot.id]
    }

    // MARK: - Activate

    func activate(_ slot: Slot) {
        guard let idx = slots.firstIndex(where: { $0.id == slot.id }) else { return }
        slots[idx].isActive = true
        saveSlots()

        let conn = connections[slot.id] ?? makeConnection(for: slots[idx])

        if slots[idx].isLocal {
            launchProcess(for: slots[idx], conn: conn)
        } else {
            conn.activate()
        }
    }

    // MARK: - Deactivate

    func deactivate(_ slot: Slot) async {
        guard let idx = slots.firstIndex(where: { $0.id == slot.id }) else { return }

        // Signal disconnecting state immediately
        connections[slot.id]?.status        = .disconnecting
        connections[slot.id]?.statusMessage = "Disconnecting…"

        if slots[idx].isLocal {
            // 1. WS shutdown
            connections[slot.id]?.sendShutdown()
            try? await Task.sleep(nanoseconds: 3_000_000_000)

            // 2. Stop script
            if let config = configs[slot.id], let stopCmd = config.stop,
               let path = slots[idx].localPath {
                await processes[slot.id]?.runScript(stopCmd, workingDir: path)
            }

            // 3. SIGTERM + wait up to 3s with polling
            processes[slot.id]?.sendSIGTERM()
            for _ in 0..<30 {
                if processes[slot.id]?.isRunning != true { break }
                try? await Task.sleep(nanoseconds: 100_000_000) // 100ms
            }

            // 4. SIGKILL if still alive
            if processes[slot.id]?.isRunning == true {
                processes[slot.id]?.sendSIGKILL()
            }
            processes.removeValue(forKey: slot.id)
            runtimePorts.removeValue(forKey: slot.id)
        }

        connections[slot.id]?.deactivate()
        slots[idx].isActive = false
        saveSlots()
    }

    // MARK: - Private

    @discardableResult
    private func makeConnection(for slot: Slot) -> SlotConnection {
        let conn = SlotConnection(slot: slot)
        connections[slot.id] = conn
        return conn
    }

    private func launchProcess(for slot: Slot, conn: SlotConnection) {
        guard let path = slot.localPath else { return }
        let folderURL = URL(fileURLWithPath: path)

        // Load config if not cached
        if configs[slot.id] == nil {
            configs[slot.id] = LocalSlotConfig.load(from: folderURL)
        }
        guard let config = configs[slot.id] else {
            conn.status        = .error
            conn.statusMessage = "rack.json not found"
            return
        }

        // Find free port starting from preferred
        let port = findFreePort(startingFrom: config.port)
        runtimePorts[slot.id] = port

        let proc = SlotProcess()
        proc.onOutput = { [weak conn] text in
            conn?.appendProcessLog(text)
        }
        proc.onTerminate = { [weak self, weak conn] in
            guard let self, let conn else { return }
            if conn.status != .connected {
                conn.status        = .error
                conn.statusMessage = "Process exited"
            }
            self.processes.removeValue(forKey: slot.id)
        }
        processes[slot.id] = proc

        do {
            try proc.launch(command: config.start, workingDir: path, port: port)
            // Small delay to let the process bind before we connect
            Task {
                try? await Task.sleep(nanoseconds: 500_000_000)
                conn.activate(port: port)
            }
        } catch {
            conn.status        = .error
            conn.statusMessage = "Launch failed: \(error.localizedDescription)"
        }
    }

    // MARK: - Persistence

    private func loadSlots() {
        guard let data = try? Data(contentsOf: slotsURL),
              let list = try? JSONDecoder().decode([Slot].self, from: data) else { return }
        slots = list
        for slot in slots where slot.isLocal {
            if let path = slot.localPath {
                configs[slot.id] = LocalSlotConfig.load(from: URL(fileURLWithPath: path))
            }
        }
    }

    private func saveSlots() {
        if let data = try? JSONEncoder().encode(slots) {
            try? data.write(to: slotsURL)
        }
    }
}
