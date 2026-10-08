import Foundation

enum SpaceAPISocketFrameError: Error, Equatable {
    case emptyPayload
    case payloadTooLarge
}

enum SpaceAPISocketFraming {
    static let headerLength = 4

    static func encode(_ payload: Data, maximumPayloadBytes: Int) throws -> Data {
        guard !payload.isEmpty else { throw SpaceAPISocketFrameError.emptyPayload }
        guard payload.count <= maximumPayloadBytes, payload.count <= Int(UInt32.max) else {
            throw SpaceAPISocketFrameError.payloadTooLarge
        }

        let length = UInt32(payload.count)
        var frame = Data([
            UInt8((length >> 24) & 0xff),
            UInt8((length >> 16) & 0xff),
            UInt8((length >> 8) & 0xff),
            UInt8(length & 0xff)
        ])
        frame.append(payload)
        return frame
    }

    static func extractFrames(
        from buffer: inout Data,
        maximumPayloadBytes: Int
    ) throws -> [Data] {
        var frames: [Data] = []

        while buffer.count >= headerLength {
            let length = (UInt32(buffer[buffer.startIndex]) << 24)
                | (UInt32(buffer[buffer.startIndex + 1]) << 16)
                | (UInt32(buffer[buffer.startIndex + 2]) << 8)
                | UInt32(buffer[buffer.startIndex + 3])

            guard length > 0 else { throw SpaceAPISocketFrameError.emptyPayload }
            guard length <= maximumPayloadBytes else { throw SpaceAPISocketFrameError.payloadTooLarge }

            let frameLength = headerLength + Int(length)
            guard buffer.count >= frameLength else { break }

            frames.append(buffer.subdata(in: headerLength..<frameLength))
            buffer.removeSubrange(0..<frameLength)
        }

        return frames
    }
}
