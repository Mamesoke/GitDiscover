# GitDiscover — Implementation Status & Remaining Work

**Reviewed:** November 9, 2026. This is a status/backlog document, not a list of features still to implement. Core MVP functionality is present. Open acceptance checks, coverage improvements and delivery preparation are separated below.

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
| Latest Debug unit suite | After network-test hardening: all 50 unit-test functions / 85 executions passed, no failures or skips, iPhone 17 Pro / iOS 26.4. |
| Earlier complete Debug suite | Retained pre-hardening result: 49 passing tests / 69 executions, including five UI workflows, no failures or skips, iPhone 17 Pro / iOS 26.4. UI workflows were not rerun for this change. |
| Earlier UI run | Previously recorded: all five workflows passed on iPhone SE (3rd generation) / iOS 17.5 before the final Data-layer review; screenshots were inspected. Not repeated here. |
| Release test compilation | Previously recorded successful `build-for-testing` with command-only `ENABLE_TESTABILITY=YES`. This is compilation evidence, not a Release runtime test. |
| Live API smoke check | Previously recorded before the final API review: 30 decoded results and one HTTP request across two equivalent queries. Not a persistent automated test. |
| Manual use | Prior delivery notes record a general successful-use confirmation on November 9, 2026, without device/OS or per-scenario outcomes. |
| Documentation update | Source/test inventory, project settings, scheme availability, Xcode 26.4 / Swift compiler 6.3 and installed simulators checked. No new build, test run or live request. |

The literal-plus encoding and cross-query cooldown defects identified in the earlier technical review are already fixed and have regression tests. They are not open tasks.

## 3. Open MVP acceptance checks

These are verification gaps, not evidence that the corresponding feature is absent.

- [ ] **Minimum OS:** run the app and relevant tests on iOS 16. No iOS 16 runtime is installed locally; document a device run or use a compatible test environment.
- [ ] **Live acceptance:** record each manual scenario in [TEST_PLAN.md](TEST_PLAN.md), including device/OS, connectivity errors, rapid query changes, clear and the external GitHub link.
- [ ] **Supported layouts:** check iPad, small screens and large Dynamic Type with the current source.
- [ ] **Accessibility:** record VoiceOver labels, focus/navigation, keyboard dismissal and control usability. Existing identifiers and fixture tests are not a full accessibility audit.

## 4. Completed network coverage hardening

These additions strengthen confidence without expanding the MVP feature set. They are included in the latest passing unit run.

- [x] Verify real `URLSessionHTTPClient` cancellation with a local `URLProtocol`, observing request start/stop and `URLError.cancelled` without network access.
- [x] Cover HTTP-date `Retry-After`, malformed/negative/non-finite values and deadline-header precedence.
- [x] Control overlapping rate-limit responses in both completion orders and verify that the longest deadline wins.
- [x] Fix the exposed negative-reset bypass: reject negative `X-RateLimit-Reset` timestamps and fall back to 60 seconds. Regression reproduced before the fix and passing afterward.

The additions reuse clocks, gates and spies, with no real TTL waits, new dependencies or public API calls. Five API test functions plus one transport test were added. The total source inventory is now 55 test functions / 90 executions, but only the 50-function unit target was executed for this change.

## 5. Repository and publication preparation

- [ ] Add `.gitignore` rules for macOS metadata, Xcode user state and generated build/test outputs.
- [ ] Unstage/untrack the currently staged `.DS_Store` and `xcuserdata` files, preserving local settings. No cleanup was performed by this documentation update.
- [ ] If automated delivery is required, commit a shared `GitDiscover` scheme and add a macOS/Xcode CI workflow. An autogenerated scheme currently supports local `xcodebuild`; no shared scheme or CI workflow is committed.
- [ ] Select an explicit license before open-source publication; no license file is present.
- [ ] Provide app-icon artwork before distribution; the existing catalog contains slots without image files.

These items do not prevent reviewing or running the local assessment MVP, but should not be mistaken for completed release preparation.

## 6. Deliberate MVP limits

- Only page 1, up to 30 repositories; no result totals or incomplete-results indicator.
- Public unauthenticated API, subject to GitHub availability and rate limits.
- In-memory cache only; no size bound, proactive eviction or request coalescing.
- One app module; layer boundaries are folder/protocol conventions.
- No favorites, authentication, pagination UI, filter controls, persistent storage, background refresh, user profiles, README preview, trending rankings, custom backend, telemetry or third-party dependencies.

Do not treat these exclusions as unfinished requirements or implement them without a separate scope decision.
