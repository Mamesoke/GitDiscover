#if DEBUG
import Foundation

actor UITestRepository: RepositorySearching {
    private var attempts: [String: Int] = [:]

    func search(query: String) async throws -> [Repository] {
        attempts[query, default: 0] += 1
        switch query.lowercased() {
        case "empty": return []
        case "offline" where attempts[query] == 1: throw RepositorySearchError.connectivity
        case "ratelimit": throw RepositorySearchError.rateLimited(retryAt: Date().addingTimeInterval(60))
        default: break
        }
        guard let swiftURL = URL(string: "https://github.com/apple/swift"),
              let sampleURL = URL(string: "https://github.com/example/sample") else {
            throw RepositorySearchError.invalidRequest
        }
        return [
            Repository(id: 1, name: "swift", fullName: "apple/swift", ownerLogin: "apple",
                       description: "The Swift programming language", language: "Swift",
                       stars: 65_000, forks: 10_000, htmlURL: swiftURL),
            Repository(id: 2, name: "sample", fullName: "example/sample", ownerLogin: "example",
                       description: nil, language: nil, stars: 0, forks: 0, htmlURL: sampleURL)
        ]
    }
}
#endif