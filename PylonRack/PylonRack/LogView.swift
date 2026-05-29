import SwiftUI

struct LogView: View {
    @ObservedObject var conn: SlotConnection

    @State private var isLoadingMore  = false
    @State private var userScrolled   = false  // true after user manually scrolls up

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
                        // Selection propagates to all Text children

                        // Load more button at top
                        if !lines.isEmpty {
                            HStack {
                                Spacer()
                                if isLoadingMore {
                                    ProgressView().controlSize(.mini)
                                        .padding(.vertical, 6)
                                } else {
                                    Button("Load earlier lines") {
                                        loadMore()
                                    }
                                    .font(.system(size: 11))
                                    .buttonStyle(.plain)
                                    .foregroundStyle(.secondary)
                                    .padding(.vertical, 6)
                                }
                                Spacer()
                            }
                            .id("top")
                        }

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
                .textSelection(.enabled)
                .background(Color(nsColor: .textBackgroundColor))
                .onChange(of: conn.logLines) { old, new in
                    if isLoadingMore {
                        isLoadingMore = false
                        return
                    }
                    // Only auto-scroll on new appended lines, not if user scrolled up
                    if new.count > old.count && !userScrolled {
                        proxy.scrollTo(displayLines.indices.last, anchor: .bottom)
                    }
                }
                .onChange(of: conn.processLog) { _, _ in
                    if !userScrolled {
                        proxy.scrollTo(displayLines.indices.last, anchor: .bottom)
                    }
                }
                .simultaneousGesture(DragGesture().onChanged { v in
                    // If user drags up, stop auto-scroll
                    if v.translation.height > 10 { userScrolled = true }
                    // If user drags to bottom, resume auto-scroll
                    if v.translation.height < -10 { userScrolled = false }
                })
            }
        }
        .onAppear {
            conn.requestLog()
        }
    }

    private var displayLines: [String] {
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

    private func loadMore() {
        guard !isLoadingMore else { return }
        isLoadingMore = true
        conn.requestLog(skip: displayLines.count)
    }

    private func lineColor(_ line: String) -> Color {
        if line.contains("[ERROR]")   { return Color.red.opacity(0.85) }
        if line.contains("[WARNING]") { return Color.orange }
        if line.contains("[DEBUG]")   { return Color(nsColor: .systemGray) }
        return Color(nsColor: .labelColor)
    }
}
