import Foundation
import Testing
@testable import GitDiscover

func makeRepository(id: Int64 = 1) throws -> Repository {
    Repository(
        id: id,
        name: "repository-\(id)",
        fullName: "owner/repository-\(id)",
        ownerLogin: "owner",
        description: "A test repository",
        language: "Swift",
        stars: 42,
        forks: 3,
        htmlURL: try #require(URL(string: "https://github.com/owner/repository-\(id)"))
    )
}

enum TestFailure: Error, Equatable {
    case offline
}

actor RepositorySpy: RepositorySearching {
    private(set) var queries: [String] = []
    var result: Result<[Repository], any Error>

    init(result: Result<[Repository], any Error> = .success([])) {
        self.result = result
    }

    func setResult(_ result: Result<[Repository], any Error>) {
        self.result = result
    }

    func search(query: String) async throws -> [Repository] {
        queries.append(query)
        return try result.get()
    }
}

actor TestTimeProvider: TimeProvider {
    private var date: Date

    init(date: Date = Date(timeIntervalSince1970: 1_000)) {
        self.date = date
    }

    func now() async -> Date { date }

    func advance(by seconds: TimeInterval) {
        date = date.addingTimeInterval(seconds)
    }
}

actor SuspensionGate {
    private var entered = false
    private var released = false
    private var continuation: CheckedContinuation<Void, Never>?
    private var arrival: CheckedContinuation<Void, Never>?

    func wait() async {
        entered = true
        arrival?.resume()
        arrival = nil
        guard !released else { return }
        await withCheckedContinuation { continuation = $0 }
    }

    func waitUntilEntered() async {
        guard !entered else { return }
        await withCheckedContinuation { arrival = $0 }
    }

    func release() {
        released = true
        continuation?.resume()
        continuation = nil
    }
}