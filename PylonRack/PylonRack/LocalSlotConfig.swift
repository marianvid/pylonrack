import Foundation

struct LocalSlotConfig: Codable {
    let name: String
    let version: String?
    let start: String
    let stop: String?
    let port: Int           // preferred port — rack finds free one starting here
    let startupDelay: Int?  // seconds to wait before first connect attempt (default 0)

    enum CodingKeys: String, CodingKey {
        case name, version, start, stop, port
        case startupDelay = "startup_delay"
    }

    static func load(from folderURL: URL) -> LocalSlotConfig? {
        let url = folderURL.appendingPathComponent("rack.json")
        guard let data   = try? Data(contentsOf: url),
              let config = try? JSONDecoder().decode(LocalSlotConfig.self, from: data),
              !config.start.isEmpty,
              (1...65535).contains(config.port)
        else { return nil }
        return config
    }
}
