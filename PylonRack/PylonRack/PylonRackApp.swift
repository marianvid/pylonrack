import SwiftUI

@main
struct PylonRackApp: App {
    @StateObject private var rack         = RackController()
    @StateObject private var settingsStore = SettingsStore()
    private let system: SystemEnvironment  = MacSystemEnvironment()

    init() {
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
