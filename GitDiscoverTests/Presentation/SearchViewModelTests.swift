import Foundation
import Testing
@testable import GitDiscover

@MainActor
struct SearchViewModelTests {
    @Test func initialStateIsIdleAndDebounceIs400Milliseconds() {
        let model = makeModel(repository: RepositorySpy())
        #expect(model.state == .idle)
        #expect(model.searchText.isEmpty)
        #expect(DebounceDelay.duration == .milliseconds(400))
    }

    @Test(arguments: ["", " ", "s", " s "])
    func invalidInputDoesNotStartSearch(text: String) async {
        let remote = RepositorySpy()
        let model = makeModel(repository: remote)
        model.updateSearchText(text)
        #expect(model.state == .idle)
        #expect(model.searchTask == nil)
        #expect(await remote.queries.isEmpty)
    }

    @Test func debounceMustCompleteBeforeRepositoryIsCalled() async {
        let gate = SuspensionGate()
        let remote = RepositorySpy()
        let model = makeModel(repository: remote, delay: GateDelay(gate: gate))
        model.updateSearchText("swift")
        await gate.waitUntilEntered()
        #expect(await remote.queries.isEmpty)
        await gate.release()
        await model.searchTask?.value
        #expect(await remote.queries == ["swift"])
    }

    @Test func clearingDuringDebounceCancelsWithoutFetching() async {
        let gate = SuspensionGate()
        let remote = RepositorySpy()
        let model = makeModel(repository: remote, delay: GateDelay(gate: gate))
        model.updateSearchText("swift")
        let previous = model.searchTask
        await gate.waitUntilEntered()
        model.updateSearchText("")
        #expect(previous?.isCancelled == true)
        #expect(model.state == .idle)
        await gate.release()
        await previous?.value
        #expect(await remote.queries.isEmpty)
    }

    @Test func clearingDuringRequestCancelsAndRejectsLateData() async throws {
        let remote = ControlledRepository()
        let model = makeModel(repository: remote)
        model.updateSearchText("swift")
        let previous = model.searchTask
        await remote.waitUntilStarted("swift")
        model.updateSearchText("")
        await remote.waitUntilCancelled("swift")
        #expect(model.state == .idle)
        await remote.resolve("swift", with: .success([try makeRepository()]))
        await previous?.value
        #expect(model.state == .idle)
    }

    @Test(arguments: [false, true])
    func oldSuccessOrFailureCannotOverwriteNewResults(oldFails: Bool) async throws {
        let remote = ControlledRepository()
        let model = makeModel(repository: remote)
        let repositories = [try makeRepository(id: 2)]
        model.updateSearchText("swift")
        let previous = model.searchTask
        await remote.waitUntilStarted("swift")
        model.updateSearchText("kotlin")
        let current = model.searchTask
        await remote.waitUntilCancelled("swift")
        await remote.waitUntilStarted("kotlin")
        #expect(previous?.isCancelled == true)
        #expect(model.state == .loading(query: "kotlin"))
        await remote.resolve("kotlin", with: .success(repositories))
        await current?.value
        #expect(model.state == .results(query: "kotlin", repositories: repositories))
        let oldResult: Result<[Repository], any Error> = oldFails
            ? .failure(TestFailure.offline) : .success([try makeRepository(id: 1)])
        await remote.resolve("swift", with: oldResult)
        await previous?.value
        #expect(model.state == .results(query: "kotlin", repositories: repositories))
    }

    @Test func newInputImmediatelyClearsDisplayedResults() async throws {
        let remote = ControlledRepository()
        let model = makeModel(repository: remote)
        model.updateSearchText("swift")
        await remote.waitUntilStarted("swift")
        await remote.resolve("swift", with: .success([try makeRepository()]))
        await model.searchTask?.value
        model.updateSearchText("kotlin")
        #expect(model.state == .loading(query: "kotlin"))
        await remote.waitUntilStarted("kotlin")
        await remote.resolve("kotlin", with: .success([]))
        await model.searchTask?.value
    }

    @Test(arguments: [false, true])
    func cancellationIsNotPresentedAsFailure(urlCancellation: Bool) async {
        let error: any Error = urlCancellation ? URLError(.cancelled) : CancellationError()
        let model = makeModel(repository: RepositorySpy(result: .failure(error)))
        model.updateSearchText("swift")
        await model.searchTask?.value
        #expect(model.state == .idle)
    }

    @Test func emptySuccessShowsEmptyState() async {
        let model = makeModel(repository: RepositorySpy())
        model.updateSearchText("  swift  ")
        await model.searchTask?.value
        #expect(model.state == .empty(query: "swift"))
    }

    @Test func failureCanBeRetriedWithCurrentQuery() async throws {
        let remote = RepositorySpy(result: .failure(RepositorySearchError.connectivity))
        let model = makeModel(repository: remote)
        model.updateSearchText("swift")
        await model.searchTask?.value
        #expect(model.canRetry(at: Date()))
        await remote.setResult(.success([try makeRepository()]))
        model.retry()
        await model.searchTask?.value
        #expect(await remote.queries == ["swift", "swift"])
        #expect(model.state == .results(query: "swift", repositories: [try makeRepository()]))
    }

    @Test func rateLimitRetryIsBlockedUntilDeadline() async {
        let now = Date(timeIntervalSince1970: 1_000)
        let deadline = now.addingTimeInterval(60)
        let remote = RepositorySpy(result: .failure(RepositorySearchError.rateLimited(retryAt: deadline)))
        let model = SearchViewModel(useCase: SearchRepositoriesUseCase(repository: remote), delay: ImmediateDelay(), now: { now })
        model.updateSearchText("swift")
        await model.searchTask?.value
        #expect(!model.canRetry(at: now))
        #expect(model.canRetry(at: deadline))
        model.retry()
        #expect(await remote.queries.count == 1)
    }

    @Test func cacheHitPublishesCurrentResultsWithoutRemoteCall() async throws {
        let remote = RepositorySpy(result: .success([try makeRepository()]))
        let repository = CachedRepositorySearchRepository(remote: remote, cache: SearchResultCache(timeProvider: TestTimeProvider()))
        let model = makeModel(repository: repository)
        model.updateSearchText("swift")
        await model.searchTask?.value
        model.updateSearchText("")
        model.updateSearchText("  SWIFT  ")
        await model.searchTask?.value
        #expect(await remote.queries == ["swift"])
        #expect(model.state == .results(query: "SWIFT", repositories: [try makeRepository()]))
    }

    @Test func deallocationCancelsPendingDebounce() async {
        let gate = SuspensionGate()
        var model: SearchViewModel? = makeModel(repository: RepositorySpy(), delay: GateDelay(gate: gate))
        let isReleased = { [weak model] in model == nil }
        model?.updateSearchText("swift")
        let pending = model?.searchTask
        await gate.waitUntilEntered()
        model = nil
        #expect(isReleased())
        #expect(pending?.isCancelled == true)
        await gate.release()
        await pending?.value
    }

    private func makeModel(repository: any RepositorySearching, delay: any SearchDelaying = ImmediateDelay()) -> SearchViewModel {
        SearchViewModel(useCase: SearchRepositoriesUseCase(repository: repository), delay: delay)
    }
}

private struct ImmediateDelay: SearchDelaying {
    func wait() async throws {}
}

private struct GateDelay: SearchDelaying {
    let gate: SuspensionGate
    func wait() async throws { await gate.wait() }
}

private actor ControlledRepository: RepositorySearching {
    private var pending: [String: CheckedContinuation<[Repository], any Error>] = [:]
    private var startedWaiters: [String: CheckedContinuation<Void, Never>] = [:]
    private var cancelledWaiters: [String: CheckedContinuation<Void, Never>] = [:]
    private var started: Set<String> = []
    private var cancelled: Set<String> = []

    func search(query: String) async throws -> [Repository] {
        try await withTaskCancellationHandler {
            try await suspend(query)
        } onCancel: {
            Task { await self.recordCancellation(query) }
        }
    }

    private func suspend(_ query: String) async throws -> [Repository] {
        try await withCheckedThrowingContinuation { continuation in
            pending[query] = continuation
            started.insert(query)
            startedWaiters.removeValue(forKey: query)?.resume()
        }
    }

    private func recordCancellation(_ query: String) {
        cancelled.insert(query)
        cancelledWaiters.removeValue(forKey: query)?.resume()
    }

    func waitUntilStarted(_ query: String) async {
        guard !started.contains(query) else { return }
        await withCheckedContinuation { startedWaiters[query] = $0 }
    }

    func waitUntilCancelled(_ query: String) async {
        guard !cancelled.contains(query) else { return }
        await withCheckedContinuation { cancelledWaiters[query] = $0 }
    }

    func resolve(_ query: String, with result: Result<[Repository], any Error>) {
        pending.removeValue(forKey: query)?.resume(with: result)
    }
}