//
//  ContentView.swift
//  GitDiscover
//
//  Created by Kevin MENENDEZ on 09/11/2026.
//

import SwiftUI

struct ContentView: View {
    @ObservedObject var viewModel: SearchViewModel

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                HStack {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("Search GitHub repositories", text: Binding(
                        get: { viewModel.searchText },
                        set: { viewModel.updateSearchText($0) }
                    ))
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.search)
                    .accessibilityIdentifier("search-field")
                    Button {
                        viewModel.updateSearchText("")
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                            .frame(width: 44, height: 44)
                    }
                    .disabled(viewModel.searchText.isEmpty)
                    .accessibilityLabel("Clear search")
                    .accessibilityIdentifier("clear-search")
                    .help("Clear search")
                }
                .padding(.horizontal)
                Divider()
                searchContent.frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .navigationTitle("GitDiscover")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: Repository.self) { repository in
                RepositoryDetailView(repository: repository)
            }
        }
    }

    @ViewBuilder
    private var searchContent: some View {
        switch viewModel.state {
        case .idle:
            status(symbol: "magnifyingglass", title: "GitHub repositories")
                .accessibilityIdentifier("idle-title")
        case .loading:
            ProgressView("Searching...").accessibilityIdentifier("loading-state")
        case .empty(let query):
            status(symbol: "tray", title: "No repositories found", message: query)
                .accessibilityIdentifier("empty-state")
        case .results(_, let repositories):
            List(repositories) { repository in
                NavigationLink(value: repository) { RepositoryRowView(repository: repository) }
                    .accessibilityIdentifier("repository-\(repository.id)")
            }
            .listStyle(.plain)
        case .failed(_, let failure):
            TimelineView(.periodic(from: .now, by: 1)) { context in
                VStack(spacing: 16) {
                    status(symbol: "exclamationmark.triangle", title: "Search unavailable", message: failure.message)
                        .accessibilityIdentifier("error-state")
                    if let date = failure.retryAt, date > context.date {
                        Text(date, style: .relative).font(.caption).foregroundStyle(.secondary)
                    }
                    Button {
                        viewModel.retry()
                    } label: {
                        Label("Retry", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.bordered)
                    .disabled(!viewModel.canRetry(at: context.date))
                    .accessibilityIdentifier("retry-search")
                }
                .padding()
            }
        }
    }

    private func status(symbol: String, title: String, message: String? = nil) -> some View {
        VStack(spacing: 12) {
            Image(systemName: symbol).font(.largeTitle).foregroundStyle(.secondary)
            Text(title).font(.headline)
            if let message {
                Text(message).font(.subheadline).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding()
    }
}

#Preview {
    ContentView(viewModel: AppCompositionRoot.makeSearchViewModel())
}
