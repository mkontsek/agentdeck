enum SubagentLimits {
    static let defaultConcurrentWorkers = 20
    static let concurrentWorkers = 1...20
    static let retainedTabs = 40
    static let legacyDefaultConcurrentWorkers = 3

    static func clampedConcurrentWorkers(_ value: Int) -> Int {
        min(concurrentWorkers.upperBound, max(concurrentWorkers.lowerBound, value))
    }
}
