import Foundation

enum DesktopRenamerAPIContract {
    static let version = "1.2.0"
    static let jsonRPCVersion = "2.0"
    static let payloadKey = "payload"
    static let maxPayloadBytes = 1_048_576

    static let rpcRequest = Notification.Name("com.michaelqiu.DesktopRenamer.RPCRequest")
    static let rpcResponse = Notification.Name("com.michaelqiu.DesktopRenamer.RPCResponse")
    static let rpcEvent = Notification.Name("com.michaelqiu.DesktopRenamer.RPCEvent")

    static let supportedMethods = [
        "getAPIInfo",
        "getAPIVersion",
        "getSpaceSnapshot",
        "getCurrentSpaceName",
        "getCurrentSpaceID",
        "getAllSpaces",
        "switchToSpace",
        "renameCurrentSpace",
        "renameSpace",
        "rearrangeSpace",
        "moveWindowNext",
        "moveWindowPrevious",
        "moveWindowToSpace",
        "reloadSpaceLabels",
        "toggleMenubar",
        "toggleLauncher",
        "toggleLabels",
        "toggleActiveLabel",
        "togglePreviewLabel",
        "toggleDesktopVisibility",
        "getWindows",
        "focusWindow",
        "executeWindowAction",
        "moveSpecificWindow"
    ]
}

enum SpaceAPIJSONValue: Codable, Equatable {
    case object([String: SpaceAPIJSONValue])
    case array([SpaceAPIJSONValue])
    case string(String)
    case number(Double)
    case bool(Bool)
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode([String: SpaceAPIJSONValue].self) {
            self = .object(value)
        } else if let value = try? container.decode([SpaceAPIJSONValue].self) {
            self = .array(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            guard value.isFinite else {
                throw SpaceAPIContractError.invalidJSON("JSON numbers must be finite.")
            }
            self = .number(value)
        } else {
            throw SpaceAPIContractError.invalidJSON("Unsupported JSON value.")
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()

        switch self {
        case .object(let value):
            try container.encode(value)
        case .array(let value):
            try container.encode(value)
        case .string(let value):
            try container.encode(value)
        case .number(let value):
            guard value.isFinite else {
                throw SpaceAPIContractError.invalidJSON("JSON numbers must be finite.")
            }
            try container.encode(value)
        case .bool(let value):
            try container.encode(value)
        case .null:
            try container.encodeNil()
        }
    }

    static func from<T: Encodable>(_ value: T, using encoder: JSONEncoder = JSONEncoder()) throws -> SpaceAPIJSONValue {
        try decoder.decode(SpaceAPIJSONValue.self, from: encoder.encode(value))
    }

    func decode<T: Decodable>(_ type: T.Type, using decoder: JSONDecoder = JSONDecoder()) throws -> T {
        try decoder.decode(type, from: JSONEncoder().encode(self))
    }

    private static let decoder = JSONDecoder()

    var objectValue: [String: SpaceAPIJSONValue]? {
        guard case .object(let value) = self else { return nil }
        return value
    }

    var stringValue: String? {
        guard case .string(let value) = self else { return nil }
        return value
    }

    var boolValue: Bool? {
        guard case .bool(let value) = self else { return nil }
        return value
    }

    var intValue: Int? {
        guard case .number(let value) = self, value.rounded() == value else { return nil }
        return Int(exactly: value)
    }
}

struct SpaceAPIJSONRPCRequest: Codable, Equatable {
    let jsonrpc: String
    let id: String?
    let method: String
    let params: SpaceAPIJSONValue?

    init(id: String, method: String, params: [String: SpaceAPIJSONValue] = [:]) {
        self.jsonrpc = DesktopRenamerAPIContract.jsonRPCVersion
        self.id = id
        self.method = method
        self.params = params.isEmpty ? nil : .object(params)
    }
}

struct SpaceAPIJSONRPCError: Codable, Equatable {
    let code: Int
    let message: String
    let data: SpaceAPIJSONValue?
}

struct SpaceAPIJSONRPCResponse: Codable, Equatable {
    let jsonrpc: String
    let id: String?
    let result: SpaceAPIJSONValue?
    let error: SpaceAPIJSONRPCError?

    init(id: String?, result: SpaceAPIJSONValue) {
        self.jsonrpc = DesktopRenamerAPIContract.jsonRPCVersion
        self.id = id
        self.result = result
        self.error = nil
    }

    init(id: String?, error: SpaceAPIJSONRPCError) {
        self.jsonrpc = DesktopRenamerAPIContract.jsonRPCVersion
        self.id = id
        self.result = nil
        self.error = error
    }
}

struct SpaceAPIJSONRPCEvent: Codable, Equatable {
    let jsonrpc: String
    let method: String
    let params: SpaceAPIJSONValue

    init(method: String, params: SpaceAPIJSONValue) {
        self.jsonrpc = DesktopRenamerAPIContract.jsonRPCVersion
        self.method = method
        self.params = params
    }
}

struct SpaceAPIErrorData: Codable, Equatable {
    let parameter: String?
    let expected: String?
    let command: String?

    init(parameter: String? = nil, expected: String? = nil, command: String? = nil) {
        self.parameter = parameter
        self.expected = expected
        self.command = command
    }
}

struct SpaceAPISpace: Codable, Equatable {
    let id: String
    let name: String
    let displayID: String
    let displayName: String
    let number: Int
    let isFullscreen: Bool
    let appName: String?
    let appPath: String?
    let globalShortcutNumber: Int?
}

struct SpaceAPIWindow: Codable, Equatable {
    let id: Int
    let pid: Int32
    let ownerName: String
    let appPath: String?
    let title: String?
    let spaceID: String
    let isMinimized: Bool
    let isHidden: Bool
}

struct SpaceAPISnapshot: Codable, Equatable {
    let apiVersion: String
    let revision: UInt64
    let timestamp: String
    let currentSpaceIDs: [String]
    let currentSpaceName: String
    let spaces: [SpaceAPISpace]
}

struct SpaceAPIWindowsSnapshot: Codable, Equatable {
    let apiVersion: String
    let revision: UInt64
    let timestamp: String
    let spaces: [SpaceAPISpace]
    let windows: [SpaceAPIWindow]
}

struct SpaceAPIOperationResult: Codable, Equatable {
    let accepted: Bool
}

struct SpaceAPIInfo: Codable, Equatable {
    let contractVersion: String
    let jsonRPCVersion: String
    let supportedMethods: [String]
    let legacyNotifications: Bool
    let eventNotifications: Bool
    let maxPayloadBytes: Int
}

enum SpaceAPIContractError: LocalizedError, Equatable {
    case invalidJSON(String)
    case invalidRequest(String)
    case invalidParams(String)
    case payloadTooLarge
    case unsupportedMethod(String)

    var errorDescription: String? {
        switch self {
        case .invalidJSON(let message), .invalidRequest(let message), .invalidParams(let message):
            return message
        case .payloadTooLarge:
            return "SpaceAPI payload exceeds the maximum size."
        case .unsupportedMethod(let method):
            return "Unsupported SpaceAPI method: \(method)"
        }
    }
}

enum SpaceAPIJSONRPCCodec {
    static func decodeRequest(_ payload: String) throws -> SpaceAPIJSONRPCRequest {
        try validatePayloadSize(payload)
        guard let data = payload.data(using: .utf8) else {
            throw SpaceAPIContractError.invalidJSON("Payload is not valid UTF-8.")
        }

        let request: SpaceAPIJSONRPCRequest
        do {
            request = try JSONDecoder().decode(SpaceAPIJSONRPCRequest.self, from: data)
        } catch {
            throw SpaceAPIContractError.invalidRequest("Request is not a valid JSON-RPC 2.0 object.")
        }

        guard request.jsonrpc == DesktopRenamerAPIContract.jsonRPCVersion else {
            throw SpaceAPIContractError.invalidRequest("Only JSON-RPC 2.0 requests are supported.")
        }
        guard let id = request.id, !id.isEmpty else {
            throw SpaceAPIContractError.invalidRequest("A non-empty string request ID is required.")
        }
        guard !request.method.isEmpty, request.method.count <= 128 else {
            throw SpaceAPIContractError.invalidRequest("A non-empty method name of at most 128 characters is required.")
        }
        if let params = request.params, params.objectValue == nil {
            throw SpaceAPIContractError.invalidParams("Named parameters must be a JSON object.")
        }
        return request
    }

    static func encode(_ response: SpaceAPIJSONRPCResponse) throws -> String {
        guard (response.result == nil) != (response.error == nil) else {
            throw SpaceAPIContractError.invalidRequest("A response must contain exactly one of result or error.")
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(response)
        guard data.count <= DesktopRenamerAPIContract.maxPayloadBytes else {
            throw SpaceAPIContractError.payloadTooLarge
        }
        return String(decoding: data, as: UTF8.self)
    }

    static func encode(_ event: SpaceAPIJSONRPCEvent) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(event)
        guard data.count <= DesktopRenamerAPIContract.maxPayloadBytes else {
            throw SpaceAPIContractError.payloadTooLarge
        }
        return String(decoding: data, as: UTF8.self)
    }

    static func errorResponse(
        id: String?,
        code: Int,
        message: String,
        data: SpaceAPIErrorData? = nil
    ) -> SpaceAPIJSONRPCResponse {
        let encodedData: SpaceAPIJSONValue?
        if let data {
            encodedData = try? SpaceAPIJSONValue.from(data)
        } else {
            encodedData = nil
        }
        return SpaceAPIJSONRPCResponse(
            id: id,
            error: SpaceAPIJSONRPCError(code: code, message: message, data: encodedData)
        )
    }

    private static func validatePayloadSize(_ payload: String) throws {
        guard payload.utf8.count <= DesktopRenamerAPIContract.maxPayloadBytes else {
            throw SpaceAPIContractError.payloadTooLarge
        }
    }
}

extension SpaceAPIContractError {
    var jsonRPCCode: Int {
        switch self {
        case .invalidJSON:
            return -32700
        case .invalidRequest:
            return -32600
        case .invalidParams:
            return -32602
        case .unsupportedMethod:
            return -32601
        case .payloadTooLarge:
            return -32006
        }
    }
}
