import Foundation

struct Slot: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    var port: Int
    var localPath: String
    var isActive: Bool

    init(id: UUID = UUID(), name: String, port: Int,
         localPath: String, isActive: Bool = false) {
        self.id        = id
        self.name      = name
        self.port      = port
        self.localPath = localPath
        self.isActive  = isActive
    }

    // Backward-compatible decoding: older slots.json files may have a
    // `host` field and `localPath` as optional. We accept those and
    // discard `host`; localPath must be present (and non-empty).
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id        = try c.decode(UUID.self, forKey: .id)
        self.name      = try c.decode(String.self, forKey: .name)
        self.port      = try c.decode(Int.self, forKey: .port)
        let path       = try c.decodeIfPresent(String.self, forKey: .localPath) ?? ""
        guard !path.isEmpty else {
            throw DecodingError.dataCorruptedError(
                forKey: .localPath, in: c,
                debugDescription: "localPath is required (remote slots are no longer supported)"
            )
        }
        self.localPath = path
        self.isActive  = try c.decodeIfPresent(Bool.self, forKey: .isActive) ?? false
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, port, localPath, isActive
    }
}
