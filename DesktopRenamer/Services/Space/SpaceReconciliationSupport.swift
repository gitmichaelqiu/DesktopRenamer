import Foundation

struct SpaceSnapshotValidationResult: Equatable {
    let hasMissingSpacesOnExistingDisplay: Bool
    let hasDuplicateSpaceIDs: Bool
    let hasDuplicatePositions: Bool

    var isValid: Bool {
        !hasMissingSpacesOnExistingDisplay && !hasDuplicateSpaceIDs && !hasDuplicatePositions
    }
}

enum SpaceReconciliationSupport {
    static func normalizedDisplayID(_ displayID: String, mainDisplayID: String? = nil) -> String {
        let trimmed = displayID.trimmingCharacters(in: .whitespacesAndNewlines)
        let uppercased = trimmed.uppercased()
        if trimmed.isEmpty || uppercased == "MAIN" || uppercased == "UNKNOWN" {
            return mainDisplayID?.uppercased() ?? "MAIN"
        }
        return uppercased
    }

    static func validateSnapshot(
        detectedSpaces: [DesktopSpace],
        cachedSpaces: [DesktopSpace],
        connectedDisplayIDs: Set<String>? = nil,
        mainDisplayID: String? = nil
    ) -> SpaceSnapshotValidationResult {
        let canonical: (String) -> String = { normalizedDisplayID($0, mainDisplayID: mainDisplayID) }
        let cachedByDisplay = Dictionary(grouping: cachedSpaces, by: { canonical($0.displayID) })
        let detectedByDisplay = Dictionary(grouping: detectedSpaces, by: { canonical($0.displayID) })

        // Fullscreen spaces are transient: closing a fullscreen window or
        // leaving fullscreen legitimately removes one from the next snapshot.
        // Regular desktops, however, must still be present before accepting a
        // snapshot so a partial WindowServer response cannot erase state.
        let missingSpaces = cachedByDisplay.contains { displayID, cached in
            guard let detected = detectedByDisplay[displayID] else {
                // A cached display that is no longer connected is a valid
                // topology change. Only a missing display that macOS still
                // reports as connected indicates a partial snapshot.
                return connectedDisplayIDs?.contains(displayID) ?? true
            }
            let cachedDesktops = cached.filter { !$0.isFullscreen }
            let detectedDesktops = detected.filter { !$0.isFullscreen }
            return detectedDesktops.count < cachedDesktops.count
        }
        let duplicateIDs = Set(detectedSpaces.map(\.id)).count != detectedSpaces.count
        let duplicatePositions = detectedByDisplay.values.contains { spaces in
            let positions = spaces.map(\.num)
            return Set(positions).count != positions.count
        }

        return SpaceSnapshotValidationResult(
            hasMissingSpacesOnExistingDisplay: missingSpaces,
            hasDuplicateSpaceIDs: duplicateIDs,
            hasDuplicatePositions: duplicatePositions
        )
    }

    static func claimAvailableName(
        from candidates: [String?],
        claimedNames: inout Set<String>
    ) -> String? {
        for candidate in candidates.compactMap({ $0 }).filter({ !$0.isEmpty }) {
            if claimedNames.insert(candidate).inserted {
                return candidate
            }
        }
        return nil
    }
}
