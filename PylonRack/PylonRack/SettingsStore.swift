import Foundation

// Pure data — no side effects, no singletons.
// Side effects (dock policy, login item) are applied by PylonRackApp at startup
// and in response to settings changes via explicit calls from the UI layer.

struct AppConfig: Codable, Equatable {
    var defaultLocation:    String
    var heartbeatInterval:  Int
    var reconnectAttempts:  Int
    var logLinesPerRequest: Int
    var startAtLogin:       Bool
    var showInDock:         Bool

    static let defaults = AppConfig(
        defaultLocation:    FileManager.default.homeDirectoryForCurrentUser.path,
        heartbeatInterval:  10,
        reconnectAttempts:  10,
        logLinesPerRequest: 50,
        startAtLogin:       false,
        showInDock:         false
    )
}

// MARK: - SettingsStore

// ObservableObject wrapper around Settings — owns persistence.
// No AppKit or ServiceManagement imports here.

import Combine

final class SettingsStore: ObservableObject {
    @Published var current: AppConfig

    private let url: URL

    // Production
    convenience init() {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory,
                                           in: .userDomainMask).first!
            .appendingPathComponent("PylonRack")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        self.init(url: dir.appendingPathComponent("settings.json"))
    }

    // Testable
    init(url: URL) {
        self.url = url
        if let data = try? Data(contentsOf: url),
           let decoded = try? JSONDecoder().decode(AppConfig.self, from: data) {
            self.current = decoded
        } else {
            self.current = .defaults
            if url.path.contains("Application Support") {
                try? JSONEncoder().encode(AppConfig.defaults).write(to: url)
            }
        }
    }

    func save() {
        try? JSONEncoder().encode(current).write(to: url)
    }
}
