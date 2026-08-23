import Foundation

@main
struct LauncherLoadGenerationSmoke {
    static func main() {
        var generations = LauncherLoadGeneration()
        let first = generations.begin()
        let second = generations.begin()

        precondition(first != second)
        precondition(!generations.accepts(first))
        precondition(generations.accepts(second))

        print("Launcher load-generation smoke tests passed")
    }
}
