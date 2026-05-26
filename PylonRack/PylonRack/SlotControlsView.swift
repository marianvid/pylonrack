import SwiftUI

struct SlotControlsView: View {
    let slot: Slot
    @ObservedObject var conn: SlotConnection

    var body: some View {
        if conn.controls.isEmpty { EmptyView() } else {
            VStack(spacing: 0) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(conn.controls) { ctrl in
                            controlView(ctrl)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                }
                Divider()
            }
            .background(.bar)
        }
    }

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
        Button {
            conn.sendAction(ctrl.id)
        } label: {
            HStack(spacing: 4) {
                Text(ctrl.label ?? ctrl.id)
                    .font(.system(size: 12, weight: .medium))
                if ctrl.badge == true {
                    Circle()
                        .fill(.orange)
                        .frame(width: 6, height: 6)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
        }
        .buttonStyle(.bordered)
        .tint(buttonTint(ctrl.style ?? .secondary))
        .controlSize(.small)
    }

    private func buttonTint(_ style: ControlStyle) -> Color {
        switch style {
        case .primary:     return .accentColor
        case .destructive: return .red
        case .warning:     return .orange
        case .success:     return .green
        case .error:       return .red
        default:           return Color(nsColor: .controlColor)
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
                ForEach(items, id: \.self) { item in
                    Text(item).tag(item)
                }
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
        Text(ctrl.value ?? ctrl.label ?? "")
            .font(.system(size: 12))
            .foregroundStyle(labelColor(ctrl.style ?? .default))
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(labelBackground(ctrl.style ?? .default))
            )
    }

    private func labelColor(_ style: ControlStyle) -> Color {
        switch style {
        case .success:     return .green
        case .warning:     return .orange
        case .error:       return .red
        case .primary:     return .accentColor
        default:           return Color(nsColor: .secondaryLabelColor)
        }
    }

    private func labelBackground(_ style: ControlStyle) -> Color {
        switch style {
        case .success:     return .green.opacity(0.1)
        case .warning:     return .orange.opacity(0.1)
        case .error:       return .red.opacity(0.1)
        case .primary:     return Color.accentColor.opacity(0.1)
        default:           return Color(nsColor: .windowBackgroundColor).opacity(0.5)
        }
    }
}
