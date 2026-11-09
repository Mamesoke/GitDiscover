import Foundation

enum RepositorySearchError: Error, Equatable, Sendable {
    case invalidRequest
    case invalidResponse
    case accessDenied
    case server
    case decoding
    case connectivity
    case rateLimited(retryAt: Date?)
}