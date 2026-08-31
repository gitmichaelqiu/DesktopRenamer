import Foundation

@main
struct SpaceAPIContractTests {
    static func main() throws {
        try testRequestRoundTripAndValidation()
        try testResponseRoundTripAndUnknownFields()
        try testEventRoundTrip()
        try testLegacyFixtures()
        print("SpaceAPI contract tests passed")
    }

    private static func testRequestRoundTripAndValidation() throws {
        let request = SpaceAPIJSONRPCRequest(
            id: "request-1",
            method: "renameSpace",
            params: [
                "spaceID": .string("space|~\"\n测试"),
                "name": .string("名称\nwith delimiters | ~")
            ]
        )
        let payload = try SpaceAPIJSONRPCCodec.encode(request)
        check(try SpaceAPIJSONRPCCodec.decodeRequest(payload) == request, "request round trip")

        expectError(-32700, payload: "{", operation: SpaceAPIJSONRPCCodec.decodeRequest)
        expectError(-32600, payload: "[]", operation: SpaceAPIJSONRPCCodec.decodeRequest)
        expectError(
            -32600,
            payload: "{\"jsonrpc\":\"1.0\",\"id\":\"1\",\"method\":\"getAPIInfo\"}",
            operation: SpaceAPIJSONRPCCodec.decodeRequest
        )
        expectError(
            -32600,
            payload: "{\"jsonrpc\":\"2.0\",\"method\":\"getAPIInfo\"}",
            operation: SpaceAPIJSONRPCCodec.decodeRequest
        )
        expectError(
            -32602,
            payload: "{\"jsonrpc\":\"2.0\",\"id\":\"1\",\"method\":\"getAPIInfo\",\"params\":[]}",
            operation: SpaceAPIJSONRPCCodec.decodeRequest
        )
        expectError(
            -32602,
            payload: "{\"jsonrpc\":\"2.0\",\"id\":\"1\",\"method\":\"getAPIInfo\",\"params\":null}",
            operation: SpaceAPIJSONRPCCodec.decodeRequest
        )
        expectError(
            -32006,
            payload: String(repeating: "x", count: DesktopRenamerAPIContract.maxPayloadBytes + 1),
            operation: SpaceAPIJSONRPCCodec.decodeRequest
        )
    }

    private static func testResponseRoundTripAndUnknownFields() throws {
        let space = SpaceAPISpace(
            id: "space|~\"\n测试",
            name: "名称\nwith delimiters | ~",
            displayID: "display-1",
            displayName: "主显示器",
            number: 4,
            isFullscreen: false,
            appName: nil,
            appPath: nil,
            globalShortcutNumber: 4
        )
        let window = SpaceAPIWindow(
            id: 123,
            pid: 456,
            ownerName: "Example | Owner",
            appPath: nil,
            title: nil,
            spaceID: space.id,
            isMinimized: false,
            isHidden: true
        )
        let snapshot = SpaceAPISnapshot(
            apiVersion: DesktopRenamerAPIContract.version,
            revision: 42,
            timestamp: "2026-08-31T00:00:00Z",
            currentSpaceIDs: [space.id],
            currentSpaceName: space.name,
            spaces: [space]
        )
        let response = SpaceAPIJSONRPCResponse(
            id: "request-2",
            result: .object([
                "snapshot": try SpaceAPIJSONValue.from(snapshot),
                "windows": try SpaceAPIJSONValue.from([window])
            ])
        )
        let payload = try SpaceAPIJSONRPCCodec.encode(response)
        let decoded = try SpaceAPIJSONRPCCodec.decodeResponse(payload)
        let decodedObject = try checkValue(decoded.result, "response result")
        let decodedSnapshot = try checkValue(decodedObject.objectValue?["snapshot"], "snapshot result")
            .decode(SpaceAPISnapshot.self)
        check(decodedSnapshot == snapshot, "snapshot with nullable and delimiter fields")

        let payloadObject = try JSONSerialization.jsonObject(with: Data(payload.utf8), options: [.fragmentsAllowed])
        var jsonObject = try checkJSONObject(payloadObject)
        var resultObject = try checkJSONObject(jsonObject["result"])
        resultObject["futureField"] = ["ignored": true]
        jsonObject["result"] = resultObject
        let unknownFieldPayload = try jsonString(jsonObject)
        let unknownFieldResponse = try SpaceAPIJSONRPCCodec.decodeResponse(unknownFieldPayload)
        let unknownResult = try checkValue(unknownFieldResponse.result, "unknown-field result")
        let compatibleSnapshot = try unknownResult.objectValue?["snapshot"]?.decode(SpaceAPISnapshot.self)
        check(compatibleSnapshot == snapshot, "unknown result fields are ignored")

        let error = SpaceAPIJSONRPCCodec.errorResponse(
            id: "request-3",
            code: -32602,
            message: "Invalid parameter.",
            data: SpaceAPIErrorData(parameter: "spaceID", expected: "string", command: "switchToSpace")
        )
        let errorPayload = try SpaceAPIJSONRPCCodec.encode(error)
        let decodedError = try SpaceAPIJSONRPCCodec.decodeResponse(errorPayload)
        check(decodedError.error?.code == -32602, "error code round trip")
        let errorData = try decodedError.error?.data?.decode(SpaceAPIErrorData.self)
        check(errorData?.parameter == "spaceID", "error metadata round trip")

        let nullResult = try SpaceAPIJSONRPCCodec.decodeResponse(
            "{\"jsonrpc\":\"2.0\",\"id\":\"null-result\",\"result\":null}"
        )
        check(nullResult.result == .null, "nullable JSON-RPC result is preserved")

        expectError(
            -32600,
            payload: "{\"jsonrpc\":\"2.0\",\"id\":\"1\",\"result\":{},\"error\":{\"code\":-1,\"message\":\"failed\"}}",
            operation: SpaceAPIJSONRPCCodec.decodeResponse
        )
        expectError(
            -32600,
            payload: "{\"jsonrpc\":\"2.0\",\"id\":\"1\"}",
            operation: SpaceAPIJSONRPCCodec.decodeResponse
        )
    }

    private static func testEventRoundTrip() throws {
        let event = SpaceAPIJSONRPCEvent(
            method: "stateChanged",
            params: .object([
                "reason": .string("spaceListChanged"),
                "revision": .number(9)
            ])
        )
        let payload = try SpaceAPIJSONRPCCodec.encode(event)
        check(try SpaceAPIJSONRPCCodec.decodeEvent(payload) == event, "event round trip")

        expectError(
            -32602,
            payload: "{\"jsonrpc\":\"2.0\",\"method\":\"stateChanged\",\"params\":[]}",
            operation: SpaceAPIJSONRPCCodec.decodeEvent
        )
    }

    private static func testLegacyFixtures() throws {
        let spaceLine = SpaceAPILegacyFormatter.spaceLine(
            id: "4",
            name: "Name|with~delimiters",
            displayName: "Display",
            number: 4,
            isFullscreen: false,
            appPath: "/Applications/Test.app"
        )
        check(
            spaceLine == ">4~Name|with~delimiters~Display~4~0~/Applications/Test.app\n",
            "legacy space fixture"
        )

        let windowLine = SpaceAPILegacyFormatter.windowLine(
            id: 123,
            pid: 456,
            ownerName: "Owner|Name",
            appPath: "/Applications/Test.app",
            title: "Title~with\ntext",
            isMinimized: true,
            isHidden: false
        )
        check(
            windowLine == "  123|456|Owner|Name|/Applications/Test.app|Title~with\ntext|1|0\n",
            "legacy window fixture"
        )
    }

    private static func expectError<T>(
        _ code: Int,
        payload: String,
        operation: (String) throws -> T
    ) {
        do {
            _ = try operation(payload)
            fail("expected error \(code)")
        } catch let error as SpaceAPIContractError {
            check(error.jsonRPCCode == code, "expected error \(code), got \(error.jsonRPCCode)")
        } catch {
            fail("unexpected error: \(error)")
        }
    }

    private static func checkValue(_ value: SpaceAPIJSONValue?, _ message: String) throws -> SpaceAPIJSONValue {
        guard let value else { throw TestFailure(message) }
        return value
    }

    private static func checkJSONObject(_ value: Any?) throws -> [String: Any] {
        guard let object = value as? [String: Any] else { throw TestFailure("expected JSON object") }
        return object
    }

    private static func jsonString(_ object: [String: Any]) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: object, options: [])
        return String(decoding: data, as: UTF8.self)
    }

    private static func check(_ condition: Bool, _ message: String) {
        if !condition { fail(message) }
    }

    private static func fail(_ message: String) -> Never {
        fatalError(message)
    }

    private struct TestFailure: Error {
        let message: String

        init(_ message: String) {
            self.message = message
        }
    }
}
