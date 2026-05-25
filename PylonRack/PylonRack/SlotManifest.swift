import Foundation

struct ManifestButton: Codable, Identifiable {
    let id: String
    let label: String
    let style: String  // primary | secondary | destructive | warning
}

struct SlotManifest: Codable {
    let name: String
    let version: String
    let heartbeatInterval: Int?
    let buttons: [ManifestButton]
    let uiURL: String?

    enum CodingKeys: String, CodingKey {
        case name, version, buttons
        case heartbeatInterval = "heartbeat_interval"
        case uiURL             = "ui_url"
    }
}
