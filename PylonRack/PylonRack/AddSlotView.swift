import SwiftUI

struct AddSlotView: View {
    @Environment(\.dismiss) private var dismiss
    var onAdd: (Slot, LocalSlotConfig?) -> Void

    @State private var localPath:   String           = ""
    @State private var localConfig: LocalSlotConfig? = nil

    private var canAdd: Bool { localConfig != nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Add Slot")
                .font(.headline)

            localPanel

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.escape, modifiers: [])
                Button("Add") { addSlot() }
                    .keyboardShortcut(.return, modifiers: [])
                    .disabled(!canAdd)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(24)
        .frame(width: 380)
    }

    // MARK: - Local panel

    private var localPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(localPath.isEmpty ? "No folder selected" : localPath)
                    .font(.system(size: 12))
                    .foregroundStyle(localPath.isEmpty ? .tertiary : .secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                Button("Browse…") { browseFolder() }
            }

            if !localPath.isEmpty {
                if let config = localConfig {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .font(.system(size: 12))
                        Text("\(config.name) · localhost:\(config.port)")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                } else {
                    HStack(spacing: 6) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.red)
                            .font(.system(size: 12))
                        Text("No valid rack.json found")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    // MARK: - Actions

    private func browseFolder() {
        let panel    = NSOpenPanel()
        let delegate = RackFolderDelegate()
        panel.delegate                = delegate
        panel.canChooseFiles          = false
        panel.canChooseDirectories    = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = URL(fileURLWithPath: SettingsStore().current.defaultLocation)
        panel.prompt       = "Open"
        panel.message      = "Select a PylonRack slot folder"

        if panel.runModal() == .OK, let url = panel.url {
            localPath   = url.path
            localConfig = LocalSlotConfig.load(from: url)
        }
        _ = delegate
    }

    private func addSlot() {
        guard let config = localConfig else { return }
        let slot = Slot(name: config.name, host: "localhost",
                        port: config.port, localPath: localPath)
        onAdd(slot, config)
        dismiss()
    }
}
