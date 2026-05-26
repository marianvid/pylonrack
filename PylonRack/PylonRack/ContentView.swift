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
                        rack.reconnect(slot)
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
                           onRestart:   { Task { await rack.restart(slot) } })
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

    var body: some View {
        VStack(spacing: 0) {
            // Top bar
            HStack(spacing: 8) {
                Circle()
                    .fill(topBarColor)
                    .frame(width: 9, height: 9)
                    .animation(.easeInOut(duration: 0.3), value: topBarColor)

                Text(slot.name)
                    .font(.system(size: 13, weight: .semibold))

                Text("·").foregroundStyle(.tertiary)

                Text(topBarLabel)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)

                Spacer()

                // Smart refresh — always visible when active
                if slot.isActive && conn.status != .connecting && conn.status != .disconnecting {
                    Button {
                        refreshAction(slot: slot, conn: conn)
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 12))
                    }
                    .buttonStyle(RackIconButtonStyle())
                    .help(refreshTooltip(conn: conn))
                }

                // Log toggle — only when connected and has UI
                if (conn.status == .connected || conn.status == .warning),
                   conn.manifest?.uiURL != nil {
                    Button {
                        conn.showLog.toggle()
                        if conn.showLog { conn.requestLog() }
                    } label: {
                        Image(systemName: conn.showLog ? "doc.text.fill" : "doc.text")
                            .font(.system(size: 12))
                    }
                    .buttonStyle(RackIconButtonStyle())
                    .help(conn.showLog ? "Show UI" : "Show log")
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.bar)

            Divider()

            // Controls header — only when connected or warning
            if conn.status == .connected || conn.status == .warning {
                SlotControlsView(slot: slot, conn: conn)
            }

            // Body
            bodyContent
        }
    }

    private var topBarColor: Color {
        if slot.isActive && conn.status == .missing { return .orange }
        if !slot.isActive { return Color(nsColor: .systemGray) }
        return conn.status.color
    }

    private var topBarLabel: String {
        if slot.isActive && conn.status == .missing { return "Connecting…" }
        if !slot.isActive { return "Inactive" }
        return conn.status.label
    }

    // MARK: - Smart refresh

    private func refreshAction(slot: Slot, conn: SlotConnection) {
        switch conn.status {
        case .connected, .warning: onReconnect()
        case .error, .missing:     onRestart()
        default: break
        }
    }

    private func refreshTooltip(conn: SlotConnection) -> String {
        switch conn.status {
        case .connected, .warning: return "Reconnect"
        case .error, .missing:     return "Restart"
        default:                   return "Refresh"
        }
    }

    @ViewBuilder
    private var bodyContent: some View {
        switch conn.status {
        case .error:
            // Error — show status message prominently
            errorContent

        case .connecting, .disconnecting:
            // Transitioning — show spinner + message
            VStack(spacing: 8) {
                ProgressView()
                Text(topBarLabel)
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
            } else if let uiURL = conn.manifest?.uiURL, let url = URL(string: uiURL) {
                WebViewPanel(url: url)
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
