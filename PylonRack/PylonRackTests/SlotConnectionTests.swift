import XCTest

@MainActor
final class SlotConnectionTests: XCTestCase {

    private var server: MockWSServer?

    override func tearDown() async throws {
        server?.stop()
        server = nil
        try await Task.sleep(nanoseconds: 100_000_000)
    }

    // MARK: - Connection lifecycle

    func test_activate_connectsAndReceivesManifest() async throws {
        server = MockWSServer(port: 19200)
        let conn = makeConn(port: 19200)
        conn.activate(port: 19200)

        try await waitFor(timeout: 5) { conn.manifest != nil }
        XCTAssertEqual(conn.manifest?.name, "MockApp")
        XCTAssertEqual(conn.status, .connected)
    }

    func test_activate_populatesControls() async throws {
        server = MockWSServer(port: 19201)
        let conn = makeConn(port: 19201)
        conn.activate(port: 19201)

        try await waitFor(timeout: 5) { !conn.controls.isEmpty }
        XCTAssertEqual(conn.controls.count, 2)
        XCTAssertTrue(conn.controls.allSatisfy { $0.type == .button })
    }

    func test_deactivate_setsMissingStatus() async throws {
        server = MockWSServer(port: 19202)
        let conn = makeConn(port: 19202)
        conn.activate(port: 19202)
        try await waitFor(timeout: 5) { conn.status == .connected }

        conn.deactivate()
        XCTAssertEqual(conn.status, .missing)
        XCTAssertFalse(conn.isActive)
    }

    func test_reconnect_onInactiveSlot_doesNothing() async throws {
        let conn = makeConn(port: 19203)
        conn.reconnect()
        try await Task.sleep(nanoseconds: 300_000_000)
        XCTAssertNotEqual(conn.status, .missing)
    }

    // MARK: - Heartbeat / pong

    func test_pong_running_setsConnectedStatus() async throws {
        server = MockWSServer(port: 19204)
        let conn = makeConn(port: 19204)
        conn.activate(port: 19204)

        try await waitFor(timeout: 5) { !conn.appMessage.isEmpty }
        XCTAssertEqual(conn.appMessage, "All good")
        XCTAssertEqual(conn.status, .connected)
    }

    func test_pong_warning_setsWarningStatus() async throws {
        server = MockWSServer(port: 19205, scenario: .warning)
        let conn = makeConn(port: 19205)
        conn.activate(port: 19205)

        try await waitFor(timeout: 5) { conn.status == .warning }
        XCTAssertEqual(conn.appMessage, "High load")
    }

    func test_pong_error_setsErrorStatus() async throws {
        server = MockWSServer(port: 19206, scenario: .errorStatus)
        let conn = makeConn(port: 19206)
        conn.activate(port: 19206)

        try await waitFor(timeout: 5) { conn.status == .error }
        XCTAssertEqual(conn.appMessage, "Critical failure")
    }

    // MARK: - Manifest variants

    func test_manifest_noUIURL_isNil() async throws {
        server = MockWSServer(port: 19207, scenario: .noUI)
        let conn = makeConn(port: 19207)
        conn.activate(port: 19207)

        try await waitFor(timeout: 5) { conn.manifest != nil }
        XCTAssertNil(conn.manifest?.uiURL)
    }

    func test_manifest_badJSON_doesNotCrash() async throws {
        server = MockWSServer(port: 19208, scenario: .badJSON)
        let conn = makeConn(port: 19208)
        conn.activate(port: 19208)

        try await Task.sleep(nanoseconds: 2_000_000_000)
        XCTAssertNil(conn.manifest)
        XCTAssertNotEqual(conn.status, .missing)
    }

    // MARK: - Controls protocol

    func test_controlData_populatesDropdownItems() async throws {
        server = MockWSServer(port: 19209, scenario: .withControls)
        let conn = makeConn(port: 19209)
        conn.activate(port: 19209)

        try await waitFor(timeout: 5) { conn.manifest != nil }
        try await waitFor(timeout: 3) {
            conn.controls.first(where: { $0.id == "model_select" })?.items != nil
        }
        let items = conn.controls.first(where: { $0.id == "model_select" })?.items
        XCTAssertEqual(items, ["llama-3.1-8b", "gemma-4-26b", "qwen3.5-35b"])
    }

    func test_controlsUpdate_updatesState() async throws {
        server = MockWSServer(port: 19210, scenario: .controlsUpdate)
        let conn = makeConn(port: 19210)
        conn.activate(port: 19210)

        try await waitFor(timeout: 5) { conn.manifest != nil }
        try await waitFor(timeout: 5) {
            conn.controls.first(where: { $0.id == "toggle" })?.label == "Stop"
        }
        let toggle = conn.controls.first(where: { $0.id == "toggle" })
        let label  = conn.controls.first(where: { $0.id == "status_label" })
        XCTAssertEqual(toggle?.label, "Stop")
        XCTAssertEqual(toggle?.style, .destructive)
        XCTAssertEqual(label?.value,  "Running")
        XCTAssertEqual(label?.style,  .success)
    }

    func test_reconnect_clearsControls_thenRepopulates() async throws {
        server = MockWSServer(port: 19211, scenario: .withControls)
        let conn = makeConn(port: 19211)
        conn.activate(port: 19211)

        try await waitFor(timeout: 5) { !conn.controls.isEmpty }
        conn.reconnect()
        try await waitFor(timeout: 5) { conn.manifest != nil && !conn.controls.isEmpty }
        XCTAssertFalse(conn.controls.isEmpty)
    }

    // MARK: - Log request

    func test_logRequest_receivesLines() async throws {
        server = MockWSServer(port: 19212)
        let conn = makeConn(port: 19212)
        conn.activate(port: 19212)

        try await waitFor(timeout: 5) { conn.manifest != nil }
        conn.requestLog(lines: 10, offset: 0)
        try await waitFor(timeout: 3) { !conn.logLines.isEmpty }
        XCTAssertEqual(conn.logLines.count, 10)
        XCTAssertEqual(conn.logTotal, 100)
    }

    // MARK: - Connection drop + reconnect

    func test_connectionDrop_triggersReconnect() async throws {
        server = MockWSServer(port: 19213, scenario: .dropAfter)
        let conn = makeConn(port: 19213)
        conn.activate(port: 19213)

        try await waitFor(timeout: 5) { conn.manifest != nil }
        try await waitFor(timeout: 5) { conn.status == .error || conn.status == .connecting }
        XCTAssertTrue(conn.status == .error || conn.status == .connecting)
    }

    func test_noServer_eventuallyErrors() async throws {
        let conn = makeConn(port: 19214)
        conn.activate(port: 19214)

        try await waitFor(timeout: 25) { conn.status == .error }
        XCTAssertEqual(conn.status, .error)
        XCTAssertFalse(conn.statusMessage.isEmpty)
    }

    func test_manualReconnect_duringRetryLoop_singleConnection() async throws {
        server = MockWSServer(port: 19215)
        let conn = makeConn(port: 19215)
        conn.activate(port: 19215)
        try await waitFor(timeout: 5) { conn.status == .connected }
        XCTAssertEqual(conn.connectionCount, 1)

        server?.stop(); server = nil
        try await waitFor(timeout: 5) { conn.status == .connecting || conn.status == .error }

        server = MockWSServer(port: 19215)
        conn.reconnect()

        try await waitFor(timeout: 5) { conn.status == .connected }
        try await Task.sleep(nanoseconds: 3_000_000_000)
        XCTAssertEqual(conn.connectionCount, 2,
            "Expected exactly 1 reconnection, got \(conn.connectionCount)")
    }

    // MARK: - Helpers

    private func makeConn(port: Int) -> SlotConnection {
        SlotConnection(slot: Slot(name: "Mock", host: "localhost", port: port),
                       settings: .defaults)
    }

    private func waitFor(timeout: TimeInterval, condition: @escaping () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
    }
}
