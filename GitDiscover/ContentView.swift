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
                SearchFieldView(
                    placeholder: "Search GitHub repositories",
                    text: Binding(
                        get: { viewModel.searchText },
                        set: { viewModel.updateSearchText($0) }
                    )
                )
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
            StatusView(symbol: "magnifyingglass", title: "GitHub repositories")
                .accessibilityIdentifier("idle-title")
        case .loading:
            ProgressView("Searching...").accessibilityIdentifier("loading-state")
        case .empty(let query):
            StatusView(symbol: "tray", title: "No repositories found", message: query)
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
                    StatusView(symbol: "exclamationmark.triangle", title: "Search unavailable", message: failure.message)
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
}

#Preview {
    ContentView(viewModel: AppCompositionRoot.makeSearchViewModel())
}
