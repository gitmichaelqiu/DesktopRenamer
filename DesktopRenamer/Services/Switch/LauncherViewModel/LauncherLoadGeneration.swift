import Foundation

struct LauncherLoadGeneration: Equatable, Sendable {
    private(set) var value: Int = 0

    mutating func begin() -> Int {
        value &+= 1
        return value
    }

    func accepts(_ generation: Int) -> Bool {
        generation == value
    }
}
