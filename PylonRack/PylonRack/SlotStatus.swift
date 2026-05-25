import SwiftUI

enum SlotStatus: Equatable {
    case connecting
    case connected
    case warning
    case error
    case missing
    case disconnecting

    var label: String {
        switch self {
        case .connecting:    return "Connecting…"
        case .connected:     return "Connected"
        case .warning:       return "Warning"
        case .error:         return "Error"
        case .missing:       return "Inactive"
        case .disconnecting: return "Disconnecting…"
        }
    }

    var color: Color {
        switch self {
        case .connecting:    return .orange
        case .connected:     return .green
        case .warning:       return .orange
        case .error:         return .red
        case .missing:       return Color(nsColor: .systemGray)
        case .disconnecting: return .orange
        }
    }
}
