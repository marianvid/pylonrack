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
