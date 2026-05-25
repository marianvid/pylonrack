import SwiftUI

@main
struct PylonRackApp: App {
    @StateObject private var rack = RackController()

    init() {
        // Apply persisted dock/activation policy before any window appears
        let settings = AppSettings.shared
        NSApp.setActivationPolicy(settings.showInDock ? .regular : .accessory)
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
            SettingsView()
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
                    MenuBarSlotSection(slot: slot, conn: conn, onOpen: {
                        rack.selectedSlotId = slot.id
                        openWindow(id: "main")
                        NSApp.activate(ignoringOtherApps: true)
                    })
                }
            }
        }

        Divider()

        Button("Open PylonRack") {
            openWindow(id: "main")
            NSApp.activate(ignoringOtherApps: true)
        }

        Button("Settings\u{2026}") {
            openSettings()
            NSApp.activate(ignoringOtherApps: true)
        }

        Divider()

        Button("Quit") { NSApp.terminate(nil) }
    }
}

// MARK: - Per-slot row

struct MenuBarSlotSection: View {
    let slot: Slot
    @ObservedObject var conn: SlotConnection
    var onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            Text("\(dotEmoji) \(slot.name) \u{2014} \(statusText)")
        }
    }

    private var dotEmoji: String {
        if !slot.isActive { return "\u{26AA}" }
        switch conn.status {
        case .connected:     return "\u{1F7E2}"
        case .connecting:    return "\u{1F535}"
        case .disconnecting: return "\u{1F7E0}"
        case .warning:       return "\u{1F7E1}"
        case .error:         return "\u{1F534}"
        case .missing:       return "\u{26AA}"
        }
    }

    private var statusText: String {
        if !slot.isActive { return "inactive" }
        switch conn.status {
        case .connected:     return "running"
        case .connecting:    return "connecting\u{2026}"
        case .disconnecting: return "stopping\u{2026}"
        case .warning:       return "warning"
        case .error:         return "error"
        case .missing:       return "missing"
        }
    }
}
