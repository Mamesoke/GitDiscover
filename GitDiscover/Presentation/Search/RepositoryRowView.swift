import SwiftUI

struct RepositoryRowView: View {
    let repository: Repository

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(repository.fullName).font(.headline).foregroundStyle(.primary)
            if let description = repository.description, !description.isEmpty {
                Text(description).font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
            }
            HStack {
                Text(repository.language ?? "Unknown language")
                Spacer()
                Label(repository.stars.formatted(), systemImage: "star")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
}