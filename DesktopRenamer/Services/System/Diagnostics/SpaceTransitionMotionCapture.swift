#if DEBUG
import AppKit
import CoreGraphics
import CoreMedia
import CoreVideo
import Foundation
import ScreenCaptureKit

/// Measures horizontal screen motion during a user-started diagnostic session.
/// Image frames stay in memory for pairwise comparison and are never saved.
final class SpaceTransitionMotionCapture: NSObject, SCStreamOutput {
    static let shared = SpaceTransitionMotionCapture()

    private struct Frame {
        let index: Int
        let timestamp: Double
        let luma: [UInt8]
        let width: Int
        let height: Int
    }

    private struct Translation {
        let deltaX: Int
        let confidence: Double
        let searchWasClipped: Bool
    }

    private struct MotionSegment {
        let index: Int
        let startTimestamp: Double
        let directionSign: Double
        var lastTimestamp: Double
        var frameCount = 0
        var idleFrameCount = 0
        var reverseFrameCount = 0
        var searchClippedFrameCount = 0
        var forwardDistance = 0.0
        var backwardDistance = 0.0
        var cumulativeDistance = 0.0
        var peakForwardDistance = 0.0
        var maximumSpeed = 0.0
        var confidenceSum = 0.0
    }

    private let stateLock = NSLock()
    private let outputQueue = DispatchQueue(
        label: "dev.mqiu.DesktopRenamer.space-motion-capture",
        qos: .userInteractive
    )
    private var generation = 0
    private var captureRequested = false
    private var stream: SCStream?

    // Output-side state is only accessed on outputQueue.
    private var previousFrame: Frame?
    private var currentSegment: MotionSegment?
    private var captureWidth = 0
    private var captureHeight = 0
    private var pointsPerCapturePixel = 1.0
    private var completeFrameCount = 0
    private var measuredSegmentCount = 0

    private let requestedFrameInterval = CMTime(value: 1, timescale: 120)
    private let maximumHorizontalShift = 48
    private let minimumMotionConfidence = 0.04

    private override init() {
        super.init()
    }

    func start() {
        stateLock.lock()
        guard !captureRequested else {
            stateLock.unlock()
            return
        }

        captureRequested = true
        generation &+= 1
        let requestedGeneration = generation
        stateLock.unlock()

        DiagnosticEventLog.shared.recordDuringCollection(
            subsystem: "SpaceMotion",
            level: "info",
            "phase=starting framePersistence=none"
        )

        Task { [weak self] in
            await self?.configureAndStart(generation: requestedGeneration)
        }
    }

    func stop() {
        stateLock.lock()
        guard captureRequested || stream != nil else {
            stateLock.unlock()
            return
        }

        captureRequested = false
        generation &+= 1
        let streamToStop = stream
        stream = nil
        stateLock.unlock()

        outputQueue.sync {
            finishCurrentSegment(reason: "collection-stopped")
            DiagnosticEventLog.shared.record(
                subsystem: "SpaceMotion",
                level: "info",
                "phase=collection-summary completeFrames=\(completeFrameCount) measuredSegments=\(measuredSegmentCount) framePersistence=none"
            )
            previousFrame = nil
        }

        guard let streamToStop else { return }
        Task {
            do {
                try await streamToStop.stopCapture()
            } catch {
                DiagnosticEventLog.shared.record(
                    subsystem: "SpaceMotion",
                    level: "warning",
                    "phase=stop-failed error=\(error.localizedDescription)"
                )
            }
        }
    }

    private func configureAndStart(generation requestedGeneration: Int) async {
        guard CGPreflightScreenCaptureAccess() else {
            failStart(
                generation: requestedGeneration,
                reason: "Screen Recording permission is not granted"
            )
            return
        }

        var streamBeingStarted: SCStream?
        do {
            let shareableContent = try await SCShareableContent.excludingDesktopWindows(
                false,
                onScreenWindowsOnly: true
            )
            guard isCurrentGeneration(requestedGeneration) else { return }

            guard let display = shareableContent.displays.first(where: {
                $0.displayID == CGMainDisplayID()
            }) ?? shareableContent.displays.first else {
                failStart(generation: requestedGeneration, reason: "No display is available")
                return
            }

            let ownApplication = shareableContent.applications.first {
                $0.bundleIdentifier == Bundle.main.bundleIdentifier
            }
            let filter = SCContentFilter(
                display: display,
                excludingApplications: ownApplication.map { [$0] } ?? [],
                exceptingWindows: []
            )

            let outputWidth = 480
            let aspectRatio = Double(display.height) / Double(max(display.width, 1))
            let outputHeight = max(1, Int((Double(outputWidth) * aspectRatio).rounded()))
            let configuration = SCStreamConfiguration()
            configuration.width = outputWidth
            configuration.height = outputHeight
            configuration.pixelFormat = kCVPixelFormatType_32BGRA
            configuration.minimumFrameInterval = requestedFrameInterval
            configuration.queueDepth = 3
            configuration.showsCursor = false
            configuration.capturesAudio = false

            let newStream = SCStream(filter: filter, configuration: configuration, delegate: nil)
            streamBeingStarted = newStream
            try newStream.addStreamOutput(self, type: .screen, sampleHandlerQueue: outputQueue)

            outputQueue.sync {
                previousFrame = nil
                currentSegment = nil
                captureWidth = outputWidth
                captureHeight = outputHeight
                pointsPerCapturePixel = Double(display.width) / Double(outputWidth)
                completeFrameCount = 0
                measuredSegmentCount = 0
            }

            stateLock.lock()
            guard captureRequested, generation == requestedGeneration else {
                stateLock.unlock()
                return
            }
            stream = newStream
            stateLock.unlock()

            try await newStream.startCapture()
            guard isCurrentGeneration(requestedGeneration) else {
                try? await newStream.stopCapture()
                return
            }

            DiagnosticEventLog.shared.recordDuringCollection(
                subsystem: "SpaceMotion",
                level: "info",
                "phase=ready displayID=\(display.displayID) resolution=\(outputWidth)x\(outputHeight) requestedFrameRate=120 framePersistence=none"
            )
        } catch {
            if let streamBeingStarted {
                try? await streamBeingStarted.stopCapture()
            }
            failStart(
                generation: requestedGeneration,
                reason: error.localizedDescription
            )
        }
    }

    private func failStart(generation requestedGeneration: Int, reason: String) {
        stateLock.lock()
        guard generation == requestedGeneration else {
            stateLock.unlock()
            return
        }
        captureRequested = false
        stream = nil
        stateLock.unlock()

        DiagnosticEventLog.shared.recordDuringCollection(
            subsystem: "SpaceMotion",
            level: "warning",
            "phase=unavailable reason=\(reason) framePersistence=none"
        )
    }

    private func isCurrentGeneration(_ requestedGeneration: Int) -> Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        return captureRequested && generation == requestedGeneration
    }

    func stream(
        _ outputStream: SCStream,
        didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
        of type: SCStreamOutputType
    ) {
        guard type == .screen,
              sampleBuffer.isValid,
              let attachments = CMSampleBufferGetSampleAttachmentsArray(
                sampleBuffer,
                createIfNecessary: false
              ) as? [[SCStreamFrameInfo: Any]],
              let statusValue = attachments.first?[.status] as? Int,
              SCFrameStatus(rawValue: statusValue) == .complete,
              let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            return
        }

        stateLock.lock()
        let shouldProcess = captureRequested && stream != nil
        stateLock.unlock()
        guard shouldProcess else { return }

        let timestamp = CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(sampleBuffer))
        guard timestamp.isFinite,
              let luma = makeLumaBuffer(from: pixelBuffer),
              captureWidth > 0,
              captureHeight > 0 else {
            return
        }

        completeFrameCount += 1
        let frame = Frame(
            index: completeFrameCount,
            timestamp: timestamp,
            luma: luma,
            width: captureWidth,
            height: captureHeight
        )

        guard let previousFrame else {
            self.previousFrame = frame
            return
        }

        guard frame.width == previousFrame.width,
              frame.height == previousFrame.height else {
            finishCurrentSegment(reason: "capture-size-changed")
            self.previousFrame = frame
            return
        }

        let frameInterval = frame.timestamp - previousFrame.timestamp
        guard frameInterval > 0, frameInterval <= 0.12 else {
            finishCurrentSegment(reason: "capture-frame-gap")
            self.previousFrame = frame
            return
        }

        let translation = estimateTranslation(from: previousFrame, to: frame)
        let isTrackableMotion = abs(translation.deltaX) >= 1
            && translation.confidence >= minimumMotionConfidence

        if isTrackableMotion {
            recordMotion(
                translation,
                frame: frame,
                frameInterval: frameInterval
            )
        } else if var segment = currentSegment {
            segment.idleFrameCount += 1
            if segment.idleFrameCount >= 3 {
                currentSegment = segment
                finishCurrentSegment(reason: "motion-settled")
            } else {
                currentSegment = segment
            }
        }

        self.previousFrame = frame
    }

    private func makeLumaBuffer(from pixelBuffer: CVPixelBuffer) -> [UInt8]? {
        guard CVPixelBufferGetPixelFormatType(pixelBuffer) == kCVPixelFormatType_32BGRA,
              CVPixelBufferGetWidth(pixelBuffer) == captureWidth,
              CVPixelBufferGetHeight(pixelBuffer) == captureHeight,
              CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly) == kCVReturnSuccess else {
            return nil
        }
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }

        guard let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else { return nil }
        let bytes = baseAddress.assumingMemoryBound(to: UInt8.self)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        var luma = [UInt8](repeating: 0, count: captureWidth * captureHeight)

        for y in 0..<captureHeight {
            let sourceRow = bytes.advanced(by: y * bytesPerRow)
            let destinationRow = y * captureWidth
            for x in 0..<captureWidth {
                let pixel = sourceRow.advanced(by: x * 4)
                let blue = Int(pixel[0])
                let green = Int(pixel[1])
                let red = Int(pixel[2])
                luma[destinationRow + x] = UInt8((29 * blue + 150 * green + 77 * red) >> 8)
            }
        }

        return luma
    }

    private func estimateTranslation(from previous: Frame, to current: Frame) -> Translation {
        let width = current.width
        let height = current.height
        let baselineError = meanDifference(
            previous: previous.luma,
            current: current.luma,
            width: width,
            height: height,
            deltaX: 0,
            horizontalStride: 4,
            verticalStride: 4
        )

        var coarseBestX = 0
        var coarseBestError = Double.greatestFiniteMagnitude
        for deltaX in stride(from: -maximumHorizontalShift, through: maximumHorizontalShift, by: 4) {
            let error = meanDifference(
                previous: previous.luma,
                current: current.luma,
                width: width,
                height: height,
                deltaX: deltaX,
                horizontalStride: 8,
                verticalStride: 6
            )
            if error < coarseBestError {
                coarseBestX = deltaX
                coarseBestError = error
            }
        }

        var bestX = coarseBestX
        var bestError = Double.greatestFiniteMagnitude
        let refineStart = max(-maximumHorizontalShift, coarseBestX - 4)
        let refineEnd = min(maximumHorizontalShift, coarseBestX + 4)
        for deltaX in refineStart...refineEnd {
            let error = meanDifference(
                previous: previous.luma,
                current: current.luma,
                width: width,
                height: height,
                deltaX: deltaX,
                horizontalStride: 4,
                verticalStride: 4
            )
            if error < bestError {
                bestX = deltaX
                bestError = error
            }
        }

        let confidence = baselineError > 0
            ? max(0, min(1, (baselineError - bestError) / baselineError))
            : 0
        let wasClipped = abs(bestX) == maximumHorizontalShift
        return Translation(deltaX: bestX, confidence: confidence, searchWasClipped: wasClipped)
    }

    private func meanDifference(
        previous: [UInt8],
        current: [UInt8],
        width: Int,
        height: Int,
        deltaX: Int,
        horizontalStride: Int,
        verticalStride: Int
    ) -> Double {
        let startX = max(2, -deltaX)
        let endX = min(width - 2, width - deltaX)
        guard startX < endX else { return Double.greatestFiniteMagnitude }

        var totalDifference = 0
        var sampleCount = 0
        for y in stride(from: 2, to: height - 2, by: verticalStride) {
            let rowOffset = y * width
            for x in stride(from: startX, to: endX, by: horizontalStride) {
                totalDifference += abs(
                    Int(current[rowOffset + x]) - Int(previous[rowOffset + x + deltaX])
                )
                sampleCount += 1
            }
        }

        guard sampleCount > 0 else { return Double.greatestFiniteMagnitude }
        return Double(totalDifference) / Double(sampleCount)
    }

    private func recordMotion(
        _ translation: Translation,
        frame: Frame,
        frameInterval: Double
    ) {
        let deltaXPoints = Double(translation.deltaX) * pointsPerCapturePixel
        let speed = deltaXPoints / frameInterval
        var segment: MotionSegment
        if let currentSegment {
            segment = currentSegment
        } else {
            measuredSegmentCount += 1
            segment = MotionSegment(
                index: measuredSegmentCount,
                startTimestamp: frame.timestamp - frameInterval,
                directionSign: deltaXPoints >= 0 ? 1 : -1,
                lastTimestamp: frame.timestamp
            )
            DiagnosticEventLog.shared.recordDuringCollection(
                subsystem: "SpaceMotion",
                level: "debug",
                "phase=motion-start segment=\(segment.index) frame=\(frame.index)"
            )
        }

        let progressAlongInitialDirection = deltaXPoints * segment.directionSign
        if progressAlongInitialDirection >= 0 {
            segment.forwardDistance += progressAlongInitialDirection
        } else {
            segment.backwardDistance += abs(progressAlongInitialDirection)
            segment.reverseFrameCount += 1
        }
        segment.cumulativeDistance += progressAlongInitialDirection
        segment.peakForwardDistance = max(segment.peakForwardDistance, segment.cumulativeDistance)
        segment.maximumSpeed = max(segment.maximumSpeed, abs(speed))
        segment.lastTimestamp = frame.timestamp
        segment.frameCount += 1
        segment.idleFrameCount = 0
        segment.confidenceSum += translation.confidence
        if translation.searchWasClipped {
            segment.searchClippedFrameCount += 1
        }
        currentSegment = segment

        DiagnosticEventLog.shared.recordDuringCollection(
            subsystem: "SpaceMotion",
            level: "debug",
            "phase=frame segment=\(segment.index) frame=\(frame.index) deltaXPoints=\(deltaXPoints) velocityPointsPerSecond=\(speed) netProgressPoints=\(segment.cumulativeDistance) confidence=\(translation.confidence) searchClipped=\(translation.searchWasClipped)"
        )
    }

    private func finishCurrentSegment(reason: String) {
        guard let segment = currentSegment else { return }
        currentSegment = nil

        let durationMilliseconds = max(0, segment.lastTimestamp - segment.startTimestamp) * 1_000
        let averageConfidence = segment.frameCount > 0
            ? segment.confidenceSum / Double(segment.frameCount)
            : 0
        DiagnosticEventLog.shared.record(
            subsystem: "SpaceMotion",
            level: segment.backwardDistance > 0 ? "warning" : "info",
            "phase=summary segment=\(segment.index) reason=\(reason) frames=\(segment.frameCount) durationMs=\(durationMilliseconds) forwardDistancePoints=\(segment.forwardDistance) backwardDistancePoints=\(segment.backwardDistance) reverseFrames=\(segment.reverseFrameCount) peakForwardPoints=\(segment.peakForwardDistance) maxSpeedPointsPerSecond=\(segment.maximumSpeed) averageConfidence=\(averageConfidence) clippedSearchFrames=\(segment.searchClippedFrameCount)"
        )
    }
}
#endif
