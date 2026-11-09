protocol SearchDelaying: Sendable {
    func wait() async throws
}

struct DebounceDelay: SearchDelaying {
    static let duration: Duration = .milliseconds(400)

    func wait() async throws {
        try await Task.sleep(for: Self.duration)
    }
}