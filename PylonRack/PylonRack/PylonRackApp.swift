import SwiftUI

@main
struct PylonRackApp: App {
    @StateObject private var rack         = RackController()
    @StateObject private var settingsStore = SettingsStore()
    private let system: SystemEnvironment  = MacSystemEnvironment()

    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    init() {
        // Reduce tooltip delay to 0.5s (default is ~2s)
        UserDefaults.standard.set(0.5, forKey: "NSInitialToolTipDelay")
        UserDefaults.standard.set(0.5, forKey: "NSToolTipDelay")
        // Apply persisted dock policy after MenuBarExtra sets .accessory.
        let showInDock = SettingsStore().current.showInDock
        if showInDock {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                MacSystemEnvironment().setDockVisibility(true)
            }
        }
    }

    var body: some Scene {
        MenuBarExtra {
            MenuBarMenuView()
                .environmentObject(rack)
        } label: {
            Image("rack-menubar")
                .resizable()
                .scaledToFit()
        }
        .menuBarExtraStyle(.menu)

        Window("PylonRack", id: "main") {
            ContentView()
                .environmentObject(rack)
        }
        .windowResizability(.contentSize)

        Window("Rack Log", id: "rack-log") {
            RackLogView()
                .environmentObject(rack)
        }
        .windowResizability(.contentSize)

        Settings {
            SettingsView(store: settingsStore, system: system)
        }
    }
}

// MARK: - Menu bar menu

struct MenuBarMenuView: View {
    @EnvironmentObject var rack: RackController
    @Environment(\.openWindow)   private var openWindow
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        if rack.slots.isEmpty {
            Text("No slots configured")
                .foregroundStyle(.secondary)
        } else {
            ForEach(rack.slots) { slot in
                if let conn = rack.connection(for: slot) {
                    MenuBarSlotRow(slot: slot, conn: conn) {
                        rack.selectedSlotId = slot.id
                        openWindow(id: "main")
                        NSApp.activate(ignoringOtherApps: true)
                    }
                }
            }
        }

        Divider()

        Button("Open PylonRack") {
            openWindow(id: "main")
            NSApp.activate(ignoringOtherApps: true)
        }

        Button("Rack Log…") {
            openWindow(id: "rack-log")
            NSApp.activate(ignoringOtherApps: true)
        }

        Button("Settings…") {
            openSettings()
            NSApp.activate(ignoringOtherApps: true)
        }

        Divider()

        Button("Quit") { NSApp.terminate(nil) }
    }
}

// MARK: - Per-slot row

struct MenuBarSlotRow: View {
    let slot: Slot
    @ObservedObject var conn: SlotConnection
    var onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            Text("\(dotEmoji) \(slot.name) — \(statusText)")
        }
    }

    private var dotEmoji: String {
        if !slot.isActive { return "⚪" }
        switch conn.status {
        case .connected:     return "🟢"
        case .connecting:    return "🔵"
        case .disconnecting: return "🟠"
        case .warning:       return "🟡"
        case .error:         return "🔴"
        case .missing:       return "⚪"
        }
    }

    private var statusText: String {
        if !slot.isActive { return "inactive" }
        switch conn.status {
        case .connected:     return "running"
        case .connecting:    return "connecting…"
        case .disconnecting: return "stopping…"
        case .warning:       return "warning"
        case .error:         return "error"
        case .missing:       return "missing"
        }
    }
}



// MARK: - App Delegate (termination cleanup)

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillTerminate(_ notification: Notification) {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/zsh")
        task.arguments = ["-c", "pkill -TERM -f server.py 2>/dev/null; sleep 1; pkill -KILL -f server.py 2>/dev/null"]
        try? task.run()
        task.waitUntilExit()
    }
}
