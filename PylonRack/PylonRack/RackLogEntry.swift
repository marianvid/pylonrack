import Foundation

struct RackLogEntry: Identifiable {
    let id        = UUID()
    let timestamp = Date()
    let message:    String

    var formatted: String {
        let fmt = DateFormatter()
        fmt.dateFormat = "HH:mm:ss"
        return "[\(fmt.string(from: timestamp))] \(message)"
    }
}
