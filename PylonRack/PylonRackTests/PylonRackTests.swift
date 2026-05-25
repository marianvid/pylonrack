import XCTest

// MARK: - PortFinder Tests

final class PortFinderTests: XCTestCase {

    func test_preferredPortFree_returnsPreferred() {
        // Find a free port first, then ask for it
        let port = findFreePort(startingFrom: 19000)
        XCTAssertGreaterThanOrEqual(port, 1024)
        XCTAssertLessThanOrEqual(port, 65535)
    }

    func test_preferredPortOccupied_returnsNext() {
        // Bind a socket to occupy a port, then ask PortFinder for it
        let sock = Darwin.socket(AF_INET, SOCK_STREAM, 0)
        XCTAssertGreaterThanOrEqual(sock, 0)
        defer { Darwin.close(sock) }

        var reuseFlag: Int32 = 1
        Darwin.setsockopt(sock, SOL_SOCKET, SO_REUSEADDR, &reuseFlag,
                          socklen_t(MemoryLayout<Int32>.size))

        var addr        = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port   = in_port_t(19100).bigEndian
        addr.sin_addr   = in_addr(s_addr: INADDR_ANY)
        addr.sin_len    = UInt8(MemoryLayout<sockaddr_in>.size)

        let bound = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.bind(sock, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        XCTAssertEqual(bound, 0, "Failed to bind test socket")
        Darwin.listen(sock, 1)

        let result = findFreePort(startingFrom: 19100)
        XCTAssertNotEqual(result, 19100, "Should not return occupied port")
        XCTAssertGreaterThan(result, 19100)
    }

    func test_belowMinInput_clampsTo1024() {
        let port = findFreePort(startingFrom: 80)
        XCTAssertGreaterThanOrEqual(port, 1024)
    }

    func test_aboveMaxInput_clampsTo65534() {
        let port = findFreePort(startingFrom: 99999)
        XCTAssertLessThanOrEqual(port, 65535)
    }

    func test_returnsValidPort() {
        let port = findFreePort(startingFrom: 20000)
        XCTAssertTrue((1024...65535).contains(port))
    }
}

// MARK: - LocalSlotConfig Tests

final class LocalSlotConfigTests: XCTestCase {

    var tempDir: URL!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("PylonRackTests_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    // MARK: Valid configs

    func test_validConfig_loadsCorrectly() throws {
        let json = """
        { "name": "TestApp", "version": "1.0", "start": "python3 app.py", "port": 9001 }
        """
        try json.write(to: tempDir.appendingPathComponent("rack.json"), atomically: true, encoding: .utf8)

        let config = LocalSlotConfig.load(from: tempDir)
        XCTAssertNotNil(config)
        XCTAssertEqual(config?.name, "TestApp")
        XCTAssertEqual(config?.version, "1.0")
        XCTAssertEqual(config?.start, "python3 app.py")
        XCTAssertEqual(config?.port, 9001)
        XCTAssertNil(config?.stop)
    }

    func test_validConfigWithStop_loadsCorrectly() throws {
        let json = """
        { "name": "TestApp", "start": "python3 app.py", "stop": "python3 stop.py", "port": 9002 }
        """
        try json.write(to: tempDir.appendingPathComponent("rack.json"), atomically: true, encoding: .utf8)

        let config = LocalSlotConfig.load(from: tempDir)
        XCTAssertNotNil(config)
        XCTAssertEqual(config?.stop, "python3 stop.py")
    }

    func test_minPort_isValid() throws {
        let json = """
        { "name": "TestApp", "start": "run", "port": 1 }
        """
        try json.write(to: tempDir.appendingPathComponent("rack.json"), atomically: true, encoding: .utf8)
        XCTAssertNotNil(LocalSlotConfig.load(from: tempDir))
    }

    func test_maxPort_isValid() throws {
        let json = """
        { "name": "TestApp", "start": "run", "port": 65535 }
        """
        try json.write(to: tempDir.appendingPathComponent("rack.json"), atomically: true, encoding: .utf8)
        XCTAssertNotNil(LocalSlotConfig.load(from: tempDir))
    }

    // MARK: Invalid configs — all must return nil

    func test_missingFile_returnsNil() {
        XCTAssertNil(LocalSlotConfig.load(from: tempDir))
    }

    func test_invalidJSON_returnsNil() throws {
        try "not json at all {{{".write(to: tempDir.appendingPathComponent("rack.json"), atomically: true, encoding: .utf8)
        XCTAssertNil(LocalSlotConfig.load(from: tempDir))
    }

    func test_emptyStart_returnsNil() throws {
        let json = """
        { "name": "TestApp", "start": "", "port": 9001 }
        """
        try json.write(to: tempDir.appendingPathComponent("rack.json"), atomically: true, encoding: .utf8)
        XCTAssertNil(LocalSlotConfig.load(from: tempDir))
    }

    func test_missingStart_returnsNil() throws {
        let json = """
        { "name": "TestApp", "port": 9001 }
        """
        try json.write(to: tempDir.appendingPathComponent("rack.json"), atomically: true, encoding: .utf8)
        XCTAssertNil(LocalSlotConfig.load(from: tempDir))
    }

    func test_missingPort_returnsNil() throws {
        let json = """
        { "name": "TestApp", "start": "run" }
        """
        try json.write(to: tempDir.appendingPathComponent("rack.json"), atomically: true, encoding: .utf8)
        XCTAssertNil(LocalSlotConfig.load(from: tempDir))
    }

    func test_zeroPort_returnsNil() throws {
        let json = """
        { "name": "TestApp", "start": "run", "port": 0 }
        """
        try json.write(to: tempDir.appendingPathComponent("rack.json"), atomically: true, encoding: .utf8)
        XCTAssertNil(LocalSlotConfig.load(from: tempDir))
    }

    func test_negativePort_returnsNil() throws {
        let json = """
        { "name": "TestApp", "start": "run", "port": -1 }
        """
        try json.write(to: tempDir.appendingPathComponent("rack.json"), atomically: true, encoding: .utf8)
        XCTAssertNil(LocalSlotConfig.load(from: tempDir))
    }

    func test_portOver65535_returnsNil() throws {
        let json = """
        { "name": "TestApp", "start": "run", "port": 99999 }
        """
        try json.write(to: tempDir.appendingPathComponent("rack.json"), atomically: true, encoding: .utf8)
        XCTAssertNil(LocalSlotConfig.load(from: tempDir))
    }

    func test_missingName_returnsNil() throws {
        let json = """
        { "start": "run", "port": 9001 }
        """
        try json.write(to: tempDir.appendingPathComponent("rack.json"), atomically: true, encoding: .utf8)
        XCTAssertNil(LocalSlotConfig.load(from: tempDir))
    }
}

// MARK: - AppSettings Tests

final class AppSettingsTests: XCTestCase {

    var tempSettingsURL: URL!
    var settings: AppSettings!

    override func setUpWithError() throws {
        tempSettingsURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("test_settings_\(UUID().uuidString).json")
        settings = AppSettings(testURL: tempSettingsURL)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempSettingsURL)
    }

    func test_defaults_areCorrect() {
        XCTAssertEqual(settings.heartbeatInterval, 10)
        XCTAssertEqual(settings.reconnectAttempts, 10)
        XCTAssertEqual(settings.logLinesPerRequest, 50)
        XCTAssertFalse(settings.defaultLocation.isEmpty)
    }

    func test_saveAndLoad_roundTrip() {
        settings.heartbeatInterval  = 25
        settings.reconnectAttempts  = 7
        settings.logLinesPerRequest = 100
        settings.defaultLocation    = "/tmp/test"
        settings.save()

        let loaded = AppSettings(testURL: tempSettingsURL)
        XCTAssertEqual(loaded.heartbeatInterval,  25)
        XCTAssertEqual(loaded.reconnectAttempts,  7)
        XCTAssertEqual(loaded.logLinesPerRequest, 100)
        XCTAssertEqual(loaded.defaultLocation,    "/tmp/test")
    }

    func test_missingFile_usesDefaults() {
        let s = AppSettings(testURL: URL(fileURLWithPath: "/nonexistent/path/settings.json"))
        XCTAssertEqual(s.heartbeatInterval, 10)
        XCTAssertEqual(s.reconnectAttempts, 10)
        XCTAssertEqual(s.logLinesPerRequest, 50)
    }

    func test_corruptFile_usesDefaults() throws {
        try "corrupt data %%%".write(to: tempSettingsURL, atomically: true, encoding: .utf8)
        let s = AppSettings(testURL: tempSettingsURL)
        XCTAssertEqual(s.heartbeatInterval, 10)
        XCTAssertEqual(s.reconnectAttempts, 10)
    }

    func test_minHeartbeatValue_savesCorrectly() {
        settings.heartbeatInterval = 1
        settings.save()
        let loaded = AppSettings(testURL: tempSettingsURL)
        XCTAssertEqual(loaded.heartbeatInterval, 1)
    }

    func test_maxHeartbeatValue_savesCorrectly() {
        settings.heartbeatInterval = 60
        settings.save()
        let loaded = AppSettings(testURL: tempSettingsURL)
        XCTAssertEqual(loaded.heartbeatInterval, 60)
    }
}

// MARK: - Slot Tests

final class SlotTests: XCTestCase {

    func test_localSlot_isLocal() {
        let slot = Slot(name: "Test", host: "localhost", port: 9001, localPath: "/tmp/app")
        XCTAssertTrue(slot.isLocal)
    }

    func test_remoteSlot_isNotLocal() {
        let slot = Slot(name: "Test", host: "192.168.1.1", port: 9001)
        XCTAssertFalse(slot.isLocal)
    }

    func test_defaultIsActive_isFalse() {
        let slot = Slot(name: "Test", host: "localhost", port: 9001)
        XCTAssertFalse(slot.isActive)
    }

    func test_slotCodable_roundTrip() throws {
        let original = Slot(name: "MyApp", host: "localhost", port: 9001,
                            localPath: "/tmp/myapp", isActive: true)
        let data   = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(Slot.self, from: data)

        XCTAssertEqual(decoded.id,          original.id)
        XCTAssertEqual(decoded.name,        original.name)
        XCTAssertEqual(decoded.host,        original.host)
        XCTAssertEqual(decoded.port,        original.port)
        XCTAssertEqual(decoded.localPath,   original.localPath)
        XCTAssertEqual(decoded.isActive,    original.isActive)
    }

    func test_slotArray_codable() throws {
        let slots = [
            Slot(name: "A", host: "localhost", port: 9001),
            Slot(name: "B", host: "remote.host", port: 9002),
        ]
        let data    = try JSONEncoder().encode(slots)
        let decoded = try JSONDecoder().decode([Slot].self, from: data)
        XCTAssertEqual(decoded.count, 2)
        XCTAssertEqual(decoded[0].name, "A")
        XCTAssertEqual(decoded[1].name, "B")
    }
}

// MARK: - Protocol Message Tests

final class ProtocolMessageTests: XCTestCase {

    func test_pingMessage_serializes() throws {
        let dict: [String: Any] = ["type": "ping"]
        let data = try JSONSerialization.data(withJSONObject: dict)
        let str  = String(data: data, encoding: .utf8)!
        XCTAssertTrue(str.contains("ping"))
    }

    func test_pongMessage_deserializes() throws {
        let raw = """
        {"type":"pong","status":"running","message":"All good"}
        """
        let data = raw.data(using: .utf8)!
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        XCTAssertEqual(json["type"] as? String,    "pong")
        XCTAssertEqual(json["status"] as? String,  "running")
        XCTAssertEqual(json["message"] as? String, "All good")
    }

    func test_manifestMessage_deserializes() throws {
        let raw = """
        {
          "type": "manifest",
          "name": "Pulse",
          "version": "1.0",
          "heartbeat_interval": 10,
          "buttons": [
            {"id": "start", "label": "Start", "style": "primary"},
            {"id": "stop",  "label": "Stop",  "style": "destructive"}
          ],
          "ui_url": "http://localhost:9101/index.html"
        }
        """
        let data     = raw.data(using: .utf8)!
        let manifest = try JSONDecoder().decode(SlotManifest.self, from: data)
        XCTAssertEqual(manifest.name,               "Pulse")
        XCTAssertEqual(manifest.version,            "1.0")
        XCTAssertEqual(manifest.heartbeatInterval,  10)
        XCTAssertEqual(manifest.buttons.count,      2)
        XCTAssertEqual(manifest.buttons[0].id,      "start")
        XCTAssertEqual(manifest.buttons[1].style,   "destructive")
        XCTAssertEqual(manifest.uiURL,              "http://localhost:9101/index.html")
    }

    func test_manifestWithoutUIURL_isValid() throws {
        let raw = """
        {
          "type": "manifest",
          "name": "Canary",
          "version": "1.0",
          "heartbeat_interval": 10,
          "buttons": []
        }
        """
        let data     = raw.data(using: .utf8)!
        let manifest = try JSONDecoder().decode(SlotManifest.self, from: data)
        XCTAssertNil(manifest.uiURL)
        XCTAssertEqual(manifest.buttons.count, 0)
    }

    func test_logRequestMessage_serializes() throws {
        let dict: [String: Any] = ["type": "log_request", "lines": 50, "offset": 0]
        let data = try JSONSerialization.data(withJSONObject: dict)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        XCTAssertEqual(json["lines"] as? Int,  50)
        XCTAssertEqual(json["offset"] as? Int, 0)
    }

    func test_logResponseMessage_deserializes() throws {
        let raw = """
        {"type":"log_response","lines":["line1","line2","line3"],"total":100}
        """
        let data = raw.data(using: .utf8)!
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        let lines = json["lines"] as? [String]
        XCTAssertEqual(lines?.count, 3)
        XCTAssertEqual(lines?[0], "line1")
        XCTAssertEqual(json["total"] as? Int, 100)
    }
}
import XCTest
import Foundation
import Darwin

// MARK: - SlotConnection Tests (mock server in pure Swift)

@MainActor
final class SlotConnectionTests: XCTestCase {

    private var server: MockWSServer?

    override func tearDown() async throws {
        server?.stop()
        server = nil
        try await Task.sleep(nanoseconds: 100_000_000)
    }

    // MARK: - Happy path

    func test_normalConnect_receivesManifest() async throws {
        server = MockWSServer(port: 19200)
        let conn = makeConn(port: 19200)
        conn.activate(port: 19200)

        try await waitFor(timeout: 5.0) { conn.manifest != nil }

        XCTAssertNotNil(conn.manifest)
        XCTAssertEqual(conn.manifest?.name, "MockApp")
        XCTAssertEqual(conn.status, .connected)
        XCTAssertEqual(conn.manifest?.buttons.count, 2)
    }

    func test_normalConnect_statusBecomesConnected() async throws {
        server = MockWSServer(port: 19201)
        let conn = makeConn(port: 19201)
        conn.activate(port: 19201)

        try await waitFor(timeout: 5.0) { conn.status == .connected }
        XCTAssertEqual(conn.status, .connected)
    }

    func test_pongRunning_appMessageSet() async throws {
        server = MockWSServer(port: 19202)
        let conn = makeConn(port: 19202)
        conn.activate(port: 19202)

        try await waitFor(timeout: 5.0) { !conn.appMessage.isEmpty }
        XCTAssertEqual(conn.appMessage, "All good")
        XCTAssertEqual(conn.status, .connected)
    }

    // MARK: - Status mapping from pong

    func test_pongWarning_statusBecomesWarning() async throws {
        server = MockWSServer(port: 19203, scenario: .warning)
        let conn = makeConn(port: 19203)
        conn.activate(port: 19203)

        try await waitFor(timeout: 5.0) { conn.status == .warning }
        XCTAssertEqual(conn.status, .warning)
        XCTAssertEqual(conn.appMessage, "High load")
    }

    func test_pongError_statusBecomesError() async throws {
        server = MockWSServer(port: 19204, scenario: .errorStatus)
        let conn = makeConn(port: 19204)
        conn.activate(port: 19204)

        try await waitFor(timeout: 5.0) { conn.appMessage == "Critical failure" }
        XCTAssertEqual(conn.status, .error)
        XCTAssertEqual(conn.appMessage, "Critical failure")
    }

    // MARK: - Manifest variants

    func test_manifestWithoutUIURL_isNil() async throws {
        server = MockWSServer(port: 19205, scenario: .noUI)
        let conn = makeConn(port: 19205)
        conn.activate(port: 19205)

        try await waitFor(timeout: 5.0) { conn.manifest != nil }
        XCTAssertNil(conn.manifest?.uiURL)
        XCTAssertEqual(conn.status, .connected)
    }

    func test_badJsonManifest_doesNotCrash() async throws {
        server = MockWSServer(port: 19206, scenario: .badJSON)
        let conn = makeConn(port: 19206)
        conn.activate(port: 19206)

        try await Task.sleep(nanoseconds: 2_000_000_000)
        XCTAssertNil(conn.manifest)
        XCTAssertNotEqual(conn.status, .missing)
    }

    // MARK: - Log request

    func test_logRequest_receivesLines() async throws {
        server = MockWSServer(port: 19207)
        let conn = makeConn(port: 19207)
        conn.activate(port: 19207)

        try await waitFor(timeout: 5.0) { conn.manifest != nil }
        conn.requestLog(lines: 10, offset: 0)

        try await waitFor(timeout: 3.0) { !conn.logLines.isEmpty }
        XCTAssertEqual(conn.logLines.count, 10)
        XCTAssertEqual(conn.logTotal, 100)
    }

    // MARK: - Deactivate

    func test_deactivate_statusBecomesMissing() async throws {
        server = MockWSServer(port: 19208)
        let conn = makeConn(port: 19208)
        conn.activate(port: 19208)

        try await waitFor(timeout: 5.0) { conn.status == .connected }
        conn.deactivate()

        XCTAssertEqual(conn.status, .missing)
        XCTAssertFalse(conn.isActive)
    }

    func test_reconnectOnInactiveSlot_doesNothing() async throws {
        let conn = makeConn(port: 19209)
        conn.reconnect() // never activated

        try await Task.sleep(nanoseconds: 300_000_000)
        // still in initial connecting state — not missing (which deactivate sets)
        XCTAssertNotEqual(conn.status, .missing)
    }

    // MARK: - Connection drop

    func test_connectionDrop_triggersReconnect() async throws {
        server = MockWSServer(port: 19210, scenario: .dropAfter)
        let conn = makeConn(port: 19210)
        conn.activate(port: 19210)

        try await waitFor(timeout: 5.0) { conn.manifest != nil }
        // after drop: should transition to error or connecting
        try await waitFor(timeout: 5.0) { conn.status == .error || conn.status == .connecting }
        XCTAssertTrue(conn.status == .error || conn.status == .connecting)
    }

    // MARK: - No server

    func test_noServer_eventuallyErrors() async throws {
        // port 19211 — nothing listening
        let conn = makeConn(port: 19211)
        conn.activate(port: 19211)

        try await waitFor(timeout: 25.0) { conn.status == .error }
        XCTAssertEqual(conn.status, .error)
        XCTAssertFalse(conn.statusMessage.isEmpty)
    }


    // MARK: - Manual reconnect during retry loop

    func test_manualReconnect_duringRetryLoop_singleConnection() async throws {
        // 1. Start server and connect
        server = MockWSServer(port: 19212)
        let conn = makeConn(port: 19212)
        conn.activate(port: 19212)
        try await waitFor(timeout: 5.0) { conn.status == .connected }
        XCTAssertEqual(conn.connectionCount, 1)

        // 2. Stop server — triggers retry loop
        server?.stop()
        server = nil
        try await waitFor(timeout: 5.0) { conn.status == .connecting || conn.status == .error }

        // 3. Restart server
        server = MockWSServer(port: 19212)

        // 4. Manual reconnect while retry loop is running (isReconnecting may be true)
        conn.reconnect()

        // 5. Should connect exactly once — connectionCount == 2, not 3+
        try await waitFor(timeout: 5.0) { conn.status == .connected }
        try await Task.sleep(nanoseconds: 3_000_000_000) // wait for any duplicate connections

        XCTAssertEqual(conn.status, .connected)
        XCTAssertEqual(conn.connectionCount, 2,
            "Expected exactly 1 reconnection (connectionCount=2), got \(conn.connectionCount) — possible duplicate connections")
    }

    // MARK: - Helpers

    private func makeConn(port: Int) -> SlotConnection {
        SlotConnection(slot: Slot(name: "Mock", host: "localhost", port: port))
    }

    private func waitFor(timeout: TimeInterval, condition: @escaping () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
    }
}
import XCTest
import Foundation

@MainActor
final class RackControllerTests: XCTestCase {

    var tempDir: URL!
    var slotsURL: URL!

    override func setUpWithError() throws {
        tempDir  = FileManager.default.temporaryDirectory
            .appendingPathComponent("RackTests_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        slotsURL = tempDir.appendingPathComponent("slots.json")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    // MARK: - Persistence

    func test_addSlot_persistedToDisk() async throws {
        let rack = RackController(slotsURL: slotsURL)
        let slot = Slot(name: "TestApp", host: "localhost", port: 9001)
        rack.addSlot(slot)

        XCTAssertTrue(FileManager.default.fileExists(atPath: slotsURL.path))
        let data    = try Data(contentsOf: slotsURL)
        let decoded = try JSONDecoder().decode([Slot].self, from: data)
        XCTAssertEqual(decoded.count, 1)
        XCTAssertEqual(decoded[0].name, "TestApp")
    }

    func test_addMultipleSlots_allPersisted() async throws {
        let rack = RackController(slotsURL: slotsURL)
        rack.addSlot(Slot(name: "App1", host: "localhost", port: 9001))
        rack.addSlot(Slot(name: "App2", host: "localhost", port: 9002))
        rack.addSlot(Slot(name: "App3", host: "remote.host", port: 9003))

        let data    = try Data(contentsOf: slotsURL)
        let decoded = try JSONDecoder().decode([Slot].self, from: data)
        XCTAssertEqual(decoded.count, 3)
    }

    func test_removeSlot_removedFromDisk() async throws {
        let rack = RackController(slotsURL: slotsURL)
        let slot = Slot(name: "TestApp", host: "localhost", port: 9001)
        rack.addSlot(slot)
        XCTAssertEqual(rack.slots.count, 1)

        rack.removeSlot(slot)

        // Wait for async deactivate + save
        try await Task.sleep(nanoseconds: 500_000_000)

        let data    = try Data(contentsOf: slotsURL)
        let decoded = try JSONDecoder().decode([Slot].self, from: data)
        XCTAssertEqual(decoded.count, 0)
        XCTAssertEqual(rack.slots.count, 0)
    }

    func test_newSlot_defaultIsActive_false() {
        let rack = RackController(slotsURL: slotsURL)
        let slot = Slot(name: "TestApp", host: "localhost", port: 9001)
        rack.addSlot(slot)
        XCTAssertFalse(rack.slots.first!.isActive)
    }

    // MARK: - Load from disk

    func test_loadFromDisk_restoredCorrectly() async throws {
        // Write slots manually
        let slots = [
            Slot(name: "App1", host: "localhost", port: 9001, isActive: false),
            Slot(name: "App2", host: "remote.host", port: 9002, isActive: false),
        ]
        let data = try JSONEncoder().encode(slots)
        try data.write(to: slotsURL)

        let rack = RackController(slotsURL: slotsURL)
        XCTAssertEqual(rack.slots.count, 2)
        XCTAssertEqual(rack.slots[0].name, "App1")
        XCTAssertEqual(rack.slots[1].name, "App2")
    }

    func test_corruptSlotsJSON_startsEmpty() throws {
        try "NOT VALID JSON {{{{".write(to: slotsURL, atomically: true, encoding: .utf8)
        let rack = RackController(slotsURL: slotsURL)
        XCTAssertEqual(rack.slots.count, 0)
    }

    func test_missingSlotsFile_startsEmpty() {
        let rack = RackController(slotsURL: slotsURL) // file doesn't exist yet
        XCTAssertEqual(rack.slots.count, 0)
    }

    // MARK: - Restart behaviour

    func test_restartWithInactiveSlots_remainsInactive() throws {
        // Persist inactive slots
        let slots = [Slot(name: "App1", host: "localhost", port: 9001, isActive: false)]
        let data  = try JSONEncoder().encode(slots)
        try data.write(to: slotsURL)

        let rack = RackController(slotsURL: slotsURL)
        XCTAssertFalse(rack.slots.first!.isActive)
        let conn = rack.connection(for: rack.slots.first!)
        XCTAssertEqual(conn?.status, .missing)
    }

    func test_restartWithActiveRemoteSlot_attemptsReconnect() async throws {
        // Persist active remote slot (no process to start)
        let slots = [Slot(name: "Remote", host: "localhost", port: 9300, isActive: true)]
        let data  = try JSONEncoder().encode(slots)
        try data.write(to: slotsURL)

        let rack = RackController(slotsURL: slotsURL)
        try await Task.sleep(nanoseconds: 300_000_000)

        let conn = rack.connection(for: rack.slots.first!)
        // Should be attempting to connect (connecting or error after fails)
        XCTAssertNotEqual(conn?.status, .missing)
    }

    // MARK: - Connection management

    func test_connectionForSlot_notNilAfterAdd() {
        let rack = RackController(slotsURL: slotsURL)
        let slot = Slot(name: "App", host: "localhost", port: 9001)
        rack.addSlot(slot)
        XCTAssertNotNil(rack.connection(for: rack.slots.first!))
    }

    func test_connectionForRemovedSlot_nilAfterRemove() async throws {
        let rack = RackController(slotsURL: slotsURL)
        let slot = Slot(name: "App", host: "localhost", port: 9001)
        rack.addSlot(slot)
        let added = rack.slots.first!
        rack.removeSlot(added)

        try await Task.sleep(nanoseconds: 500_000_000)
        XCTAssertNil(rack.connection(for: added))
    }

    // MARK: - selectedSlotId

    func test_selectedSlotId_defaultNil() {
        let rack = RackController(slotsURL: slotsURL)
        XCTAssertNil(rack.selectedSlotId)
    }

    func test_selectedSlotId_setAndRead() {
        let rack = RackController(slotsURL: slotsURL)
        let slot = Slot(name: "App", host: "localhost", port: 9001)
        rack.addSlot(slot)
        rack.selectedSlotId = rack.slots.first!.id
        XCTAssertEqual(rack.selectedSlotId, rack.slots.first!.id)
    }

    // MARK: - Activate / Deactivate

    func test_activateRemoteSlot_isActiveTrue() async throws {
        server = MockWSServer(port: 19300)
        let rack = RackController(slotsURL: slotsURL)
        let slot = Slot(name: "App", host: "localhost", port: 19300)
        rack.addSlot(slot)
        XCTAssertFalse(rack.slots.first!.isActive)

        rack.activate(rack.slots.first!)
        XCTAssertTrue(rack.slots.first!.isActive)

        // Verify persisted as active
        try await Task.sleep(nanoseconds: 200_000_000)
        let data    = try Data(contentsOf: slotsURL)
        let decoded = try JSONDecoder().decode([Slot].self, from: data)
        XCTAssertTrue(decoded.first!.isActive)
    }

    func test_deactivateSlot_isActiveFalse() async throws {
        let rack = RackController(slotsURL: slotsURL)
        let slot = Slot(name: "App", host: "localhost", port: 9001)
        rack.addSlot(slot)
        rack.activate(rack.slots.first!)
        XCTAssertTrue(rack.slots.first!.isActive)

        await rack.deactivate(rack.slots.first!)
        XCTAssertFalse(rack.slots.first!.isActive)

        let data    = try Data(contentsOf: slotsURL)
        let decoded = try JSONDecoder().decode([Slot].self, from: data)
        XCTAssertFalse(decoded.first!.isActive)
    }

    // MARK: -  Server ref for tests that need it
    private var server: MockWSServer?
    override func tearDown() async throws {
        server?.stop()
        server = nil
    }
}
