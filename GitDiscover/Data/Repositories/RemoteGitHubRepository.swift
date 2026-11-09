struct RemoteGitHubRepository: RepositorySearching {
    let client: GitHubAPIClient

    func search(query: String) async throws -> [Repository] {
        try await client.search(query: query)
    }
}