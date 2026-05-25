import SwiftUI

struct StatusBarView: View {
    @EnvironmentObject var rack: RackController

    private var selectedSlot: Slot? {
        guard let id = rack.selectedSlotId else { return nil }
        return rack.slots.first { $0.id == id }
    }

    var body: some View {
        VStack(spacing: 0) {
            Divider()

            if let slot = selectedSlot,
               let conn = rack.connection(for: slot) {
                StatusBarTwoLineView(rackSummary: rack.rackSummary, slot: slot, conn: conn)
            } else {
                // Single line — no slot selected
                HStack {
                    Text(rack.rackSummary)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
                .background(.bar)
            }
        }
    }
}

// Two-line view — observes conn directly for instant updates
private struct StatusBarTwoLineView: View {
    let rackSummary: String
    let slot: Slot
    @ObservedObject var conn: SlotConnection

    var body: some View {
        VStack(spacing: 0) {
            // Line 1 — rack info + connection state
            HStack {
                Text(rackSummary)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Spacer()
                // Connection status from rack (only when not connected)
                if conn.status != .connected || conn.statusMessage.isEmpty {
                    Text(connStatusText)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .animation(.easeInOut(duration: 0.15), value: connStatusText)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
            .background(.bar)

            // Line 2 — app message (only when active and received at least one pong)
            if slot.isActive && !conn.appMessage.isEmpty {
                Divider()
                HStack {
                    Text(slot.name)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                    Text("\u{00B7}")
                        .foregroundStyle(.tertiary)
                        .font(.system(size: 11))
                    Text(conn.appMessage)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .animation(.easeInOut(duration: 0.15), value: conn.appMessage)
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
                .background(.bar)
            }
        }
    }

    private var connStatusText: String {
        switch conn.status {
        case .connecting:    return "Connecting\u{2026}"
        case .disconnecting: return "Disconnecting\u{2026}"
        case .warning:       return conn.statusMessage.isEmpty ? "Warning" : conn.statusMessage
        case .error:         return conn.statusMessage.isEmpty ? "Error"   : conn.statusMessage
        case .missing:       return "Inactive"
        case .connected:     return conn.statusMessage
        }
    }
}
