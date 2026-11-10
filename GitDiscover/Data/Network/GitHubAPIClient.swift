import Foundation

actor GitHubAPIClient {
    private let httpClient: any HTTPClient
    private let timeProvider: any TimeProvider
    private var retryNotBefore: Date?

    init(httpClient: any HTTPClient, timeProvider: any TimeProvider = SystemTimeProvider()) {
        self.httpClient = httpClient
        self.timeProvider = timeProvider
    }

    func search(query: String) async throws -> [Repository] {
        try Task.checkCancellation()
        if retryNotBefore != nil {
            let now = await timeProvider.now()
            try Task.checkCancellation()
            if let deadline = retryNotBefore, now < deadline {
                throw RepositorySearchError.rateLimited(retryAt: deadline)
            }
        }
        var components = URLComponents()
        components.scheme = "https"
        components.host = "api.github.com"
        components.path = "/search/repositories"
        let allowedCharacters = CharacterSet.urlQueryAllowed.subtracting(CharacterSet(charactersIn: "+&=;%"))
        guard let encodedQuery = query.addingPercentEncoding(withAllowedCharacters: allowedCharacters) else {
            throw RepositorySearchError.invalidRequest
        }
        components.percentEncodedQueryItems = [
            URLQueryItem(name: "q", value: encodedQuery),
            URLQueryItem(name: "per_page", value: "30"),
            URLQueryItem(name: "page", value: "1")
        ]
        guard let url = components.url else { throw RepositorySearchError.invalidRequest }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2026-03-10", forHTTPHeaderField: "X-GitHub-Api-Version")
        request.setValue("GitDiscover", forHTTPHeaderField: "User-Agent")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await httpClient.data(for: request)
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as URLError where error.code == .cancelled {
            throw CancellationError()
        } catch {
            try Task.checkCancellation()
            throw RepositorySearchError.connectivity
        }
        try Task.checkCancellation()
        guard let response = response as? HTTPURLResponse else {
            throw RepositorySearchError.invalidResponse
        }

        if isRateLimited(response: response, data: data) {
            let now = await timeProvider.now()
            try Task.checkCancellation()
            let deadline = retryDate(response: response, now: now) ?? now.addingTimeInterval(60)
            retryNotBefore = max(retryNotBefore ?? deadline, deadline)
            throw RepositorySearchError.rateLimited(retryAt: retryNotBefore)
        }
        switch response.statusCode {
        case 200..<300: break
        case 403: throw RepositorySearchError.accessDenied
        case 500..<600: throw RepositorySearchError.server
        default: throw RepositorySearchError.invalidResponse
        }

        do {
            let dto = try JSONDecoder().decode(GitHubSearchResponseDTO.self, from: data)
            let repositories = try dto.items.map { try $0.toDomain() }
            try Task.checkCancellation()
            return repositories
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw RepositorySearchError.decoding
        }
    }

    private func isRateLimited(response: HTTPURLResponse, data: Data) -> Bool {
        if response.statusCode == 429 { return true }
        guard response.statusCode == 403 else { return false }
        if response.value(forHTTPHeaderField: "X-RateLimit-Remaining") == "0"
            || response.value(forHTTPHeaderField: "Retry-After") != nil {
            return true
        }
        struct ErrorResponse: Decodable { let message: String }
        let message = (try? JSONDecoder().decode(ErrorResponse.self, from: data))?.message.lowercased() ?? ""
        return message.contains("rate limit") || message.contains("secondary rate")
    }

    private func retryDate(response: HTTPURLResponse, now: Date) -> Date? {
        if let value = response.value(forHTTPHeaderField: "Retry-After") {
            if let seconds = Double(value), seconds.isFinite, seconds >= 0 {
                return now.addingTimeInterval(seconds)
            }
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone(secondsFromGMT: 0)
            formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
            if let date = formatter.date(from: value) { return date }
        }
        guard let value = response.value(forHTTPHeaderField: "X-RateLimit-Reset"),
              let seconds = Double(value), seconds.isFinite, seconds >= 0 else { return nil }
        return Date(timeIntervalSince1970: seconds)
    }
}