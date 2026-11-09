import Foundation
import Testing
@testable import GitDiscover

struct GitHubAPIClientTests {
    @Test(arguments: [
        "swift + concurrency language:Swift owner:apple/swift",
        "C++ language:C++",
        "100% \"a&b=c;d\"",
        "caf\u{00E9} \u{65E5}\u{672C}\u{8A9E}"
    ])
    func validResponseMapsToDomainAndBuildsEncodedRequest(query: String) async throws {
        let http = HTTPSpy(result: .success((try searchJSON(), try response(status: 200))))
        let client = GitHubAPIClient(httpClient: http)
        let repositories = try await RemoteGitHubRepository(client: client).search(query: query)

        #expect(repositories == [try makeRepository()])
        let request = try #require(await http.requests.first)
        let url = try #require(request.url)
        let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
        #expect(url.host == "api.github.com")
        #expect(url.path == "/search/repositories")
        #expect(components.queryItems == [URLQueryItem(name: "q", value: query), URLQueryItem(name: "per_page", value: "30"), URLQueryItem(name: "page", value: "1")])
        #expect(components.percentEncodedQuery?.contains("+") == false)
        #expect(request.httpMethod == "GET")
        #expect(request.value(forHTTPHeaderField: "Accept") == "application/vnd.github+json")
        #expect(request.value(forHTTPHeaderField: "X-GitHub-Api-Version") == "2026-03-10")
    }

    @Test(arguments: [true, false])
    func nullableAndAbsentOptionalFieldsDecode(includeFields: Bool) async throws {
        let http = HTTPSpy(result: .success((try searchJSON(nullOptionals: true, includeOptionals: includeFields), try response(status: 200))))
        let repositories = try await GitHubAPIClient(httpClient: http).search(query: "swift")
        #expect(repositories.first?.description == nil)
        #expect(repositories.first?.language == nil)
    }

    @Test(arguments: [403, 429])
    func rateLimitHeadersAreRecognizedWithoutRetry(status: Int) async throws {
        let headers = ["X-RateLimit-Remaining": "0", "X-RateLimit-Reset": "2000"]
        let http = HTTPSpy(result: .success((Data(), try response(status: status, headers: headers))))
        let client = GitHubAPIClient(httpClient: http)
        await #expect(throws: RepositorySearchError.rateLimited(retryAt: Date(timeIntervalSince1970: 2_000))) {
            try await client.search(query: "swift")
        }
        #expect(await http.requests.count == 1)
    }

    @Test func retryAfterUsesInjectedTime() async throws {
        let clock = TestTimeProvider()
        let http = HTTPSpy(result: .success((Data(), try response(status: 429, headers: ["Retry-After": "60"]))))
        let client = GitHubAPIClient(httpClient: http, timeProvider: clock)
        await #expect(throws: RepositorySearchError.rateLimited(retryAt: Date(timeIntervalSince1970: 1_060))) {
            try await client.search(query: "swift")
        }
    }

    @Test(arguments: [403, 429])
    func rateLimitDeadlineAppliesToSubsequentQueries(status: Int) async throws {
        let clock = TestTimeProvider()
        let http = HTTPSpy(result: .success((Data(), try response(status: status, headers: ["Retry-After": "60"]))))
        let client = GitHubAPIClient(httpClient: http, timeProvider: clock)

        await #expect(throws: RepositorySearchError.rateLimited(retryAt: Date(timeIntervalSince1970: 1_060))) {
            try await client.search(query: "swift")
        }
        await #expect(throws: RepositorySearchError.rateLimited(retryAt: Date(timeIntervalSince1970: 1_060))) {
            try await client.search(query: "kotlin")
        }
        #expect(await http.requests.count == 1)

        await clock.advance(by: 60)
        await #expect(throws: RepositorySearchError.rateLimited(retryAt: Date(timeIntervalSince1970: 1_120))) {
            try await client.search(query: "kotlin")
        }
        #expect(await http.requests.count == 2)
    }

    @Test func cachedResultsRemainAvailableDuringRateLimit() async throws {
        let clock = TestTimeProvider()
        let http = HTTPSpy(result: .success((try searchJSON(), try response(status: 200))))
        let client = GitHubAPIClient(httpClient: http, timeProvider: clock)
        let repository = CachedRepositorySearchRepository(
            remote: RemoteGitHubRepository(client: client),
            cache: SearchResultCache(timeProvider: clock)
        )
        let repositories = try await repository.search(query: "swift")
        await http.setResult(.success((Data(), try response(status: 429, headers: ["Retry-After": "60"]))))

        await #expect(throws: RepositorySearchError.rateLimited(retryAt: Date(timeIntervalSince1970: 1_060))) {
            try await repository.search(query: "kotlin")
        }
        #expect(try await repository.search(query: "SWIFT") == repositories)
        await #expect(throws: RepositorySearchError.rateLimited(retryAt: Date(timeIntervalSince1970: 1_060))) {
            try await repository.search(query: "rust")
        }
        #expect(await http.requests.count == 2)

        await clock.advance(by: 60)
        await http.setResult(.success((try searchJSON(), try response(status: 200))))
        #expect(try await repository.search(query: "rust") == repositories)
        #expect(await http.requests.count == 3)
    }

    @Test func rateLimitBodyIsRecognized() async throws {
        let data = Data(#"{"message":"API rate limit exceeded"}"#.utf8)
        let http = HTTPSpy(result: .success((data, try response(status: 403))))
        let client = GitHubAPIClient(httpClient: http, timeProvider: TestTimeProvider())
        await #expect(throws: RepositorySearchError.rateLimited(retryAt: Date(timeIntervalSince1970: 1_060))) {
            try await client.search(query: "swift")
        }
        await #expect(throws: RepositorySearchError.rateLimited(retryAt: Date(timeIntervalSince1970: 1_060))) {
            try await client.search(query: "kotlin")
        }
        #expect(await http.requests.count == 1)
    }

    @Test func generic403IsNotMisclassified() async throws {
        let http = HTTPSpy(result: .success((Data(), try response(status: 403))))
        await #expect(throws: RepositorySearchError.accessDenied) {
            try await GitHubAPIClient(httpClient: http).search(query: "swift")
        }
    }

    @Test func serverErrorIsDistinct() async throws {
        let http = HTTPSpy(result: .success((Data(), try response(status: 500))))
        await #expect(throws: RepositorySearchError.server) {
            try await GitHubAPIClient(httpClient: http).search(query: "swift")
        }
    }

    @Test func malformedJSONFailsWithoutCrashing() async throws {
        let http = HTTPSpy(result: .success((Data("not json".utf8), try response(status: 200))))
        await #expect(throws: RepositorySearchError.decoding) {
            try await GitHubAPIClient(httpClient: http).search(query: "swift")
        }
    }

    @Test(arguments: ["/owner/repository", "javascript:alert(1)", "https://example.com/repo"])
    func untrustedRepositoryURLIsRejected(url: String) async throws {
        let http = HTTPSpy(result: .success((try searchJSON(url: url), try response(status: 200))))
        await #expect(throws: RepositorySearchError.decoding) {
            try await GitHubAPIClient(httpClient: http).search(query: "swift")
        }
    }

    @Test func nonHTTPResponseIsRejected() async throws {
        let url = try #require(URL(string: "https://api.github.com/search/repositories"))
        let response = URLResponse(url: url, mimeType: nil, expectedContentLength: 0, textEncodingName: nil)
        let http = HTTPSpy(result: .success((Data(), response)))
        await #expect(throws: RepositorySearchError.invalidResponse) {
            try await GitHubAPIClient(httpClient: http).search(query: "swift")
        }
    }

    @Test func connectivityErrorIsDistinct() async {
        let http = HTTPSpy(result: .failure(URLError(.notConnectedToInternet)))
        await #expect(throws: RepositorySearchError.connectivity) {
            try await GitHubAPIClient(httpClient: http).search(query: "swift")
        }
    }

    @Test func transportCancellationIsPreserved() async {
        let http = HTTPSpy(result: .failure(URLError(.cancelled)))
        await #expect(throws: CancellationError.self) {
            try await GitHubAPIClient(httpClient: http).search(query: "swift")
        }
    }

    @Test func taskCancellationReachesSuspendedTransportAndBlocksLateSuccess() async throws {
        let gate = SuspensionGate()
        let http = SuspendedHTTPClient(gate: gate, response: try response(status: 200), data: try searchJSON())
        let client = GitHubAPIClient(httpClient: http)
        let task = Task { try await client.search(query: "swift") }
        await gate.waitUntilEntered()
        task.cancel()
        await gate.release()

        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(await http.observedCancellation)
    }

    private func response(status: Int, headers: [String: String] = [:]) throws -> HTTPURLResponse {
        let url = try #require(URL(string: "https://api.github.com/search/repositories"))
        return try #require(HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers))
    }

    private func searchJSON(nullOptionals: Bool = false, includeOptionals: Bool = true, url: String = "https://github.com/owner/repository-1") throws -> Data {
        var item: [String: Any] = [
            "id": 1, "name": "repository-1", "full_name": "owner/repository-1",
            "owner": ["login": "owner"], "stargazers_count": 42, "forks_count": 3, "html_url": url
        ]
        if includeOptionals {
            item["description"] = nullOptionals ? NSNull() : "A test repository"
            item["language"] = nullOptionals ? NSNull() : "Swift"
        }
        return try JSONSerialization.data(withJSONObject: ["items": [item]])
    }
}

private actor HTTPSpy: HTTPClient {
    private(set) var requests: [URLRequest] = []
    private var result: Result<(Data, URLResponse), any Error>

    init(result: Result<(Data, URLResponse), any Error>) { self.result = result }

    func setResult(_ result: Result<(Data, URLResponse), any Error>) {
        self.result = result
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        requests.append(request)
        return try result.get()
    }
}

private actor SuspendedHTTPClient: HTTPClient {
    let gate: SuspensionGate
    let response: URLResponse
    let data: Data
    private(set) var observedCancellation = false

    init(gate: SuspensionGate, response: URLResponse, data: Data) {
        self.gate = gate
        self.response = response
        self.data = data
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        await gate.wait()
        observedCancellation = Task.isCancelled
        return (data, response)
    }
}