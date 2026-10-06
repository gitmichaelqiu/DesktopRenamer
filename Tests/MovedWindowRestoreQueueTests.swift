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

private func testMovedWindowRestoreQueueCoordinator() {
    var coordinator = MovedWindowRestoreQueueCoordinator()

    check(coordinator.enqueue([10, 20, 10]), "first restore request starts a queue run")
    let generation = coordinator.generation
    check(coordinator.pendingWindowIDs == [10, 20], "restore queue keeps first-seen order and removes duplicates")
    check(coordinator.takeNext(generation: generation) == 10, "restore queue activates one window at a time")
    check(
        !coordinator.enqueue([10, 20, 30]),
        "new restore requests append to an active run without starting a competing run"
    )
    check(coordinator.pendingWindowIDs == [20, 30], "active and pending windows are not enqueued twice")
    check(
        !coordinator.finishIfDrained(generation: generation),
        "restore queue cannot finish while a window is active"
    )

    check(coordinator.completeActive(windowID: 10, generation: generation), "active window completion advances the queue")
    check(coordinator.takeNext(generation: generation) == 20, "queued windows retain their order")
    check(coordinator.completeActive(windowID: 20, generation: generation), "second active window completes")
    check(coordinator.takeNext(generation: generation) == 30, "windows added during a run are processed")
    check(coordinator.completeActive(windowID: 30, generation: generation), "last active window completes")
    check(coordinator.finishIfDrained(generation: generation), "drained restore queue ends its run")

    check(coordinator.enqueue([40]), "a later restore request starts a fresh run")
    let nextGeneration = coordinator.generation
    check(
        coordinator.takeNext(generation: generation) == nil,
        "callbacks from an earlier run cannot start work in a later run"
    )
    check(coordinator.takeNext(generation: nextGeneration) == 40, "the current run accepts its own callback")
    check(coordinator.enqueue([50, 60]) == false, "additional restores join the current run")
    coordinator.clearPending()
    check(
        coordinator.activeWindowID == 40 && coordinator.pendingWindowIDs.isEmpty,
        "clearing the queue preserves the in-flight window but drops pending windows"
    )
    check(coordinator.completeActive(windowID: 40, generation: nextGeneration), "in-flight restoration can finish after clearing")
    check(coordinator.finishIfDrained(generation: nextGeneration), "the cleared queue completes after its active operation")
}

@main
struct MovedWindowRestoreQueueTestRunner {
    static func main() {
        testMovedWindowRestoreQueueCoordinator()
        if failures > 0 {
            print("Moved window restore queue tests failed: \(failures)")
            exit(1)
        }
        print("Moved window restore queue tests passed")
    }
}
