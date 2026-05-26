import Foundation
import Network
import CryptoKit

// MARK: - Mock scenarios

enum MockScenario {
    case normal         // standard manifest + heartbeat
    case warning        // pong returns warning status
    case errorStatus    // pong returns error status
    case noUI           // manifest without ui_url
    case dropAfter      // drops connection after first pong
    case badJSON        // sends invalid JSON as manifest
    case withControls   // manifest with dropdown + button + label
    case controlsUpdate // sends controls_update on first pong
}

// MARK: - MockWSServer

@MainActor
final class MockWSServer {
    let port: Int
    private let scenario: MockScenario
    private var listener:    NWListener?
    private var connections: [NWConnection] = []
    private var pongCount = 0

    private static let queue = DispatchQueue(label: "mock.ws.server", qos: .userInitiated)

    init(port: Int, scenario: MockScenario = .normal) {
        self.port     = port
        self.scenario = scenario
        start()
    }

    private func start() {
        let params = NWParameters.tcp
        params.allowLocalEndpointReuse = true
        guard let listener = try? NWListener(using: params,
                                             on: NWEndpoint.Port(integerLiteral: UInt16(port)))
        else { return }
        self.listener = listener

        listener.newConnectionHandler = { [weak self] conn in
            Task { @MainActor [weak self] in self?.accept(conn) }
        }
        listener.start(queue: Self.queue)

        let deadline = Date().addingTimeInterval(3)
        while listener.state != .ready && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.05)
        }
    }

    private func accept(_ conn: NWConnection) {
        connections.append(conn)
        conn.start(queue: Self.queue)
        handshake(conn)
    }

    private func handshake(_ conn: NWConnection) {
        conn.receive(minimumIncompleteLength: 1, maximumLength: 4096) { [weak self] data, _, _, _ in
            guard let self, let data, !data.isEmpty else { return }
            let request = String(data: data, encoding: .utf8) ?? ""
            guard let keyLine = request.components(separatedBy: "\r\n")
                    .first(where: { $0.hasPrefix("Sec-WebSocket-Key:") }),
                  let key = keyLine.components(separatedBy: ": ").last?.trimmingCharacters(in: .whitespaces)
            else { return }

            let accept   = Self.acceptKey(for: key)
            let response = "HTTP/1.1 101 Switching Protocols\r\n" +
                           "Upgrade: websocket\r\nConnection: Upgrade\r\n" +
                           "Sec-WebSocket-Accept: \(accept)\r\n\r\n"
            conn.send(content: response.data(using: .utf8),
                      completion: .contentProcessed { [weak self] _ in self?.receive(conn) })
        }
    }

    private func receive(_ conn: NWConnection) {
        conn.receive(minimumIncompleteLength: 2, maximumLength: 65536) { [weak self] data, _, _, _ in
            guard let self, let data, data.count >= 2 else { return }
            if let text = Self.decodeFrame(data) { self.handle(text, conn: conn) }
            self.receive(conn)
        }
    }

    private func handle(_ raw: String, conn: NWConnection) {
        guard let data = raw.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = json["type"] as? String else { return }

        switch type {
        case "ping":     handlePing(conn: conn)
        case "manifest": handleManifest(conn: conn)
        case "control_data":
            let id = json["control_id"] as? String ?? ""
            if id == "model_select" {
                send(["type": "control_data", "control_id": "model_select",
                      "items": ["llama-3.1-8b", "gemma-4-26b", "qwen3.5-35b"]], to: conn)
            }
        case "action":
            let id = json["control_id"] as? String ?? ""
            send(["type": "action_result", "control_id": id, "success": true], to: conn)
        case "log_request":
            let n = json["lines"] as? Int ?? 10
            send(["type": "log_response",
                  "lines": (0..<n).map { "Log line \($0)" },
                  "total": 100], to: conn)
        default: break
        }
    }

    private func handlePing(conn: NWConnection) {
        pongCount += 1
        switch scenario {
        case .warning:
            send(["type": "pong", "status": "warning",  "message": "High load"],      to: conn)
        case .errorStatus:
            send(["type": "pong", "status": "error",    "message": "Critical failure"], to: conn)
        case .dropAfter where pongCount >= 1:
            conn.cancel()
        case .controlsUpdate where pongCount == 1:
            send(["type": "pong", "status": "running", "message": "All good"], to: conn)
            send(["type": "controls_update", "controls": [
                ["id": "toggle",       "label": "Stop",    "style": "destructive"],
                ["id": "status_label", "value": "Running", "style": "success"]
            ]], to: conn)
        default:
            send(["type": "pong", "status": "running", "message": "All good"], to: conn)
        }
    }

    private func handleManifest(conn: NWConnection) {
        switch scenario {
        case .badJSON:
            sendRaw("NOT VALID JSON {{{", to: conn)
        case .noUI:
            send(["type": "manifest", "name": "MockApp", "version": "1.0",
                  "heartbeat_interval": 1,
                  "controls": [
                    ["id": "run", "type": "button", "label": "Run", "style": "primary"]
                  ]], to: conn)
        case .withControls, .controlsUpdate:
            send(["type": "manifest", "name": "MockApp", "version": "1.0",
                  "heartbeat_interval": 1,
                  "controls": [
                    ["id": "model_select", "type": "dropdown", "label": "Model"],
                    ["id": "toggle",       "type": "button",   "label": "Start", "style": "primary"],
                    ["id": "status_label", "type": "label",    "label": "Idle",  "style": "default"]
                  ]], to: conn)
        default:
            send(["type": "manifest", "name": "MockApp", "version": "1.0",
                  "heartbeat_interval": 1,
                  "controls": [
                    ["id": "start", "type": "button", "label": "Start", "style": "primary"],
                    ["id": "stop",  "type": "button", "label": "Stop",  "style": "destructive"]
                  ],
                  "ui_url": "http://localhost:\(port)/index.html"], to: conn)
        }
    }

    private func send(_ dict: [String: Any], to conn: NWConnection) {
        guard let data = try? JSONSerialization.data(withJSONObject: dict),
              let str  = String(data: data, encoding: .utf8) else { return }
        sendRaw(str, to: conn)
    }

    private func sendRaw(_ text: String, to conn: NWConnection) {
        guard let frame = Self.encodeFrame(text) else { return }
        conn.send(content: frame, completion: .contentProcessed { _ in })
    }

    func stop() {
        connections.forEach { $0.cancel() }
        connections.removeAll()
        listener?.cancel()
        listener = nil
    }

    // MARK: - RFC 6455 frame codec

    private static func encodeFrame(_ text: String) -> Data? {
        guard let payload = text.data(using: .utf8) else { return nil }
        var frame = Data()
        frame.append(0x81)
        let len = payload.count
        if len < 126 {
            frame.append(UInt8(len))
        } else if len < 65536 {
            frame.append(126)
            frame.append(UInt8((len >> 8) & 0xFF))
            frame.append(UInt8(len & 0xFF))
        } else {
            frame.append(127)
            for i in stride(from: 56, through: 0, by: -8) { frame.append(UInt8((len >> i) & 0xFF)) }
        }
        frame.append(contentsOf: payload)
        return frame
    }

    private static func decodeFrame(_ data: Data) -> String? {
        guard data.count >= 2 else { return nil }
        let b0 = data[0], b1 = data[1]
        guard b0 & 0x0F == 0x01 else { return nil }
        let masked = (b1 & 0x80) != 0
        var payloadLen = Int(b1 & 0x7F)
        var offset = 2
        if payloadLen == 126 {
            guard data.count >= 4 else { return nil }
            payloadLen = Int(data[2]) << 8 | Int(data[3]); offset = 4
        } else if payloadLen == 127 {
            guard data.count >= 10 else { return nil }
            payloadLen = 0
            for i in 0..<8 { payloadLen = payloadLen << 8 | Int(data[2 + i]) }
            offset = 10
        }
        var maskKey = [UInt8](repeating: 0, count: 4)
        if masked {
            guard data.count >= offset + 4 else { return nil }
            maskKey = [data[offset], data[offset+1], data[offset+2], data[offset+3]]
            offset += 4
        }
        guard data.count >= offset + payloadLen else { return nil }
        var payload = [UInt8](data[offset..<(offset + payloadLen)])
        if masked { for i in 0..<payload.count { payload[i] ^= maskKey[i % 4] } }
        return String(bytes: payload, encoding: .utf8)
    }

    private static func acceptKey(for key: String) -> String {
        let combined = (key + "258EAFA5-E914-47DA-95CA-C5AB0DC85B11").data(using: .utf8)!
        return Data(Insecure.SHA1.hash(data: combined)).base64EncodedString()
    }
}
