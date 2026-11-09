import Foundation

struct SearchRepositoriesUseCase: Sendable {
    private let repository: any RepositorySearching

    init(repository: any RepositorySearching) {
        self.repository = repository
    }

    static func normalizedQuery(_ query: String) -> String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func execute(query: String) async throws -> [Repository] {
        try Task.checkCancellation()
        let normalized = Self.normalizedQuery(query)
        guard normalized.count >= 2 else { return [] }

        let repositories = try await repository.search(query: normalized)
        try Task.checkCancellation()
        return repositories
    }
}