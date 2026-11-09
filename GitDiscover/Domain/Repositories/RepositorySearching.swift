protocol RepositorySearching: Sendable {
    func search(query: String) async throws -> [Repository]
}