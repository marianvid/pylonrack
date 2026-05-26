import XCTest

final class SlotManifestTests: XCTestCase {

    func test_decodesControls() throws {
        let json = """
        {
            "type": "manifest",
            "name": "TestApp",
            "version": "1.0",
            "heartbeat_interval": 5,
            "controls": [
                {"id": "start", "type": "button", "label": "Start", "style": "primary"},
                {"id": "model", "type": "dropdown", "label": "Model"},
                {"id": "status", "type": "label", "value": "Idle"}
            ],
            "ui_url": "http://localhost:9000"
        }
        """
        let m = try JSONDecoder().decode(SlotManifest.self, from: Data(json.utf8))
        XCTAssertEqual(m.name, "TestApp")
        XCTAssertEqual(m.version, "1.0")
        XCTAssertEqual(m.heartbeatInterval, 5)
        XCTAssertEqual(m.controls.count, 3)
        XCTAssertEqual(m.controls[0].id,    "start")
        XCTAssertEqual(m.controls[0].type,  .button)
        XCTAssertEqual(m.controls[0].style, .primary)
        XCTAssertEqual(m.controls[1].type,  .dropdown)
        XCTAssertEqual(m.controls[2].type,  .label)
        XCTAssertEqual(m.controls[2].value, "Idle")
        XCTAssertEqual(m.uiURL, "http://localhost:9000")
    }

    func test_emptyControls_isValid() throws {
        let json = """
        {"type":"manifest","name":"X","version":"1.0","controls":[]}
        """
        let m = try JSONDecoder().decode(SlotManifest.self, from: Data(json.utf8))
        XCTAssertTrue(m.controls.isEmpty)
        XCTAssertNil(m.uiURL)
    }

    func test_missingOptionals_decodesGracefully() throws {
        let json = """
        {"type":"manifest","name":"Bare","version":"","controls":[]}
        """
        let m = try JSONDecoder().decode(SlotManifest.self, from: Data(json.utf8))
        XCTAssertNil(m.heartbeatInterval)
        XCTAssertNil(m.uiURL)
    }

    func test_controlStyle_allCases() {
        let cases: [(String, ControlStyle)] = [
            ("primary", .primary), ("secondary", .secondary),
            ("destructive", .destructive), ("warning", .warning),
            ("success", .success), ("error", .error), ("default", .default)
        ]
        for (raw, expected) in cases {
            XCTAssertEqual(ControlStyle(rawValue: raw), expected, "Failed for \(raw)")
        }
    }

    func test_unknownStyle_isNil() {
        XCTAssertNil(ControlStyle(rawValue: "banana"))
    }
}
