import Foundation

enum SpaceAPIParameterKind: Equatable {
    case string
    case positiveInteger
    case direction
    case windowAction

    var description: String {
        switch self {
        case .string:
            return "string"
        case .positiveInteger:
            return "positive integer"
        case .direction:
            return "one of: up, down"
        case .windowAction:
            return "one of: " + DesktopRenamerAPIContract.windowActionNames.joined(separator: ", ")
        }
    }
}

enum SpaceAPIResultKind: Equatable {
    case operation
    case boolean
}

enum SpaceAPIJSONRPCCode {
    static let parseError = -32700
    static let invalidRequest = -32600
    static let methodNotFound = -32601
    static let invalidParams = -32602
    static let internalError = -32603
    static let apiDisabled = -32001
    static let appUnavailable = -32002
    static let operationFailed = -32004
    static let payloadTooLarge = -32006
}

struct SpaceAPIMethodDefinition: Equatable {
    let name: String
    let parameters: [String: SpaceAPIParameterKind]
    let requiredParameters: Set<String>
    let resultKind: SpaceAPIResultKind

    init(
        name: String,
        parameters: [String: SpaceAPIParameterKind] = [:],
        requiredParameters: Set<String> = [],
        resultKind: SpaceAPIResultKind = .operation
    ) {
        self.name = name
        self.parameters = parameters
        self.requiredParameters = requiredParameters
        self.resultKind = resultKind
    }
}

enum DesktopRenamerAPIContract {
    static let version = "1.0.0"
    static let jsonRPCVersion = "2.0"
    static let payloadKey = "payload"
    static let maxPayloadBytes = 1_048_576

    static let rpcRequest = Notification.Name("com.michaelqiu.DesktopRenamer.RPCRequest")
    static let rpcResponse = Notification.Name("com.michaelqiu.DesktopRenamer.RPCResponse")
    static let rpcEvent = Notification.Name("com.michaelqiu.DesktopRenamer.RPCEvent")
    static let windowActionNames = [
        "close", "minimize", "hide", "enterFullScreen", "exitFullScreen", "quit", "restore"
    ]

    static let methodDefinitions = [
        SpaceAPIMethodDefinition(name: "getAPIInfo"),
        SpaceAPIMethodDefinition(name: "getAPIVersion"),
        SpaceAPIMethodDefinition(name: "getSpaceSnapshot"),
        SpaceAPIMethodDefinition(name: "getCurrentSpaceName"),
        SpaceAPIMethodDefinition(name: "getCurrentSpaceID"),
        SpaceAPIMethodDefinition(name: "getAllSpaces"),
        SpaceAPIMethodDefinition(
            name: "switchToSpace",
            parameters: ["spaceID": .string],
            requiredParameters: ["spaceID"]
        ),
        SpaceAPIMethodDefinition(
            name: "renameCurrentSpace",
            parameters: ["name": .string],
            requiredParameters: ["name"]
        ),
        SpaceAPIMethodDefinition(
            name: "renameSpace",
            parameters: ["spaceID": .string, "name": .string],
            requiredParameters: ["spaceID", "name"]
        ),
        SpaceAPIMethodDefinition(
            name: "rearrangeSpace",
            parameters: ["spaceID": .string, "direction": .direction],
            requiredParameters: ["spaceID", "direction"]
        ),
        SpaceAPIMethodDefinition(name: "moveWindowNext"),
        SpaceAPIMethodDefinition(name: "moveWindowPrevious"),
        SpaceAPIMethodDefinition(
            name: "moveWindowToSpace",
            parameters: ["spaceID": .string],
            requiredParameters: ["spaceID"]
        ),
        SpaceAPIMethodDefinition(name: "reloadSpaceLabels"),
        SpaceAPIMethodDefinition(name: "toggleMenubar", resultKind: .boolean),
        SpaceAPIMethodDefinition(name: "toggleLauncher", resultKind: .boolean),
        SpaceAPIMethodDefinition(name: "toggleLabels", resultKind: .boolean),
        SpaceAPIMethodDefinition(name: "toggleActiveLabel", resultKind: .boolean),
        SpaceAPIMethodDefinition(name: "togglePreviewLabel", resultKind: .boolean),
        SpaceAPIMethodDefinition(name: "toggleDesktopVisibility", resultKind: .boolean),
        SpaceAPIMethodDefinition(name: "getWindows"),
        SpaceAPIMethodDefinition(
            name: "focusWindow",
            parameters: ["windowID": .positiveInteger, "pid": .positiveInteger],
            requiredParameters: ["windowID", "pid"]
        ),
        SpaceAPIMethodDefinition(
            name: "executeWindowAction",
            parameters: [
                "windowID": .positiveInteger,
                "pid": .positiveInteger,
                "action": .windowAction
            ],
            requiredParameters: ["windowID", "pid", "action"]
        ),
        SpaceAPIMethodDefinition(
            name: "moveSpecificWindow",
            parameters: [
                "windowID": .positiveInteger,
                "pid": .positiveInteger,
                "fromSpaceID": .string,
                "targetSpaceID": .string
            ],
            requiredParameters: ["windowID", "fromSpaceID", "targetSpaceID"]
        )
    ]

    static let supportedMethods = methodDefinitions.map(\.name)
    private static let methodDefinitionsByName = Dictionary(
        uniqueKeysWithValues: methodDefinitions.map { ($0.name, $0) }
    )

    static func definition(for method: String) -> SpaceAPIMethodDefinition? {
        methodDefinitionsByName[method]
    }
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

enum SpaceAPIContractError: LocalizedError, Equatable {
    case invalidJSON(String)
    case invalidRequest(String)
    case invalidParams(String)
    case invalidParamsWithData(String, SpaceAPIErrorData)
    case payloadTooLarge
    case unsupportedMethod(String)

    var errorDescription: String? {
        switch self {
        case .invalidJSON(let message), .invalidRequest(let message), .invalidParams(let message),
             .invalidParamsWithData(let message, _):
            return message
        case .payloadTooLarge:
            return "SpaceAPI payload exceeds the maximum size."
        case .unsupportedMethod(let method):
            return "Unsupported SpaceAPI method: \(method)"
        }
    }
}

enum SpaceAPIArgumentValidator {
    static func stringArguments(from params: SpaceAPIJSONValue?, method: String) throws -> [String: String] {
        guard let definition = DesktopRenamerAPIContract.definition(for: method) else {
            throw SpaceAPIContractError.unsupportedMethod(method)
        }

        guard let params else {
            return try validateRequiredParameters([:], definition: definition)
        }
        guard let object = params.objectValue else {
            throw invalidParameter(
                method: method,
                name: "params",
                expected: "object",
                message: "Parameters must be a JSON object."
            )
        }

        let allowedParameters = Set(definition.parameters.keys)
        if let unknownParameter = object.keys.sorted().first(where: { !allowedParameters.contains($0) }) {
            throw invalidParameter(
                method: method,
                name: unknownParameter,
                expected: "a supported parameter",
                message: "Parameter '\(unknownParameter)' is not supported for \(method)."
            )
        }

        let arguments = try object.reduce(into: [String: String]()) { result, item in
            guard let kind = definition.parameters[item.key] else { return }
            let expected = kind.description
            switch item.value {
            case .string(let value):
                if kind == .positiveInteger, !isPositiveInteger(value, parameter: item.key) {
                    throw invalidParameter(
                        method: method,
                        name: item.key,
                        expected: expected,
                        message: "Parameter '\(item.key)' must be a positive integer."
                    )
                }
                if kind == .direction {
                    let direction = value.lowercased()
                    guard direction == "up" || direction == "down" else {
                        throw invalidParameter(
                            method: method,
                            name: item.key,
                            expected: expected,
                            message: "Parameter '\(item.key)' must be either 'up' or 'down'."
                        )
                    }
                    result[item.key] = direction
                } else if kind == .windowAction {
                    guard DesktopRenamerAPIContract.windowActionNames.contains(value) else {
                        throw invalidParameter(
                            method: method,
                            name: item.key,
                            expected: expected,
                            message: "Parameter '\(item.key)' is not a supported window action."
                        )
                    }
                    result[item.key] = value
                } else {
                    result[item.key] = value
                }
            case .number(let value) where value.isFinite && value.rounded() == value && kind == .positiveInteger:
                guard let integer = Int(exactly: value) else {
                    throw invalidParameter(
                        method: method,
                        name: item.key,
                        expected: expected,
                        message: "Parameter '\(item.key)' is outside the supported integer range."
                    )
                }
                guard integer > 0 else {
                    throw invalidParameter(
                        method: method,
                        name: item.key,
                        expected: expected,
                        message: "Parameter '\(item.key)' must be a positive integer."
                    )
                }
                result[item.key] = String(integer)
            default:
                throw invalidParameter(
                    method: method,
                    name: item.key,
                    expected: expected,
                    message: "Parameter '\(item.key)' must be \(typeDescription(expected))."
                )
            }
        }

        return try validateRequiredParameters(arguments, definition: definition)
    }

    private static func validateRequiredParameters(
        _ arguments: [String: String],
        definition: SpaceAPIMethodDefinition
    ) throws -> [String: String] {
        for parameter in definition.requiredParameters.sorted() {
            guard let value = arguments[parameter], !value.isEmpty else {
                throw invalidParameter(
                    method: definition.name,
                    name: parameter,
                    expected: definition.parameters[parameter]?.description ?? "string",
                    message: "Missing required parameter '\(parameter)'."
                )
            }
        }
        return arguments
    }

    private static func isPositiveInteger(_ value: String, parameter: String) -> Bool {
        if parameter == "pid", let pid = Int32(value) {
            return pid > 0
        }
        if parameter == "windowID", let windowID = Int(value) {
            return windowID > 0
        }
        return Int(value).map { $0 > 0 } ?? false
    }

    private static func typeDescription(_ expected: String) -> String {
        expected.hasPrefix("one of:") ? expected : "a \(expected)"
    }

    private static func invalidParameter(
        method: String,
        name: String,
        expected: String,
        message: String
    ) -> SpaceAPIContractError {
        .invalidParamsWithData(
            message,
            SpaceAPIErrorData(parameter: name, expected: expected, command: method)
        )
    }
}

enum SpaceAPIJSONRPCCodec {
    static func encode(_ request: SpaceAPIJSONRPCRequest) throws -> String {
        guard request.jsonrpc == DesktopRenamerAPIContract.jsonRPCVersion,
              !request.id.isEmpty,
              !request.method.isEmpty, request.method.count <= 128 else {
            throw SpaceAPIContractError.invalidRequest("A JSON-RPC request requires a non-empty ID and method.")
        }
        if let params = request.params, params.objectValue == nil {
            throw SpaceAPIContractError.invalidParams("Named parameters must be a JSON object.")
        }
        return try encodeJSON(request)
    }

    static func decodeRequest(_ payload: String) throws -> SpaceAPIJSONRPCRequest {
        let data = try validatedPayloadData(payload)
        try requireJSONObject(data, message: "Request must be a JSON object.")

        let request: SpaceAPIJSONRPCRequest
        do {
            request = try JSONDecoder().decode(SpaceAPIJSONRPCRequest.self, from: data)
        } catch {
            throw SpaceAPIContractError.invalidRequest("Request is not a valid JSON-RPC 2.0 object.")
        }

        guard request.jsonrpc == DesktopRenamerAPIContract.jsonRPCVersion else {
            throw SpaceAPIContractError.invalidRequest("Only JSON-RPC 2.0 requests are supported.")
        }
        guard !request.id.isEmpty else {
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

    static func decodeResponse(_ payload: String) throws -> SpaceAPIJSONRPCResponse {
        let data = try validatedPayloadData(payload)
        try requireJSONObject(data, message: "Response must be a JSON object.")

        let response: SpaceAPIJSONRPCResponse
        do {
            response = try JSONDecoder().decode(SpaceAPIJSONRPCResponse.self, from: data)
        } catch {
            throw SpaceAPIContractError.invalidRequest("Response is not a valid JSON-RPC 2.0 object.")
        }

        guard response.jsonrpc == DesktopRenamerAPIContract.jsonRPCVersion else {
            throw SpaceAPIContractError.invalidRequest("Only JSON-RPC 2.0 responses are supported.")
        }
        return try validateResponse(response)
    }

    static func decodeEvent(_ payload: String) throws -> SpaceAPIJSONRPCEvent {
        let data = try validatedPayloadData(payload)
        try requireJSONObject(data, message: "Event must be a JSON object.")

        let event: SpaceAPIJSONRPCEvent
        do {
            event = try JSONDecoder().decode(SpaceAPIJSONRPCEvent.self, from: data)
        } catch {
            throw SpaceAPIContractError.invalidRequest("Event is not a valid JSON-RPC 2.0 notification.")
        }

        if let object = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) as? [String: Any],
           object["id"] != nil {
            throw SpaceAPIContractError.invalidRequest("JSON-RPC events must not contain an ID.")
        }
        guard event.jsonrpc == DesktopRenamerAPIContract.jsonRPCVersion else {
            throw SpaceAPIContractError.invalidRequest("Only JSON-RPC 2.0 events are supported.")
        }
        guard !event.method.isEmpty, event.method.count <= 128 else {
            throw SpaceAPIContractError.invalidRequest("A non-empty event method of at most 128 characters is required.")
        }
        guard event.params.objectValue != nil else {
            throw SpaceAPIContractError.invalidParams("Event parameters must be a JSON object.")
        }
        return event
    }

    static func encode(_ response: SpaceAPIJSONRPCResponse) throws -> String {
        guard response.jsonrpc == DesktopRenamerAPIContract.jsonRPCVersion else {
            throw SpaceAPIContractError.invalidRequest("Only JSON-RPC 2.0 responses are supported.")
        }
        return try encodeJSON(try validateResponse(response))
    }

    static func encode(_ event: SpaceAPIJSONRPCEvent) throws -> String {
        guard event.jsonrpc == DesktopRenamerAPIContract.jsonRPCVersion,
              !event.method.isEmpty, event.method.count <= 128,
              event.params.objectValue != nil else {
            throw SpaceAPIContractError.invalidRequest("Events require JSON-RPC 2.0, a method, and object parameters.")
        }
        return try encodeJSON(event)
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

    private static func encodeJSON<T: Encodable>(_ value: T) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(value)
        guard data.count <= DesktopRenamerAPIContract.maxPayloadBytes else {
            throw SpaceAPIContractError.payloadTooLarge
        }
        return String(decoding: data, as: UTF8.self)
    }

    private static func validatedPayloadData(_ payload: String) throws -> Data {
        guard payload.utf8.count <= DesktopRenamerAPIContract.maxPayloadBytes else {
            throw SpaceAPIContractError.payloadTooLarge
        }
        guard let data = payload.data(using: .utf8) else {
            throw SpaceAPIContractError.invalidJSON("Payload is not valid UTF-8.")
        }
        do {
            _ = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
        } catch {
            throw SpaceAPIContractError.invalidJSON("Payload is not valid JSON.")
        }
        return data
    }

    private static func requireJSONObject(_ data: Data, message: String) throws {
        guard let object = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]),
              object is [String: Any] else {
            throw SpaceAPIContractError.invalidRequest(message)
        }
    }

    private static func validateResponse(_ response: SpaceAPIJSONRPCResponse) throws -> SpaceAPIJSONRPCResponse {
        if let id = response.id, id.isEmpty {
            throw SpaceAPIContractError.invalidRequest("A response ID must be a non-empty string when present.")
        }
        if response.id == nil, response.result != nil {
            throw SpaceAPIContractError.invalidRequest("A successful response requires a non-null request ID.")
        }
        guard (response.result == nil) != (response.error == nil) else {
            throw SpaceAPIContractError.invalidRequest("A response must contain exactly one of result or error.")
        }
        if let error = response.error, error.message.isEmpty {
            throw SpaceAPIContractError.invalidRequest("A JSON-RPC error requires a message.")
        }
        return response
    }

}

extension SpaceAPIContractError {
    var jsonRPCCode: Int {
        switch self {
        case .invalidJSON:
            return SpaceAPIJSONRPCCode.parseError
        case .invalidRequest:
            return SpaceAPIJSONRPCCode.invalidRequest
        case .invalidParams:
            return SpaceAPIJSONRPCCode.invalidParams
        case .invalidParamsWithData:
            return SpaceAPIJSONRPCCode.invalidParams
        case .unsupportedMethod:
            return SpaceAPIJSONRPCCode.methodNotFound
        case .payloadTooLarge:
            return SpaceAPIJSONRPCCode.payloadTooLarge
        }
    }

    var jsonRPCData: SpaceAPIErrorData? {
        jsonRPCData(command: nil)
    }

    func jsonRPCData(command: String?) -> SpaceAPIErrorData? {
        switch self {
        case .invalidParamsWithData(_, let data):
            guard data.command == nil, let command else { return data }
            return SpaceAPIErrorData(
                parameter: data.parameter,
                expected: data.expected,
                command: command
            )
        case .invalidParams:
            return command.map { SpaceAPIErrorData(command: $0) }
        case .unsupportedMethod(let method):
            return SpaceAPIErrorData(command: method)
        default:
            return nil
        }
    }
}
