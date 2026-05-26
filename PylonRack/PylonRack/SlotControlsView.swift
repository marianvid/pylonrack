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
    var showLog:     Bool
    var onToggleLog: () -> Void

    var body: some View {
        if conn.controls.isEmpty && conn.manifest?.uiURL == nil { EmptyView() } else {
            HStack(spacing: 8) {
                ForEach(conn.controls) { ctrl in
                    controlView(ctrl)
                }

                if conn.manifest?.uiURL != nil {
                    Divider().frame(height: 16)
                    logToggleButton
                }

                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(.bar)
        }
    }

    // MARK: - Log toggle

    private var logToggleButton: some View {
        Button { onToggleLog() } label: {
            Image(systemName: showLog ? "doc.text.fill" : "doc.text")
        }
        .buttonStyle(ControlButtonStyle(color: showLog ? .accentColor : Color(nsColor: .secondaryLabelColor)))
        .help(showLog ? "Show UI" : "Show log")
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
        .help(ctrl.label ?? ctrl.id)
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
