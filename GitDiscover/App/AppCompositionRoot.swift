import Foundation

@MainActor
enum AppCompositionRoot {
    static func makeSearchViewModel() -> SearchViewModel {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--ui-testing") {
            return SearchViewModel(useCase: SearchRepositoriesUseCase(repository: UITestRepository()))
        }
        #endif
        let session = URLSession(configuration: .ephemeral)
        let client = GitHubAPIClient(httpClient: URLSessionHTTPClient(session: session))
        let remote = RemoteGitHubRepository(client: client)
        let cache = SearchResultCache()
        let repository = CachedRepositorySearchRepository(remote: remote, cache: cache)
        return SearchViewModel(useCase: SearchRepositoriesUseCase(repository: repository))
    }
}