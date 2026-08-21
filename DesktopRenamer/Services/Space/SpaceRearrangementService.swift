import AppKit
import Combine

/// Reorders spaces through a native Dock scripting-addition backend.
///
/// macOS does not expose a public API for changing the order of spaces. The
/// optional yabai backend is therefore used when its scripting addition is
/// installed; Accessibility-only mouse automation cannot perform this change.
final class SpaceRearrangementService: ObservableObject {
    static let shared = SpaceRearrangementService()

    @Published private(set) var debugStatus = "Idle"

    enum Result {
        case success
        case failure(String)
    }

    private let backendCandidates = [
        "/opt/homebrew/bin/yabai",
        "/usr/local/bin/yabai"
    ]

    private init() {}

    func setDebugStatus(_ status: String) {
        if Thread.isMainThread {
            debugStatus = status
        } else {
            DispatchQueue.main.async { [weak self] in
                self?.debugStatus = status
            }
        }
    }

    func rearrange(
        sourceID: String,
        before targetID: String,
        orderedSpaceIDs: [String],
        displayID: String? = nil,
        completion: @escaping (Result) -> Void
    ) {
        guard sourceID != targetID,
              let sourceIndex = orderedSpaceIDs.firstIndex(of: sourceID),
              let targetIndex = orderedSpaceIDs.firstIndex(of: targetID) else {
            finish(.failure(String(localized: "Choose two different spaces.")), completion: completion)
            return
        }

        guard let backendURL else {
            finish(.failure(String(localized: "Space rearrangement requires yabai with its Dock scripting addition. Accessibility permission alone cannot reorder spaces.")), completion: completion)
            return
        }

        setDebugStatus("Rearranging spaces…")
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let result = self?.runMove(
                executableURL: backendURL,
                sourceIndex: sourceIndex,
                targetIndex: targetIndex
            ) ?? .failure(String(localized: "Space rearrangement was cancelled."))

            DispatchQueue.main.async {
                guard case .success = result else {
                    self?.finish(result, completion: completion)
                    return
                }

                self?.verify(
                    sourceID: sourceID,
                    before: targetID,
                    displayID: displayID,
                    attempt: 0,
                    completion: completion
                )
            }
        }
    }

    private var backendURL: URL? {
        backendCandidates
            .map(URL.init(fileURLWithPath:))
            .first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }

    private func runMove(executableURL: URL, sourceIndex: Int, targetIndex: Int) -> Result {
        let process = Process()
        let output = Pipe()
        process.executableURL = executableURL
        process.arguments = [
            "-m", "space", String(sourceIndex + 1), "--move", String(targetIndex + 1)
        ]
        process.standardOutput = output
        process.standardError = output

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return .failure(String(localized: "Could not start the space rearrangement backend: \(error.localizedDescription)"))
        }

        guard process.terminationStatus == 0 else {
            let message = String(data: output.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return .failure(message?.isEmpty == false ? message! : String(localized: "The Dock rejected the space move. Check that yabai's scripting addition is loaded and that both spaces are on the same display."))
        }

        return .success
    }

    private func verify(
        sourceID: String,
        before targetID: String,
        displayID: String?,
        attempt: Int,
        completion: @escaping (Result) -> Void
    ) {
        guard let state = SpaceHelper.getSystemState(onDisplayID: displayID) else {
            retryVerification(sourceID: sourceID, targetID: targetID, displayID: displayID, attempt: attempt, completion: completion)
            return
        }

        let regularSpaces = state.spaces.filter { !$0.isFullscreen }
        if let sourceIndex = regularSpaces.firstIndex(where: { $0.id == sourceID }),
           let targetIndex = regularSpaces.firstIndex(where: { $0.id == targetID }),
           sourceIndex < targetIndex {
            finish(.success, completion: completion)
            return
        }

        retryVerification(sourceID: sourceID, targetID: targetID, displayID: displayID, attempt: attempt, completion: completion)
    }

    private func retryVerification(
        sourceID: String,
        targetID: String,
        displayID: String?,
        attempt: Int,
        completion: @escaping (Result) -> Void
    ) {
        guard attempt < 8 else {
            finish(.failure(String(localized: "The backend completed without changing the reported space order.")), completion: completion)
            return
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            self?.verify(
                sourceID: sourceID,
                before: targetID,
                displayID: displayID,
                attempt: attempt + 1,
                completion: completion
            )
        }
    }

    private func finish(_ result: Result, completion: @escaping (Result) -> Void) {
        setDebugStatus(status(for: result))
        completion(result)
    }

    private func status(for result: Result) -> String {
        switch result {
        case .success:
            return "Debug rearrangement completed."
        case .failure(let error):
            return "Debug rearrangement failed: \(error)"
        }
    }
}
