import Foundation

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
