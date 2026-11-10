# GitDiscover — Product & Technical Specification

**Status:** as-built MVP specification, reviewed on November 10, 2026; implementation and in-scope acceptance checks are complete.

**Version:** MVP 1.0  
**Platform:** iOS 16+  
**Language / UI:** Swift 6 language mode, SwiftUI  
**API:** GitHub REST API — Search repositories

## 1. Goal

GitDiscover is a small, maintainable iOS application for discovering public GitHub repositories. This iOS technical assessment prioritizes correctness, cancellation, cache behavior, testability and clear responsibilities over extra features or sophisticated design. The features below are implemented; execution evidence and open checks are tracked separately in [TEST_PLAN.md](TEST_PLAN.md) and [TASKS.md](TASKS.md).

## 2. In scope

- One search screen with a text field and list of matching repositories.
- Search requests to GitHub's public REST API.
- Cancel an in-flight request when the input changes; prevent old responses from replacing newer results.
- A detail screen for a selected repository, with at least three useful fields.
- An in-memory query cache with a **180-second TTL**, bypassing the network on a valid hit.
- Swift Testing unit tests for Domain, Data and Presentation, plus XCTest UI workflows.
- Clear loading, empty, error and rate-limit UI states.
- Brief README documenting setup and implementation choices.

## 3. Out of scope

Authentication, favorites, persistence, pagination, filters, suggestions, trending discovery, analytics, background refresh, custom backend, third-party dependencies, elaborate UI or advanced DI frameworks. Do not add these unless explicitly requested after the MVP passes all tests.

## 4. API contract

- **Endpoint:** `GET https://api.github.com/search/repositories`
- **Parameters:** `q=<percent-encoded query>`, `per_page=30`, `page=1`.
- **Headers:** `Accept: application/vnd.github+json`, `X-GitHub-Api-Version: 2026-03-10`, `User-Agent: GitDiscover`.
- **Authentication:** not required for public repositories.
- **Important limitation:** unauthenticated Search API has a dedicated limit of **10 requests/minute**; it may return HTTP 403/429. Search requests also count toward applicable primary/secondary limits. Do not automatically retry on a rate-limit response.
- **Response consumed:** `items: [...]`; `total_count`, `incomplete_results` and `updated_at` are not decoded or displayed.
- **Mapping:** `id`, `name`, `full_name`, `description?`, `language?`, `stargazers_count`, `forks_count`, `html_url`, `owner.login`.
- **URL validation:** mapped repository links must use `https` and host `github.com`; an invalid item URL fails response mapping with a decoding error.
- **Encoding:** `URLComponents` and percent-encoded query items preserve literal plus signs, percent signs, query separators and Unicode.
- Decode nullable and absent optional fields gracefully. Do not presume a repository always has a description or primary language.

API reference: https://docs.github.com/en/rest/search/search
Rate limit reference: https://docs.github.com/en/rest/using-the-rest-api/rate-limits-for-the-rest-api

## 5. Functional requirements and acceptance criteria

### FR-01 — Search

1. The initial screen displays a search field with appropriate placeholder and an empty/idle state.
2. Trim leading/trailing whitespace and newlines. The trimmed query must contain at least **2 Swift characters** to search. Invalid input returns `[]` without a repository call in the use case and stays idle in Presentation.
3. Use a **400 ms debounce** after the most recent text change.
4. Submit valid input to GitHub and show up to 30 results in a native SwiftUI `List`.
5. Each result shows `fullName`, optional description, language fallback and stars.
6. Empty results produce an explicit empty state, not an error.

**AC:** Typing `swift concurrency` and stopping produces a search. Empty/whitespace input never sends a request. Results appear in a list.

### FR-02 — Cancellation and stale-result protection

1. **On each text change**, immediately invalidate the previous search generation and cancel any existing debounce/search task (not only when the next debounced request starts).
2. The current task must propagate cancellation to the `URLSession` request, rather than merely hiding its result.
3. Check cancellation before and after awaited operations; never publish data or errors from a canceled or superseded generation.
4. On a new query, hide/clear results from the previous query while loading to avoid displaying stale data.
5. Clearing the input cancels work and restores the idle state.
6. The screen must never show results for a query other than the current input.

**AC:** Start query A, then type query B before A completes. A is canceled/ignored and only B can update the list. If A ignores cancellation and completes late, it still cannot overwrite B.

### FR-03 — Repository detail

1. Tap a row to navigate using SwiftUI `NavigationStack`.
2. Display full name, description (fallback: `No description provided`), owner, language (fallback: `Unknown language`), stars and forks.
3. Use the selected search result; no second API call is made.
4. Provide an `Open on GitHub` link using the URL validated during DTO mapping.

**AC:** The selected repository opens a detail view with at least three clearly labeled values.

### FR-04 — TTL query cache

1. Cache **successful search results only** in memory; empty successful result arrays are cacheable.
2. Cache key: trim, collapse whitespace **outside quoted expressions**, preserve quoted whitespace and escaped quotes, then lowercase with locale-neutral `lowercased()`. The same key is used for reads and writes. The API receives the trimmed expression with its original case and internal whitespace.
3. **TTL = 180 seconds**, measured from the successful insertion time.
4. Entry is fresh if `now < expiresAt`; expired if `now >= expiresAt`.
5. Fresh hit returns cached repositories without any HTTP request.
6. Miss/expired hit calls the API; only a successful, non-canceled response updates cache.
7. Errors must not replace valid cached entries or be cached as successes.
8. The cache must be concurrency-safe (`actor`). Inject a clock/time provider so expiry tests do not sleep.
9. Expired entries are removed on lookup. There is no capacity bound, proactive eviction, disk persistence or same-key in-flight request coalescing.

**AC:** A second identical search within 180 s does not increase API-client call count. A search after 180 s does.

### FR-05 — Error and state handling

- Distinguish idle, loading, results, empty, recoverable failure and GitHub rate-limit failures.
- Provide a concise retry action for a non-empty valid query, subject to API limits.
- Cancellation must not appear as an error or trigger a retry.
- Handle bad URL/building, non-2xx responses, malformed JSON and connectivity errors without crashing.
- Treat HTTP 403/429 as potentially rate-limited, but distinguish generic 403 from rate limiting using headers/body where possible; show a useful message and avoid aggressive retries.
- The shared `GitHubAPIClient` actor enforces a cooldown across query changes. `Retry-After` seconds or an HTTP date take precedence over `X-RateLimit-Reset`; absent/unusable deadlines fall back to 60 seconds. Overlapping responses cannot shorten the stored deadline.
- During cooldown, fresh cache hits still work. New HTTP searches are blocked while `now < deadline`; a new request is allowed at the deadline. Already in-flight requests are not retroactively canceled by a later rate-limit response.
- Presentation disables Retry until the deadline and refreshes the countdown once per second; retry still uses the normal debounce. No automatic retry is scheduled.
- No hardcoded access token or credential in source control.

## 6. Non-functional requirements

- Architecture: distinct `Presentation -> Domain <- Data` dependency direction.
- UI: 100% SwiftUI, `@MainActor` for presentation state.
- Observation: `ObservableObject` / `@Published`, owned through `@StateObject`, to preserve iOS 16 compatibility.
- Async: structured Swift concurrency (`async/await`); no callback-based networking.
- Dependencies: Foundation and Apple frameworks only.
- Tests: deterministic, no real network, avoid sleeps in cache tests.
- Keep the app intentionally simple and explain any deviation from this spec in README.

## 7. Implementation and acceptance status

Completed checks combine observed automated results with the project owner's manual validation on November 10, 2026.

- [x] Live API search is implemented and manually confirmed by the project owner.
- [x] New input immediately cancels its task; injected transport tests verify propagation, and a real `URLSession` / local `URLProtocol` integration test verifies underlying URL-loading cancellation.
- [x] Superseded success/error responses cannot update Presentation in controlled-continuation tests.
- [x] Detail shows name, description, owner, language, stars, forks and a GitHub link; fixture UI tests exercise navigation and fallback values, and the project owner confirmed opening the external link.
- [x] Cache tests verify fresh hits, exact 180-second expiry, normalization and canceled writes.
- [x] After the shared-component refactor, all 50 unit-test functions / 85 executions pass on iPad (10th generation) / iOS 18.0, with no failures or skips; all five UI workflows also passed on iPhone 17 Pro / iOS 26.4.
- [x] Deployment is configured for iOS 16.0; the project owner confirmed execution on iPhone and iPad across OS versions 16 through 26.
- [x] Documentation describes the actual source layout, behavior, test evidence and agreed scope.
- [x] The production graph uses no credentials, authentication or third-party packages.
- [x] Complete acceptance coverage for search, details, cancellation, cache and errors through manual confirmation and automated tests.
- [x] Complete supported-layout and in-scope accessibility checks, including Dynamic Type, focus, keyboard/navigation and control usability.

VoiceOver testing is excluded from the agreed scope. Repository hygiene, publication preparation and completed test hardening are listed in [TASKS.md](TASKS.md). Authentication, favorites and pagination remain out of scope, not unfinished MVP requirements.
