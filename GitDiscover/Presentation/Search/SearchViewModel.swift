import Combine
import Foundation

enum SearchState: Equatable, Sendable {
    case idle
    case loading(query: String)
    case results(query: String, repositories: [Repository])
    case empty(query: String)
    case failed(query: String, failure: SearchFailure)
}

struct SearchFailure: Equatable, Sendable {
    let message: String
    let retryAt: Date?

    init(error: any Error, now: Date) {
        if case .rateLimited(let date) = error as? RepositorySearchError {
            retryAt = max(now, date ?? now.addingTimeInterval(60))
        } else {
            retryAt = nil
        }
        switch error as? RepositorySearchError {
        case .connectivity:
            message = "Unable to connect. Check your internet connection."
        case .server:
            message = "GitHub is temporarily unavailable."
        case .accessDenied:
            message = "GitHub denied this search request."
        case .decoding, .invalidResponse:
            message = "GitHub returned an unexpected response."
        case .invalidRequest:
            message = "The search request could not be created."
        case .rateLimited:
            message = "GitHub's search limit was reached. Please wait before retrying."
        case nil:
            message = "The search could not be completed. Please try again."
        }
    }
}

@MainActor
final class SearchViewModel: ObservableObject {
    @Published private(set) var searchText = ""
    @Published private(set) var state: SearchState = .idle
    private(set) var searchTask: Task<Void, Never>?

    private let useCase: SearchRepositoriesUseCase
    private let delay: any SearchDelaying
    private let now: @Sendable () -> Date
    private var generation: UInt64 = 0

    init(useCase: SearchRepositoriesUseCase, delay: any SearchDelaying = DebounceDelay(), now: @escaping @Sendable () -> Date = { Date() }) {
        self.useCase = useCase
        self.delay = delay
        self.now = now
    }

    deinit { searchTask?.cancel() }

    func updateSearchText(_ text: String) {
        searchText = text
        generation += 1
        searchTask?.cancel()
        searchTask = nil
        let query = SearchRepositoriesUseCase.normalizedQuery(text)
        guard query.count >= 2 else {
            state = .idle
            return
        }
        state = .loading(query: query)
        let currentGeneration = generation
        let useCase = useCase
        let delay = delay
        searchTask = Task { [weak self] in
            do {
                try await delay.wait()
                try Task.checkCancellation()
                guard self?.generation == currentGeneration else { return }
                let repositories = try await useCase.execute(query: query)
                try Task.checkCancellation()
                guard let self, self.generation == currentGeneration else { return }
                self.state = repositories.isEmpty
                    ? .empty(query: query)
                    : .results(query: query, repositories: repositories)
            } catch {
                guard !Task.isCancelled, let self, self.generation == currentGeneration else { return }
                if error is CancellationError || (error as? URLError)?.code == .cancelled {
                    self.state = .idle
                } else {
                    self.state = .failed(query: query, failure: SearchFailure(error: error, now: self.now()))
                }
            }
        }
    }

    func canRetry(at date: Date) -> Bool {
        guard case .failed(_, let failure) = state,
              SearchRepositoriesUseCase.normalizedQuery(searchText).count >= 2 else { return false }
        return failure.retryAt.map { date >= $0 } ?? true
    }

    func retry() {
        guard canRetry(at: now()) else { return }
        updateSearchText(searchText)
    }
}