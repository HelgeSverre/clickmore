# Code cleanup evidence

## Scope and baseline

The target is the ClickMore macOS application and its first-party ClickMoreCore
library: all `Sources/` and `Tests/`, plus package wiring needed to validate them.
The coordinator owns integration and this document. The three reviewers are
read-only. The marketing `website/`, generated media, release/signing/publishing
scripts and workflows, vendored PermissionFlow implementation, OS permission
services, and Homebrew integration are excluded from edits. Build/runtime scripts
and CI are read as validation requirements.

Baseline: `976a6adcf7cdedaa588f7d81cc3e909ef303220b`, clean worktree. No existing dirty
files were included. All original public core APIs and serialized preferences are
pre-existing contracts with unknown external consumption; retain them unless
compatibility can be established. No publishing, tracker writes, or CI run is
authorized by this cleanup.

Toolchain: Apple Swift 6.2.4 (`swiftlang-6.2.4.1.4`), Xcode 26.3 (17C529), macOS
15.6 (24G84), arm64 host. `Package.resolved` pins PermissionFlow 2.11.3. CI uses
macOS 15, and release CI selects Xcode 26.2; that exact release configuration,
signing, notarization and installation are not local validation claims.

## Validation matrix

Logs are kept locally under ignored `test-results/code-cleanup/`. Source snapshots
are baseline plus a task patch SHA-256, frozen before review/testing; artifact
hashes refer to the actual binaries at the time of each check.

| Evidence / gate | Source / configuration / command (repository cwd) | Baseline outcome / artifact | Final outcome |
| --- | --- | --- | --- |
| E1 core and app tests | `ci.yml`; native arm64 Debug; `swift test` | 20 tests passed; `.build/arm64-apple-macosx/debug/ClickMorePackageTests.xctest/Contents/MacOS/ClickMorePackageTests`, SHA-256 `cfffcf281610f0ead30cb972ab7c2232823a7a3c6adc6a24b1eadbbec0d5111b` | Passed E13, 21 tests / 3 suites on A3 |
| E2 app bundle | `ci.yml`; Xcode backend universal Debug; `./script/build_and_run.sh --build` | Passed; `dist/ClickMore.app/Contents/MacOS/ClickMore`, SHA-256 `dec62c23dced9d2b2c8d690c9d6fb4a797b2478319df7f0d3688bd86baeccb8f` | Passed E14 on A3 |
| E3 executable fixture | `script/test_runtime.sh`; bundled Debug arm64 execution; `CLICKMORE_TEST_APP="$PWD/dist/ClickMore.app" ./script/test_runtime.sh --self-test` | Passed: local AppKit events, counts `[1,1,1,1]`, order `[0,1,2,3]`; E2 artifact | Passed E14 on A3 |
| E4 shell syntax | `ci.yml`; `for file in script/*.sh; do bash -n "$file" || exit; done` | Passed | Passed E15; scripts unchanged |
| E5 system delivery | Cross-process `--integration-test`, real WindowServer events | Unavailable: baseline reports `postEventAccess: false`; not executed | Gap |
| E6 release/CI | macOS 15 CI and signed universal Release, Xcode 26.2 | Not run; no authorized PR or release operation | Gap |
| E16 local Release | Shipping compile flags; `swift build --scratch-path .build/code-cleanup-release -c release --arch arm64 --arch x86_64 --product ClickMore`; assemble resources and ad-hoc-sign task-local bundle; `CLICKMORE_TEST_APP="$PWD/test-results/code-cleanup/ClickMore.app" ./script/test_runtime.sh --self-test` | Not run before edits; supplementary build-mode check | Universal compilation and arm64 local AppKit execution passed on A3; exact artifact below |

There are no observed baseline failures. The executable self-test does not prove
system event delivery, focus preservation across processes, physical drag behavior,
or x86_64 execution. Universal compilation is distinct from x86_64 runtime coverage.

## Machine inventory and invariants

| ID / owner | Representation and entry points | Invariant / interaction | Disposition |
| --- | --- | --- | --- |
| M1 App lifecycle / AppDelegate, AppController | constructed, started (timer/observers), terminating; `start`, `shutdown` | I1 normal delegate calls start once; termination cancels firing, releases button synchronously and persists | Inspected |
| M2 Click batch / AppController, ClickSequencer | idle, scheduled, pressed, between clicks, cancelling; `fire`, `run`, `cancelSequence` | I2 one batch owns poster; `firing` stays true until its task settles; each successful down gets release on completion/cancellation | Changed and verified A3, E13/E14/E16; system delivery gap E5 |
| M3 Persistence / AppController, StateStore | loaded or unreadable, dirty/debounce, saved, temporary board backup; `changed`, `persist`, test-layout methods | I3 cancelled debounce cannot save later; atomic writes; unreadable input backed up before replacement; temporary board state never replaces saved layout | Inspected |
| M4 Display and overlays / Layout, OverlayCoordinator | enabled/hidden, active/offline spots, edit/pass-through, screen topology | I4 targets on disconnected screens are skipped, trigger recovered; overlays do not intercept synthetic batches or focused settings | Inspected |
| M5 Gestures / DraggableOverlayView, TriggerView, SpotView | idle, down, threshold crossed, create/group/plain drag, up | I5 one accepted physical gesture owns its start/snapshot; tagged synthetic down events are rejected | Inspected; physical gestures deferred to E5 |
| M6 Permission / AppController, MouseAccessView | denied/granted, attention generation, animation task, guide panel | I6 firing rechecks authorization, permission cue cancels/restarts with task identity | Inspected |
| M7 Settings draft / SettingsView, SettingsWindow | delay draft/focused, committed/discarded | I7 commit before stepper/outside action/termination; validated finite bounded delay | Inspected |
| M8 Test board / TestBoardController, TestBoardView, RuntimeVerification | normal/temporary layout, pressed card, counts/order, local/system verification task | I8 close restores original state; matching down/up counts once; runtime report describes actual tested backend | B1 drawing ownership changed; local event contract verified E14/E16; external backend E5 gap |
| M9 Routing / ConnectorRouter | pure layout-to-routes calculation, angular groups and lane stations | I9 endpoints/IDs preserved, deterministic ordering; seeded fixtures cover bounded geometric cases | Verified E13; unchanged |

## Transition tables

All app transitions run on the main actor. Synchronous effects have no inter-task
interleaving; suspension points are explicitly listed.

| From | Event / guard | Owner, effects and ordering | To | Failure / retry / cancellation | Evidence |
| --- | --- | --- | --- | --- | --- |
| Idle batch | `fire`, enabled, not firing, not editing, active targets, permission | Snapshot points/delay; mark firing before scheduling task and refresh hit testing | Scheduled | Duplicate fire rejected; editing fire exits edit mode instead; empty layout adds a spot | M2 source |
| Idle sequencer | `run`, not running and authorized | Mark running, poster.begin, then post down and remember pressed point | Pressed | Busy/unauthorized throws without begin | E1 |
| Pressed | 2ms sleep completes | Recheck cancellation before posting up and clearing pressed | Between clicks / complete | Even successful delay completion enters cleanup if cancelled; shutdown's earlier release is not repeated | E12/E13 controlled regression |
| Between clicks | delay completes | Check cancellation/permission before next down | Pressed | Cancellation or revoked permission enters cleanup | M2 source |
| Active batch | cancel / disable / edit / remove existing spot or all spots / test layout / screen change | Cancel task; retain firing ownership until task resumes | Cancelling | Replacement remains rejected until old task finishes | M2 source; A1 regression |
| Any batch | remove unknown spot ID | Membership guard returns before cancellation, mutation or persistence | Unchanged | Current batch and layout are untouched | E10 missing-ID regression |
| Active sequencer | return / error / cancellation | Deferred release, poster.finish, clear running; controller then clears firing/task and refreshes | Idle | Error surfaced in message; cancellation logged | E1 |
| Pressed | shutdown | Cancel task then immediate release; clear pressed | Cancelling, no held button | Deferred cleanup must not duplicate successful release | E12/E13 termination regression |
| Dirty state | `changed` | Refresh overlay, cancel old debounce, schedule 200ms sleep | Pending save | Cancelled sleep returns without persistence | M3 source |
| Pending save / shutdown | timer completion / sync persist | Back up unreadable original if present, then atomic save of boardBackup or current state | Saved | Errors retained in message; later mutation retries | E1 store tests |
| Normal layout | `useTestLayout` | Cancel batch; save original once; replace temporary layout and enable | Temporary layout | Repeat placement retains original backup | M3/M8 source |
| Temporary layout | close / restore | Cancel batch; restore layout/preferences, clear backup, schedule save | Normal layout | Restore without backup is no-op | M3/M8 source |
| Any display state | screen notification | Cancel batch; recover trigger, rebuild connections, refresh/save | Updated display state | Empty screen list leaves trigger unchanged; offline targets retained | E1 |
| Any overlay state | refresh | Hide when disabled; otherwise reconcile panels, derive visibility/hit testing | Refreshed | No awaits; stale panel IDs closed | M4 source |
| Permission denied/granted | refresh / fire | Preflight; update state and panel; fire rejects denied state | Current permission | Sequencer also checks before each down | E1 |
| Permission cue inactive/active | attention generation changes, denied | SwiftUI cancels prior task; highlight flashes or stays on with reduced motion | Active cue, then inactive | Cancellation/disappearance clears highlight in defer; no permission grant is inferred | M6 source; OS/UI execution gap |
| Draft delay | commit / stepper / focus loss | Parse finite value, round/clamp, controller validates; stepper commits draft first | Committed | Invalid draft replaced by stored value; Escape restores stored text | M7 source |
| Gesture idle | untagged mouse down | Record pointer/position and modifier-selected mode; group move captures original layout | Pressed | Tagged synthetic down rejected by base view | M5 source |
| Gesture pressed | drag over 4-point threshold | Plain/group moves use original snapshot; creation adds one spot then moves its ID | Dragging | Under-threshold drag no-op; 64-spot cap refuses addition | M5 source; physical gesture gap E5 |
| Gesture pressed/dragging | mouse up | Plain click fires; group modifier-click suppresses firing; creation restores prior editing; clear gesture snapshot | Idle | Mouse up without accepted down is ignored by base view | M5 source |
| Board idle | mouse down on card | Remember card index | Pressed card | Down outside clears selection | M8 source |
| Pressed card | mouse up | Increment only if same card; clear pressed; publish receipt | Idle | Reset clears pressed and counts | E3 |

## Findings and module decisions

| ID | Priority / impact | Root invariant and reachable trace | Batch / acceptance | Evidence / current status |
| --- | --- | --- | --- | --- |
| A1 | Medium: click delivered to a target after its deletion | I2: trigger snapshots two targets; while suspended after first down, Settings trash removes second target; `removeSpot` leaves task alive, unlike Remove All | A1/A2: cancel only when an existing spot is removed. Controlled suspension checks removed-target suppression, one release/finish, rejected replacement during cancellation, later reuse, and missing-ID no-op | Fixed and locally verified at final A3; E7 red, E13 all21 green including all3 deletion cases; three-agent Challenge/Verify complete. OS delivery remains E5 gap |
| A3 | Medium: duplicate mouse-up and successful result after cancellation | I2: press delay becomes ready, shutdown cancels and releases synchronously, successful delay continuation resumes and unconditionally posts another up | A3: check cancellation immediately after the press delay, before posting up. Controlled sleeper queues success before cancel/release; require CancellationError, one down/up, one finish, idle owner | Fixed and locally verified at A3; E11 intermediate failure, E12 deterministic pre-fix red, E13 all21 green; fresh three-agent A Verify complete. OS delivery remains E5 gap |

Batch A1 includes controller injection of the existing sequencer and permission
check, an internal sequencer sleeper seam, and a new app test target so the
regression invokes the real `fire`/`removeSpot` path without posting OS events.
The existing public sequencer initializer and all production defaults are retained.
The control gate pauses precisely after a down; no timing race or wall-clock sleep
is used to decide when deletion happens.

E7: `swift test --filter AppControllerTests` with only the injection seams/new test
applied and original `removeSpot` behavior: 4 assertion failures in single-delete
case; Remove All case passed. Log `A1-prefixed-tests.log`. E8: full `swift test` on
fixed A1 snapshot; log `A1-tests.log`.

A1 code patch SHA-256: `d010a0d0fbb38a9fb84d64437af3f535607f7a8d187676096fcf302bf99a8885`.
E8 passed all 21 tests; test binary SHA-256
`70e79a0460f3ad19178028726594973d8d18273862d785e25ae17069cf3365ba`.
E9 A1 universal Debug bundle build and local self-test passed, artifact SHA-256
`97d8970c109df6b217150918772b5fbaba583ff9ba1b5bac71570f278974ff0e`;
logs `A1-build.log` and `A1-runtime.log`.

Challenge raised cancellation for nonexistent IDs. Its UI reachability was disputed,
but the boundary is inexpensive to preserve: A2 checks membership before cancelling
and tests that an unknown ID leaves both pending targets intact. No claim is made
that a user-visible stale-action defect was reproduced. E10 is the focused A2 test
run in `A2-tests.log`; unchanged core coverage carries forward from E8 because A2
changes only controller membership guarding and the controller test cases.

A2 patch SHA-256: `c64718e809d49c5aa41f57bcd2941ece4cd980d87de9246ec96e6f7bbd42a898`.
E10 passed all three cases; test binary SHA-256
`a518be5a5668e3158112dbec0bfc164eaef77d7dda678497251dc36164c130c5`.

## Module inventory

| ID / cluster and callers | Caller knowledge and deletion test | Decision / interface provenance | Evidence / disposition |
| --- | --- | --- | --- |
| D1 ScreenPoint, ScreenBounds, ClickSpot / app, store, routing, tests | Coordinate conversion, bounds and identity vocabulary would spread to every caller if removed | Retain baseline public/Codable shapes; compatibility unknown | E1/E8 and B Discover; inspected, retained |
| D2 Layout / AppController, runtime fixtures | Owns active-display filtering, recovery and offset-preserving movement; displays and radii are independent caller inputs | Retain deep baseline public owner | E1/E8 geometry tests; verified, retained |
| D3 Preferences, DragModifier, SavedState / controller, views, persistence | Own bounds/defaults/distinct modifiers and serialized version; removal would duplicate policy | Retain baseline serialized/public contracts | E1/E8 compatibility/roundtrip tests; verified, retained |
| D4 StateStore / AppController | Owns atomic I/O and validated reads; deletion would move persistence details to controller | Retain public load/save/url; unknown external contract. Controller still owns session backup/debounce policy | E1/E8 store tests; verified, retained |
| D5 ConnectorRouter, ConnectorRoute / ConnectionView | Computes ordered routes, sectors, lanes and endpoints; renderer supplies actual visual geometry | Retain deep public owner; spacing and radius inputs are supported choices | E8 deterministic stress tests; verified bounded fixtures |
| D6 ClickSequencer, ClickEventPosting, ClickError / controller, runtime self-test | Owns busy/permission/pressed/cancel cleanup; protocol separates platform effects | Retain baseline public APIs and new internal controlled sleeper; deletion leaks lifecycle into callers | E12/E13/E14/E16; changed/verified A3 |
| D7 RoutingFixtures, RoutingMetrics / core tests and media tooling | Own seeded fixtures and crossing/rounding metrics; removal duplicates test logic | Retain test helpers | E8; verified, retained |
| D8 AppController / delegate, views, overlays, runtime | Owns edits, persistence scheduling, permission and batch lifetime. Writable state plus callable low-level helpers previously allowed bypassing owner policy | B1: make layout/preferences setters private and changed/cancelSequence private. Existing callers already use commands/updatePreferences; no migration shim. Baseline app-internal surfaces, not public/serialized | B1 changed; verified at A3 E13/E14/E16 and B Verify |
| D9 OverlayCoordinator, OverlayPanel, ConnectionView / controller | Owns nonactivating windows, visual routing and display topology; deletion would scatter lifetime/geometry rules | Retain. Explicit screen-notification rebuild is justified. Typed diagnostics deferred: only two casts in one verification consumer, no confirmed defect, broad representation change adds little in this scope | E9; inspected/retained; display topology runtime gap |
| D10 DraggableOverlayView, TriggerView, SpotView, material/glyph, MenuAction / overlays, menu | Owns gesture state, rendering, accessibility actions and closure lifetime | Retain these owners; B1 removes unrelated global drawCentered helper from overlay module | B1 changed; verified E14/E16 and B Verify; physical gestures E5 gap |
| D11 SystemClickPoster / controller, sequencer | Owns CGEvent tagging, coordinate conversion and pointer restoration; restorePointer is genuinely caller-owned policy | Retain distinct backend and AppKit modifier adapter; no cosmetic level enum | Build only; inspected/retained; E5 gap |
| D12 AppDelegate, SettingsView, SettingsWindow, MouseAccessView / app | Own app lifecycle/window focus, delay draft and permission presentation; deletion would move those rules into unrelated callers | Retain; settings writes already use controller commands | E9 / static review; inspected/retained |
| D13 TestBoardController/View, RuntimeVerification, NativeTestPoster / app diagnostic flags | Own temporary test layout, down/up receipts and backend-specific verification | Retain baseline CLI flags. B1 moves drawCentered to TestBoard.swift as file-private implementation; all five callers already there | B1 changed; verified local backend E14/E16 and B Verify |
| D14 AppControllerTests / SwiftPM test target | Uses controlled poster/sleeper to exercise actual controller entry points | New task-local tests; retain useful injection, no compatibility shell | E7/E10 |

Batch B1 is a visibility/ownership refactor with no intended behavior change:
four controller mutation surfaces close, and one unrelated global drawing helper
becomes private to its sole consumer. No baseline public, Codable, CLI, export or
configuration interface changes. Before: callers could directly mutate state and
manually call changed/cancelSequence; the test board depended on an overlay-file
global. After: callers read state and issue semantic commands; board drawing owns
its helper. Compiler validation covers every first-party caller, E10 covers the
affected cancellation invariant, and the bundled local fixture exercises board
rendering/event delivery. Existing tests are retained; no mirror test is needed
for access-control-only edits. Typed diagnostics are an optional deferred design
proposal, not an unresolved correctness finding.

E11: B1 full integration `swift test` failed in
`terminationCanReleaseBeforeTaskResumes` (2 assertions, 3 events rather than 2).
All other tests passed; log `B1-tests.log`. This invalidates final correctness
acceptance regardless of earlier A2 passes. B1 bundle build passed (`B1-build.log`),
but its runtime fixture has not yet been used as final evidence.

The race is newly demonstrated on this task's code. Baseline source also lacked
the post-await fence, but E1 did not exercise this exact interleaving; there is no
baseline executable reproduction and no claim that the task introduced the race.
E11 is retained as an actual intermediate failure, not waived as baseline. A3
strengthens the termination regression with a
controlled sleeper that returns success after cancellation, modeling a completed
timer whose actor continuation has not yet run. E12 pre-fix deterministic replay
is recorded in `A3-prefixed-tests.log`. This repair is causally separate from the
B1 access-control/drawing refactor; it triggers a fresh three-reviewer A Verify
round covering the post-await boundary, cleanup and controller callers.

Final code snapshot A3 (also the resulting B1 implementation): baseline plus patch
SHA-256 `75e90b52d7851dcd4b853e7d83141ed311def11d14d4e6cdb40c19e1d4326335`.
The patch includes tracked source/package/test changes and the new app test file;
this evidence document is excluded to permit status updates without changing code
identity. Patch files are retained under `test-results/code-cleanup/`.

E13: `swift test`, native arm64 Debug, all 21 tests across 3 suites passed (the app
test has 3 argument cases). Test artifact SHA-256
`5b3c48b9f736177f59f1e4683c0350de388c17cc5084da414f66e2a74632bcb8`;
log `A3-tests.log`. Existing cancellation and busy tests now use controlled
continuations instead of polling to catch a brief timer window; suite has a
one-minute test limit.

E14: universal Debug build and local AppKit self-test passed, binary SHA-256
`4b2420d48b0eeedcec5ca538941793ef68fb9fb94125ea7244b542640903603b`;
logs `A3-build.log`, `A3-runtime.log`. Counts/order remain `[1,1,1,1]` and
`[0,1,2,3]`. E15: final shell syntax and `git diff --check` passed.

E16: universal Release compiled with the shipping `--arch arm64 --arch x86_64`
flags and Xcode backend, using the same local toolchain as E14. Resources were
staged with `script/stage_package_resources.sh`, bundle signed ad hoc, and
`lipo -verify_arch arm64 x86_64` passed. Local AppKit self-test passed with the
same counts/order on arm64. Tested executable:
`test-results/code-cleanup/ClickMore.app/Contents/MacOS/ClickMore`, SHA-256
`fc6c31768d8e7fada80e7dc029ca5c99fa8d7e688cfc5f78bf2c72c85abbdc3b`.
Logs: `A3-release-build.log`, `A3-release-runtime.log`. This is a local optimized
artifact, not a notarized distribution. Dependency lock SHA-256 throughout:
`0e6426f7adb707b24c5729f2e3bc9d8dba50808003f74232aacea58005067f0a`.

Hypotheses not promoted to findings: reorder/move during a batch retain the
documented snapshot; there is insufficient evidence that this violates intended
behavior. Cooperative cancellation outside termination can wait for actor
resumption; no permanent held-button failure was demonstrated. Repeated start is
not a production entry path (AppDelegate starts once). No stale completion can
clear a replacement because firing remains true until cleanup finishes.

## Round log

| Round | Frozen snapshot / assignments | Evidence and limits |
| --- | --- | --- |
| A Discover | baseline; review1 lifecycle, review2 retries/concurrency, review3 consumers/coverage | Three independent read-only reviewers. E1–E4 baseline checks passed. |
| A Challenge | A1 patch `d010a0d…`; review1 executable/regression, review2 consumers/evidence, review3 atomicity/cleanup | E7–E9. Review raised unknown-ID cancellation boundary; resolved in A2 before Verify. |
| A Verify | A2 patch `c64718e…`; review1 consumers/evidence, review2 atomicity/recovery, review3 executable/regression | All three returned no code findings; added missing-ID no-op to documentation. E10 passed; E8 core coverage retained. Sweep A complete. |
| B Discover | A2; review1 core/geometry/persistence, review2 overlays/gestures/poster, review3 app/settings/test board | Inventory complete; selected B1 visibility/helper ownership changes; retained deep owners and deferred optional typed diagnostics. |
| B Challenge | B1 patch `8198a42…`; review1 app behavior, review2 depth/core scope, review3 callers/retirement | No structural defect; E11 caught A3 cancellation race. Trailing blank removed. A correctness repair completed before final B verification. |
| A Verify repeat | A3 patch `75e90b5…`; review1 executable/orderings, review2 consumers/evidence, review3 atomicity/cleanup | Trigger: E11 duplicate release. All three scoped reviewers found no further defect; E12 red/E13 green/E14 runtime green. Earlier unrelated A2 coverage carried forward. |
| B Verify | Resulting A3 patch `75e90b5…`; review1 depth/scope, review2 callers/retirement, review3 behavior | All three returned no code findings. E13–E16 validate final composition. Only evidence bookkeeping followed this dispatch. |

## Current verification status

Both sweeps are **locally verified** at final A3. Two confirmed correctness findings
are fixed; five app-internal mutation/helper surfaces were narrowed or localized.
Every inventory entry has a disposition; no confirmed in-scope defect is left open.
No public core or persisted/CLI interface was removed.

Remaining limits: E5 real OS posting/physical gestures require macOS permission;
E6 hosted CI, exact Xcode 26.2 release, Developer ID signing/notarization and
installation were not run. Intel binaries were compiled but not executed. UI
permission animation, physical display unplug/replug and persistence failure
injection were inspected rather than exhaustively exercised. Finite deterministic
and seeded tests do not prove exhaustive concurrency or geometry safety. No push,
PR, release or deployment was performed during the cleanup sweep. Its changes
were subsequently committed as `c869ae87fe645f8d2c55cffb93e69e583d59e18d`.

## Release follow-up

The user subsequently authorized committing, pushing, and cutting a release.
Release preparation advances `Info.plist` to 0.1.3 (build 4) and adds the changelog
at `docs/releases/0.1.3.md`. App/core/test sources are unchanged from final A3, so
E13–E16 remain applicable to their behavior; hosted CI will validate the actual
release commit and versioned artifacts.

The release-only scope also replaces existing process-mask changes with explicit
private-file creation in `script/ci_signing.sh` and `.github/workflows/release.yml`,
as required by the user's global instructions. Credential files are created at
mode 600 before secret bytes are written; the temporary keychain receives an
explicit mode 600. Shell syntax, plist lint, diff whitespace and a harmless local
file-write/mode probe passed. Three read-only reviewers check credential ordering,
workflow integration and release-note accuracy before publication.

Release patch identity before this bookkeeping:
`0aa4c080c2e6062e23d9be091a3213538943f84639d434e296c55e44537546a1`.
The first release review identified that the existing-assets guard omitted the
two certificate paths. The final patch adds both before any trap or write; a
sentinel test confirmed that an existing installer certificate causes an early
failure and preserves its bytes. The three reviewers rechecked this narrow delta
with prior release-path coverage carried forward.
Signing/notarization, hosted CI and Homebrew installation remain pending until
the release workflow completes; no earlier local self-test clears those gates.
