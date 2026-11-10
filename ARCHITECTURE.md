# GitDiscover — Architecture & Engineering Decisions

**Status:** implemented architecture, checked against source on November 10, 2026. Runtime evidence and remaining validation are documented in [TEST_PLAN.md](TEST_PLAN.md).

## 1. Architectural principle

The app uses **lightweight Clean Architecture + MVVM** within one Xcode app target, plus separate unit-test and UI-test targets. Layers are separated by folders and protocol dependencies, not separate Swift packages:

```text
SwiftUI Views -> SearchViewModel -> SearchRepositoriesUseCase
                                           |
                                           v
                                  RepositorySearching (Domain protocol)
                                           ^
                                           |
                        CachedRepositorySearchRepository (Data)
                              |                          |
                              v                          v
                    SearchResultCache (actor)   RemoteGitHubRepository
                                                         |
                                                         v
                                                  GitHubAPIClient
                                                         |
                                                         v
                                            HTTPClient / URLSessionHTTPClient
                                                         |
                                                         v
                                                   URLSession
```

Domain imports Foundation where needed, but no SwiftUI, URLSession, GitHub DTOs, JSON or cache implementation details. These boundaries are conventions inside one module, not compiler-enforced module boundaries.

## 2. Actual project structure

```text
GitDiscover/
  GitDiscoverApp.swift
  ContentView.swift                 # search screen and NavigationStack
  App/
    AppCompositionRoot.swift
    UITestRepository.swift           # Debug-only offline UI fixtures
  Domain/
    Models/
      Repository.swift
    Repositories/
      RepositorySearching.swift
      RepositorySearchError.swift
    UseCases/
      SearchRepositoriesUseCase.swift
  Data/
    Network/
      GitHubAPIClient.swift
      GitHubSearchResponseDTO.swift  # both response and repository DTOs
      HTTPClient.swift               # protocol and URLSession adapter
    Repositories/
      RemoteGitHubRepository.swift
      CachedRepositorySearchRepository.swift
    Cache/
      SearchResultCache.swift
      TimeProvider.swift
  Presentation/
    Components/
      SearchFieldView.swift          # search input and clear button
      StatusView.swift               # symbol, title and optional message
    Search/
      SearchDelay.swift
      SearchViewModel.swift
      RepositoryRowView.swift
    Detail/
      RepositoryDetailView.swift
GitDiscoverTests/
  Domain/SearchRepositoriesUseCaseTests.swift
  Data/CachedRepositorySearchRepositoryTests.swift
  Data/GitHubAPIClientTests.swift
  Data/URLSessionHTTPClientTests.swift
  Presentation/SearchViewModelTests.swift
  TestSupport.swift
GitDiscoverUITests/
  GitDiscoverUITests.swift
```

The app entry point and search screen remain at the app folder root. DTOs share one file; there is no separate `SearchView` or `GitHubRepositoryDTO` file.

Shared SwiftUI components live in `Presentation/Components`. `SearchFieldView` receives a placeholder and a `Binding<String>`; `StatusView` receives display values only. Neither depends on the search ViewModel. `ContentView` retains navigation, state selection, retry handling and the binding that forwards text changes (including clear) to the ViewModel's cancellation/debounce logic.

## 3. Domain contracts

The immutable Domain entity is `Hashable` for typed navigation (and therefore also `Equatable`):

```swift
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

protocol RepositorySearching: Sendable {
    func search(query: String) async throws -> [Repository]
}
```

`SearchRepositoriesUseCase` depends only on `RepositorySearching`. It trims surrounding whitespace/newlines and returns `[]` without fetching for fewer than two characters. It preserves internal whitespace, case and qualifiers when delegating.

The use case checks task cancellation before validation and after the repository await. Repository errors, including `CancellationError`, propagate to its caller.

## 4. Data layer

### GitHubAPIClient / RemoteGitHubRepository

- `RemoteGitHubRepository` delegates to the shared `GitHubAPIClient` actor.
- Requests use `URLComponents` and `percentEncodedQueryItems`; the encoded value excludes literal `+`, `&`, `=`, `;` and `%` so form-query parsing cannot change the search expression.
- Requests target `/search/repositories?q=<query>&per_page=30&page=1`, with GitHub JSON Accept, API version `2026-03-10` and `GitDiscover` User-Agent headers.
- `HTTPClient` is an injected `Sendable` protocol; its production adapter directly awaits `URLSession.data(for:)` using an ephemeral session.
- The client validates HTTP responses/status and maps DTOs to Domain. Nullable/absent description and language decode as `nil`. Repository URLs must use `https://github.com`; an invalid item fails the mapping.
- Only `items` is decoded. Total counts, incomplete-results metadata and update timestamps are not consumed.
- `CancellationError` is preserved, and `URLError.cancelled` becomes `CancellationError`. Other transport errors map to connectivity failure.
- `RepositorySearchError` distinguishes invalid requests/responses, access denial, server failure, decoding, connectivity and rate limiting. Presentation owns the user-facing wording.

### Shared rate-limit cooldown

HTTP 429 is rate-limited. HTTP 403 is rate-limited when quota/retry headers or the error body indicate it; a generic 403 maps to access denial.

The client uses its injected `TimeProvider` to interpret `Retry-After` (seconds or HTTP date), then `X-RateLimit-Reset`, falling back to 60 seconds. Its stored deadline never shortens when overlapping responses arrive. Subsequent queries cannot make HTTP requests before that deadline; requests are allowed at equality. No automatic retry or background scheduler exists.

The cache decorator sits above this gate, so fresh cached results remain usable. Actor isolation protects cooldown state, but suspended HTTP calls can overlap: this is not request serialization or coalescing. A newly observed limit does not cancel already in-flight requests.

### CachedRepositorySearchRepository

Apply a simple repository decorator:

```text
search(query)
  -> normalize cache key
  -> lookup key in actor cache
  -> if fresh: return value (no network)
  -> check cancellation
  -> await remote.search(query)
  -> check cancellation
  -> store successful result under normalized key
  -> return result
```

Caching stays below Domain, so Domain tests use a mock repository without cache knowledge.

**Cancellation/cache race rule:** the decorator checks cancellation around awaits; cache insertion checks both before and after the clock await. A response already observed as canceled is not inserted. Cancellation after a completed insertion cannot retroactively undo it. Empty successful arrays are cached; errors are not.

**Cache key:** one decorator helper trims and lowercases with locale-neutral semantics, collapses whitespace outside quotes and preserves quoted whitespace/escaped quotes. Reads and writes use the same key. The remote still receives the original trimmed expression.

**Concurrent same-key requests:** parallel misses can both fetch. The actor guarantees data-race safety, not request coalescing.

### SearchResultCache actor

- Private dictionary `[String: CacheEntry]`.
- `Entry` contains `[Repository]` and `expiresAt`.
- `value(for:)` returns only if `now < expiresAt`; equality is expired and removes the entry.
- `insert(_:for:)` records expiry as insertion time + 180 seconds.
- `TimeProvider: Sendable` exposes `func now() async -> Date`; production uses `Date()`, tests manually advance an actor clock.
- Dictionary reads/writes happen after clock retrieval without further suspension; cancellation is checked after that await.
- No proactive eviction, capacity bound or disk persistence exists. Untouched expired keys remain until lookup or cache deallocation. TTL uses wall-clock time, not a monotonic clock.

## 5. Presentation and cancellation

`SearchViewModel` is `@MainActor`, uses `ObservableObject` + `@Published`, and is owned by the app's `@StateObject`. `ContentView` observes the same instance. This supports iOS 16 without requiring Observation.

The explicit UI state is:

```text
idle
loading(query)
results(query, repositories)
empty(query)
failed(query, displayError)
```

Flow for **every** text change:

1. Update `searchText`.
2. Increment a `generation` token.
3. Call `searchTask?.cancel()` immediately, including pending debounce.
4. If trimmed query has fewer than 2 characters, set `.idle`, clear displayed results and stop.
5. Replace previous results with `.loading(query)`; this state includes the debounce interval.
6. Start a stored `Task` that awaits an injected `SearchDelaying` strategy, then checks cancellation/generation before calling the use case.
7. After the use-case await, check cancellation and the captured generation before publishing results or empty state.
8. Ignore completion from canceled/superseded tasks. A current dependency cancellation restores idle; other current errors become `SearchFailure`.

Production `DebounceDelay` uses `Task.sleep(for: .milliseconds(400))`. Unit tests use immediate or gated delays; UI tests use the production delay. The **same stored task** awaits both debounce and search. There is no detached task; deinitialization cancels pending work.

The generation guard is necessary even when tasks are canceled: mocks, adapters or a race may deliver a late success after cancellation.

**Cached-result fast path:** the generation guard still applies. A cache hit is not exempt from stale-result protection.

**Retry:** `SearchFailure` supplies messages and an optional deadline. A one-second `TimelineView` updates the countdown/Retry availability. Retry reuses the current valid query and debounce; the API client independently enforces the shared network cooldown.

## 6. Detail & navigation

- `ContentView` owns a `NavigationStack`, with `NavigationLink(value:)` and a typed `Repository` destination.
- Rows show full name, a nonempty description if available, language (or `Unknown language`) and stars.
- Detail shows full name, owner, description (or `No description provided`), language (or `Unknown language`), stars and forks.
- A `Link` opens the validated `htmlURL`. Detail uses the selected entity without a second request.

## 7. Composition and dependency injection

`GitDiscoverApp` owns a single ViewModel constructed through `AppCompositionRoot`:

```text
URLSession -> GitHubAPIClient -> RemoteGitHubRepository
TimeProvider -> SearchResultCache
(RemoteGitHubRepository + SearchResultCache) -> CachedRepositorySearchRepository
CachedRepositorySearchRepository -> SearchRepositoriesUseCase -> SearchViewModel
```

Dependencies use initializer injection; there is no DI framework, mutable global singleton or service locator. Normal launches build the real graph with an ephemeral `URLSession`.

In Debug only, `--ui-testing` replaces the repository with `UITestRepository`. It returns fixture results, an empty result for `empty`, a first-attempt connectivity failure for `offline`, and a rate limit for `ratelimit`. This bypasses the production HTTP/cache graph: UI tests verify views and interactions, not real transport or cache behavior. Release excludes fixture injection.

## 8. ADRs (small, explicit decisions)

| ID | Decision | Reason / trade-off |
|---|---|---|
| ADR-01 | Single target, 3 layers | Clear boundaries without SPM overhead |
| ADR-02 | SwiftUI + MVVM | Native UI, presentation state easily tested |
| ADR-03 | `async/await` + cancellable `Task` | Cancellation propagates to `URLSession` |
| ADR-04 | `actor` in-memory TTL cache | Race-free storage, no disk complexity |
| ADR-05 | Clock injection | Deterministic expiration tests |
| ADR-06 | Generation token in ViewModel | Protects UI even if cancellation is ignored downstream |
| ADR-07 | Details from search result | Meets requirements with less networking |
| ADR-08 | No external dependencies | Easy reviewer setup, smaller surface area |
| ADR-09 | `ObservableObject` on iOS 16 | Broader runtime compatibility instead of iOS 17-only Observation |
| ADR-10 | API-client cooldown below cache | Shared server backoff across queries without blocking fresh cached results |
| ADR-11 | Injected HTTP client and search delay | Offline transport tests and deterministic debounce/concurrency tests |

## 9. Build configuration and remaining checks

- All three targets use Swift 6 language mode; project settings enable complete strict-concurrency checking in Debug and Release.
- There is no module-wide `MainActor` default. Presentation and composition explicitly opt in; cache and client isolate mutable state in actors. Approachable concurrency remains enabled.
- The configured iOS 16.0 deployment target is not evidence of execution on iOS 16. That runtime check is still open.
- Cancellation tests use injected transports and a real ephemeral `URLSession` / local `URLProtocol` integration test that observes request start/stop. The test protocol has no mutable state and uses request-specific notification observations; no global mutable handler or external network is involved.
- Source boundaries, cache memory policy and wall-clock TTL are deliberate simplicity trade-offs; no additional framework or module split is required for this MVP.
