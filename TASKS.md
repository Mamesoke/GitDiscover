# GitDiscover — Implementation & Verification Status

**Reviewed:** November 10, 2026. Core MVP functionality and in-scope acceptance checks are complete. Automated results are recorded below; manual device, search/link and accessibility validation was confirmed by the project owner.

See [SPEC.md](SPEC.md) for behavior, [ARCHITECTURE.md](ARCHITECTURE.md) for the implemented design and [TEST_PLAN.md](TEST_PLAN.md) for test-to-requirement mapping.

## 1. Completed implementation

### Project and Domain

- [x] Reuse one Xcode app target plus dedicated unit-test and UI-test targets.
- [x] Configure iOS 16.0, Swift 6 language mode and complete concurrency checking.
- [x] Implement immutable `Repository`, `RepositorySearching` and typed `RepositorySearchError`.
- [x] Implement use-case trimming, the two-character minimum, `[]` for invalid input without fetching, and cancellation/error propagation.
- [x] Cover Domain cases D-01 through D-05.

### Data, networking and cache

- [x] Build requests with GitHub headers and encoding that preserves literal plus signs, separators, percent signs and Unicode.
- [x] Decode DTOs, handle nullable/absent fields and validate HTTPS GitHub repository URLs.
- [x] Implement injected `HTTPClient` and the production `URLSession.data(for:)` adapter.
- [x] Distinguish connectivity, server, access-denied, malformed-response and rate-limit failures.
- [x] Enforce a shared cooldown across queries, honoring server deadlines with a 60-second fallback and no automatic retries.
- [x] Implement an actor cache with injected time and a 180-second TTL, expired at equality.
- [x] Normalize keys without collapsing quoted whitespace or rewriting the remote expression.
- [x] Cache empty successes; exclude failures and observed cancellations, including cancellation during the actor write's clock await.
- [x] Cover cache cases C-01 through C-10 and API behavior, including cooldown/cache interaction.

### Presentation and UI workflows

- [x] Implement `@MainActor` ViewModel with idle/loading/results/empty/failed states.
- [x] Cancel immediately on every text change, debounce 400 ms and guard publication by generation.
- [x] Remove old results immediately, support clear/retry and gate Retry until rate-limit deadlines.
- [x] Implement typed navigation, repository details, missing-field fallbacks and a GitHub link.
- [x] Construct dependencies at the app entry point, with Debug-only offline UI fixtures.
- [x] Cover P-01 through P-08 plus debounce, retry, late failures and ViewModel deallocation.
- [x] Add five XCTest UI workflows for navigation/clear, missing fields, empty results, recoverable failure and rate limiting.

## 2. Verification record

| Evidence | Status and scope |
|---|---|
| Latest Debug unit suite | November 10, after the shared-component refactor: all 50 unit-test functions / 85 executions passed, no failures or skips, iPad (10th generation) / iOS 18.0. The `.xcresult` summary was inspected. |
| Complete Debug suite | Earlier on November 10: all 55 test functions / 90 executions passed, including five UI workflows, no failures or skips, iPhone 17 Pro / iOS 26.4. Shared scheme and original app icon included. |
| Latest UI run | After the shared-component refactor on November 10: all five UI workflows passed on iPhone 17 Pro / iOS 26.4, with no failures or skips. |
| Previous Debug unit suite | November 9, after network-test hardening: all 50 unit-test functions / 85 executions passed, no failures or skips, iPhone 17 Pro / iOS 26.4. |
| Earlier complete Debug suite | Retained pre-hardening result: 49 passing tests / 69 executions, including five UI workflows, no failures or skips, iPhone 17 Pro / iOS 26.4. |
| Earlier UI run | All five workflows passed on iPhone SE (3rd generation) / iOS 17.5 before the final Data-layer review; screenshots were inspected. |
| Live API smoke check | Previously recorded before the final API review: 30 decoded results and one HTTP request across two equivalent queries. Not a persistent automated test. |
| Manual use | November 10: project owner confirmed execution on iPhone and iPad across OS versions 16 through 26, live search, the external GitHub link, supported layouts and in-scope accessibility. |
| Local repository preparation | Metadata removed from the index while preserved on disk; ignore rules and the shared scheme checked locally. |

The literal-plus encoding and cross-query cooldown defects identified in the earlier technical review are already fixed and have regression tests. They are not open tasks.

## 3. Completed MVP acceptance checks

Manual results below were confirmed by the project owner on November 10, 2026; automated checks retain their observed execution evidence.

- [x] **Unit tests:** rerun all 50 unit-test functions / 85 executions after the shared-component refactor; no failures or skips.
- [x] **Runtime compatibility:** execute the app on iPhone and iPad across OS versions 16 through 26, including the minimum supported version.
- [x] **Search and details:** confirm live search and opening the external GitHub link manually; verify invalid input, cancellation, clear, cache and error handling through the automated coverage in [TEST_PLAN.md](TEST_PLAN.md).
- [x] **Supported layouts:** confirm iPhone/iPad layouts, small screens and large Dynamic Type.
- [x] **Accessibility:** confirm focus/navigation, keyboard dismissal and control usability.

VoiceOver testing is excluded from the agreed scope.

## 4. Completed network coverage hardening

These additions strengthen confidence without expanding the MVP feature set. They are included in the latest passing complete Debug run.

- [x] Verify real `URLSessionHTTPClient` cancellation with a local `URLProtocol`, observing request start/stop and `URLError.cancelled` without network access.
- [x] Cover HTTP-date `Retry-After`, malformed/negative/non-finite values and deadline-header precedence.
- [x] Control overlapping rate-limit responses in both completion orders and verify that the longest deadline wins.
- [x] Fix the exposed negative-reset bypass: reject negative `X-RateLimit-Reset` timestamps and fall back to 60 seconds. Regression reproduced before the fix and passing afterward.

The additions reuse clocks, gates and spies, with no real TTL waits, new dependencies or public API calls. Five API test functions plus one transport test were added. The total source inventory is 55 test functions / 90 executions; both test targets passed in the November 10 repository-preparation run.

## 5. Repository and publication preparation

- [x] Add `.gitignore` rules for macOS metadata, Xcode user state and generated build/test outputs.
- [x] Remove tracked `.DS_Store` and `xcuserdata` files from the Git index while preserving every local file and setting. Their index removals remain staged locally.
- [x] Preserve the shared [`GitDiscover` scheme](GitDiscover.xcodeproj/xcshareddata/xcschemes/GitDiscover.xcscheme) for local app, unit-test and UI-test validation.
- [x] Add an explicit [MIT license](LICENSE) and link it from the README.
- [x] Provide original [app-icon artwork](GitDiscover/Assets.xcassets/AppIcon.appiconset/AppIcon.png): opaque 1024 x 1024 PNG, wired into the asset catalog and compiled for iPhone/iPad.

Repository preparation and the in-scope acceptance checks in section 3 are complete. Publication and signing/distribution are outside this MVP validation scope.

## 6. Deliberate MVP limits

- Only page 1, up to 30 repositories; no result totals or incomplete-results indicator.
- Public unauthenticated API, subject to GitHub availability and rate limits.
- In-memory cache only; no size bound, proactive eviction or request coalescing.
- One app module; layer boundaries are folder/protocol conventions.
- No favorites, authentication, pagination UI, filter controls, persistent storage, background refresh, user profiles, README preview, trending rankings, custom backend, telemetry or third-party dependencies.

Do not treat these exclusions as unfinished requirements or implement them without a separate scope decision.
