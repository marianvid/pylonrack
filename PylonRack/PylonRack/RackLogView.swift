import SwiftUI

struct RackLogView: View {
    @EnvironmentObject var rack: RackController

    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            HStack {
                Text("Rack Log")
                    .font(.headline)
                Spacer()
                Button("Clear") { rack.rackLog.removeAll() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.bar)

            Divider()

            if rack.rackLog.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "doc.text")
                        .font(.system(size: 32))
                        .foregroundStyle(.quaternary)
                    Text("No rack events yet")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 2) {
                            ForEach(rack.rackLog) { entry in
                                Text(entry.formatted)
                                    .font(.system(size: 12, design: .monospaced))
                                    .foregroundStyle(entryColor(entry))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.horizontal, 12)
                                    .id(entry.id)
                            }
                        }
                        .padding(.vertical, 8)
                    }
                    .onChange(of: rack.rackLog.count) { _, _ in
                        if let last = rack.rackLog.last {
                            proxy.scrollTo(last.id, anchor: .bottom)
                        }
                    }
                }
            }
        }
        .frame(minWidth: 600, minHeight: 300)
    }

    private func entryColor(_ entry: RackLogEntry) -> Color {
        let msg = entry.message.lowercased()
        if msg.contains("error") || msg.contains("failed") || msg.contains("cannot") {
            return .red
        }
        if msg.contains("warning") { return .orange }
        return Color(nsColor: .labelColor)
    }
}
