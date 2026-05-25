import Foundation
import ServiceManagement

class AppSettings: ObservableObject {
    static let shared = AppSettings()

    private let settingsURL: URL

    @Published var defaultLocation: String = ""
    @Published var heartbeatInterval: Int = 10
    @Published var reconnectAttempts: Int = 3
    @Published var logLinesPerRequest: Int = 50
    @Published var startAtLogin: Bool = false {
        didSet { applyStartAtLogin() }
    }
    @Published var showInDock: Bool = false {
        didSet { applyShowInDock() }
    }

    private struct SettingsData: Codable {
        var defaultLocation: String
        var heartbeatInterval: Int
        var reconnectAttempts: Int
        var logLinesPerRequest: Int
        var startAtLogin: Bool
        var showInDock: Bool
    }

    // Production init
    convenience init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory,
                                                   in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("PylonRack")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        self.init(testURL: dir.appendingPathComponent("settings.json"))
    }

    // Testable init
    init(testURL: URL) {
        self.settingsURL = testURL
        load()
    }

    func load() {
        guard let data = try? Data(contentsOf: settingsURL),
              let decoded = try? JSONDecoder().decode(SettingsData.self, from: data) else {
            applyDefaults()
            return
        }
        defaultLocation    = decoded.defaultLocation
        heartbeatInterval  = decoded.heartbeatInterval
        reconnectAttempts  = decoded.reconnectAttempts
        logLinesPerRequest = decoded.logLinesPerRequest
        startAtLogin       = decoded.startAtLogin
        showInDock         = decoded.showInDock
    }

    func save() {
        let data = SettingsData(
            defaultLocation:    defaultLocation,
            heartbeatInterval:  heartbeatInterval,
            reconnectAttempts:  reconnectAttempts,
            logLinesPerRequest: logLinesPerRequest,
            startAtLogin:       startAtLogin,
            showInDock:         showInDock
        )
        if let encoded = try? JSONEncoder().encode(data) {
            try? encoded.write(to: settingsURL)
        }
    }

    private func applyDefaults() {
        defaultLocation    = FileManager.default.homeDirectoryForCurrentUser.path
        heartbeatInterval  = 10
        reconnectAttempts  = 10
        logLinesPerRequest = 50
        startAtLogin       = false
        showInDock         = false
        if settingsURL.path.contains("Application Support") { save() }
    }

    // MARK: - Side effects

    private func applyStartAtLogin() {
        let service = SMAppService.mainApp
        do {
            if startAtLogin {
                if service.status != .enabled { try service.register() }
            } else {
                if service.status == .enabled { try service.unregister() }
            }
        } catch {
            // Registration can fail if the user hasn't granted permission yet —
            // not fatal, setting is still persisted.
        }
        save()
    }

    private func applyShowInDock() {
        NSApp.setActivationPolicy(showInDock ? .regular : .accessory)
        save()
    }
}
