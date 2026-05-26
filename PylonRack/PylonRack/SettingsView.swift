import SwiftUI

struct SettingsView: View {
    @ObservedObject var store:  SettingsStore
    let system: SystemEnvironment

    var body: some View {
        TabView {
            GeneralTab(store: store, system: system)
                .tabItem { Label("General", systemImage: "gear") }
            LogTab(store: store)
                .tabItem { Label("Logs", systemImage: "doc.text") }
        }
        .frame(width: 480)
        .padding(20)
    }
}

// MARK: - General tab

private struct GeneralTab: View {
    @ObservedObject var store:  SettingsStore
    let system: SystemEnvironment

    var body: some View {
        Form {
            Section {
                HStack {
                    TextField("", text: $store.current.defaultLocation)
                        .textFieldStyle(.roundedBorder)
                    Button("Choose…") { chooseFolder() }
                }
            } header: {
                Text("Default Location")
                Text("Default folder opened when adding a new slot.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Behavior") {
                Toggle("Start at login", isOn: $store.current.startAtLogin)
                    .onChange(of: store.current.startAtLogin) { _, v in
                        system.setLaunchAtLogin(v)
                        store.save()
                    }
                Toggle("Show in Dock", isOn: $store.current.showInDock)
                    .onChange(of: store.current.showInDock) { _, v in
                        system.setDockVisibility(v)
                        store.save()
                    }
            }

            Section("Connection") {
                NumericStepperField(
                    label: "Heartbeat interval",
                    unit: "sec",
                    value: $store.current.heartbeatInterval,
                    range: 1...60, step: 1
                )
                NumericStepperField(
                    label: "Reconnect attempts",
                    unit: "",
                    value: $store.current.reconnectAttempts,
                    range: 1...20, step: 1
                )
            }
        }
        .formStyle(.grouped)
        .onChange(of: store.current.defaultLocation) { _, _ in store.save() }
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles       = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = URL(fileURLWithPath: store.current.defaultLocation)
        if panel.runModal() == .OK, let url = panel.url {
            store.current.defaultLocation = url.path
            store.save()
        }
    }
}

// MARK: - Log tab

private struct LogTab: View {
    @ObservedObject var store: SettingsStore

    var body: some View {
        Form {
            Section("Log") {
                NumericStepperField(
                    label: "Lines per request",
                    unit: "",
                    value: $store.current.logLinesPerRequest,
                    range: 10...500, step: 10
                )
            }
        }
        .formStyle(.grouped)
        .onChange(of: store.current.logLinesPerRequest) { _, _ in store.save() }
    }
}

// MARK: - Reusable numeric field

struct NumericStepperField: View {
    let label:  String
    let unit:   String
    @Binding var value: Int
    let range:  ClosedRange<Int>
    let step:   Int

    @State private var text: String = ""

    var body: some View {
        HStack {
            Text(label)
            Spacer()
            TextField("", text: $text)
                .multilineTextAlignment(.trailing)
                .frame(width: 52)
                .textFieldStyle(.roundedBorder)
                .onAppear { text = "\(value)" }
                .onChange(of: value) { _, v in text = "\(v)" }
                .onSubmit { commit() }
            if !unit.isEmpty { Text(unit).foregroundStyle(.secondary) }
            Stepper("", value: $value, in: range, step: step)
                .labelsHidden()
        }
    }

    private func commit() {
        if let v = Int(text), range.contains(v) { value = v }
        else { text = "\(value)" }
    }
}
