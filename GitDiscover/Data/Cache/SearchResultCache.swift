import Foundation

actor SearchResultCache {
    private struct Entry {
        let repositories: [Repository]
        let expiresAt: Date
    }

    private var entries: [String: Entry] = [:]
    private let timeProvider: any TimeProvider
    private let ttl: TimeInterval = 180

    init(timeProvider: any TimeProvider = SystemTimeProvider()) {
        self.timeProvider = timeProvider
    }

    func value(for key: String) async throws -> [Repository]? {
        let now = await timeProvider.now()
        try Task.checkCancellation()
        guard let entry = entries[key] else { return nil }
        guard now < entry.expiresAt else {
            entries.removeValue(forKey: key)
            return nil
        }
        return entry.repositories
    }

    func insert(_ repositories: [Repository], for key: String) async throws {
        try Task.checkCancellation()
        let now = await timeProvider.now()
        try Task.checkCancellation()
        entries[key] = Entry(repositories: repositories, expiresAt: now.addingTimeInterval(ttl))
    }
}