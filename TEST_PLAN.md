# GitDiscover — Test Plan

**Reviewed:** November 10, 2026.

**Frameworks:** Swift Testing in `GitDiscoverTests`; XCTest/XCUIApplication in `GitDiscoverUITests` for UI automation. The split is intentional.

**Principle:** automated tests run without GitHub access. Unit tests use controlled time and continuations; UI tests use fixtures and the real 400 ms debounce.

## 1. Test inventory and execution evidence

| Suite | Source | Test functions | Executions including parameters |
|---|---|---:|---:|
| Domain | [SearchRepositoriesUseCaseTests.swift](GitDiscoverTests/Domain/SearchRepositoriesUseCaseTests.swift) | 5 | 9 |
| Cache/decorator | [CachedRepositorySearchRepositoryTests.swift](GitDiscoverTests/Data/CachedRepositorySearchRepositoryTests.swift) | 11 | 14 |
| API client | [GitHubAPIClientTests.swift](GitDiscoverTests/Data/GitHubAPIClientTests.swift) | 20 | 43 |
| URLSession integration | [URLSessionHTTPClientTests.swift](GitDiscoverTests/Data/URLSessionHTTPClientTests.swift) | 1 | 1 |
| Presentation | [SearchViewModelTests.swift](GitDiscoverTests/Presentation/SearchViewModelTests.swift) | 13 | 18 |
| UI workflows | [GitDiscoverUITests.swift](GitDiscoverUITests/GitDiscoverUITests.swift) | 5 | 5 |
| **Total inventory** | | **55** | **90** |

The latest unit-only Debug run on November 10, 2026, after the shared-component refactor, executed **all 50 unit-test functions / 85 executions**, with zero failures or skips, on iPad (10th generation) / iOS 18.0. The `.xcresult` summary was inspected.

The earlier complete Debug run that day executed **all 55 test functions / 90 executions**, including the five UI workflows, with zero failures or skips, on iPhone 17 Pro / iOS 26.4. Its `.xcresult` summary was inspected. This local run used the shared scheme and compiled the new original app icon.

Earlier delivery notes also record:

- The unit-only run after network-test hardening on November 9 passed all 50 unit-test functions / 85 executions on iPhone 17 Pro / iOS 26.4, with zero failures or skips.
- A complete Debug run, before this hardening, passed all then-existing 49 tests / 69 executions on iPhone 17 Pro / iOS 26.4, including the five UI workflows.
- Five UI workflows passed on iPhone SE (3rd generation) / iOS 17.5 before the final Data-layer review, with search/detail screenshots inspected.
- A separate, temporary live API smoke check decoded 30 results and observed one HTTP request for two equivalent queries before the final API review. It is not part of the offline automated suite.

The network regressions first reproduced acceptance of a negative reset timestamp; the corrected client rejects it and the tests pass. Automated runs make no live API requests. Reproduction commands are in [README.md](README.md#reproduce-the-checks): the first runs both targets, the second reproduces the latest unit-only scope and the third runs UI tests only. Manual runtime validation on iPhone and iPad across OS versions 16 through 26 was confirmed by the project owner on November 10, 2026.

## 2. Boundaries and fixtures actually used

- [TestSupport.swift](GitDiscoverTests/TestSupport.swift) supplies repository fixtures, `RepositorySpy`, an actor-backed `TestTimeProvider` and a continuation-based `SuspensionGate`.
- Domain tests inject `RepositorySearching` spies and assert forwarded queries, results and errors.
- Cache tests inject a fake repository and clock, advance time directly and count remote calls. Cancellation tests suspend the remote or cache-write clock.
- API tests generate small JSON payloads in memory and inject `HTTPSpy`, `SuspendedHTTPClient` or `GatedHTTPClient`. Separate transport integration coverage uses a real ephemeral `URLSession` with a local `URLProtocol`.
- The transport test observes `startLoading` before canceling, then requires `stopLoading` and a canceled-URL error before session cleanup. Unique request URLs isolate notification observations; no mutable global test handler or real network is used. A test time limit bounds a missing callback.
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
| N-13 | HTTP-date `Retry-After`; both deadline headers present | Absolute date parsed; valid Retry-After seconds/date wins over reset |
| N-14 | Malformed, negative or non-finite deadline header | Invalid Retry-After falls through to valid reset or 60-second fallback; invalid reset uses fallback and blocks another query |
| N-15 | Two HTTP requests pending before either reports a rate limit | Both completion orders retain the longest deadline; another query stays blocked at the shorter deadline |

**Transport integration:** [URLSessionHTTPClientTests.swift](GitDiscoverTests/Data/URLSessionHTTPClientTests.swift) proves that canceling the adapter's task invokes `URLProtocol.stopLoading` and returns `URLError.cancelled`. This exercises the real URLSession loading lifecycle locally, not a live socket or GitHub server. N-07 separately verifies API-layer cancellation translation and rejection of late fake responses.

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
| `testSearchDetailAndClear` | Search placeholder/value, clear-button enabled state, fixture results, navigation, owner/language/stars/forks, link existence, back navigation and clear to idle; captures screenshots |
| `testMissingFieldsHaveDetailFallbacks` | Description and language fallback labels |
| `testEmptySearchState` | Empty state with title/query text and without result rows |
| `testRecoverableFailureCanBeRetried` | First fixture failure enables Retry; retry returns results |
| `testRateLimitDisablesImmediateRetry` | Error state with disabled Retry |

External GitHub-link behavior is covered by the project owner's manual validation. Cache hits, TTL expiry and cooldown behavior are covered by deterministic unit tests; offline UI fixtures cover the corresponding screen states.

After extracting `SearchFieldView` and `StatusView` on November 10, all five UI workflows passed again on iPhone 17 Pro / iOS 26.4, with no failures or skips; the `.xcresult` summary was inspected. The added assertions verify binding updates, clear-button state and optional status-message rendering. All unit tests subsequently passed on iPad / iOS 18.0 as recorded in section 1.

## 8. Completed acceptance matrix

The project owner confirmed manual execution on iPhone and iPad across OS versions 16 through 26, live search, opening the external GitHub link and in-scope accessibility on November 10, 2026. The matrix distinguishes that confirmation from automated coverage; no additional device models, screenshots or network captures are inferred.

VoiceOver testing is outside the agreed scope.

| Status | Scenario | Verification |
|---|---|---|
| Completed | Launch; use the search field; enter invalid/empty input | Domain/Presentation tests verify no invalid search; UI tests verify input and idle state |
| Completed | Live search | Project owner confirmed manual search |
| Completed | Open a result and tap `Open on GitHub` | Project owner confirmed the external link; UI tests verify detail fields |
| Completed | Rapidly replace A with B; clear during a request | Controlled-response Presentation tests verify that old results/errors cannot reappear |
| Completed | Repeat an equivalent query before TTL | Cache tests verify one remote call across equivalent queries |
| Completed | Repeat at/after TTL | Fake-clock tests prove exact 180-second expiry and refetch |
| Completed | No-results query and offline failure/retry | Unit and fixture UI tests verify empty/error states and recovery |
| Completed | Rate-limit failure | API/Presentation tests verify deadlines, blocked early retry and no automatic retry; UI test verifies disabled Retry |
| Completed | Run on iPhone and iPad across OS versions 16 through 26 | Manual execution confirmed by the project owner |
| Completed | iPhone/iPad layouts, small screens and large Dynamic Type | Manual layout and in-scope accessibility validation confirmed by the project owner |
| Completed | Focus, keyboard/navigation and control usability | Manual in-scope accessibility validation confirmed by the project owner |

## 9. Completed hardening and acceptance

The requested network hardening is implemented and passing in the latest Debug unit run:

- [x] Local `URLProtocol` coverage of real `URLSessionHTTPClient` cancellation.
- [x] HTTP-date parsing, invalid deadline values and deadline-header precedence.
- [x] Overlapping rate-limit responses in both completion orders, preserving the longest deadline.
- [x] Regression for negative `X-RateLimit-Reset`, reproduced before and passing after the production fix.

In-scope acceptance is complete through the observed automated results and the project owner's manual confirmation. VoiceOver testing is excluded. After future code changes, rerun affected suites and keep automated tests offline and deterministic.
