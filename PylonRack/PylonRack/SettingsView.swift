import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettingsTab()
                .tabItem { Label("General", systemImage: "gear") }
            LogSettingsTab()
                .tabItem { Label("Logs", systemImage: "doc.text") }
        }
        .frame(width: 480)
        .padding(20)
    }
}

// MARK: - Reusable numeric stepper with editable field

struct NumericStepperField: View {
    let label: String
    let unit: String
    @Binding var value: Int
    let range: ClosedRange<Int>
    let step: Int

    @State private var text: String = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                Text("\(range.lowerBound) – \(range.upperBound)")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            Spacer()
            TextField("", text: $text)
                .frame(width: 64)
                .multilineTextAlignment(.trailing)
                .textFieldStyle(.roundedBorder)
                .focused($isFocused)
                .onAppear { text = "\(value)" }
                .onChange(of: value) { _, newVal in
                    if !isFocused { text = "\(newVal)" }
                }
                .onChange(of: text) { _, newText in
                    // Strip anything that's not a digit
                    let filtered = newText.filter { $0.isNumber }
                    if filtered != newText { text = filtered }
                }
                .onChange(of: isFocused) { _, focused in
                    if !focused { commit() }
                }
                .onSubmit { commit() }
            if !unit.isEmpty {
                Text(unit)
                    .foregroundStyle(.secondary)
                    .frame(width: 44, alignment: .leading)
            }
            Stepper("", value: $value, in: range, step: step)
                .labelsHidden()
        }
    }

    private func commit() {
        if let parsed = Int(text), parsed > 0 {
            value = min(range.upperBound, max(range.lowerBound, parsed))
        }
        text = "\(value)"
    }
}

// MARK: - General Tab

struct GeneralSettingsTab: View {
    @ObservedObject private var settings = AppSettings.shared

    var body: some View {
        Form {
            Section {
                HStack {
                    TextField("", text: $settings.defaultLocation)
                        .textFieldStyle(.roundedBorder)
                    Button("Choose…") { chooseFolder() }
                }
            } header: {
                Text("Default Location")
                Text("The default folder opened when adding a new slot.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section {
                Toggle("Start at login", isOn: $settings.startAtLogin)
                Toggle("Show in Dock", isOn: $settings.showInDock)
            } header: {
                Text("Behavior")
            }

            Section {
                NumericStepperField(
                    label: "Heartbeat interval",
                    unit: "sec",
                    value: $settings.heartbeatInterval,
                    range: 1...60,
                    step: 5
                )
                NumericStepperField(
                    label: "Reconnect attempts",
                    unit: "",
                    value: $settings.reconnectAttempts,
                    range: 1...20,
                    step: 1
                )
            } header: {
                Text("Connection")
            }
        }
        .formStyle(.grouped)
        .onChange(of: settings.heartbeatInterval)   { _, _ in settings.save() }
        .onChange(of: settings.reconnectAttempts)   { _, _ in settings.save() }
        .onChange(of: settings.defaultLocation)     { _, _ in settings.save() }
        .onChange(of: settings.startAtLogin)        { _, _ in settings.save() }
        .onChange(of: settings.showInDock)          { _, _ in settings.save() }
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = URL(fileURLWithPath: settings.defaultLocation)
        if panel.runModal() == .OK, let url = panel.url {
            settings.defaultLocation = url.path
        }
    }
}

// MARK: - Logs Tab

struct LogSettingsTab: View {
    @ObservedObject private var settings = AppSettings.shared

    var body: some View {
        Form {
            Section {
                NumericStepperField(
                    label: "Lines per request",
                    unit: "lines",
                    value: $settings.logLinesPerRequest,
                    range: 10...500,
                    step: 10
                )
            } header: {
                Text("Log Streaming")
                Text("Number of log lines fetched per scroll chunk.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onChange(of: settings.logLinesPerRequest) { _, _ in settings.save() }
    }
}
