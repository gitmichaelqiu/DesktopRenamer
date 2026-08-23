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
    static func normalizedDisplayID(_ displayID: String) -> String {
        let trimmed = displayID.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "MAIN" : trimmed.uppercased()
    }

    static func validateSnapshot(
        detectedSpaces: [DesktopSpace],
        cachedSpaces: [DesktopSpace]
    ) -> SpaceSnapshotValidationResult {
        let cachedByDisplay = Dictionary(grouping: cachedSpaces, by: { normalizedDisplayID($0.displayID) })
        let detectedByDisplay = Dictionary(grouping: detectedSpaces, by: { normalizedDisplayID($0.displayID) })

        let missingSpaces = cachedByDisplay.contains { displayID, cached in
            guard let detected = detectedByDisplay[displayID] else { return true }
            return detected.count < cached.count
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
