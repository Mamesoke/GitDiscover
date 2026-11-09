# GitDiscover — Test Plan

**Reviewed:** November 9, 2026.

**Frameworks:** Swift Testing in `GitDiscoverTests`; XCTest/XCUIApplication in `GitDiscoverUITests` for UI automation. The split is intentional.

**Principle:** automated tests run without GitHub access. Unit tests use controlled time and continuations; UI tests use fixtures and the real 400 ms debounce.

## 1. Test inventory and execution evidence

| Suite | Source | Test functions | Executions including parameters |
|---|---|---:|---:|
| Domain | [SearchRepositoriesUseCaseTests.swift](GitDiscoverTests/Domain/SearchRepositoriesUseCaseTests.swift) | 5 | 9 |
| Cache/decorator | [CachedRepositorySearchRepositoryTests.swift](GitDiscoverTests/Data/CachedRepositorySearchRepositoryTests.swift) | 11 | 14 |
| API client | [GitHubAPIClientTests.swift](GitDiscoverTests/Data/GitHubAPIClientTests.swift) | 15 | 23 |
| Presentation | [SearchViewModelTests.swift](GitDiscoverTests/Presentation/SearchViewModelTests.swift) | 13 | 18 |
| UI workflows | [GitDiscoverUITests.swift](GitDiscoverUITests/GitDiscoverUITests.swift) | 5 | 5 |
| **Total** | | **49** | **69** |

The retained final Debug `.xcresult`, dated November 9, 2026, was inspected during this documentation update: **49 passing tests, 69 device executions, zero failures and zero skips**, on iPhone 17 Pro / iOS 26.4. The table matches the current source inventory. This is a saved execution result, **not a new test run**.

Earlier delivery notes also record:

- Five UI workflows passed on iPhone SE (3rd generation) / iOS 17.5 before the final Data-layer review, with search/detail screenshots inspected.
- Release `build-for-testing` succeeded with command-only `ENABLE_TESTABILITY=YES`; this does not prove Release runtime behavior.
- A separate, temporary live API smoke check decoded 30 results and observed one HTTP request for two equivalent queries before the final API review. It is not part of the offline automated suite.

No build, new test run or live request was made for this documentation-only change. Reproduction commands are in [README.md](README.md#reproduce-the-checks). No iOS 16 runtime is installed locally, so minimum-OS execution remains open.

## 2. Boundaries and fixtures actually used

- [TestSupport.swift](GitDiscoverTests/TestSupport.swift) supplies repository fixtures, `RepositorySpy`, an actor-backed `TestTimeProvider` and a continuation-based `SuspensionGate`.
- Domain tests inject `RepositorySearching` spies and assert forwarded queries, results and errors.
- Cache tests inject a fake repository and clock, advance time directly and count remote calls. Cancellation tests suspend the remote or cache-write clock.
- API tests generate small JSON payloads in memory and inject `HTTPSpy` / `SuspendedHTTPClient`. They do **not** use a real `URLSession` or `URLProtocol`.
- Presentation tests inject immediate/gated delays and a `ControlledRepository` that can report cancellation yet resolve later, with different repository IDs for old/new searches.
- UI tests launch a Debug app with `--ui-testing`. `UITestRepository` replaces the repository below the use case, bypassing production HTTP/cache. `empty`, `offline` and `ratelimit` select fixture behaviors.
- Unit tests do not sleep for TTL expiry or guess response order. UI tests wait for elements and use the production debounce.

## 3. Domain coverage — implemented

All D-cases are covered by [SearchRepositoriesUseCaseTests.swift](GitDiscoverTests/Domain/SearchRepositoriesUseCaseTests.swift).

| ID | Given | When | Expected |
|---|---|---|---|
| D-01 | Mock returns repositories | Search valid `swift` | Same Domain repositories returned |
| D-02 | Query has surrounding whitespace | Search an expression with internal spaces/qualifiers | Trimmed expression forwarded without internal changes |
| D-03 | Empty, whitespace or one-character query | Execute invalid input | `[]` and **no repository call** |
| D-04 | Mock throws network error | Search valid query | Error propagates, not silently swallowed |
| D-05 | Mock throws `CancellationError` | Search valid query | Cancellation propagates; not converted to empty success |

## 4. Cache/decorator coverage — implemented

All C-cases are covered by [CachedRepositorySearchRepositoryTests.swift](GitDiscoverTests/Data/CachedRepositorySearchRepositoryTests.swift); some share a test function. TTL is 180 seconds, with fake time rather than real waits.

| ID | Sequence | Expected remote calls |
|---|---|---|
| C-01 | Search `swift` first time | 1 |
| C-02 | Search `swift`, advance +30s, search `swift` | 1 total |
| C-03 | Search `swift`, advance +179s, repeat | 1 total |
| C-04 | Search `swift`, advance **exactly +180s**, repeat | 2 total |
| C-05 | Search `swift`, then `kotlin` | 2 total |
| C-06 | Search equivalent case/whitespace variants of `swift concurrency` | 1 total (normalized key) |
| C-07 | First search returns `[]`, repeat before TTL | 1 total (empty success cached) |
| C-08 | First remote request throws, retry | 2 total (errors not cached) |
| C-09 | Remote throws cancellation or returns late after cancellation; cancel during the write's clock await | No insertion; a later request fetches |
| C-10 | Cache expired, second remote result differs | New data returned and cache updated |

Additional assertions preserve the original network expression and distinguish quoted whitespace so `"my  topic"` and `"my topic"` do not share a key. The exact-expiry test also checks that refreshed data is reused on the next lookup.

## 5. Network and DTO coverage — implemented

Covered by [GitHubAPIClientTests.swift](GitDiscoverTests/Data/GitHubAPIClientTests.swift). Request counts refer to the injected HTTP client, not real internet traffic.

| ID | Scenario | Expected |
|---|---|---|
| N-01 | HTTP 200 valid JSON | Correct DTO-to-domain mapping |
| N-02 | Nullable or absent description/language | Decode succeeds with `nil`; separate UI tests cover fallbacks |
| N-03 | HTTP 403/429 with headers/body | Typed rate-limit failure, parsed deadline/fallback and no automatic retry; generic 403 is access denied |
| N-04 | HTTP 500 | Meaningful server failure |
| N-05 | HTTP 200 malformed JSON | Decoding error, no crash |
| N-06 | Spaces, `+`, qualifiers, `/`, `%`, separators and Unicode | Request preserves the decoded expression; no raw plus sign in encoded query; expected headers and paging parameters |
| N-07 | Cancellation error or cancellation during suspended fake HTTP call | Cancellation propagates, fake observes task cancellation and late success is rejected |
| N-08 | Relative, non-HTTPS or non-GitHub repository URL | Mapping fails with decoding error |
| N-09 | Non-HTTP response | Invalid-response failure |
| N-10 | Connectivity failure | Distinct connectivity error |
| N-11 | New query before/at a shared cooldown deadline | No extra HTTP call before the deadline; a request is permitted at equality |
| N-12 | Fresh cache entry while another query is rate-limited | Cached result still returned; uncached queries remain blocked |

**Boundary:** N-07 proves the task's cancellation state reaches the injected transport. It does not assert that `URLSessionHTTPClient` stops an actual URL loading request. That integration test remains open.

## 6. Presentation coverage — implemented

Covered by [SearchViewModelTests.swift](GitDiscoverTests/Presentation/SearchViewModelTests.swift).

| ID | Scenario | Expected UI state |
|---|---|---|
| P-01 | Initial view model | `.idle` |
| P-02 | Input cleared | Previous task canceled; `.idle`, no visible old result |
| P-03 | New query B entered while A is pending | A task canceled; B starts after debounce |
| P-04 | A ignores cancellation and succeeds or fails **after** B | Only B results displayed |
| P-05 | A throws cancellation | No visible error |
| P-06 | Current query returns zero items | `.empty` |
| P-07 | Current query fails | Failure enables retry for the current valid query; rate-limit retry is blocked until its deadline |
| P-08 | Current query resolves from valid cache | Correct data; no stale-generation regression |

**Key regression:** `oldSuccessOrFailureCannotOverwriteNewResults` controls two pending requests, resolves B first and then resolves canceled A as either success or failure. Final state must remain B. No timing guesses are used.

Additional tests assert the configured 400 ms duration, no fetch before a gated debounce completes, invalid input, immediate removal of old results, clearing during debounce/request, and cancellation when the ViewModel is deallocated.

## 7. Offline UI workflow coverage — implemented

| Test | Assertions |
|---|---|
| `testSearchDetailAndClear` | Fixture results, navigation, owner/language/stars/forks, link existence, back navigation and clear to idle; captures screenshots |
| `testMissingFieldsHaveDetailFallbacks` | Description and language fallback labels |
| `testEmptySearchState` | Empty state without result rows |
| `testRecoverableFailureCanBeRetried` | First fixture failure enables Retry; retry returns results |
| `testRateLimitDisablesImmediateRetry` | Error state with disabled Retry |

The tests do not tap the external GitHub link, wait through a real cooldown, inspect actual network traffic or exercise production cache behavior. Unit tests cover cache/cooldown logic separately.

## 8. Manual acceptance matrix — pending scenario-level evidence

The earlier general successful-use confirmation does not identify a device, OS or individual scenario outcomes. Recorded fixture UI passes and screenshots must not be relabeled as complete live/manual acceptance.

For each pending item, record device/model, OS, source revision, steps, result and relevant screenshots/logs.

| Status | Scenario | Evidence needed |
|---|---|---|
| Pending | Launch; use the search field; enter invalid/empty input | Idle state and no invalid search |
| Pending | Live `swift concurrency` search | Loading followed by real GitHub results |
| Pending | Open a result and tap `Open on GitHub` | Correct fields and external repository URL |
| Pending | Rapidly replace A with B; clear during a request | No old result/error reappears |
| Pending | Repeat an equivalent query before TTL | Network inspection shows no extra request |
| Automated expiry covered; manual optional | Repeat at/after TTL | Fake-clock test already proves exact boundary; inspect live traffic if manually checked |
| Pending | No-results query and offline failure/retry | Useful empty/error states and recovery |
| Pending | Rate-limit failure | Useful message/countdown, blocked early retry and no automatic retry; prefer controlled stubbing over exhausting public quota |
| Blocked locally | Run on iOS 16 | Install/use a compatible runtime or physical device; no iOS 16 runtime is currently installed |
| Pending | iPad, small screen, large Dynamic Type, VoiceOver and keyboard/navigation | Readable layout, usable controls and sensible focus/labels |

## 9. Remaining automated coverage and completion criteria

Recommended additions, not existing tests:

- Local `URLProtocol` integration coverage of real `URLSessionHTTPClient` request cancellation.
- HTTP-date `Retry-After`, malformed/negative/non-finite deadline headers and precedence when both deadline headers are present.
- Overlapping rate-limit responses with different deadlines, asserting that a shorter response cannot reduce the shared cooldown.

The existing required Domain/cache and stale-response Presentation cases are implemented and have a passing retained run. Full acceptance still requires minimum-OS and scenario-level manual checks. After code changes, rerun the affected suites; do not infer fresh success from this historical record. Keep new automated tests offline and deterministic, and report skipped/blocked checks explicitly.
