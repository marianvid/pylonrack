import SwiftUI

// MARK: - Control button style with hover + press feedback

struct ControlButtonStyle: ButtonStyle {
    let color: Color
    @State private var isHovered = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .medium))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(background(configuration))
            .foregroundStyle(foreground(configuration))
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(border(configuration), lineWidth: 1)
            )
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
            .animation(.easeOut(duration: 0.15), value: isHovered)
            .onHover { isHovered = $0 }
    }

    private func background(_ c: Configuration) -> Color {
        if c.isPressed { return color.opacity(0.35) }
        if isHovered   { return color.opacity(0.18) }
        return color.opacity(0.08)
    }

    private func foreground(_ c: Configuration) -> Color {
        if c.isPressed { return color }
        if isHovered   { return color }
        return color.opacity(0.85)
    }

    private func border(_ c: Configuration) -> Color {
        if c.isPressed { return color.opacity(0.6) }
        if isHovered   { return color.opacity(0.5) }
        return color.opacity(0.25)
    }
}

// MARK: - SlotControlsView

struct SlotControlsView: View {
    let slot: Slot
    @ObservedObject var conn: SlotConnection
    var onToggleMode: (BodyMode) -> Void

    var body: some View {
        if conn.controls.isEmpty && conn.manifest?.uiURL == nil { EmptyView() } else {
            HStack(spacing: 8) {
                // Left: model controls (all except update)
                ForEach(conn.controls.filter { $0.id != "update" }) { ctrl in
                    controlView(ctrl)
                }

                Spacer()

                // Right: update button + mode toggles
                if let update = conn.controls.first(where: { $0.id == "update" }) {
                    controlView(update)
                    Divider().frame(height: 16)
                }
                modeButtons
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(.bar)
        }
    }

    // MARK: - Mode toggle buttons

    @ViewBuilder
    private var modeButtons: some View {
        HStack(spacing: 4) {
            ModeToggleButton(
                icon:   "doc.text",
                active: conn.bodyMode == .log,
                help:   conn.bodyMode == .log ? "Hide log" : "Show process log"
            ) { onToggleMode(.log) }

            ModeToggleButton(
                icon:   "square.grid.2x2",
                active: conn.bodyMode == .models,
                help:   conn.bodyMode == .models ? "Hide model manager" : "Download & manage models"
            ) { onToggleMode(.models) }
        }
    }

    // MARK: - Control routing

    @ViewBuilder
    private func controlView(_ ctrl: SlotControl) -> some View {
        switch ctrl.type {
        case .button:   buttonView(ctrl)
        case .dropdown: dropdownView(ctrl)
        case .label:    labelView(ctrl)
        }
    }

    // MARK: - Button

    private func buttonView(_ ctrl: SlotControl) -> some View {
        Button { conn.sendAction(ctrl.id) } label: {
            HStack(spacing: 5) {
                Text(ctrl.label ?? ctrl.id)
                if ctrl.badge == true {
                    Circle().fill(.orange).frame(width: 6, height: 6)
                }
            }
        }
        .buttonStyle(ControlButtonStyle(color: buttonColor(ctrl.style ?? .secondary)))
        .help(buttonTooltip(ctrl))
    }

    private func buttonTooltip(_ ctrl: SlotControl) -> String {
        switch ctrl.id {
        case "toggle":
            return (ctrl.label == "Stop" || ctrl.label == "Stopping…")
                ? "Stop llama-server" : "Start llama-server"
        case "update":
            let badge = ctrl.badge == true
            return badge
                ? "Update available — click to pull & rebuild llama.cpp"
                : "llama.cpp is up to date"
        default:
            return ctrl.label ?? ctrl.id
        }
    }

    private func buttonColor(_ style: ControlStyle) -> Color {
        switch style {
        case .primary:               return .accentColor
        case .destructive, .error:   return .red
        case .warning:               return .orange
        case .success:               return .green
        default:                     return Color(nsColor: .secondaryLabelColor)
        }
    }

    // MARK: - Dropdown

    private func dropdownView(_ ctrl: SlotControl) -> some View {
        let items   = ctrl.items ?? []
        let current = ctrl.value ?? items.first ?? ""

        return Picker(ctrl.label ?? ctrl.id, selection: Binding(
            get: { current },
            set: { conn.sendAction(ctrl.id, value: $0) }
        )) {
            if items.isEmpty {
                Text("Loading…").tag("").foregroundStyle(.secondary)
            } else {
                ForEach(items, id: \.self) { Text($0).tag($0) }
            }
        }
        .pickerStyle(.menu)
        .controlSize(.small)
        .frame(maxWidth: 240)
        .labelsHidden()
        .help("Select model")
    }

    // MARK: - Label

    private func labelView(_ ctrl: SlotControl) -> some View {
        let style = ctrl.style ?? .default
        return Text(ctrl.value ?? ctrl.label ?? "")
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(labelColor(style))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(labelColor(style).opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 5))
            .overlay(
                RoundedRectangle(cornerRadius: 5)
                    .strokeBorder(labelColor(style).opacity(0.25), lineWidth: 1)
            )
    }

    private func labelColor(_ style: ControlStyle) -> Color {
        switch style {
        case .success:  return .green
        case .warning:  return .orange
        case .error:    return .red
        case .primary:  return .accentColor
        default:        return Color(nsColor: .secondaryLabelColor)
        }
    }
}

// MARK: - ModeToggleButton

struct ModeToggleButton: View {
    let icon:   String
    let active: Bool
    let help:   String
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: active ? "\(icon).fill" : icon)
                .font(.system(size: 12))
                .foregroundStyle(active ? Color.accentColor : Color(nsColor: .secondaryLabelColor))
                .padding(6)
                .background(
                    RoundedRectangle(cornerRadius: 5)
                        .fill(active
                              ? Color.accentColor.opacity(0.12)
                              : (isHovered ? Color(nsColor: .secondaryLabelColor).opacity(0.1) : Color.clear))
                )
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .help(help)
    }
}
