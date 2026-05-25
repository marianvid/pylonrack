import SwiftUI

struct SlotRowView: View {
    let slot: Slot
    @ObservedObject var conn: SlotConnection
    var onToggleActive: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {

            // Row 1 — name
            Text(slot.name)
                .font(.system(size: 13, weight: .medium))
                .lineLimit(1)

            // Row 2 — status dot + label + controls
            HStack(spacing: 4) {
                // Animated status dot
                Circle()
                    .fill(statusColor)
                    .frame(width: 7, height: 7)
                    .animation(.easeInOut(duration: 0.3), value: statusColor)

                Text(statusText)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .animation(.easeInOut(duration: 0.2), value: statusText)

                Spacer()

                // Log toggle
                Button {
                    conn.showLog.toggle()
                    if conn.showLog { conn.requestLog() }
                } label: {
                    Image(systemName: conn.showLog ? "doc.text.fill" : "doc.text")
                        .font(.system(size: 11))
                        .foregroundStyle(conn.showLog ? Color.white.opacity(0.9) : .secondary)
                }
                .buttonStyle(RackIconButtonStyle())
                .help(conn.showLog ? "Show UI panel" : "Show log")

                // Activate / Deactivate
                Button { onToggleActive() } label: {
                    Image(systemName: activateIcon)
                        .font(.system(size: 11))
                        .foregroundStyle(activateColor)
                }
                .buttonStyle(RackIconButtonStyle())
                .disabled(isTransitioning)
                .help(activateTooltip)
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - Computed

    private var isTransitioning: Bool {
        conn.status == .connecting || conn.status == .disconnecting
    }

    private var statusColor: Color {
        if slot.isActive && conn.status == .missing { return .orange }
        return conn.status.color
    }

    private var statusText: String {
        // Show connecting immediately after activate — before conn.status updates
        if slot.isActive && conn.status == .missing { return "Connecting…" }
        return conn.status.label
    }

    private var activateIcon: String {
        switch conn.status {
        case .disconnecting: return "stop.circle"
        case .connecting:    return "circle.dotted"
        case .missing:       return "play.fill"
        default:             return "stop.fill"
        }
    }

    private var activateColor: Color {
        if isTransitioning        { return .secondary }
        if conn.status == .missing { return .green }
        return .red
    }

    private var activateTooltip: String {
        switch conn.status {
        case .disconnecting: return "Disconnecting…"
        case .connecting:    return "Connecting…"
        case .missing:       return "Activate slot"
        default:             return "Deactivate slot"
        }
    }
}
