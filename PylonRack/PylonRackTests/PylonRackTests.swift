import XCTest
import Darwin

// MARK: - PortFinder Tests

final class PortFinderTests: XCTestCase {

    func test_preferredPortFree_returnsValidPort() {
        let port = findFreePort(startingFrom: 19000)
        XCTAssertTrue((1024...65535).contains(port))
    }

    func test_occupiedPort_returnsNext() {
        let sock = Darwin.socket(AF_INET, SOCK_STREAM, 0)
        defer { Darwin.close(sock) }
        var reuse: Int32 = 1
        Darwin.setsockopt(sock, SOL_SOCKET, SO_REUSEADDR, &reuse, socklen_t(MemoryLayout<Int32>.size))
        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port   = in_port_t(19100).bigEndian
        addr.sin_addr   = in_addr(s_addr: INADDR_ANY)
        addr.sin_len    = UInt8(MemoryLayout<sockaddr_in>.size)
        withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.bind(sock, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        Darwin.listen(sock, 1)
        XCTAssertNotEqual(findFreePort(startingFrom: 19100), 19100)
    }

    func test_belowMin_clampsTo1024() {
        XCTAssertGreaterThanOrEqual(findFreePort(startingFrom: 80), 1024)
    }

    func test_aboveMax_clampsTo65535() {
        XCTAssertLessThanOrEqual(findFreePort(startingFrom: 99999), 65535)
    }
}

// MARK: - LocalSlotConfig Tests

final class LocalSlotConfigTests: XCTestCase {

    private var dir: URL!

    override func setUp() {
        dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("SlotConfigTests_\(UUID().uuidString)")
        try! FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: dir)
    }

    private func write(_ json: String) throws {
        try json.write(to: dir.appendingPathComponent("rack.json"),
                       atomically: true, encoding: .utf8)
    }

    func test_validConfig_loadsCorrectly() throws {
        try write(#"{"name":"TestApp","version":"1.0","start":"python3 app.py","port":9001}"#)
        let c = LocalSlotConfig.load(from: dir)
        XCTAssertEqual(c?.name,    "TestApp")
        XCTAssertEqual(c?.version, "1.0")
        XCTAssertEqual(c?.start,   "python3 app.py")
        XCTAssertEqual(c?.port,    9001)
        XCTAssertNil(c?.stop)
    }

    func test_configWithStop_loadsStop() throws {
        try write(#"{"name":"A","start":"run","stop":"stop.sh","port":9002}"#)
        XCTAssertEqual(LocalSlotConfig.load(from: dir)?.stop, "stop.sh")
    }

    func test_minPort_isValid() throws {
        try write(#"{"name":"A","start":"run","port":1}"#)
        XCTAssertNotNil(LocalSlotConfig.load(from: dir))
    }

    func test_maxPort_isValid() throws {
        try write(#"{"name":"A","start":"run","port":65535}"#)
        XCTAssertNotNil(LocalSlotConfig.load(from: dir))
    }

    func test_missingFile_returnsNil() {
        XCTAssertNil(LocalSlotConfig.load(from: dir))
    }

    func test_invalidJSON_returnsNil() throws {
        try write("not json {{{")
        XCTAssertNil(LocalSlotConfig.load(from: dir))
    }

    func test_emptyStart_returnsNil() throws {
        try write(#"{"name":"A","start":"","port":9001}"#)
        XCTAssertNil(LocalSlotConfig.load(from: dir))
    }

    func test_missingStart_returnsNil() throws {
        try write(#"{"name":"A","port":9001}"#)
        XCTAssertNil(LocalSlotConfig.load(from: dir))
    }

    func test_missingPort_returnsNil() throws {
        try write(#"{"name":"A","start":"run"}"#)
        XCTAssertNil(LocalSlotConfig.load(from: dir))
    }

    func test_zeroPort_returnsNil() throws {
        try write(#"{"name":"A","start":"run","port":0}"#)
        XCTAssertNil(LocalSlotConfig.load(from: dir))
    }

    func test_negativePort_returnsNil() throws {
        try write(#"{"name":"A","start":"run","port":-1}"#)
        XCTAssertNil(LocalSlotConfig.load(from: dir))
    }

    func test_portOver65535_returnsNil() throws {
        try write(#"{"name":"A","start":"run","port":99999}"#)
        XCTAssertNil(LocalSlotConfig.load(from: dir))
    }

    func test_missingName_returnsNil() throws {
        try write(#"{"start":"run","port":9001}"#)
        XCTAssertNil(LocalSlotConfig.load(from: dir))
    }
}

// MARK: - Slot Tests

final class SlotTests: XCTestCase {

    func test_slotHasLocalPath() {
        let slot = Slot(name: "A", port: 9001, localPath: "/tmp")
        XCTAssertEqual(slot.localPath, "/tmp")
    }

    func test_defaultIsActive_isFalse() {
        XCTAssertFalse(Slot(name: "A", port: 9001, localPath: "/tmp").isActive)
    }

    func test_codableRoundTrip() throws {
        let original = Slot(name: "App", port: 9001,
                            localPath: "/tmp/app", isActive: true)
        let decoded  = try JSONDecoder().decode(Slot.self, from: JSONEncoder().encode(original))
        XCTAssertEqual(decoded.id,        original.id)
        XCTAssertEqual(decoded.name,      original.name)
        XCTAssertEqual(decoded.port,      original.port)
        XCTAssertEqual(decoded.localPath, original.localPath)
        XCTAssertEqual(decoded.isActive,  original.isActive)
    }

    func test_decodesLegacySlotsJsonWithHost() throws {
        // Pre-refactor slots.json had a `host` field; ensure we silently accept it.
        let id = UUID().uuidString
        let legacy = "{\"id\":\"\(id)\",\"name\":\"L\",\"host\":\"localhost\",\"port\":9001,\"localPath\":\"/tmp/x\",\"isActive\":true}"
        let data = legacy.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(Slot.self, from: data)
        XCTAssertEqual(decoded.name,      "L")
        XCTAssertEqual(decoded.port,      9001)
        XCTAssertEqual(decoded.localPath, "/tmp/x")
        XCTAssertTrue(decoded.isActive)
    }

    func test_rejectsLegacyRemoteSlot() {
        // Pre-refactor remote slots had no localPath (or null). Should fail to decode.
        let id = UUID().uuidString
        let legacy = "{\"id\":\"\(id)\",\"name\":\"R\",\"host\":\"192.168.1.1\",\"port\":9001,\"isActive\":false}"
        let data = legacy.data(using: .utf8)!
        XCTAssertThrowsError(try JSONDecoder().decode(Slot.self, from: data))
    }
}
