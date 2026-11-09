import Foundation

struct GitHubSearchResponseDTO: Decodable {
    let items: [GitHubRepositoryDTO]
}

struct GitHubRepositoryDTO: Decodable {
    struct Owner: Decodable {
        let login: String
    }

    let id: Int64
    let name: String
    let fullName: String
    let owner: Owner
    let description: String?
    let language: String?
    let stars: Int
    let forks: Int
    let htmlURL: String

    enum CodingKeys: String, CodingKey {
        case id, name, owner, description, language
        case fullName = "full_name"
        case stars = "stargazers_count"
        case forks = "forks_count"
        case htmlURL = "html_url"
    }

    func toDomain() throws -> Repository {
        guard let url = URL(string: htmlURL),
              url.scheme == "https", url.host == "github.com" else {
            throw RepositorySearchError.decoding
        }
        return Repository(
            id: id, name: name, fullName: fullName, ownerLogin: owner.login,
            description: description, language: language, stars: stars,
            forks: forks, htmlURL: url
        )
    }
}