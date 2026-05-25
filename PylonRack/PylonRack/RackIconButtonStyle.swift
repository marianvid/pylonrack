import SwiftUI

// Hover + press feedback pentru butoane mici (borderless)
struct RackIconButtonStyle: ButtonStyle {
    @State private var isHovered = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(5)
            .background(
                RoundedRectangle(cornerRadius: 5)
                    .fill(backgroundColor(pressed: configuration.isPressed))
            )
            .scaleEffect(configuration.isPressed ? 0.88 : 1.0)
            .animation(.easeOut(duration: 0.08), value: configuration.isPressed)
            .animation(.easeInOut(duration: 0.12), value: isHovered)
            .onHover { isHovered = $0 }
    }

    private func backgroundColor(pressed: Bool) -> Color {
        if pressed   { return Color.secondary.opacity(0.28) }
        if isHovered { return Color.secondary.opacity(0.14) }
        return .clear
    }
}
