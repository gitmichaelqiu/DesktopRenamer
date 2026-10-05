import Foundation

private var failures = 0

private func check(_ condition: @autoclosure () -> Bool, _ message: String) {
    if condition() {
        print("PASS: \(message)")
    } else {
        failures += 1
        print("FAIL: \(message)")
    }
}

private func testSpaceAPIIdentityPersistence() throws {
    let original = DesktopSpace(
        id: "42",
        customName: "Development",
        num: 2,
        displayID: "DISPLAY-UUID",
        persistentID: "PERSISTENT-SPACE-UUID"
    )
    let encoded = try JSONEncoder().encode(original)
    let decoded = try JSONDecoder().decode(DesktopSpace.self, from: encoded)
    check(decoded.spaceAPIID == original.spaceAPIID, "app-owned ID persists in saved space data")

    let legacyPayload = Data(#"{"id":"7","customName":"Legacy","num":1}"#.utf8)
    let legacySpace = try JSONDecoder().decode(DesktopSpace.self, from: legacyPayload)
    check(UUID(uuidString: legacySpace.spaceAPIID) != nil, "legacy spaces receive a generated app-owned ID")
    let migratedSpace = try JSONDecoder().decode(DesktopSpace.self, from: JSONEncoder().encode(legacySpace))
    check(migratedSpace.spaceAPIID == legacySpace.spaceAPIID, "migrated ID remains stable after persistence")
}

private func testSpaceAPIIdentityReconciliation() {
    let previous = DesktopSpace(
        id: "42",
        customName: "Development",
        num: 2,
        displayID: "DISPLAY-UUID",
        persistentID: "PERSISTENT-SPACE-UUID",
        spaceAPIID: "DESKTOPRENAMER-SPACE-ID"
    )

    var afterRestart = DesktopSpace(
        id: "9001",
        customName: "",
        num: 2,
        displayID: "DISPLAY-UUID",
        persistentID: "PERSISTENT-SPACE-UUID"
    )
    afterRestart.preserveSpaceAPIIdentity(from: [previous], afterBoot: true)
    check(
        afterRestart.spaceAPIID == previous.spaceAPIID,
        "persistent system identity carries app-owned ID across managed-ID changes"
    )

    var sameBootRecreated = DesktopSpace(
        id: previous.id,
        customName: "",
        num: 2,
        displayID: "DISPLAY-UUID",
        persistentID: "RECREATED-SPACE-UUID",
        spaceAPIID: "NEW-SPACE-ID"
    )
    sameBootRecreated.preserveSpaceAPIIdentity(from: [previous], afterBoot: false)
    check(
        sameBootRecreated.spaceAPIID == "NEW-SPACE-ID",
        "a reused managed ID cannot override a changed persistent ID"
    )

    let previousWithoutPersistentID = DesktopSpace(
        id: "73",
        customName: "Temporary",
        num: 3,
        displayID: "DISPLAY-UUID",
        spaceAPIID: "TEMPORARY-SPACE-ID"
    )
    var refreshedSameBoot = DesktopSpace(
        id: "73",
        customName: "",
        num: 3,
        displayID: "DISPLAY-UUID"
    )
    refreshedSameBoot.preserveSpaceAPIIdentity(from: [previousWithoutPersistentID], afterBoot: false)
    check(
        refreshedSameBoot.spaceAPIID == previousWithoutPersistentID.spaceAPIID,
        "managed ID preserves identity for an unidentifiable space within one boot"
    )

    var restoredAfterBoot = DesktopSpace(
        id: "73",
        customName: "",
        num: 3,
        displayID: "DISPLAY-UUID",
        spaceAPIID: "NEW-SPACE-AFTER-BOOT"
    )
    restoredAfterBoot.preserveSpaceAPIIdentity(from: [previousWithoutPersistentID], afterBoot: true)
    check(
        restoredAfterBoot.spaceAPIID == "NEW-SPACE-AFTER-BOOT",
        "identity is not guessed from a reused managed ID after reboot"
    )
}

@main
struct SpaceAPIIdentityTestRunner {
    static func main() throws {
        try testSpaceAPIIdentityPersistence()
        testSpaceAPIIdentityReconciliation()
        if failures > 0 {
            print("SpaceAPI identity tests failed: \(failures)")
            exit(1)
        }
        print("SpaceAPI identity tests passed")
    }
}
