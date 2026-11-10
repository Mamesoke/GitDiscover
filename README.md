# GitDiscover

A small SwiftUI iOS application for searching and exploring public GitHub repositories. Built as a technical assessment focused on clean architecture, async cancellation, an in-memory TTL cache and unit tests.

> **Status as of November 9, 2026:** the search/detail MVP is implemented with Domain, Data/cache and Presentation layers. After network-test hardening, all **50 unit-test functions (85 executions)** pass on iOS 26.4. The five UI workflows passed in an earlier run and were not rerun for this change. The deployment target is iOS 16.0, but execution on iOS 16 remains unverified.

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

- macOS with a compatible Xcode toolchain. Xcode 26.4 with Swift compiler 6.3 is verified; older toolchains have not been validated for this project configuration.
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

The latest Debug run built and executed the complete unit-test target after adding network regressions and fixing negative reset-header handling: **50 passing test functions, 85 executions, no failures or skips**, on iPhone 17 Pro / iOS 26.4. Its `.xcresult` summary was inspected. UI tests, Release compilation and live API checks were not repeated for this change; their earlier evidence is listed separately below.

- Toolchain checked locally: Xcode 26.4, Swift compiler 6.3 and iOS Simulator SDK 26.4.
- Earlier complete Debug test run on iPhone 17 Pro / iOS 26.4, before network-test hardening: **49 tests passed, 0 failed, 0 skipped**, with **69 executions** (44 unit-test functions / 64 unit executions, plus 5 UI tests). This is historical evidence, not the current test inventory.
- Before the final Data-layer review, the five UI tests also passed on iPhone SE (3rd generation) / iOS 17.5. Search and detail screenshots were inspected on both devices.
- `build-for-testing` succeeded in Release for the complete app and test targets. No Swift concurrency errors or Swift compiler warnings were reported in the final builds.
- Effective build settings confirm Swift 6.0, complete concurrency checking and iOS 16.0 in all three targets in both configurations, without a module-wide `MainActor` default.
- Release test compilation requires `ENABLE_TESTABILITY=YES` for unit tests' `@testable import`. This is a validation-command override only; production Release testability settings remain unchanged.
- The built app's `MinimumOSVersion` is `16.0`.
- Earlier live smoke check using the production Domain/Data files, before the final API review: 30 repositories decoded for `swift concurrency`; repeating an equivalent normalized query returned the same results with **1 HTTP request total**. This was a temporary local executable, not a persistent test or alternate implementation.
- Xcode emitted destination/debugger metadata warnings during testing; they did not prevent successful execution.
- Runtime compatibility with iOS 16 has not been verified: no iOS 16 simulator runtime is currently installed. Compilation against a newer SDK is not a substitute for running on the minimum supported OS.
- On November 9, 2026, the user confirmed that the app works in manual use. The device, OS version and individual scenario outcomes were not specified; this confirmation is not evidence that every manual acceptance case or iOS 16 has been verified. Automated UI coverage uses offline fixtures.

## Implemented review fixes

- Corrected a rate-limit bypass: changing the query could previously send another HTTP request during a known cooldown. Tests first reproduced this for both HTTP 403 and 429, then verified that the shared deadline blocks new requests, allows a request at exactly the deadline, and does not block fresh cache hits. Responses without a deadline use the same conservative fallback across queries.
- Corrected literal-plus encoding: plain `queryItems` preserved `+` on the wire, where form-query parsing can treat it as a space. Parameterized tests now verify both the decoded expression and the absence of unescaped plus signs in the outgoing query, including `C++`, percent signs, separators and Unicode.
- Added real `URLSession` cancellation integration coverage, HTTP-date `Retry-After`, deadline-header precedence, malformed/negative/non-finite values and controlled overlapping rate-limit responses in both completion orders.
- The new regressions exposed a negative `X-RateLimit-Reset` bypass: `-1` was accepted as a past date, allowing another request immediately. Negative reset values now use the conservative fallback, with a failing-before/passing-after test.
- Cancellation, generation-safe publication, quoted cache keys, the exact 180-second expiry boundary and cancellation during actor writes are covered by focused tests. This is not a guarantee of defect-free behavior or minimum-OS runtime compatibility.

### Reproduce the checks

Run these commands from the repository root. Discover a destination with `xcrun simctl list devices available`, then replace `YOUR_SIMULATOR_UDID` with an installed iOS 16+ simulator's UUID. Build outputs stay outside the repository. The Debug command runs both unit and UI tests; the second command is an optional UI-only run on the same or another simulator.

To reproduce the latest **unit-only** verification scope, add `-only-testing:GitDiscoverTests` to the first command.

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
    -only-testing:GitDiscoverUITests \
    -parallel-testing-enabled NO \
    CODE_SIGNING_ALLOWED=NO -quiet

xcodebuild build-for-testing \
    -project GitDiscover.xcodeproj \
    -scheme GitDiscover \
    -configuration Release \
    -destination 'platform=iOS Simulator,id=YOUR_SIMULATOR_UDID' \
    -derivedDataPath /tmp/GitDiscover-release \
    CODE_SIGNING_ALLOWED=NO ENABLE_TESTABILITY=YES -quiet
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
GitDiscoverTests/
    Domain/                       5 tests, including invalid-query parameters
    Data/                         32 API, transport and cache tests
    Presentation/                 13 ViewModel tests
GitDiscoverUITests/              5 offline UI workflow tests
```

The cache actor guarantees race-free storage, not in-flight request coalescing: concurrent misses for the same key can both fetch. There is no persistent storage or proactive cache-size bound. Expired entries are removed when their keys are read; process termination clears the cache.

See [`SPEC.md`](SPEC.md), [`ARCHITECTURE.md`](ARCHITECTURE.md), [`TEST_PLAN.md`](TEST_PLAN.md), and [`TASKS.md`](TASKS.md) for implementation and acceptance criteria.

## Remaining work and limitations

No missing core search/detail/cache feature was identified in this documentation review. Implementation is not the same as complete runtime acceptance:

| Area | Remaining work |
|---|---|
| Minimum OS | Run on an actual iOS 16 simulator/device; no iOS 16 runtime is installed locally. |
| Manual acceptance | Record scenario-level outcomes, device and OS for live search, cancellation, errors and opening the GitHub link. A general user confirmation does not close this checklist. |
| Layout and accessibility | Verify iPad, large Dynamic Type, VoiceOver and keyboard/navigation behavior; these checks have no recorded scenario-level results. |
| Repository hygiene | Add a `.gitignore` and remove staged `.DS_Store` / Xcode `xcuserdata` from version control without deleting local user settings. |
| Delivery automation | No CI workflow or committed shared scheme exists. Local autogenerated schemes work; share a scheme and add CI if repeatable automated delivery is required. |
| Publication | Choose a license before open-source release. The app-icon catalog has no image files; supply artwork before distribution. |

These are tracked in [TASKS.md](TASKS.md), with coverage and acceptance details in [TEST_PLAN.md](TEST_PLAN.md). The network-test hardening closes the previously listed transport and deadline-header coverage gaps; it does not perform repository cleanup or complete manual acceptance.

The app intentionally has no authentication, pagination, favorites or offline persistence. The response DTO reads `items` only: `total_count` and `incomplete_results` are not displayed. Live availability depends on connectivity and anonymous GitHub limits. The in-memory cache has no size bound, persistence or in-flight request coalescing; these are documented MVP trade-offs, not promised features.

## License

No license file is present. Choose a license explicitly before publishing the project as open source; do not assume a license is granted by default.
