import SwiftUI

struct ContentView: View {
    @EnvironmentObject var rack: RackController
    @State private var showRemoveAlert = false

    private var selectedSlot: Slot? {
        rack.slots.first { $0.id == rack.selectedSlotId }
    }

    var body: some View {
        VStack(spacing: 0) {
            HSplitView {
                leftPanel
                rightPanel
            }
            StatusBarView()
                .environmentObject(rack)
        }
        .frame(minWidth: 800, minHeight: 500)
        .alert("Remove Slot", isPresented: $showRemoveAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Remove", role: .destructive) { removeSelected() }
        } message: {
            Text("Are you sure you want to remove \(selectedSlot?.name ?? "this slot")? This cannot be undone.")
        }
    }

    // MARK: - Left panel

    private var leftPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("PylonRack")
                .font(.headline)
                .padding(.horizontal, 12)
                .padding(.top, 12)
                .padding(.bottom, 8)

            HStack(spacing: 2) {
                Button { addSlotDirect() } label: {
                    Image(systemName: "plus").font(.system(size: 12))
                }
                .buttonStyle(RackIconButtonStyle())
                .help("Add slot")

                Button { showRemoveAlert = true } label: {
                    Image(systemName: "minus").font(.system(size: 12))
                }
                .buttonStyle(RackIconButtonStyle())
                .disabled(rack.selectedSlotId == nil)
                .help("Remove selected slot")

                Spacer()
            }
            .padding(.horizontal, 8)
            .padding(.bottom, 8)

            Divider()

            List(rack.slots, id: \.id, selection: $rack.selectedSlotId) { slot in
                if let conn = rack.connection(for: slot) {
                    SlotRowView(slot: slot, conn: conn) {
                        rack.toggleActive(slot)
                    } onReconnect: {
                        if conn.status == .error { Task { await rack.restart(slot) } }
                        else { rack.reconnect(slot) }
                    }
                    .tag(slot.id)
                }
            }
            .listStyle(.sidebar)
        }
        .frame(minWidth: 200, idealWidth: 240, maxWidth: 320)
    }

    // MARK: - Right panel

    @ViewBuilder
    private var rightPanel: some View {
        if let slot = selectedSlot, let conn = rack.connection(for: slot) {
            SlotDetailView(slot: slot, conn: conn,
                           onReconnect:   { rack.reconnect(slot) },
                           onRestart:     { Task { await rack.restart(slot) } },
                           onToggleMode:  { conn.toggleMode($0) })
        } else {
            emptyState
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "square.grid.2x2")
                .font(.system(size: 36))
                .foregroundStyle(.quaternary)
            Text("No slot selected")
                .font(.title3).foregroundStyle(.secondary)
            Text("Add a slot with + or select one from the list.")
                .font(.caption).foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Actions

    private func addSlotDirect() {
        let panel    = NSOpenPanel()
        let delegate = RackFolderDelegate()
        panel.delegate                = delegate
        panel.canChooseFiles          = false
        panel.canChooseDirectories    = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = URL(fileURLWithPath: SettingsStore().current.defaultLocation)
        panel.prompt       = "Add Slot"
        panel.message      = "Select a PylonRack slot folder (must contain rack.json)"

        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard let config = LocalSlotConfig.load(from: url) else { return }
        _ = delegate  // retain

        let slot = Slot(name: config.name, port: config.port, localPath: url.path)
        rack.addSlot(slot, config: config)
    }

    private func removeSelected() {
        guard let slot = selectedSlot else { return }
        rack.removeSlot(slot)
    }
}

// MARK: - Slot detail

struct SlotDetailView: View {
    let slot: Slot
    @ObservedObject var conn: SlotConnection
    var onReconnect:  () -> Void
    var onRestart:    () -> Void
    var onToggleMode: (BodyMode) -> Void

    var body: some View {
        VStack(spacing: 0) {
            if conn.status == .connected || conn.status == .warning {
                SlotControlsView(slot: slot, conn: conn, onToggleMode: onToggleMode)
                Divider()
            }
            bodyContent
        }
    }

    @ViewBuilder
    private var bodyContent: some View {
        switch conn.status {
        case .error:
            // Error — show status message prominently
            errorContent

        case .connecting, .disconnecting:
            VStack(spacing: 8) {
                ProgressView()
                Text(conn.status == .disconnecting ? "Disconnecting…" : "Connecting…")
                    .font(.title3).foregroundStyle(.secondary)
                if !conn.statusMessage.isEmpty {
                    Text(conn.statusMessage)
                        .font(.caption).foregroundStyle(.tertiary)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

        case .missing:
            if slot.isActive {
                // Active but missing = still trying
                VStack(spacing: 8) {
                    ProgressView()
                    Text("Connecting…")
                        .font(.title3).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                inactiveContent
            }

        default:
            let isLive = conn.status == .connected || conn.status == .warning
            if let wv = conn.webView, conn.status == .connected,
               let uiURL = conn.manifest?.uiURL, let url = URL(string: uiURL) {
                ZStack {
                    WebViewPanel(webView: wv, url: url)
                    if conn.bodyMode == .log {
                        LogView(conn: conn)
                            .background(Color(nsColor: .textBackgroundColor))
                    }
                    if conn.bodyMode == .models {
                        ModelManagerView(conn: conn)
                            .background(Color(nsColor: .textBackgroundColor))
                    }
                    if conn.bodyMode == .settings {
                        SettingsPanelView(conn: conn)
                            .background(Color(nsColor: .textBackgroundColor))
                    }
                }
            } else if isLive && conn.bodyMode == .log {
                LogView(conn: conn)
            } else if isLive && conn.bodyMode == .models {
                ModelManagerView(conn: conn)
            } else if isLive && conn.bodyMode == .settings {
                SettingsPanelView(conn: conn)
            } else {
                connectedPlaceholder
            }
        }
    }

    private var errorContent: some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 36))
                .foregroundStyle(.red)
            Text("Connection failed")
                .font(.title3).foregroundStyle(.primary)
            if !conn.statusMessage.isEmpty {
                Text(conn.statusMessage)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
            Text("Check the Rack Log for details.")
                .font(.caption).foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var inactiveContent: some View {
        VStack(spacing: 8) {
            Image(systemName: "pause.circle")
                .font(.system(size: 36)).foregroundStyle(.quaternary)
            Text("Slot inactive")
                .font(.title3).foregroundStyle(.secondary)
            Text("Press ▶ in the list to activate.")
                .font(.caption).foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var connectedPlaceholder: some View {
        VStack(spacing: 8) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 36)).foregroundStyle(.green)
            Text("Connected")
                .font(.title3).foregroundStyle(.secondary)
            if !conn.appMessage.isEmpty {
                Text(conn.appMessage)
                    .font(.caption).foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
