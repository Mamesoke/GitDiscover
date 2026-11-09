import Foundation

struct Repository: Identifiable, Hashable, Sendable {
    let id: Int64
    let name: String
    let fullName: String
    let ownerLogin: String
    let description: String?
    let language: String?
    let stars: Int
    let forks: Int
    let htmlURL: URL
}