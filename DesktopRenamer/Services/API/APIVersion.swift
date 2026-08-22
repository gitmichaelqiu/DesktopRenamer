import Foundation

/// Version of the external SpaceAPI and AppleScript contract.
///
/// This is intentionally independent from the app's marketing/build version.
/// Increase the major version for incompatible command or payload changes.
enum DesktopRenamerAPIVersion {
    static let current = "1.1.0"
}
