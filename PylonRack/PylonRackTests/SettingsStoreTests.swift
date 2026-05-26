import XCTest

// MARK: - SettingsStore Tests

final class SettingsStoreTests: XCTestCase {

    private var url: URL!

    override func setUp() {
        url = FileManager.default.temporaryDirectory
            .appendingPathComponent("test_settings_\(UUID().uuidString).json")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: url)
    }

    func test_defaults_areCorrect() {
        let store = SettingsStore(url: url)
        XCTAssertEqual(store.current.heartbeatInterval,  10)
        XCTAssertEqual(store.current.reconnectAttempts,  10)
        XCTAssertEqual(store.current.logLinesPerRequest, 50)
        XCTAssertFalse(store.current.startAtLogin)
        XCTAssertFalse(store.current.showInDock)
        XCTAssertFalse(store.current.defaultLocation.isEmpty)
    }

    func test_saveAndLoad_roundTrip() {
        let store = SettingsStore(url: url)
        store.current.heartbeatInterval  = 25
        store.current.reconnectAttempts  = 7
        store.current.logLinesPerRequest = 100
        store.current.defaultLocation    = "/tmp/test"
        store.current.startAtLogin       = true
        store.current.showInDock         = true
        store.save()

        let loaded = SettingsStore(url: url)
        XCTAssertEqual(loaded.current.heartbeatInterval,  25)
        XCTAssertEqual(loaded.current.reconnectAttempts,  7)
        XCTAssertEqual(loaded.current.logLinesPerRequest, 100)
        XCTAssertEqual(loaded.current.defaultLocation,    "/tmp/test")
        XCTAssertTrue(loaded.current.startAtLogin)
        XCTAssertTrue(loaded.current.showInDock)
    }

    func test_missingFile_usesDefaults() {
        let nonexistent = URL(fileURLWithPath: "/nonexistent/path/settings.json")
        let store = SettingsStore(url: nonexistent)
        XCTAssertEqual(store.current, .defaults)
    }

    func test_corruptFile_usesDefaults() throws {
        try "corrupt data %%%".write(to: url, atomically: true, encoding: .utf8)
        let store = SettingsStore(url: url)
        XCTAssertEqual(store.current, .defaults)
    }
}

// MARK: - Settings Equatable

final class SettingsTests: XCTestCase {

    func test_defaults_equatable() {
        XCTAssertEqual(AppConfig.defaults, AppConfig.defaults)
    }

    func test_modified_notEqual() {
        var s = AppConfig.defaults
        s.heartbeatInterval = 99
        XCTAssertNotEqual(s, AppConfig.defaults)
    }
}
