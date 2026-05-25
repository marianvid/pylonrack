import SwiftUI

struct AddSlotView: View {
    @Environment(\.dismiss) private var dismiss
    var onAdd: (Slot, LocalSlotConfig?) -> Void

    enum Mode { case local, remote }
    @State private var mode: Mode = .local

    // Local
    @State private var localPath:   String          = ""
    @State private var localConfig: LocalSlotConfig? = nil

    // Remote
    @State private var remoteName: String = ""
    @State private var remoteHost: String = "localhost"
    @State private var remotePort: String = ""

    private var remotePortValid: Bool { (1...65535).contains(Int(remotePort) ?? 0) }

    private var canAdd: Bool {
        switch mode {
        case .local:  return localConfig != nil
        case .remote:
            return !remoteName.trimmingCharacters(in: .whitespaces).isEmpty &&
                   !remoteHost.trimmingCharacters(in: .whitespaces).isEmpty &&
                   remotePortValid
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Add Slot")
                .font(.headline)

            Picker("", selection: $mode) {
                Text("Local").tag(Mode.local)
                Text("Remote").tag(Mode.remote)
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            if mode == .local {
                localPanel
            } else {
                remotePanel
            }

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
                VStack(alignment: .leading, spacing: 2) {
                    if localConfig != nil {
                        Text(localPath)
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    } else {
                        Text(localPath.isEmpty ? "No folder selected" : localPath)
                            .font(.system(size: 12))
                            .foregroundStyle(localPath.isEmpty ? .tertiary : .secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
                Spacer()
                Button("Browse…") { browseFolder() }
            }

            if !localPath.isEmpty {
                if let config = localConfig {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .font(.system(size: 12))
                        Text("\(config.name) - \("localhost"):\(String(config.port))")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                } else {
                    HStack(spacing: 6) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.red)
                            .font(.system(size: 12))
                        Text("No valid rack.json found in this folder")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    // MARK: - Remote panel

    private var remotePanel: some View {
        Form {
            TextField("Name", text: $remoteName)
            TextField("Host", text: $remoteHost)
            HStack {
                TextField("Port", text: $remotePort)
                    .onChange(of: remotePort) { _, v in
                        remotePort = v.filter { $0.isNumber }
                    }
                if !remotePort.isEmpty && !remotePortValid {
                    Text("1–65535").font(.caption2).foregroundStyle(.red)
                }
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - Actions

    private func browseFolder() {
        let panel    = NSOpenPanel()
        let delegate = RackFolderDelegate()
        panel.delegate              = delegate
        panel.canChooseFiles        = false
        panel.canChooseDirectories  = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = URL(fileURLWithPath: AppSettings.shared.defaultLocation)
        panel.prompt       = "Open"
        panel.message      = "Select a PylonRack application folder"

        if panel.runModal() == .OK, let url = panel.url {
            localPath   = url.path
            localConfig = LocalSlotConfig.load(from: url)
        }
        _ = delegate  // retain delegate for panel lifetime
    }

    private func addSlot() {
        switch mode {
        case .local:
            guard let config = localConfig else { return }
            let slot = Slot(name: config.name, host: "localhost",
                            port: config.port, localPath: localPath)
            onAdd(slot, config)
        case .remote:
            let slot = Slot(name: remoteName.trimmingCharacters(in: .whitespaces),
                            host: remoteHost.trimmingCharacters(in: .whitespaces),
                            port: Int(remotePort)!)
            onAdd(slot, nil)
        }
        dismiss()
    }
}
