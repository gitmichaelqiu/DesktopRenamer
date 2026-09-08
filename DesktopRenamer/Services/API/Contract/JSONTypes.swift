import Foundation

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
        try JSONDecoder().decode(SpaceAPIJSONValue.self, from: encoder.encode(value))
    }

    func decode<T: Decodable>(_ type: T.Type, using decoder: JSONDecoder = JSONDecoder()) throws -> T {
        try decoder.decode(type, from: JSONEncoder().encode(self))
    }

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
    let id: String
    let method: String
    let params: SpaceAPIJSONValue?

    init(id: String, method: String, params: [String: SpaceAPIJSONValue] = [:]) {
        self.jsonrpc = DesktopRenamerAPIContract.jsonRPCVersion
        self.id = id
        self.method = method
        self.params = params.isEmpty ? nil : .object(params)
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        jsonrpc = try container.decode(String.self, forKey: .jsonrpc)
        id = try container.decode(String.self, forKey: .id)
        method = try container.decode(String.self, forKey: .method)
        params = container.contains(.params) ? try container.decode(SpaceAPIJSONValue.self, forKey: .params) : nil
    }

    private enum CodingKeys: String, CodingKey {
        case jsonrpc
        case id
        case method
        case params
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

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        jsonrpc = try container.decode(String.self, forKey: .jsonrpc)
        guard container.contains(.id) else {
            throw SpaceAPIContractError.invalidRequest("A JSON-RPC response requires an ID, including null when unknown.")
        }
        id = try container.decodeIfPresent(String.self, forKey: .id)
        result = container.contains(.result) ? try container.decode(SpaceAPIJSONValue.self, forKey: .result) : nil
        error = container.contains(.error) ? try container.decode(SpaceAPIJSONRPCError.self, forKey: .error) : nil
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(jsonrpc, forKey: .jsonrpc)
        // JSON-RPC requires an explicit null ID when the request ID cannot be
        // recovered (for example, after a parse error).
        try container.encode(id, forKey: .id)
        try container.encodeIfPresent(result, forKey: .result)
        try container.encodeIfPresent(error, forKey: .error)
    }

    private enum CodingKeys: String, CodingKey {
        case jsonrpc
        case id
        case result
        case error
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

    init(
        id: String,
        name: String,
        displayID: String,
        displayName: String,
        number: Int,
        isFullscreen: Bool,
        appName: String?,
        appPath: String?,
        globalShortcutNumber: Int?
    ) {
        self.id = id
        self.name = name
        self.displayID = displayID
        self.displayName = displayName
        self.number = number
        self.isFullscreen = isFullscreen
        self.appName = appName
        self.appPath = appPath
        self.globalShortcutNumber = globalShortcutNumber
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        displayID = try container.decode(String.self, forKey: .displayID)
        displayName = try container.decode(String.self, forKey: .displayName)
        number = try container.decode(Int.self, forKey: .number)
        isFullscreen = try container.decode(Bool.self, forKey: .isFullscreen)
        appName = try container.decodeIfPresent(String.self, forKey: .appName)
        appPath = try container.decodeIfPresent(String.self, forKey: .appPath)
        globalShortcutNumber = try container.decodeIfPresent(Int.self, forKey: .globalShortcutNumber)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(displayID, forKey: .displayID)
        try container.encode(displayName, forKey: .displayName)
        try container.encode(number, forKey: .number)
        try container.encode(isFullscreen, forKey: .isFullscreen)
        try container.encode(appName, forKey: .appName)
        try container.encode(appPath, forKey: .appPath)
        try container.encode(globalShortcutNumber, forKey: .globalShortcutNumber)
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case displayID
        case displayName
        case number
        case isFullscreen
        case appName
        case appPath
        case globalShortcutNumber
    }
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

    init(
        id: Int,
        pid: Int32,
        ownerName: String,
        appPath: String?,
        title: String?,
        spaceID: String,
        isMinimized: Bool,
        isHidden: Bool
    ) {
        self.id = id
        self.pid = pid
        self.ownerName = ownerName
        self.appPath = appPath
        self.title = title
        self.spaceID = spaceID
        self.isMinimized = isMinimized
        self.isHidden = isHidden
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(Int.self, forKey: .id)
        pid = try container.decode(Int32.self, forKey: .pid)
        ownerName = try container.decode(String.self, forKey: .ownerName)
        appPath = try container.decodeIfPresent(String.self, forKey: .appPath)
        title = try container.decodeIfPresent(String.self, forKey: .title)
        spaceID = try container.decode(String.self, forKey: .spaceID)
        isMinimized = try container.decode(Bool.self, forKey: .isMinimized)
        isHidden = try container.decode(Bool.self, forKey: .isHidden)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(pid, forKey: .pid)
        try container.encode(ownerName, forKey: .ownerName)
        try container.encode(appPath, forKey: .appPath)
        try container.encode(title, forKey: .title)
        try container.encode(spaceID, forKey: .spaceID)
        try container.encode(isMinimized, forKey: .isMinimized)
        try container.encode(isHidden, forKey: .isHidden)
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case pid
        case ownerName
        case appPath
        case title
        case spaceID
        case isMinimized
        case isHidden
    }
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
    let legacyCompatibility: String
    let eventNotifications: Bool
    let eventCapabilities: [String]
    let maxPayloadBytes: Int
}
