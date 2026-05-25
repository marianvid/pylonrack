import SwiftUI

struct ContentView: View {
    @EnvironmentObject var rack: RackController
    @State private var showAddSlot    = false
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

                Button { refreshSelected() } label: {
                    Image(systemName: "arrow.clockwise").font(.system(size: 12))
                }
                .buttonStyle(RackIconButtonStyle())
                .disabled(rack.selectedSlotId == nil)
                .help("Reconnect selected slot")

                Spacer()
            }
            .padding(.horizontal, 8)
            .padding(.bottom, 8)

            Divider()

            List(rack.slots, id: \.id, selection: $rack.selectedSlotId) { slot in
                if let conn = rack.connection(for: slot) {
                    SlotRowView(slot: slot, conn: conn) {
                        rack.toggleActive(slot)
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
            SlotDetailView(slot: slot, conn: conn)
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

    private func refreshSelected() {
        guard let slot = selectedSlot else { return }
        rack.reconnect(slot)
    }
}

// MARK: - Slot detail

struct SlotDetailView: View {
    let slot: Slot
    @ObservedObject var conn: SlotConnection

    var body: some View {
        VStack(spacing: 0) {
            // Top bar — name + status only
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
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.bar)

            Divider()

            // Content
            if conn.showLog {
                LogView(conn: conn)
            } else {
                mainContent
            }
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

    @ViewBuilder
    private var mainContent: some View {
        VStack(spacing: 12) {
            if !slot.isActive && conn.status == .missing {
                Image(systemName: "pause.circle")
                    .font(.system(size: 36)).foregroundStyle(.quaternary)
                Text("Slot inactive")
                    .font(.title3).foregroundStyle(.secondary)
                Text("Press \u{25B6} in the list to activate.")
                    .font(.caption).foregroundStyle(.tertiary)
            } else if conn.status == .connecting || (slot.isActive && conn.status == .missing) {
                ProgressView()
                Text("Connecting\u{2026}")
                    .font(.title3).foregroundStyle(.secondary)
            } else if conn.status == .disconnecting {
                ProgressView()
                Text("Disconnecting\u{2026}")
                    .font(.title3).foregroundStyle(.secondary)
            } else if conn.manifest != nil {
                Image(systemName: "checkmark.circle")
                    .font(.system(size: 36)).foregroundStyle(.green)
                Text("Connected")
                    .font(.title3).foregroundStyle(.secondary)
                Text("UI panel and action buttons \u{2014} coming next.")
                    .font(.caption).foregroundStyle(.tertiary)
            } else {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 36)).foregroundStyle(.orange)
                Text(conn.status.label)
                    .font(.title3).foregroundStyle(.secondary)
                if !conn.statusMessage.isEmpty {
                    Text(conn.statusMessage)
                        .font(.caption).foregroundStyle(.tertiary)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
