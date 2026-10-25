import Darwin
import Foundation

enum SpaceAPISocketFrameError: Error, Equatable {
    case emptyPayload
    case payloadTooLarge
}

enum SpaceAPISocketFraming {
    static let headerLength = 4

    static func readExactly(_ count: Int, from descriptor: Int32, deadline: DispatchTime? = nil) -> Data? {
        guard count >= 0 else { return nil }

        var data = Data(count: count)
        var offset = 0

        while offset < count {
            if let deadline {
                let now = DispatchTime.now().uptimeNanoseconds
                guard now < deadline.uptimeNanoseconds else { return nil }

                let remainingNanoseconds = deadline.uptimeNanoseconds - now
                let remainingMilliseconds = min(
                    (remainingNanoseconds + 999_999) / 1_000_000,
                    UInt64(Int32.max)
                )
                var pollDescriptor = pollfd()
                pollDescriptor.fd = descriptor
                pollDescriptor.events = Int16(POLLIN)

                let pollResult = Darwin.poll(&pollDescriptor, 1, Int32(remainingMilliseconds))
                if pollResult < 0 {
                    if errno == EINTR { continue }
                    return nil
                }
                guard pollResult > 0,
                      pollDescriptor.revents & Int16(POLLIN) != 0 else {
                    return nil
                }
            }

            let result = data.withUnsafeMutableBytes { bytes in
                guard let baseAddress = bytes.baseAddress else { return -1 }
                return recv(descriptor, baseAddress.advanced(by: offset), count - offset, 0)
            }
            if result == 0 { return nil }
            if result < 0 {
                if errno == EINTR { continue }
                return nil
            }
            offset += result
        }

        return data
    }

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
