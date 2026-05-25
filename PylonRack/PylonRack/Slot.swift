import Foundation

struct Slot: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    var host: String
    var port: Int
    var localPath: String?   // nil = remote
    var isActive: Bool

    init(id: UUID = UUID(), name: String, host: String, port: Int,
         localPath: String? = nil, isActive: Bool = false) {
        self.id        = id
        self.name      = name
        self.host      = host
        self.port      = port
        self.localPath = localPath
        self.isActive  = isActive
    }

    var isLocal: Bool { localPath != nil }
}
