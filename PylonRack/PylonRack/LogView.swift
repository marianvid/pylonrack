import SwiftUI

struct LogView: View {
    @ObservedObject var conn: SlotConnection

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Image(systemName: "doc.text")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Text("Log")
                    .font(.system(size: 12, weight: .medium))
                Spacer()
                if conn.logTotal > 0 {
                    Text("\(conn.logTotal) lines total")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                }
                Button {
                    conn.requestLog()
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 11))
                }
                .buttonStyle(RackIconButtonStyle())
                .help("Refresh log")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(nsColor: .controlBackgroundColor))

            Divider()

            // Log content
            ScrollViewReader { proxy in
                let lines = displayLines
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        if lines.isEmpty {
                            Text(emptyMessage)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(.tertiary)
                                .padding(12)
                        } else {
                            ForEach(Array(lines.enumerated()), id: \.offset) { idx, line in
                                Text(line)
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundStyle(lineColor(line))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 1)
                                    .id(idx)
                            }
                        }
                    }
                }
                .background(Color(nsColor: .textBackgroundColor))
                .onChange(of: conn.logLines) { _, _ in
                    proxy.scrollTo(displayLines.indices.last, anchor: .bottom)
                }
                .onChange(of: conn.processLog) { _, _ in
                    proxy.scrollTo(displayLines.indices.last, anchor: .bottom)
                }
            }
        }
        .onAppear {
            conn.requestLog()
        }
    }

    private var displayLines: [String] {
        // Show WS log if connected and available, else show process stdout
        if !conn.logLines.isEmpty { return conn.logLines }
        return conn.processLog
    }

    private var emptyMessage: String {
        switch conn.status {
        case .connecting, .disconnecting: return "Waiting for connection…"
        case .missing:                    return "Slot inactive — no log available"
        default:                          return "No log entries yet"
        }
    }

    private func lineColor(_ line: String) -> Color {
        if line.contains("[ERROR]")   { return Color.red.opacity(0.85) }
        if line.contains("[WARNING]") { return Color.orange }
        if line.contains("[DEBUG]")   { return Color(nsColor: .systemGray) }
        return Color(nsColor: .labelColor)
    }
}
