import Foundation

@main
struct SpaceReconciliationSupportSmoke {
    static func main() {
        let first = DesktopSpace(id: "1", customName: "Main", num: 1, displayID: "main")
        let second = DesktopSpace(id: "2", customName: "Coding", num: 2, displayID: "MAIN")
        let external = DesktopSpace(id: "3", customName: "Research", num: 1, displayID: "external")

        let valid = SpaceReconciliationSupport.validateSnapshot(
            detectedSpaces: [first, second, external],
            cachedSpaces: [first, second, external]
        )
        precondition(valid.isValid)
        precondition(SpaceReconciliationSupport.normalizedDisplayID(" main ") == "MAIN")
        precondition(SpaceReconciliationSupport.normalizedDisplayID("") == "MAIN")
        precondition(
            SpaceReconciliationSupport.normalizedDisplayID("main", mainDisplayID: "MAIN-UUID") == "MAIN-UUID"
        )

        let missingDisplay = SpaceReconciliationSupport.validateSnapshot(
            detectedSpaces: [first, second],
            cachedSpaces: [first, second, external]
        )
        precondition(missingDisplay.hasMissingSpacesOnExistingDisplay)
        precondition(!missingDisplay.isValid)

        let disconnectedDisplay = SpaceReconciliationSupport.validateSnapshot(
            detectedSpaces: [first, second],
            cachedSpaces: [first, second, external],
            connectedDisplayIDs: ["MAIN"]
        )
        precondition(disconnectedDisplay.isValid)

        let fullscreen = DesktopSpace(
            id: "fullscreen", customName: "Editor", num: 3, displayID: "MAIN", isFullscreen: true
        )
        let fullscreenRemoved = SpaceReconciliationSupport.validateSnapshot(
            detectedSpaces: [first, second],
            cachedSpaces: [first, second, fullscreen]
        )
        precondition(fullscreenRemoved.isValid)

        let duplicateID = DesktopSpace(id: "1", customName: "Duplicate", num: 3, displayID: "MAIN")
        let duplicateIdentity = SpaceReconciliationSupport.validateSnapshot(
            detectedSpaces: [first, second, duplicateID],
            cachedSpaces: [first, second]
        )
        precondition(duplicateIdentity.hasDuplicateSpaceIDs)
        precondition(!duplicateIdentity.isValid)

        let duplicatePosition = DesktopSpace(id: "4", customName: "Other", num: 2, displayID: "MAIN")
        let duplicateOrdering = SpaceReconciliationSupport.validateSnapshot(
            detectedSpaces: [first, second, duplicatePosition],
            cachedSpaces: [first, second]
        )
        precondition(duplicateOrdering.hasDuplicatePositions)
        precondition(!duplicateOrdering.isValid)

        var claimedNames: Set<String> = ["Coding"]
        let claimed = SpaceReconciliationSupport.claimAvailableName(
            from: ["Coding", "Research"],
            claimedNames: &claimedNames
        )
        precondition(claimed == "Research")
        precondition(claimedNames == ["Coding", "Research"])

        let legacyData = Data("{\"id\":\"legacy\",\"num\":1}".utf8)
        let legacySpace = try! JSONDecoder().decode(DesktopSpace.self, from: legacyData)
        precondition(legacySpace.customName.isEmpty)
        precondition(legacySpace.displayID == "Main")

        let structuredData = Data("{\"id\":\"1\",\"name\":\"Main\",\"displayName\":\"Built-in\",\"num\":1,\"isFullscreen\":false,\"windows\":[{\"id\":7,\"pid\":42,\"ownerName\":\"Editor\",\"appPath\":\"/Applications/Editor.app\",\"title\":\"A|B~C\",\"isMinimized\":false,\"isHidden\":false}]}".utf8)
        let structuredSpace = try! JSONDecoder().decode(SpaceWindowSnapshot.self, from: structuredData)
        precondition(structuredSpace.windows.first?.title == "A|B~C")

        print("Space reconciliation smoke tests passed")
    }
}
