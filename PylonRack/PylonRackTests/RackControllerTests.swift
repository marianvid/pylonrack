import XCTest

@MainActor
final class RackControllerTests: XCTestCase {

    private var tempDir:  URL!
    private var slotsURL: URL!

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

    func test_addSlot_persistsToDisk() throws {
        let rack = makeRack()
        rack.addSlot(Slot(name: "App", port: 9001, localPath: "/tmp"))

        XCTAssertTrue(FileManager.default.fileExists(atPath: slotsURL.path))
        let slots = try loadSlots()
        XCTAssertEqual(slots.count, 1)
        XCTAssertEqual(slots[0].name, "App")
    }

    func test_addSlot_defaultIsInactive() {
        let rack = makeRack()
        rack.addSlot(Slot(name: "App", port: 9001, localPath: "/tmp"))
        XCTAssertFalse(rack.slots.first!.isActive)
    }

    func test_addMultipleSlots_allPersisted() throws {
        let rack = makeRack()
        rack.addSlot(Slot(name: "A", port: 9001, localPath: "/tmp"))
        rack.addSlot(Slot(name: "B", port: 9002, localPath: "/tmp"))
        rack.addSlot(Slot(name: "C", port: 9003, localPath: "/tmp"))
        XCTAssertEqual(try loadSlots().count, 3)
    }

    func test_removeSlot_removedFromDisk() async throws {
        let rack = makeRack()
        let slot = Slot(name: "App", port: 9001, localPath: "/tmp")
        rack.addSlot(slot)
        rack.removeSlot(rack.slots.first!)
        try await Task.sleep(nanoseconds: 500_000_000)
        XCTAssertEqual(try loadSlots().count, 0)
        XCTAssertEqual(rack.slots.count, 0)
    }

    // MARK: - Load from disk

    func test_loadFromDisk_restoresSlots() throws {
        try saveSlots([
            Slot(name: "A", port: 9001, localPath: "/tmp"),
            Slot(name: "B", port: 9002, localPath: "/tmp"),
        ])
        let rack = makeRack()
        XCTAssertEqual(rack.slots.count, 2)
        XCTAssertEqual(rack.slots[0].name, "A")
        XCTAssertEqual(rack.slots[1].name, "B")
    }

    func test_corruptFile_startsEmpty() throws {
        try "NOT VALID JSON {{{{".write(to: slotsURL, atomically: true, encoding: .utf8)
        XCTAssertEqual(makeRack().slots.count, 0)
    }

    func test_missingFile_startsEmpty() {
        XCTAssertEqual(makeRack().slots.count, 0)
    }

    // MARK: - Restart behaviour

    func test_inactiveSlotOnRestart_remainsInactive() throws {
        try saveSlots([Slot(name: "A", port: 9001, localPath: "/tmp", isActive: false)])
        let rack = makeRack()
        XCTAssertFalse(rack.slots.first!.isActive)
        XCTAssertEqual(rack.connection(for: rack.slots.first!)?.status, .missing)
    }

    func test_activeRemoteSlotOnRestart_attemptsConnect() async throws {
        try saveSlots([Slot(name: "R", port: 9300, localPath: "/tmp", isActive: true)])
        let rack = makeRack()
        try await Task.sleep(nanoseconds: 300_000_000)
        let conn = rack.connection(for: rack.slots.first!)
        XCTAssertNotEqual(conn?.status, .missing)
    }

    // MARK: - Connection management

    func test_connectionForSlot_notNilAfterAdd() {
        let rack = makeRack()
        rack.addSlot(Slot(name: "App", port: 9001, localPath: "/tmp"))
        XCTAssertNotNil(rack.connection(for: rack.slots.first!))
    }

    func test_connectionForRemovedSlot_nilAfterRemove() async throws {
        let rack = makeRack()
        rack.addSlot(Slot(name: "App", port: 9001, localPath: "/tmp"))
        let added = rack.slots.first!
        rack.removeSlot(added)
        try await Task.sleep(nanoseconds: 500_000_000)
        XCTAssertNil(rack.connection(for: added))
    }

    // MARK: - Selection

    func test_selectedSlotId_defaultNil() {
        XCTAssertNil(makeRack().selectedSlotId)
    }

    func test_selectedSlotId_setAndRead() {
        let rack = makeRack()
        rack.addSlot(Slot(name: "App", port: 9001, localPath: "/tmp"))
        rack.selectedSlotId = rack.slots.first!.id
        XCTAssertEqual(rack.selectedSlotId, rack.slots.first!.id)
    }

    func test_removeSelectedSlot_clearsSelection() async throws {
        let rack = makeRack()
        rack.addSlot(Slot(name: "App", port: 9001, localPath: "/tmp"))
        rack.selectedSlotId = rack.slots.first!.id
        rack.removeSlot(rack.slots.first!)
        try await Task.sleep(nanoseconds: 300_000_000)
        XCTAssertNil(rack.selectedSlotId)
    }

    // MARK: - Activate / Deactivate

    func test_activateSlot_isActiveTrue() throws {
        let rack = makeRack()
        rack.addSlot(Slot(name: "App", port: 9001, localPath: "/tmp"))
        rack.activate(rack.slots.first!)
        XCTAssertTrue(rack.slots.first!.isActive)
    }

    func test_deactivateSlot_isActiveFalse() async throws {
        let rack = makeRack()
        rack.addSlot(Slot(name: "App", port: 9001, localPath: "/tmp"))
        rack.activate(rack.slots.first!)
        await rack.deactivate(rack.slots.first!)
        XCTAssertFalse(rack.slots.first!.isActive)
    }

    func test_toggleActive_togglesState() async throws {
        let rack = makeRack()
        rack.addSlot(Slot(name: "App", port: 9001, localPath: "/tmp"))
        XCTAssertFalse(rack.slots.first!.isActive)
        rack.toggleActive(rack.slots.first!)
        XCTAssertTrue(rack.slots.first!.isActive)
    }

    // MARK: - Helpers

    private func makeRack() -> RackController {
        RackController(slotsURL: slotsURL, settingsStore: SettingsStore(url: tempDir.appendingPathComponent("s.json")))
    }

    private func loadSlots() throws -> [Slot] {
        try JSONDecoder().decode([Slot].self, from: Data(contentsOf: slotsURL))
    }

    private func saveSlots(_ slots: [Slot]) throws {
        try JSONEncoder().encode(slots).write(to: slotsURL)
    }
}
