# GitDiscover

A small SwiftUI iOS application for searching and exploring public GitHub repositories. Built as a technical assessment focused on clean architecture, async cancellation, an in-memory TTL cache and unit tests.

> **Status as of November 10, 2026:** the search/detail MVP and in-scope acceptance checks are complete. The latest unit run passes all **50 test functions (85 executions)** on iPad / iOS 18.0; the five offline UI workflows also have passing results on iOS 26.4. Manual validation on iPhone and iPad across OS versions 16 through 26, live search, the external GitHub link and in-scope accessibility were confirmed.

## MVP features

- Search public GitHub repositories with at least two trimmed characters and a 400 ms debounce; display the first page of up to 30 results.
- View results in a list and open a detail screen.
- Cancel outdated searches; never show superseded responses.
- Cache successful query results in memory for 180 seconds.
- Show loading, empty, connectivity and rate-limit states.
- Run automated Domain, Data/cache and Presentation tests, plus five offline UI workflows.

## Public API

GitHub REST API: `GET https://api.github.com/search/repositories?q=<query>&per_page=30&page=1`

Public repository search does not require authentication. Unauthenticated requests to GitHub Search are rate-limited (documented at 10/minute), so the implementation uses 400 ms debounce and cache. Requests specify API version `2026-03-10`. Rate-limit responses are not automatically retried: the shared API-client actor blocks further HTTP searches across query changes until the server deadline, or for a conservative 60 seconds when no deadline is provided. Fresh cached results remain available during that cooldown. Requests already in flight are not coalesced or retroactively blocked. API details: [Search API](https://docs.github.com/en/rest/search/search), [rate limits](https://docs.github.com/en/rest/using-the-rest-api/rate-limits-for-the-rest-api), and [API versions](https://docs.github.com/en/rest/about-the-rest-api/api-versions).

URLs are built with `URLComponents` and structured query items. Query values use Foundation percent-encoding and `percentEncodedQueryItems` so literal `+`, `%` and form-query separators survive transport without changing expressions such as `C++ language:C++`. Tests cover those characters and Unicode, not just a URLComponents round trip.

## Requirements

- macOS with a compatible Xcode toolchain. The verified local toolchain is Xcode 26.4 with Swift compiler 6.3.
- iOS 16+ simulator/device.
- Internet connection to run live searches (not required for unit tests).
- No API keys, backend or third-party packages.

## Why iOS 16 is the minimum

For this assessment, iOS 16.0 is the minimum deployment target to retain broader device compatibility without giving up the capabilities required by the MVP. This preserves support for iPhone 8, iPhone 8 Plus and iPhone X, which cannot upgrade to iOS 17. For iPad, it also retains iPad (5th generation), iPad Pro 9.7-inch and iPad Pro 12.9-inch (1st generation), which cannot upgrade to iPadOS 17. These are model counts, not a measured percentage of active users.

iOS 16 supports `async/await`, `Task`, actors and cancellation, the asynchronous `URLSession.data(for:)` API, and SwiftUI `NavigationStack`. An actor-backed in-memory cache with a 180-second TTL does not require a newer OS.

Presentation uses `ObservableObject`, `@Published` and `@StateObject` instead of `@Observable`, whose native SwiftUI integration requires iOS 17. For this small two-screen app, broader compatibility takes priority over Observation's reduced boilerplate and more granular view updates. This choice does not replace the need for `@MainActor`, explicit cancellation checks or stale-response protection.

Swift 6 language mode and a recent SDK are separate from the deployment target: using a newer compiler or SDK does not require users to run that SDK's iOS version. Any newer runtime APIs must be availability-checked or have an iOS 16-compatible alternative.

Apple references: [iOS/iPadOS 16 compatible devices](https://support.apple.com/en-us/103267), [iOS 17 compatibility](https://www.apple.com/newsroom/2023/09/ios-17-is-available-today/), [iPadOS 17 compatibility](https://www.apple.com/newsroom/2023/09/ipados-17-is-now-available/), and [Observation](https://developer.apple.com/documentation/observation).

## Swift concurrency configuration

- The app, unit-test and UI-test targets use `SWIFT_VERSION = 6.0` in Debug and Release.
- Both configurations inherit `SWIFT_STRICT_CONCURRENCY = complete` from the project. Swift 6 enforces concurrency-safety violations as compiler errors.
- The app-wide `MainActor` default has been removed. Types use the compiler's nonisolated default unless an explicit annotation or protocol conformance supplies isolation. SwiftUI's own actor annotations still apply; the search ViewModel explicitly uses `@MainActor`.
- The existing approachable-concurrency setting remains enabled. `async` alone does not guarantee execution on a background thread; isolation and cancellation must still be handled deliberately.

## Run the app

1. Open `GitDiscover.xcodeproj` in Xcode.
2. Select the `GitDiscover` app scheme and an iOS 16+ simulator.
3. Build and run with **Cmd+R**.
4. Search for `swift concurrency`, open a repository, and inspect its details.

Normal launches use the live public API. For offline UI tests only, a Debug build with launch argument `--ui-testing` injects fixtures: `empty` returns no results, `offline` fails once then succeeds on retry, and `ratelimit` returns a rate-limit failure. Fixture injection is excluded from Release builds. The normal dependency graph is constructed once at the app entry point; there are no mutable global singletons.

## Run tests

1. Open the project in Xcode.
2. Run **Product > Test** (**Cmd+U**).
3. Review Domain, API/cache, Presentation and UI results in the test navigator.

Automated tests use fakes, controlled continuations and injected clocks/delays. An ephemeral `URLSession` with a local `URLProtocol` also verifies that cancellation stops underlying URL loading and produces `URLError.cancelled`, without sending traffic to GitHub. Tests do not wait for cache expiry in real time. UI tests use the production debounce and Debug-only fixtures. The separate live API smoke check was not part of the automated suite.

## Verification record

The latest unit-only Debug run on November 10, 2026, after the shared-component refactor, passed all **50 test functions / 85 executions**, with no failures or skips, on iPad (10th generation) / iOS 18.0. The `.xcresult` summary was inspected.

The earlier complete Debug run that day built and executed both test targets using the shared scheme and the new app icon: **55 passing test functions / 90 executions**, with no failures or skips, on iPhone 17 Pro / iOS 26.4. After extracting the shared search-field and status components, all **five UI workflows** passed again on that simulator, including added assertions for the search binding, clear-button state and empty-state text.

- Toolchain checked locally: Xcode 26.4, Swift compiler 6.3 and iOS Simulator SDK 26.4.
- Previous unit-only run after network-test hardening on November 9: **50 passing functions / 85 executions**, with no failures or skips, on iPhone 17 Pro / iOS 26.4.
- Earlier complete Debug test run on iPhone 17 Pro / iOS 26.4, before network-test hardening: **49 tests passed, 0 failed, 0 skipped**, with **69 executions** (44 unit-test functions / 64 unit executions, plus 5 UI tests). This is historical evidence, not the current test inventory.
- Before the final Data-layer review, the five UI tests also passed on iPhone SE (3rd generation) / iOS 17.5. Search and detail screenshots were inspected on both devices.
- Effective build settings confirm Swift 6.0, complete concurrency checking and iOS 16.0 in all three targets in both configurations, without a module-wide `MainActor` default.
- The built app's `MinimumOSVersion` is `16.0`.
- Asset compilation produced iPhone and iPad app icons from the original opaque 1024 x 1024 PNG.
- Earlier live smoke check using the production Domain/Data files, before the final API review: 30 repositories decoded for `swift concurrency`; repeating an equivalent normalized query returned the same results with **1 HTTP request total**. This was a temporary local executable, not a persistent test or alternate implementation.
- Xcode emitted destination/debugger metadata warnings during testing; they did not prevent successful execution.
- On November 10, 2026, the project owner confirmed manual execution on iPhone and iPad across OS versions 16 through 26, live search and opening the external GitHub link. Layout and accessibility checks are complete within the agreed scope; VoiceOver testing is excluded. Automated UI coverage remains offline and fixture-based.

## Implemented review fixes

- Corrected a rate-limit bypass: changing the query could previously send another HTTP request during a known cooldown. Tests first reproduced this for both HTTP 403 and 429, then verified that the shared deadline blocks new requests, allows a request at exactly the deadline, and does not block fresh cache hits. Responses without a deadline use the same conservative fallback across queries.
- Corrected literal-plus encoding: plain `queryItems` preserved `+` on the wire, where form-query parsing can treat it as a space. Parameterized tests now verify both the decoded expression and the absence of unescaped plus signs in the outgoing query, including `C++`, percent signs, separators and Unicode.
- Added real `URLSession` cancellation integration coverage, HTTP-date `Retry-After`, deadline-header precedence, malformed/negative/non-finite values and controlled overlapping rate-limit responses in both completion orders.
- The new regressions exposed a negative `X-RateLimit-Reset` bypass: `-1` was accepted as a past date, allowing another request immediately. Negative reset values now use the conservative fallback, with a failing-before/passing-after test.
- Cancellation, generation-safe publication, quoted cache keys, the exact 180-second expiry boundary and cancellation during actor writes are covered by focused tests.

### Reproduce the checks

Run these commands from the repository root. Discover a destination with `xcrun simctl list devices available`, then replace `YOUR_SIMULATOR_UDID` with an installed iOS 16+ simulator's UUID. Build outputs stay outside the repository. The commands run the complete Debug suite, unit tests only and UI tests only, respectively.

```sh
xcodebuild test \
    -project GitDiscover.xcodeproj \
    -scheme GitDiscover \
    -destination 'platform=iOS Simulator,id=YOUR_SIMULATOR_UDID' \
    -derivedDataPath /tmp/GitDiscover-validation \
    -parallel-testing-enabled NO \
    CODE_SIGNING_ALLOWED=NO -quiet

xcodebuild test \
    -project GitDiscover.xcodeproj \
    -scheme GitDiscover \
    -destination 'platform=iOS Simulator,id=YOUR_SIMULATOR_UDID' \
    -derivedDataPath /tmp/GitDiscover-validation \
    -only-testing:GitDiscoverTests \
    -parallel-testing-enabled NO \
    CODE_SIGNING_ALLOWED=NO -quiet

xcodebuild test \
    -project GitDiscover.xcodeproj \
    -scheme GitDiscover \
    -destination 'platform=iOS Simulator,id=YOUR_SIMULATOR_UDID' \
    -derivedDataPath /tmp/GitDiscover-validation \
    -only-testing:GitDiscoverUITests \
    -parallel-testing-enabled NO \
    CODE_SIGNING_ALLOWED=NO -quiet
```

## Architecture

```text
Presentation (SwiftUI + SearchViewModel)
                 |
                 v
Domain (Repository + SearchRepositoriesUseCase + protocol)
                 ^
                 |
Data (GitHub REST client + cache decorator + actor TTL cache)
```

- **Cancellation:** new input invalidates the old query generation and cancels the stored task; guarded completion prevents stale results, even if a test double returns after cancellation.
- **Cache:** trim and locale-neutral lowercase keys, collapsing whitespace outside quoted expressions while preserving quoted whitespace. The original trimmed expression is sent to GitHub without collapsing or lowercasing it. TTL is 180 seconds from successful insertion; `now < expiresAt` is fresh, and exactly 180 seconds is expired. Empty successes are cached; failures and canceled responses are not. Cancellation is checked again after the clock await on the actor write path.
- **Rate limits:** the API-client actor owns the shared network cooldown below the cache decorator, keeping server backoff independent of presentation state while allowing network-free cache hits.
- **Details:** use fields returned in the search response; no redundant API call.
- **Scope:** intentionally one small app target with three separated layers; no external dependencies.

Source layout:

```text
GitDiscover/
    GitDiscoverApp.swift           App lifecycle and ViewModel ownership
    ContentView.swift              Search and navigation
    App/                          Composition root and Debug-only UI fixtures
    Domain/                       Entity, search contract, errors and use case
    Data/                         HTTP client, DTOs, repositories and actor cache
    Presentation/                 Search state/ViewModel, row and detail views
        Components/               Reusable search field and status views
GitDiscoverTests/
    Domain/                       5 tests, including invalid-query parameters
    Data/                         32 API, transport and cache tests
    Presentation/                 13 ViewModel tests
GitDiscoverUITests/              5 offline UI workflow tests
```

The cache actor guarantees race-free storage, not in-flight request coalescing: concurrent misses for the same key can both fetch. There is no persistent storage or proactive cache-size bound. Expired entries are removed when their keys are read; process termination clears the cache.

See [`SPEC.md`](SPEC.md), [`ARCHITECTURE.md`](ARCHITECTURE.md), [`TEST_PLAN.md`](TEST_PLAN.md), and [`TASKS.md`](TASKS.md) for implementation and acceptance criteria.

## Repository and delivery preparation

The repository includes:

- [`.gitignore`](.gitignore) excludes macOS metadata, Xcode user state and generated build/test outputs. Previously tracked `.DS_Store` and `xcuserdata` files have been removed from the Git index, not from disk; local Xcode settings are preserved. Those index removals are staged locally.
- The shared [`GitDiscover` scheme](GitDiscover.xcodeproj/xcshareddata/xcschemes/GitDiscover.xcscheme), used for local validation, includes the app, unit tests and UI tests.
- The [app-icon catalog](GitDiscover/Assets.xcassets/AppIcon.appiconset) includes original magnifying-glass/branch artwork as an opaque 1024 x 1024 PNG. Xcode generates the required device sizes; no GitHub logo or third-party artwork is included.
- The project is distributed under the [MIT License](LICENSE).

## Validation and scope

Core search/detail/cache functionality and in-scope acceptance checks are complete:

| Area | Completed verification |
|---|---|
| Automated unit tests | 50 functions / 85 executions passed on iPad / iOS 18.0 after the shared-component refactor. |
| Runtime compatibility | Project owner confirmed execution on iPhone and iPad across OS versions 16 through 26. |
| Search and details | Live search and the external GitHub link confirmed manually; cancellation, cache and error handling covered by automated tests. |
| Layout and accessibility | Project owner confirmed supported layouts and in-scope accessibility, including Dynamic Type and keyboard/navigation behavior. |

VoiceOver testing is outside the agreed scope. Completed checks are tracked in [TASKS.md](TASKS.md), with coverage and acceptance details in [TEST_PLAN.md](TEST_PLAN.md).

The app intentionally has no authentication, pagination, favorites or offline persistence. The response DTO reads `items` only: `total_count` and `incomplete_results` are not displayed. Live availability depends on connectivity and anonymous GitHub limits. The in-memory cache has no size bound, persistence or in-flight request coalescing; these are documented MVP trade-offs, not promised features.

## License

Distributed under the [MIT License](LICENSE). See the license for permissions, conditions and the warranty disclaimer.
