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
