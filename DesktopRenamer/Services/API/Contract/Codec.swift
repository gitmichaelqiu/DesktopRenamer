import Foundation

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
