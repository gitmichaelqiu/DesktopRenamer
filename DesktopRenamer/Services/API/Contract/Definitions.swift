import Foundation

enum SpaceAPIParameterKind: Equatable {
    case string
    case positiveInteger
    case boolean
    case direction
    case windowAction

    var description: String {
        switch self {
        case .string:
            return "string"
        case .positiveInteger:
            return "positive integer"
        case .boolean:
            return "Boolean"
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
    static let version = "1.1.0"
    static let jsonRPCVersion = "2.0"
    static let payloadKey = "payload"
    static let maxPayloadBytes = 1_048_576

    // The current bundle identifier is the preferred notification namespace.
    // The legacy namespace remains available so existing integrations continue
    // to work after the bundle-identifier migration.
    static let preferredAPIPrefix = "dev.mqiu.DesktopRenamer"
    static let legacyAPIPrefix = "com.michaelqiu.DesktopRenamer"

    static let rpcRequest = Notification.Name(preferredAPIPrefix + ".RPCRequest")
    static let rpcResponse = Notification.Name(preferredAPIPrefix + ".RPCResponse")
    static let rpcEvent = Notification.Name(preferredAPIPrefix + ".RPCEvent")
    static let legacyRPCRequest = Notification.Name(legacyAPIPrefix + ".RPCRequest")
    static let legacyRPCResponse = Notification.Name(legacyAPIPrefix + ".RPCResponse")
    static let legacyRPCEvent = Notification.Name(legacyAPIPrefix + ".RPCEvent")

    static let rpcRequestNotifications = [rpcRequest, legacyRPCRequest]
    static let rpcResponseNotifications = [rpcResponse, legacyRPCResponse]
    static let rpcEventNotifications = [rpcEvent, legacyRPCEvent]
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
            name: "toggleLockSpace",
            parameters: ["spaceID": .string],
            requiredParameters: ["spaceID"]
        ),
        SpaceAPIMethodDefinition(name: "restoreMovedWindows"),
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
                "targetSpaceID": .string,
                // Optional presentation metadata lets clients that already
                // enumerated the window avoid losing a true minimized/hidden
                // state when Accessibility is temporarily unavailable.
                "isMinimized": .boolean,
                "isHidden": .boolean
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
