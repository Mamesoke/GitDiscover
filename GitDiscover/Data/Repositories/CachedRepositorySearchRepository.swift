import Foundation

struct CachedRepositorySearchRepository: RepositorySearching {
    let remote: any RepositorySearching
    let cache: SearchResultCache

    static func cacheKey(for query: String) -> String {
        var key = ""
        var quoted = false
        var escaped = false
        var pendingSpace = false
        for character in query.trimmingCharacters(in: .whitespacesAndNewlines) {
            if character == "\"", !escaped { quoted.toggle() }
            if character.isWhitespace, !quoted {
                pendingSpace = true
            } else {
                if pendingSpace, !key.isEmpty { key.append(" ") }
                pendingSpace = false
                key.append(character)
            }
            escaped = character == "\\" && !escaped
        }
        return key.lowercased()
    }

    func search(query: String) async throws -> [Repository] {
        try Task.checkCancellation()
        let key = Self.cacheKey(for: query)
        if let cached = try await cache.value(for: key) {
            try Task.checkCancellation()
            return cached
        }
        try Task.checkCancellation()
        let repositories = try await remote.search(query: query)
        try Task.checkCancellation()
        try await cache.insert(repositories, for: key)
        try Task.checkCancellation()
        return repositories
    }
}