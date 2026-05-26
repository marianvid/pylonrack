import Foundation

// MARK: - Control types

enum ControlType: String, Codable {
    case button
    case dropdown
    case label
}

enum ControlStyle: String, Codable {
    case primary
    case secondary
    case destructive
    case warning
    case success
    case error
    case `default` = "default"
}

// MARK: - SlotControl

struct SlotControl: Codable, Identifiable, Equatable {
    let id:    String
    let type:  ControlType
    var label: String?
    var style: ControlStyle?
    var value: String?     // current display value (label text / dropdown selection)
    var badge: Bool?       // badge dot on button
    var items: [String]?   // dropdown items, populated via control_data response
}

// MARK: - SlotManifest

struct SlotManifest: Decodable, Equatable {
    let name:              String
    let version:           String
    let heartbeatInterval: Int?
    let controls:          [SlotControl]
    let uiURL:             String?

    enum CodingKeys: String, CodingKey {
        case name, version, controls
        case heartbeatInterval = "heartbeat_interval"
        case uiURL             = "ui_url"
    }

    init(name: String, version: String, heartbeatInterval: Int? = nil,
         controls: [SlotControl] = [], uiURL: String? = nil) {
        self.name              = name
        self.version           = version
        self.heartbeatInterval = heartbeatInterval
        self.controls          = controls
        self.uiURL             = uiURL
    }
}
