// Protocol.swift
// SessionPad JSON wire protocol — shared contract with Python Protocol.py.

import Foundation

enum SPProtocol {
    static let version = 1
    static let supportedVersions = [1]
    static let serviceType = "_sessionpad._tcp"
    static let heartbeatIntervalMs = 2000
    static let defaultCapabilities = ["session", "transport", "clips", "commands"]
    static let defaultTopics = ["session", "transport", "clips"]
}

enum SPBridge {
    static let liveLinkPort: UInt16 = 17345
    static let iosWebSocketPort: UInt16 = 17346
}

// MARK: - ClipState

enum ClipState: String, Codable, Equatable {
    case empty
    case stopped
    case playing
    case recording
    case queued
    case recQueued
}

// MARK: - Wire Message

struct WireMessage: Codable, Sendable {
    let v: Int
    let t: String
    var seq: Int?
    var id: String?
    var payload: JSONValue?

    init(v: Int = SPProtocol.version, t: String, seq: Int? = nil, id: String? = nil, payload: JSONValue? = nil) {
        self.v = v
        self.t = t
        self.seq = seq
        self.id = id
        self.payload = payload
    }
}

// MARK: - JSONValue (flexible payload)

enum JSONValue: Codable, Sendable, Equatable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
    case array([JSONValue])
    case object([String: JSONValue])
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let v = try? container.decode(Bool.self) {
            self = .bool(v)
        } else if let v = try? container.decode(Int.self) {
            self = .int(v)
        } else if let v = try? container.decode(Double.self) {
            self = .double(v)
        } else if let v = try? container.decode(String.self) {
            self = .string(v)
        } else if let v = try? container.decode([JSONValue].self) {
            self = .array(v)
        } else if let v = try? container.decode([String: JSONValue].self) {
            self = .object(v)
        } else {
            self = .null
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let v): try container.encode(v)
        case .int(let v): try container.encode(v)
        case .double(let v): try container.encode(v)
        case .bool(let v): try container.encode(v)
        case .array(let v): try container.encode(v)
        case .object(let v): try container.encode(v)
        case .null: try container.encodeNil()
        }
    }

    var objectValue: [String: JSONValue]? {
        if case .object(let o) = self { return o }
        return nil
    }

    var arrayValue: [JSONValue]? {
        if case .array(let a) = self { return a }
        return nil
    }

    var stringValue: String? {
        if case .string(let s) = self { return s }
        return nil
    }

    var intValue: Int? {
        switch self {
        case .int(let i): return i
        case .double(let d): return Int(d)
        default: return nil
        }
    }

    var doubleValue: Double? {
        switch self {
        case .double(let d): return d
        case .int(let i): return Double(i)
        default: return nil
        }
    }

    var boolValue: Bool? {
        if case .bool(let b) = self { return b }
        return nil
    }
}

// MARK: - Message Types

enum MessageType {
    static let hello = "hello"
    static let welcome = "welcome"
    static let error = "error"
    static let subscribe = "subscribe"
    static let getState = "getState"
    static let stateFull = "state.full"
    static let deltaClip = "delta.clip"
    static let deltaTrack = "delta.track"
    static let deltaScene = "delta.scene"
    static let deltaTransport = "delta.transport"
    static let heartbeat = "heartbeat"
    static let ack = "ack"
    static let cmd = "cmd"
    static let bridgeSession = "bridge.session"
}

// MARK: - Payload Structs

struct HelloPayload: Codable, Sendable {
    let protocolVersions: [Int]
    let appVersion: String
    let capabilities: [String]
}

struct WelcomePayload: Codable, Sendable {
    let chosenVersion: Int
    let liveVersion: String
    let capabilities: [String]
    let heartbeatIntervalMs: Int
    let snapshotRev: Int
    let sessionName: String
}

struct SubscribePayload: Codable, Sendable {
    let topics: [String]
}

struct CommandPayload: Codable, Sendable {
    let name: String
    let data: [String: JSONValue]?
}

struct AckPayload: Codable, Sendable {
    let ok: Bool
    let error: String?
}

struct HeartbeatPayload: Codable, Sendable {
    let ts: Int
}

struct FullStatePayload: Codable, Sendable {
    let rev: Int
    let tracks: Int
    let scenes: Int
    let trackHeaders: [TrackDelta]
    let scenes_meta: [SceneDelta]
    let clips: [ClipDelta]
    let transport: TransportDelta
}

struct ClipDelta: Codable, Sendable {
    let track: Int
    let scene: Int
    let state: ClipState
    let color: Int
    let name: String
}

struct TrackDelta: Codable, Sendable {
    let track: Int
    let name: String
    let color: Int
    let muted: Bool
    let solo: Bool
    let armed: Bool
}

struct SceneDelta: Codable, Sendable {
    let scene: Int
    let name: String
    let color: Int
}

struct TransportDelta: Codable, Sendable {
    let playing: Bool
    let recording: Bool
    let metronome: Bool
    let bpm: Double
}

// MARK: - Codec

enum ProtocolCodec {
    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = []
        return e
    }()

    private static let decoder = JSONDecoder()

    static func encode(_ message: WireMessage) throws -> String {
        let data = try encoder.encode(message)
        guard let text = String(data: data, encoding: .utf8) else {
            throw ProtocolError.encodeFailed
        }
        return text
    }

    static func decode(_ text: String) throws -> WireMessage {
        guard let data = text.data(using: .utf8) else {
            throw ProtocolError.decodeFailed
        }
        return try decoder.decode(WireMessage.self, from: data)
    }

    static func hello(appVersion: String) throws -> String {
        let payload = HelloPayload(
            protocolVersions: SPProtocol.supportedVersions,
            appVersion: appVersion,
            capabilities: SPProtocol.defaultCapabilities
        )
        let data = try encoder.encode(payload)
        let json = try decoder.decode(JSONValue.self, from: data)
        return try encode(WireMessage(t: MessageType.hello, payload: json))
    }

    static func subscribe() throws -> String {
        let payload = SubscribePayload(topics: SPProtocol.defaultTopics)
        let data = try encoder.encode(payload)
        let json = try decoder.decode(JSONValue.self, from: data)
        return try encode(WireMessage(t: MessageType.subscribe, payload: json))
    }

    static func getState() throws -> String {
        try encode(WireMessage(t: MessageType.getState))
    }

    static func heartbeat() throws -> String {
        let payload = HeartbeatPayload(ts: Int(Date().timeIntervalSince1970 * 1000))
        let data = try encoder.encode(payload)
        let json = try decoder.decode(JSONValue.self, from: data)
        return try encode(WireMessage(t: MessageType.heartbeat, payload: json))
    }

    static func command(name: String, data: [String: JSONValue], id: String) throws -> String {
        let payload = CommandPayload(name: name, data: data)
        let encoded = try encoder.encode(payload)
        let json = try decoder.decode(JSONValue.self, from: encoded)
        return try encode(WireMessage(t: MessageType.cmd, id: id, payload: json))
    }

    static func welcome(
        chosenVersion: Int,
        snapshotRev: Int,
        sessionName: String,
        msgId: String?
    ) throws -> String {
        let payload = WelcomePayload(
            chosenVersion: chosenVersion,
            liveVersion: "11/12",
            capabilities: SPProtocol.defaultCapabilities,
            heartbeatIntervalMs: SPProtocol.heartbeatIntervalMs,
            snapshotRev: snapshotRev,
            sessionName: sessionName
        )
        let data = try encoder.encode(payload)
        let json = try decoder.decode(JSONValue.self, from: data)
        return try encode(WireMessage(t: MessageType.welcome, id: msgId, payload: json))
    }

    static func ack(ok: Bool, error: String? = nil, msgId: String?) throws -> String {
        let payload = AckPayload(ok: ok, error: error)
        let data = try encoder.encode(payload)
        let json = try decoder.decode(JSONValue.self, from: data)
        return try encode(WireMessage(t: MessageType.ack, id: msgId, payload: json))
    }

    static func errorMessage(_ message: String, msgId: String? = nil) throws -> String {
        let json: JSONValue = .object(["message": .string(message)])
        return try encode(WireMessage(t: MessageType.error, id: msgId, payload: json))
    }

    static func decodePayload<T: Decodable>(_ type: T.Type, from message: WireMessage) throws -> T {
        guard let payload = message.payload else {
            throw ProtocolError.missingPayload
        }
        let data = try encoder.encode(payload)
        return try decoder.decode(T.self, from: data)
    }
}

enum ProtocolError: Error {
    case encodeFailed
    case decodeFailed
    case missingPayload
}
