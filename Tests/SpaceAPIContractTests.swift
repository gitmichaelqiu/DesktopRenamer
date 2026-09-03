import Foundation

@main
struct SpaceAPIContractTests {
    static func main() throws {
        try testMethodDefinitions()
        try testParameterValidation()
        try testRequestRoundTripAndValidation()
        try testResponseRoundTripAndUnknownFields()
        try testNullableFieldBackwardCompatibility()
        try testEventRoundTrip()
        try testLegacyFixtures()
        print("SpaceAPI contract tests passed")
    }

    private static func testMethodDefinitions() throws {
        let definitions = DesktopRenamerAPIContract.methodDefinitions
        let names = definitions.map(\.name)
        check(Set(names).count == names.count, "method names are unique")
        check(names == DesktopRenamerAPIContract.supportedMethods, "supported methods follow definitions")

        for definition in definitions {
            check(
                definition.requiredParameters.isSubset(of: Set(definition.parameters.keys)),
                "required parameters are declared for \(definition.name)"
            )
        }

        let booleanMethods = definitions.filter { $0.resultKind == .boolean }.map(\.name)
        check(
            booleanMethods == [
                "toggleMenubar",
                "toggleLauncher",
                "toggleLabels",
                "toggleActiveLabel",
                "togglePreviewLabel",
                "toggleDesktopVisibility"
            ],
            "toggle methods expose Boolean results"
        )
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

        expectError(SpaceAPIJSONRPCCode.parseError, payload: "{", operation: SpaceAPIJSONRPCCodec.decodeRequest)
        expectError(SpaceAPIJSONRPCCode.invalidRequest, payload: "[]", operation: SpaceAPIJSONRPCCodec.decodeRequest)
        expectError(
            SpaceAPIJSONRPCCode.invalidRequest,
            payload: "{\"jsonrpc\":\"1.0\",\"id\":\"1\",\"method\":\"getAPIInfo\"}",
            operation: SpaceAPIJSONRPCCodec.decodeRequest
        )
        expectError(
            SpaceAPIJSONRPCCode.invalidRequest,
            payload: "{\"jsonrpc\":\"2.0\",\"method\":\"getAPIInfo\"}",
            operation: SpaceAPIJSONRPCCodec.decodeRequest
        )
        expectError(
            SpaceAPIJSONRPCCode.invalidParams,
            payload: "{\"jsonrpc\":\"2.0\",\"id\":\"1\",\"method\":\"getAPIInfo\",\"params\":[]}",
            operation: SpaceAPIJSONRPCCodec.decodeRequest
        )
        expectError(
            SpaceAPIJSONRPCCode.invalidParams,
            payload: "{\"jsonrpc\":\"2.0\",\"id\":\"1\",\"method\":\"getAPIInfo\",\"params\":null}",
            operation: SpaceAPIJSONRPCCodec.decodeRequest
        )
        expectError(
            SpaceAPIJSONRPCCode.payloadTooLarge,
            payload: String(repeating: "x", count: DesktopRenamerAPIContract.maxPayloadBytes + 1),
            operation: SpaceAPIJSONRPCCodec.decodeRequest
        )

        let oversizedRequest = SpaceAPIJSONRPCRequest(
            id: "large-request",
            method: "renameCurrentSpace",
            params: ["name": .string(String(repeating: "x", count: DesktopRenamerAPIContract.maxPayloadBytes))]
        )
        do {
            _ = try SpaceAPIJSONRPCCodec.encode(oversizedRequest)
            fail("expected oversized request to be rejected")
        } catch let error as SpaceAPIContractError {
            check(error.jsonRPCCode == SpaceAPIJSONRPCCode.payloadTooLarge, "encoded requests enforce payload limit")
        }
    }

    private static func testParameterValidation() throws {
        let normalized = try SpaceAPIArgumentValidator.stringArguments(
            from: .object([
                "spaceID": .string("space-4"),
                "direction": .string("UP")
            ]),
            method: "rearrangeSpace"
        )
        check(normalized["direction"] == "up", "direction parameters are normalized")

        let numeric = try SpaceAPIArgumentValidator.stringArguments(
            from: .object([
                "windowID": .number(123),
                "pid": .number(456),
                "fromSpaceID": .string("4"),
                "targetSpaceID": .string("5")
            ]),
            method: "moveSpecificWindow"
        )
        check(numeric["windowID"] == "123" && numeric["pid"] == "456", "numeric IDs are normalized")

        let withoutOptionalPID = try SpaceAPIArgumentValidator.stringArguments(
            from: .object([
                "windowID": .string("123"),
                "fromSpaceID": .string("4"),
                "targetSpaceID": .string("5")
            ]),
            method: "moveSpecificWindow"
        )
        check(withoutOptionalPID["pid"] == nil, "optional process IDs can be omitted")

        expectParameterError(
            parameter: "spaceID",
            params: .object([:]),
            method: "switchToSpace"
        )
        expectParameterError(
            parameter: "unexpected",
            params: .object(["unexpected": .string("value")]),
            method: "getAPIInfo"
        )
        expectParameterError(
            parameter: "direction",
            params: .object(["spaceID": .string("4"), "direction": .string("sideways")]),
            method: "rearrangeSpace"
        )
        expectParameterError(
            parameter: "pid",
            params: .object(["windowID": .number(123), "pid": .number(0)]),
            method: "focusWindow"
        )
        expectParameterError(
            parameter: "params",
            params: .array([]),
            method: "getAPIInfo"
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

        let encodedResponse = try checkJSONObject(
            JSONSerialization.jsonObject(with: Data(payload.utf8), options: [.fragmentsAllowed])
        )
        let encodedResult = try checkJSONObject(encodedResponse["result"])
        let encodedSnapshot = try checkJSONObject(encodedResult["snapshot"])
        let encodedSpace = try checkJSONObject(try checkArray(encodedSnapshot["spaces"]).first)
        check(encodedSpace["appName"] is NSNull, "nullable space appName is encoded as null")
        check(encodedSpace["appPath"] is NSNull, "nullable space appPath is encoded as null")

        let encodedWindows = try checkArray(encodedResult["windows"])
        let encodedWindow = try checkJSONObject(encodedWindows.first)
        check(encodedWindow["appPath"] is NSNull, "nullable window appPath is encoded as null")
        check(encodedWindow["title"] is NSNull, "nullable window title is encoded as null")

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
            code: SpaceAPIJSONRPCCode.invalidParams,
            message: "Invalid parameter.",
            data: SpaceAPIErrorData(parameter: "spaceID", expected: "string", command: "switchToSpace")
        )
        let errorPayload = try SpaceAPIJSONRPCCodec.encode(error)
        let decodedError = try SpaceAPIJSONRPCCodec.decodeResponse(errorPayload)
        check(decodedError.error?.code == SpaceAPIJSONRPCCode.invalidParams, "error code round trip")
        let errorData = try decodedError.error?.data?.decode(SpaceAPIErrorData.self)
        check(errorData?.parameter == "spaceID", "error metadata round trip")

        let nullResult = try SpaceAPIJSONRPCCodec.decodeResponse(
            "{\"jsonrpc\":\"2.0\",\"id\":\"null-result\",\"result\":null}"
        )
        check(nullResult.result == .null, "nullable JSON-RPC result is preserved")

        let nullIDError = SpaceAPIJSONRPCCodec.errorResponse(
            id: nil,
            code: SpaceAPIJSONRPCCode.invalidRequest,
            message: "Malformed request."
        )
        let nullIDPayload = try SpaceAPIJSONRPCCodec.encode(nullIDError)
        let nullIDObject = try checkJSONObject(
            JSONSerialization.jsonObject(with: Data(nullIDPayload.utf8), options: [.fragmentsAllowed])
        )
        check(nullIDObject["id"] is NSNull, "unknown response IDs are encoded as explicit null")
        check(try SpaceAPIJSONRPCCodec.decodeResponse(nullIDPayload).id == nil, "null response IDs decode as nil")

        expectError(
            SpaceAPIJSONRPCCode.invalidRequest,
            payload: "{\"jsonrpc\":\"2.0\",\"id\":\"1\",\"result\":{},\"error\":{\"code\":-1,\"message\":\"failed\"}}",
            operation: SpaceAPIJSONRPCCodec.decodeResponse
        )
        expectError(
            SpaceAPIJSONRPCCode.invalidRequest,
            payload: "{\"jsonrpc\":\"2.0\",\"id\":\"1\"}",
            operation: SpaceAPIJSONRPCCodec.decodeResponse
        )
        expectError(
            SpaceAPIJSONRPCCode.invalidRequest,
            payload: "{\"jsonrpc\":\"2.0\",\"result\":{}}",
            operation: SpaceAPIJSONRPCCodec.decodeResponse
        )
        expectError(
            SpaceAPIJSONRPCCode.invalidRequest,
            payload: "{\"jsonrpc\":\"2.0\",\"id\":null,\"result\":{}}",
            operation: SpaceAPIJSONRPCCodec.decodeResponse
        )

        let successfulResponseWithNullID = SpaceAPIJSONRPCResponse(id: nil, result: .object([:]))
        do {
            _ = try SpaceAPIJSONRPCCodec.encode(successfulResponseWithNullID)
            fail("expected successful response with null ID to be rejected")
        } catch let error as SpaceAPIContractError {
            check(error.jsonRPCCode == SpaceAPIJSONRPCCode.invalidRequest, "null result ID uses invalid request code")
        }

        let oversizedResponse = SpaceAPIJSONRPCResponse(
            id: "large-response",
            result: .string(String(repeating: "x", count: DesktopRenamerAPIContract.maxPayloadBytes))
        )
        do {
            _ = try SpaceAPIJSONRPCCodec.encode(oversizedResponse)
            fail("expected oversized response to be rejected")
        } catch let error as SpaceAPIContractError {
            check(error.jsonRPCCode == SpaceAPIJSONRPCCode.payloadTooLarge, "encoded responses enforce payload limit")
        }
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
            SpaceAPIJSONRPCCode.invalidParams,
            payload: "{\"jsonrpc\":\"2.0\",\"method\":\"stateChanged\",\"params\":[]}",
            operation: SpaceAPIJSONRPCCodec.decodeEvent
        )
        expectError(
            SpaceAPIJSONRPCCode.invalidRequest,
            payload: "{\"jsonrpc\":\"2.0\",\"id\":\"event-1\",\"method\":\"stateChanged\",\"params\":{}}",
            operation: SpaceAPIJSONRPCCodec.decodeEvent
        )
        expectError(
            SpaceAPIJSONRPCCode.invalidRequest,
            payload: "{\"jsonrpc\":\"2.0\",\"method\":\"\(String(repeating: "x", count: 129))\",\"params\":{}}",
            operation: SpaceAPIJSONRPCCodec.decodeEvent
        )
    }

    private static func testNullableFieldBackwardCompatibility() throws {
        let spacePayload = """
        {
          "id": "space-1",
          "name": "Writing",
          "displayID": "display-1",
          "displayName": "Built-in Display",
          "number": 1,
          "isFullscreen": false
        }
        """
        let space = try JSONDecoder().decode(SpaceAPISpace.self, from: Data(spacePayload.utf8))
        check(space.appName == nil && space.appPath == nil && space.globalShortcutNumber == nil,
              "missing nullable space fields decode as nil")

        let windowPayload = """
        {
          "id": 123,
          "pid": 456,
          "ownerName": "Example",
          "spaceID": "space-1",
          "isMinimized": false,
          "isHidden": false
        }
        """
        let window = try JSONDecoder().decode(SpaceAPIWindow.self, from: Data(windowPayload.utf8))
        check(window.appPath == nil && window.title == nil, "missing nullable window fields decode as nil")
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

    private static func expectParameterError(
        parameter: String,
        params: SpaceAPIJSONValue?,
        method: String
    ) {
        do {
            _ = try SpaceAPIArgumentValidator.stringArguments(from: params, method: method)
            fail("expected parameter error for \(parameter)")
        } catch let error as SpaceAPIContractError {
            check(error.jsonRPCCode == SpaceAPIJSONRPCCode.invalidParams, "expected invalid parameter code")
            guard case .invalidParamsWithData(_, let data) = error else {
                fail("expected parameter metadata for \(parameter)")
            }
            check(
                data.parameter == parameter && data.command == method,
                "parameter metadata for \(parameter): \(String(describing: data.parameter)) / \(String(describing: data.command))"
            )
        } catch {
            fail("unexpected parameter error: \(error)")
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

    private static func checkArray(_ value: Any?) throws -> [Any] {
        guard let array = value as? [Any] else { throw TestFailure("expected JSON array") }
        return array
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
