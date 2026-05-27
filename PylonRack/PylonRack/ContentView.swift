import SwiftUI

struct ContentView: View {
    @EnvironmentObject var rack: RackController
    @State private var showAddSlot     = false
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
        .sheet(isPresented: $showAddSlot) {
            AddSlotView { slot, config in rack.addSlot(slot, config: config) }
        }
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
                Button { showAddSlot = true } label: {
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
                           onReconnect: { rack.reconnect(slot) },
                           onRestart:   { Task { await rack.restart(slot) } },
                           onToggleLog: {
                               conn.showLog.toggle()
                               if conn.showLog { conn.requestLog() }
                           })
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

    private func removeSelected() {
        guard let slot = selectedSlot else { return }
        rack.removeSlot(slot)
    }
}

// MARK: - Slot detail

struct SlotDetailView: View {
    let slot: Slot
    @ObservedObject var conn: SlotConnection
    var onReconnect: () -> Void
    var onRestart:   () -> Void
    var onToggleLog: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Controls bar — always at top, only when connected
            if conn.status == .connected || conn.status == .warning {
                SlotControlsView(slot: slot, conn: conn,
                                 showLog: conn.showLog,
                                 onToggleLog: onToggleLog)
                Divider()
            }

            // Body
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
            // Connected or warning
            if conn.showLog {
                LogView(conn: conn)
            } else if conn.status == .connected,
                      let uiURL = conn.manifest?.uiURL,
                      let url = URL(string: uiURL) {
                // WebView only when fully connected (status=running from slot)
                // warning = slot reachable but backend not running → show placeholder
                WebViewPanel(url: url, reloadToken: conn.reloadUIToken)
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
