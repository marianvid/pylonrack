import SwiftUI

// MARK: - Settings Panel

struct SettingsPanelView: View {
    @ObservedObject var conn: SlotConnection

    // Server
    @State private var ctxSize:    String = "131072"
    @State private var nGpuLayers: String = "99"
    @State private var threads:    String = "8"
    @State private var batchSize:  String = "512"
    @State private var uBatchSize: String = "256"

    // Chat / sampling
    @State private var temperature:   String = "0.8"
    @State private var topP:          String = "0.95"
    @State private var topK:          String = "40"
    @State private var repeatPenalty: String = "1.1"

    // Toggles
    @State private var flashAttn: Bool = true
    @State private var mlock:     Bool = false

    // UI state
    @State private var isSaving:    Bool   = false
    @State private var savedBanner: Bool   = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    section("Model & Context") {
                        row("Context size", hint: "tokens") {
                            IntField(value: $ctxSize, range: 512...2097152)
                        }
                        row("GPU layers", hint: "99 = all") {
                            IntField(value: $nGpuLayers, range: 0...999)
                        }
                        row("CPU threads", hint: "") {
                            IntField(value: $threads, range: 1...64)
                        }
                        row("Batch size", hint: "tokens") {
                            IntField(value: $batchSize, range: 32...4096)
                        }
                        row("µBatch size", hint: "tokens") {
                            IntField(value: $uBatchSize, range: 32...4096)
                        }
                    }
                    section("Sampling") {
                        row("Temperature", hint: "0.0 – 2.0") {
                            FloatField(value: $temperature, range: 0.0...2.0)
                        }
                        row("Top-P", hint: "0.0 – 1.0") {
                            FloatField(value: $topP, range: 0.0...1.0)
                        }
                        row("Top-K", hint: "0 = disabled") {
                            IntField(value: $topK, range: 0...1000)
                        }
                        row("Repeat penalty", hint: "1.0 = off") {
                            FloatField(value: $repeatPenalty, range: 1.0...2.0)
                        }
                    }
                    section("Hardware") {
                        Toggle("Flash Attention", isOn: $flashAttn)
                            .font(.system(size: 13))
                            .toggleStyle(.switch)
                            .controlSize(.small)
                        Toggle("Lock model in RAM (mlock)", isOn: $mlock)
                            .font(.system(size: 13))
                            .toggleStyle(.switch)
                            .controlSize(.small)
                    }
                }
                .frame(width: 480, alignment: .leading)
                .padding(24)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            Divider()
            HStack {
                Text("Changes take effect after restart.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                footer
            }
            .frame(width: 480)
            .padding(.horizontal, 24)
            .padding(.vertical, 14)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { loadFromConn() }
        .onChange(of: conn.actionResultToken) { handleActionResult() }
    }

    // MARK: - Sub-views

    private var header: some View {
        HStack {
            Image(systemName: "gearshape.fill")
                .foregroundStyle(.secondary)
            Text("Server Settings")
                .font(.headline)
            Spacer()

        }
        .padding(.horizontal, 24)
        .padding(.top, 20)
        .padding(.bottom, 16)
    }

    private var footer: some View {
        Button {
            saveSettings()
        } label: {
            HStack(spacing: 6) {
                if isSaving {
                    ProgressView().controlSize(.mini)
                    Text("Restarting…")
                } else {
                    Text("Save & Restart")
                }
            }
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.regular)
        .disabled(isSaving)
    }

    @ViewBuilder
    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .tracking(0.5)
            VStack(alignment: .leading, spacing: 10) {
                content()
            }
            .padding(16)
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 1))
        }
    }

    @ViewBuilder
    private func row<Content: View>(_ label: String, hint: String, @ViewBuilder field: () -> Content) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.system(size: 13))
                if !hint.isEmpty {
                    Text(hint)
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                }
            }
            Spacer()
            field()
                .frame(width: 110)
        }
    }

    // MARK: - Load / Save

    private func loadFromConn() {
        // Read current values from settings via action_result
        conn.sendAction("get_settings")
    }

    private func handleActionResult() {
        guard let data = conn.lastActionResult else { return }
        switch data["type"] as? String {
        case "settings":
            if let s = data["server"] as? [String: Any] {
                ctxSize      = "\(s["ctx_size"]      ?? 131072)"
                nGpuLayers   = "\(s["n_gpu_layers"]  ?? 99)"
                threads      = "\(s["threads"]       ?? 8)"
                batchSize    = "\(s["batch_size"]    ?? 512)"
                uBatchSize   = "\(s["ubatch_size"]   ?? 256)"
                temperature  = "\(s["temperature"]   ?? 0.8)"
                topP         = "\(s["top_p"]         ?? 0.95)"
                topK         = "\(s["top_k"]         ?? 40)"
                repeatPenalty = "\(s["repeat_penalty"] ?? 1.1)"
                flashAttn    = s["flash_attn"]  as? Bool ?? true
                mlock        = s["mlock"]       as? Bool ?? false
            }
        case "settings_saved":
            isSaving = false
            // Close settings panel — return to webview
            conn.toggleMode(.settings)
        default:
            break
        }
    }

    private func saveSettings() {
        isSaving = true
        let settings: [String: Any] = [
            "ctx_size":       Int(ctxSize)      ?? 131072,
            "n_gpu_layers":   Int(nGpuLayers)   ?? 99,
            "threads":        Int(threads)      ?? 8,
            "batch_size":     Int(batchSize)    ?? 512,
            "ubatch_size":    Int(uBatchSize)   ?? 256,
            "temperature":    Double(temperature)   ?? 0.8,
            "top_p":          Double(topP)          ?? 0.95,
            "top_k":          Int(topK)             ?? 40,
            "repeat_penalty": Double(repeatPenalty) ?? 1.1,
            "flash_attn":     flashAttn,
            "mlock":          mlock,
        ]
        conn.sendActionWithSettings("save_settings", settings: settings)
    }
}

// MARK: - Compact number fields

struct IntField: View {
    @Binding var value: String
    let range: ClosedRange<Int>

    var body: some View {
        TextField("", text: $value)
            .textFieldStyle(.roundedBorder)
            .font(.system(size: 13, design: .monospaced))
            .multilineTextAlignment(.trailing)
            .onSubmit { clamp() }
    }

    private func clamp() {
        let n = Int(value) ?? range.lowerBound
        value = "\(min(max(n, range.lowerBound), range.upperBound))"
    }
}

struct FloatField: View {
    @Binding var value: String
    let range: ClosedRange<Double>

    var body: some View {
        TextField("", text: $value)
            .textFieldStyle(.roundedBorder)
            .font(.system(size: 13, design: .monospaced))
            .multilineTextAlignment(.trailing)
            .onSubmit { clamp() }
    }

    private func clamp() {
        let n = Double(value) ?? range.lowerBound
        let clamped = min(max(n, range.lowerBound), range.upperBound)
        value = String(format: "%.2f", clamped)
    }
}
