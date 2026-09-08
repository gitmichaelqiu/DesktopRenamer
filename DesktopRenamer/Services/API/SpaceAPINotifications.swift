import Foundation
import AppKit
import Combine

extension SpaceAPI {

    @objc nonisolated func handleActiveSpaceRequest() {
        Task { @MainActor [weak self] in
            guard let self else { return }
            DiagnosticEventLog.shared.record(subsystem: "SpaceAPI", level: "info", "handleActiveSpaceRequest")
            self.broadcastCurrentSpace()
        }
    }
    @objc nonisolated func handleSpaceListRequest() {
        Task { @MainActor [weak self] in
            guard let self else { return }
            DiagnosticEventLog.shared.record(subsystem: "SpaceAPI", level: "info", "handleSpaceListRequest")
            self.broadcastSpaceList()
        }
    }

    @objc nonisolated func handleAPIVersionRequest() {
        Task { @MainActor [weak self] in
            guard let self else { return }
            DiagnosticEventLog.shared.record(subsystem: "SpaceAPI", level: "info", "handleAPIVersionRequest")
            self.broadcastAPIVersion()
        }
    }

    @objc nonisolated func handleCommandRequest(_ notification: Notification) {
        let userInfo = notification.userInfo ?? [:]
        let requestID = (userInfo["requestID"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? UUID().uuidString
        let command = userInfo["command"] as? String ?? ""
        var arguments: [String: String] = [:]
        var argumentError: String?
        if let argumentsJSON = userInfo["argumentsJSON"] as? String {
            if let data = argumentsJSON.data(using: .utf8),
               let decoded = try? JSONDecoder().decode([String: String].self, from: data) {
                arguments = decoded
            } else {
                argumentError = "Arguments must be a JSON object containing only string values."
            }
        } else if let rawArguments = userInfo["arguments"] {
            if let decoded = rawArguments as? [String: String] {
                arguments = decoded
            } else {
                argumentError = "Arguments must be a dictionary containing only string values."
            }
        }

        Task { @MainActor [weak self] in
            guard let self else { return }
            guard SpaceManager.isAPIEnabled else {
                self.postCommandResult(requestID: requestID, error: SpaceAPIError.apiDisabled.localizedDescription)
                return
            }
            if let argumentError {
                self.postCommandResult(requestID: requestID, error: argumentError)
                return
            }
            do {
                let validatedArguments = try SpaceAPIArgumentValidator.stringArguments(
                    from: .object(arguments.mapValues { .string($0) }),
                    method: command
                )
                let result = try await self.executeCommand(command, arguments: validatedArguments)
                self.postCommandResult(requestID: requestID, result: result)
            } catch {
                self.postCommandResult(requestID: requestID, error: error.localizedDescription)
            }
        }
    }

    @objc nonisolated func handleRPCRequest(_ notification: Notification) {
        let payload = notification.userInfo?[DesktopRenamerAPIContract.payloadKey] as? String
        Task { @MainActor [weak self] in
            guard let self else { return }
            await self.processRPCRequest(payload)
        }
    }

    private func processRPCRequest(_ payload: String?) async {
        guard let payload else {
            postRPCResponse(SpaceAPIJSONRPCCodec.errorResponse(
                id: nil,
                code: SpaceAPIJSONRPCCode.invalidRequest,
                message: "A JSON-RPC payload is required."
            ))
            return
        }

        let recoverableRequestID = Self.recoverableRequestID(from: payload)

        let request: SpaceAPIJSONRPCRequest
        do {
            request = try SpaceAPIJSONRPCCodec.decodeRequest(payload)
        } catch let error as SpaceAPIContractError {
            postRPCResponse(SpaceAPIJSONRPCCodec.errorResponse(
                id: recoverableRequestID,
                code: error.jsonRPCCode,
                message: error.localizedDescription,
                data: error.jsonRPCData
            ))
            DiagnosticEventLog.shared.record(
                subsystem: "SpaceAPI",
                level: "warning",
                "Rejected structured request: \(error.localizedDescription)"
            )
            return
        } catch {
            postRPCResponse(SpaceAPIJSONRPCCodec.errorResponse(
                id: recoverableRequestID,
                code: SpaceAPIJSONRPCCode.invalidRequest,
                message: "Request could not be validated."
            ))
            return
        }

        guard SpaceManager.isAPIEnabled else {
            postRPCResponse(SpaceAPIJSONRPCCodec.errorResponse(
                id: request.id,
                code: SpaceAPIError.apiDisabled.jsonRPCCode,
                message: SpaceAPIError.apiDisabled.localizedDescription
            ))
            return
        }

        do {
            let result = try await executeRPCMethod(request)
            postRPCResponse(SpaceAPIJSONRPCResponse(id: request.id, result: result))
            DiagnosticEventLog.shared.record(
                subsystem: "SpaceAPI",
                level: "info",
                "Completed structured request method=\(request.method) id=\(request.id)"
            )
        } catch let error as SpaceAPIContractError {
            postRPCResponse(SpaceAPIJSONRPCCodec.errorResponse(
                id: request.id,
                code: error.jsonRPCCode,
                message: error.localizedDescription,
                data: error.jsonRPCData(command: request.method)
            ))
        } catch let error as SpaceAPIError {
            postRPCResponse(SpaceAPIJSONRPCCodec.errorResponse(
                id: request.id,
                code: error.jsonRPCCode,
                message: error.localizedDescription,
                data: error.jsonRPCData(command: request.method)
            ))
        } catch {
            postRPCResponse(SpaceAPIJSONRPCCodec.errorResponse(
                id: request.id,
                code: SpaceAPIJSONRPCCode.internalError,
                message: "DesktopRenamer could not complete the request."
            ))
        }
    }

    private static func recoverableRequestID(from payload: String) -> String? {
        guard payload.utf8.count <= DesktopRenamerAPIContract.maxPayloadBytes,
              let data = payload.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]),
              let dictionary = object as? [String: Any],
              let id = dictionary["id"] as? String,
              !id.isEmpty else {
            return nil
        }
        return id
    }
}

enum SpaceAPIError: LocalizedError {
    case apiDisabled
    case appUnavailable
    case invalidArgument(String)
    case operationFailed(String)
    case unsupportedCommand(String)

    var errorDescription: String? {
        switch self {
        case .apiDisabled: return "SpaceAPI Disabled"
        case .appUnavailable: return "DesktopRenamer is not ready."
        case .invalidArgument(let message), .operationFailed(let message): return message
        case .unsupportedCommand(let command): return "Unsupported SpaceAPI command: \(command)"
        }
    }
}

private extension SpaceAPIError {
    var jsonRPCCode: Int {
        switch self {
        case .apiDisabled:
            return SpaceAPIJSONRPCCode.apiDisabled
        case .appUnavailable:
            return SpaceAPIJSONRPCCode.appUnavailable
        case .invalidArgument:
            return SpaceAPIJSONRPCCode.invalidParams
        case .operationFailed:
            return SpaceAPIJSONRPCCode.operationFailed
        case .unsupportedCommand:
            return SpaceAPIJSONRPCCode.methodNotFound
        }
    }

    func jsonRPCData(command: String? = nil) -> SpaceAPIErrorData? {
        switch self {
        case .invalidArgument:
            return SpaceAPIErrorData(expected: "valid command parameters", command: command)
        case .operationFailed:
            return command.map { SpaceAPIErrorData(command: $0) }
        case .unsupportedCommand(let command):
            return SpaceAPIErrorData(command: command)
        default:
            return nil
        }
    }
}
