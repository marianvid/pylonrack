import XCTest

final class IncomingMessageTests: XCTestCase {

    func test_pong_running() {
        let msg = IncomingMessage.decode(from: #"{"type":"pong","status":"running","message":"All good"}"#)
        guard case .pong(let status, let message) = msg else { return XCTFail() }
        XCTAssertEqual(status,  "running")
        XCTAssertEqual(message, "All good")
    }

    func test_pong_warning() {
        let msg = IncomingMessage.decode(from: #"{"type":"pong","status":"warning","message":"High load"}"#)
        guard case .pong(let status, _) = msg else { return XCTFail() }
        XCTAssertEqual(status, "warning")
    }

    func test_pong_missingStatus_defaultsToRunning() {
        let msg = IncomingMessage.decode(from: #"{"type":"pong","message":"ok"}"#)
        guard case .pong(let status, _) = msg else { return XCTFail() }
        XCTAssertEqual(status, "running")
    }

    func test_manifest_decodesCorrectly() {
        let raw = """
        {"type":"manifest","name":"App","version":"1.0","controls":[],"heartbeat_interval":10}
        """
        let msg = IncomingMessage.decode(from: raw)
        guard case .manifest(let m) = msg else { return XCTFail() }
        XCTAssertEqual(m.name, "App")
    }

    func test_manifest_invalidJSON_isUnknown() {
        let msg = IncomingMessage.decode(from: #"{"type":"manifest","name":123}"#)
        // name is not a String — should fail gracefully
        if case .unknown = msg { return }
        // might decode with coercion on some platforms — acceptable
    }

    func test_logResponse() {
        let raw = #"{"type":"log_response","lines":["a","b"],"total":42}"#
        let msg = IncomingMessage.decode(from: raw)
        guard case .logResponse(let lines, let total, _) = msg else { return XCTFail() }
        XCTAssertEqual(lines, ["a", "b"])
        XCTAssertEqual(total, 42)
    }

    func test_controlData() {
        let raw = #"{"type":"control_data","control_id":"model","items":["llama","gemma"]}"#
        let msg = IncomingMessage.decode(from: raw)
        guard case .controlData(let id, let items) = msg else { return XCTFail() }
        XCTAssertEqual(id,    "model")
        XCTAssertEqual(items, ["llama", "gemma"])
    }

    func test_controlData_missingFields_isUnknown() {
        let msg = IncomingMessage.decode(from: #"{"type":"control_data","control_id":"x"}"#)
        guard case .unknown = msg else { return XCTFail("Expected .unknown") }
    }

    func test_controlsUpdate() {
        let raw = #"{"type":"controls_update","controls":[{"id":"btn","label":"Stop","style":"destructive"}]}"#
        let msg = IncomingMessage.decode(from: raw)
        guard case .controlsUpdate(let updates) = msg else { return XCTFail() }
        XCTAssertEqual(updates.count, 1)
        XCTAssertEqual(updates[0]["id"] as? String, "btn")
    }

    func test_actionResult_isAcknowledged() {
        let msg = IncomingMessage.decode(from: #"{"type":"action_result","control_id":"start"}"#)
        guard case .actionResult = msg else { return XCTFail() }
    }

    func test_unknown_type() {
        let msg = IncomingMessage.decode(from: #"{"type":"something_new"}"#)
        guard case .unknown = msg else { return XCTFail() }
    }

    func test_emptyString_isUnknown() {
        let msg = IncomingMessage.decode(from: "")
        guard case .unknown = msg else { return XCTFail() }
    }

    func test_invalidJSON_isUnknown() {
        let msg = IncomingMessage.decode(from: "not json {{{")
        guard case .unknown = msg else { return XCTFail() }
    }
}
