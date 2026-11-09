import SwiftUI

struct RepositoryDetailView: View {
    let repository: Repository

    var body: some View {
        Form {
            Section {
                Text(repository.fullName).font(.headline).textSelection(.enabled)
                Text(repository.description ?? "No description provided")
                    .foregroundStyle(.secondary).textSelection(.enabled)
                    .accessibilityIdentifier("description-value")
            }
            Section("Repository") {
                LabeledContent("Owner") {
                    Text(repository.ownerLogin).accessibilityIdentifier("owner-value")
                }
                LabeledContent("Language") {
                    Text(repository.language ?? "Unknown language").accessibilityIdentifier("language-value")
                }
                LabeledContent("Stars") {
                    Text(repository.stars.formatted()).accessibilityIdentifier("stars-value")
                }
                LabeledContent("Forks") {
                    Text(repository.forks.formatted()).accessibilityIdentifier("forks-value")
                }
            }
            Section {
                Link(destination: repository.htmlURL) { Label("Open on GitHub", systemImage: "safari") }
                    .accessibilityIdentifier("github-link")
            }
        }
        .navigationTitle(repository.name)
        .navigationBarTitleDisplayMode(.inline)
    }
}