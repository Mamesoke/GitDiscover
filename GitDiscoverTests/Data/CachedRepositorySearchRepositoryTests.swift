import Foundation
import Testing
@testable import GitDiscover

struct CachedRepositorySearchRepositoryTests {
    @Test(arguments: [30.0, 179.0])
    func freshHitBypassesRemote(seconds: Double) async throws {
        let repositories = [try makeRepository()]
        let remote = RepositorySpy(result: .success(repositories))
        let clock = TestTimeProvider()
        let cached = CachedRepositorySearchRepository(remote: remote, cache: SearchResultCache(timeProvider: clock))

        #expect(try await cached.search(query: "swift") == repositories)
        await clock.advance(by: seconds)
        #expect(try await cached.search(query: "swift") == repositories)
        #expect(await remote.queries == ["swift"])
    }

    @Test func exactly180SecondsExpiresAndReplacesData() async throws {
        let first = [try makeRepository(id: 1)]
        let second = [try makeRepository(id: 2)]
        let remote = RepositorySpy(result: .success(first))
        let clock = TestTimeProvider()
        let cached = CachedRepositorySearchRepository(remote: remote, cache: SearchResultCache(timeProvider: clock))

        _ = try await cached.search(query: "swift")
        await clock.advance(by: 179)
        _ = try await cached.search(query: "swift")
        await clock.advance(by: 1)
        await remote.setResult(.success(second))

        #expect(try await cached.search(query: "swift") == second)
        #expect(try await cached.search(query: "swift") == second)
        #expect(await remote.queries == ["swift", "swift"])
    }

    @Test func differentQueriesFetchSeparately() async throws {
        let remote = RepositorySpy()
        let cached = CachedRepositorySearchRepository(remote: remote, cache: SearchResultCache())
        _ = try await cached.search(query: "swift")
        _ = try await cached.search(query: "kotlin")
        #expect(await remote.queries == ["swift", "kotlin"])
    }

    @Test(arguments: ["  SWIFT  concurrency  ", "swift\nconcurrency", "Swift\tConcurrency"])
    func equivalentKeysShareCache(query: String) async throws {
        let remote = RepositorySpy()
        let cached = CachedRepositorySearchRepository(remote: remote, cache: SearchResultCache())
        _ = try await cached.search(query: "swift concurrency")
        _ = try await cached.search(query: query)
        #expect(await remote.queries == ["swift concurrency"])
    }

    @Test func networkExpressionIsPreserved() async throws {
        let remote = RepositorySpy()
        let cached = CachedRepositorySearchRepository(remote: remote, cache: SearchResultCache())
        let query = "Swift  language:Swift topic:\"my topic\""
        _ = try await cached.search(query: query)
        #expect(await remote.queries == [query])
    }

    @Test func quotedWhitespaceDoesNotCauseCacheCollision() async throws {
        let remote = RepositorySpy()
        let cached = CachedRepositorySearchRepository(remote: remote, cache: SearchResultCache())
        _ = try await cached.search(query: #""my  topic" language:Swift"#)
        _ = try await cached.search(query: #""my topic" language:Swift"#)
        #expect(await remote.queries.count == 2)
        #expect(CachedRepositorySearchRepository.cacheKey(for: #"topic:"my \" quoted  topic"  language:Swift"#)
            == #"topic:"my \" quoted  topic" language:swift"#)
    }

    @Test func emptySuccessIsCached() async throws {
        let remote = RepositorySpy()
        let cached = CachedRepositorySearchRepository(remote: remote, cache: SearchResultCache())
        #expect(try await cached.search(query: "swift").isEmpty)
        #expect(try await cached.search(query: "swift").isEmpty)
        #expect(await remote.queries.count == 1)
    }

    @Test func errorsAreNotCached() async throws {
        let remote = RepositorySpy(result: .failure(TestFailure.offline))
        let cached = CachedRepositorySearchRepository(remote: remote, cache: SearchResultCache())
        await #expect(throws: TestFailure.offline) { try await cached.search(query: "swift") }
        await remote.setResult(.success([]))
        _ = try await cached.search(query: "swift")
        #expect(await remote.queries.count == 2)
    }

    @Test func cancellationErrorIsNotCached() async throws {
        let remote = RepositorySpy(result: .failure(CancellationError()))
        let cached = CachedRepositorySearchRepository(remote: remote, cache: SearchResultCache())
        await #expect(throws: CancellationError.self) { try await cached.search(query: "swift") }
        await remote.setResult(.success([]))
        _ = try await cached.search(query: "swift")
        #expect(await remote.queries.count == 2)
    }

    @Test func successFromCancellationIgnoringRemoteIsNotCached() async throws {
        let gate = SuspensionGate()
        let remote = SuspendedRepository(gate: gate, repositories: [try makeRepository()])
        let cache = SearchResultCache()
        let cached = CachedRepositorySearchRepository(remote: remote, cache: cache)
        let task = Task { try await cached.search(query: "swift") }
        await gate.waitUntilEntered()
        task.cancel()
        await gate.release()

        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(try await cache.value(for: "swift") == nil)
        _ = try await cached.search(query: "swift")
        #expect(await remote.calls == 2)
    }

    @Test func cancellationDuringActorWriteClockAwaitPreventsInsertion() async throws {
        let gate = SuspensionGate()
        let clock = SuspendedClock(gate: gate)
        let cache = SearchResultCache(timeProvider: clock)
        let remote = RepositorySpy()
        let cached = CachedRepositorySearchRepository(remote: remote, cache: cache)
        let task = Task { try await cached.search(query: "swift") }
        await gate.waitUntilEntered()
        task.cancel()
        await gate.release()

        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(try await cache.value(for: "swift") == nil)
        _ = try await cached.search(query: "swift")
        #expect(await remote.queries.count == 2)
    }
}

private actor SuspendedRepository: RepositorySearching {
    let gate: SuspensionGate
    let repositories: [Repository]
    private(set) var calls = 0

    init(gate: SuspensionGate, repositories: [Repository]) {
        self.gate = gate
        self.repositories = repositories
    }

    func search(query: String) async throws -> [Repository] {
        calls += 1
        await gate.wait()
        return repositories
    }
}

private actor SuspendedClock: TimeProvider {
    let gate: SuspensionGate
    private var calls = 0

    init(gate: SuspensionGate) { self.gate = gate }

    func now() async -> Date {
        calls += 1
        if calls == 2 { await gate.wait() }
        return Date(timeIntervalSince1970: 1_000)
    }
}