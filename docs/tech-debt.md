# VaultExplorer — Technical Debt Audit

Generated 2026-07-30. Scope: `lib/` (Dart/Flutter, 156 files), `android/app/src/main` (Kotlin, 82 files + C++, ~15K LOC), `test/`, `.github/`. Every finding below is backed by a specific file/line, not a general impression — see "Evidence" on each.

**Execution status (2026-07-30, same day):** Phase 0 and Phase 1 have been executed — see the ✅ markers below and the per-finding "Resolution" notes. Phase 2, Phase 3, and the TD-5 standing program are still open. None of the code changes below have been run through `flutter pub get` / `flutter test` / `./gradlew testDebugUnitTest` in a real environment (this was done in a sandboxed environment with no network access) — the new CI workflow (TD-2) is exactly the mechanism that will catch anything that doesn't build clean on the first real run. Treat that first CI run as the actual verification step, not this report.

**Scoring:** `Priority = (Impact + Risk) × (6 − Effort)`, each 1–5. Higher = do sooner. This formula rewards *cheap-but-important* fixes over *expensive-but-important* ones by design — see the note on TD-5, where I've overridden the raw score for exactly that reason.

---

## Prioritized findings

| # | Finding | Category | Impact | Risk | Effort | Priority | Status |
|---|---|---|---|---|---|---|---|
| TD-2 | No test job in CI at all | Infrastructure/Test | 5 | 5 | 2 | **40** | ✅ Done |
| TD-1 | `activeSessions` map mutated from two threads without a lock | Architecture | 4 | 4 | 2 | **32** | ✅ Done |
| TD-3 | Broken Kotlin test references a renamed class | Test | 2 | 3 | 1 | **25** | ✅ Done |
| TD-11 | `docs/architecture.md` silently went missing; nothing catches that | Documentation | 3 | 2 | 1 | **25** | ✅ Done |
| TD-6 | String-matching on class name to decide locking behavior | Code | 3 | 3 | 2 | **24** | ✅ Done |
| TD-9 | Blanket global suppression of a class of stream errors | Code | 2 | 3 | 2 | **20** | Open (Phase 2) |
| TD-10 | Lint config is bare defaults only | Documentation/Code | 2 | 2 | 1 | **20** | Open (Phase 2) |
| TD-8 | `file_browser_screen.dart` god-widget (2,402 lines) | Architecture | 4 | 2 | 4 | **12** | Open (Phase 3) |
| TD-4 | Two Kotlin unit tests exist but one is an empty stub | Test | 2 | 3 | 3 | **15** | Open (Phase 2) |
| TD-7 | Local/USB unlock (and create) sheets duplicate ~2,800 lines | Code | 3 | 2 | 4 | **10** | Open (Phase 3) |
| TD-12 | `pointycastle` one major version behind (`^3.6.2` vs. 4.0.0) | Dependency | 2 | 2 | 2 | **8** | ✅ Done |
| TD-5 | Near-zero automated test coverage on the native crypto/FS engine | Test | 5 | 5 | 5 | **10\*** | Open (standing program) |

\* *TD-5's raw score is artificially low because the formula penalizes large effort regardless of stakes. Impact and Risk are both maxed — this is the cryptographic and filesystem core of a security product. I'm calling it out explicitly rather than letting the formula bury it; see the phased plan below, where it's treated as a standing program, not a single ticket.*

---

## Findings in detail

### TD-1 — `ContainerSessionRegistry.activeSessions` is written from two different threads without synchronization
**Architecture debt.** `activeSessions` is a plain `mutableMapOf<Int, ContainerSession>()`. Writes on unlock happen inside `activity.runOnUiThread { ... }` (`VaultUnlockHandlers.kt:87`, `:166`, `:241`, `:328`; `UsbContainerHandlers.kt:172`). But `handleLockContainer`'s `ContainerSessionRegistry.removeSession(volId)` call (`VaultUnlockHandlers.kt:532`, and the USB equivalent at `UsbContainerHandlers.kt:354`) runs **inside `ioExecutor.execute { ... }`**, i.e. on a background thread, *before* the `runOnUiThread` block that follows it. The per-`volId` `ReentrantReadWriteLock` in the same registry guards native calls (`ContainerFileSystem`, §3.2 of the architecture doc) but was never intended to and does not guard this map. Meanwhile the sibling registry for the exact same kind of state — `VaultBackendRegistry.sessions` — correctly uses a `ConcurrentHashMap` (`VaultBackend.kt:44`). One half of the ownership model got the thread-safe treatment; the other half didn't.

**Why it matters:** a `HashMap` under concurrent read/write without synchronization can corrupt its internal structure or produce stale/torn reads under the JVM memory model — not hypothetically, this is a textbook data race. In practice this would surface as intermittent "container appears unlocked when it isn't" or vice versa, exactly the kind of bug that's brutal to reproduce and dangerous in a vault app.

**Fix:** swap `activeSessions` to a `ConcurrentHashMap` (matches the existing sibling pattern, near-zero behavior change, ~15 minutes) — or, if ordering guarantees matter somewhere, route every mutation through `runOnUiThread` including the lock path. The former is less invasive and consistent with `VaultBackendRegistry`.

**✅ Resolution:** `activeSessions` is now a `ConcurrentHashMap` (`ContainerSessionRegistry.kt`). Audited all ~30 call sites first (`ContainerFileSystem`, `FolderDocumentProviderHandlers`, `VaultUnlockHandlers`, `UsbContainerHandlers`, `ContainerDocumentsProvider`) — every one is a plain get/set/iterate/filter/clear, all supported directly, and no code ever stores a null value, so this was a safe drop-in with no other call sites needing changes. Recorded as ADR-021.

---

### TD-2 — CI builds release APKs but never runs a test
**Infrastructure/Test debt.** `.github/workflows/Build release .yml` triggers on version tags or manual dispatch and runs `flutter build apk --release --split-per-abi`. There is no `flutter test`, no `flutter analyze`, and no `./gradlew test` step anywhere in the workflow, and no second workflow exists. This is the root cause that let TD-3 (a test file referencing a class that no longer exists) sit unnoticed — it isn't that the team is ignoring failing tests, it's that nothing has ever run them.

**Fix:** add a `pull_request`/`push`-triggered workflow that runs `flutter analyze`, `flutter test`, and `./gradlew testDebugUnitTest` before any release workflow is allowed to proceed. This is close to a pure win: cheap, and it's the prerequisite for TD-3/TD-4/TD-5 to ever matter going forward — a test suite nobody runs provides exactly the same protection as no test suite.

**✅ Resolution:** added `.github/workflows/test.yml` with three jobs — `flutter-checks` (`flutter analyze` + `flutter test`), `kotlin-unit-tests` (`./gradlew testDebugUnitTest`, with the test report uploaded as an artifact), and `architecture-doc-check` (TD-11, folded in here since it's the same kind of "make CI catch this" fix). Triggers on push to `main` and on every PR — deliberately not gated behind tags the way the release workflow is. **Caveat:** this could not be run in the sandboxed environment this was built in (no network access to fetch Flutter/Gradle dependencies), so the first real run on your infrastructure is the actual verification, not this document. If any of the existing 5 Dart test files were already failing before this change, this workflow is what will finally surface that — which is the point of TD-2, not a sign something went wrong.

---

### TD-3 — `VeraCryptSessionTest.kt` references a class that no longer exists
**Test debt.** The test calls `VeraCryptSession.activeSessions`, `VeraCryptSession.getVolumeIdByUri(...)`, `VeraCryptSession.isUnlocked(...)`, `VeraCryptSession.removeSession(...)`, and `VeraCryptSession.MAX_VOLUMES`. No such object exists anywhere in `android/app/src/main` — the equivalent live code is `ContainerSessionRegistry` (`ContainerSessionRegistry.kt`), which has the same method names and shape, strongly suggesting a rename happened and this test was never updated. This file cannot compile as part of a real test run.

**Fix:** rename `VeraCryptSession` → `ContainerSessionRegistry` throughout the file (mechanical, ~10 minutes) and confirm it passes once TD-2's CI job exists to actually run it.

**✅ Resolution — turned out to be two bugs, not one.** The rename alone wasn't sufficient: two of the four original test cases (`getFreeVolumeId skips occupied slots...`, `getFreeVolumeId returns null when all MAX_VOLUMES slots are occupied`) call `getFreeVolumeId()`, which internally reads `ContainerSessionRegistry.MAX_VOLUMES` — `by lazy { ContainerEngine.maxVolumes() }` — which resolves through `NativeEngine.getMaxVolumesNative()`. `NativeEngine` is a Kotlin `object` with `init { System.loadLibrary("vaultexplorer") }`, which runs on first access to *any* member. In a plain JVM unit test process (`src/test`, no Android runtime, no compiled `.so` on the library path) that throws `UnsatisfiedLinkError` — these two test cases could never have passed here, independent of the class-name bug. Renamed and moved to `ContainerSessionRegistryTest.kt`, kept the two tests that don't touch `MAX_VOLUMES`, replaced the two that do with two new tests covering the same class's other pure-map behavior (`getVolumeIdByUri` disambiguating between sessions, `hasAnyActiveSessions`), and left a comment explaining why `getFreeVolumeId()`'s slot-exhaustion behavior needs an instrumented test instead — this repo has no `androidTest` source set yet, so standing that up is scoped as follow-up work, not attempted here.

---

### TD-4 — `PendingResultLeakTest.kt` is a comment, not a test
**Test debt.** The entire file body is a `@Test` annotation over a function with no code, only a comment describing what the test *should* do ("Requires a test MethodChannel.Result fake ... asserting each result.error()/success() fires exactly once"). It currently passes trivially (an empty function body) while asserting nothing. The scenario it describes — a `createContainer` call with no password failing without leaking `pendingFlutterResult` into the next `pickContainer` call — sounds like a real, previously-observed bug given how specifically it's described, which makes the missing regression test more concerning, not less.

**Fix:** either implement the fake `MethodChannel.Result` and the actual assertions described, or delete the file so it stops looking like coverage that doesn't exist. Implementing it is the better outcome given the specificity of the scenario described.

---

### TD-5 — The native crypto/filesystem engine (~15,000 lines of C++) has zero automated tests
**Test debt, foundational.** Across the whole repository there are 7 test files: 3 native/Kotlin (one broken, one a stub, one with 4 real assertions) and 5 Dart (1,529 lines, reasonably substantial for the Dart layer). The C++ layer — VeraCrypt/LUKS/BitLocker session handling, FAT/NTFS/ext filesystem drivers, the USB Bulk-Only-Transport SCSI driver, all cipher/KDF primitives — has no test harness at all in this snapshot (`cpp/test/fs_scan_test.cpp` exists but is a manual scan utility, not an automated assertion-based test). This is the layer that, if wrong, silently corrupts or destroys a person's encrypted data.

**Fix (phased, not a single ticket — see below):** start with the highest-value, lowest-effort slice: golden-file round-trip tests (create container → write known files → lock → unlock → read back byte-identical) for each of the 6 supported formats, run in CI headlessly against the compiled native lib. This doesn't require a device/emulator if the native lib can be exercised via a JVM unit test with JNI loaded — worth confirming feasibility as the first spike.

---

### TD-6 — Locking behavior branches on a stringly-typed class name check
**Code debt.** `ContainerFileSystem.getFileSize` and `.readFileChunk` (lines ~70–91) do:
```kotlin
val name = session.javaClass.simpleName
return if (name.contains("Cryptomator") || name.contains("Gocryptfs")) {
    ContainerEngine.getFileSize(fatPath, volId)   // no lock
} else {
    withReadLock(volId) { ... }                    // locked
}
```
This is a deliberate, documented perf carve-out, not an accident — but it's implemented as a runtime string match against a class name, which the Kotlin compiler cannot check. Renaming `CryptomatorSession` or `GocryptfsSession` — or adding a fourth pure-Kotlin backend whose name doesn't happen to contain a matched substring — silently changes locking behavior with no compile error and no test failure (see TD-5).

**Fix:** add a `val requiresFatLock: Boolean` (or inverse) property to the `VaultBackend` interface, set per implementation, and check `VaultBackendRegistry.get(volId)?.requiresFatLock ?? true` instead. Small, mechanical, and makes the intent a compiler-checked property instead of a string pattern.

**✅ Resolution — this was actually worse than "fragile," it was dead.** Before fixing it, verified the claim directly: `session` in that check comes from `requireSession(volId)`, typed `ContainerSession` — the generic per-volId registry entry declared in `ContainerSessionRegistry.kt`. It is a single concrete class for *every* backend, native or not. `session.javaClass.simpleName` is therefore always exactly the literal string `"ContainerSession"`, never `"CryptomatorSession"` or `"GocryptfsSession"` (those are separate classes held in `VaultBackendRegistry`, not what `session` refers to here). So `.contains("Cryptomator")` was permanently false — the carve-out never fired for any backend, ever; every Cryptomator/gocryptfs read has been paying for the per-volume lock this was supposed to let them skip. Not a correctness bug (over-locking is safe), but a real, confirmed dead-code bug, not merely a fragile-but-working pattern as originally characterized above. Fixed by adding `VaultBackend.skipsPerVolumeLock` (default `false`), overridden `true` on `CryptomatorSession` and `GocryptfsSession` only (matching the original intent — `CryfsSession` was never in the skip list), and `ContainerFileSystem` now checks `VaultBackendRegistry.get(volId)?.skipsPerVolumeLock` — the actual backend instance — instead of the session-registry entry. Recorded as ADR-022.

---

### TD-7 — `unlock_sheet.dart` / `usb_unlock_sheet.dart` duplicate substantial logic
**Code debt.** 1,543 and 1,242 lines respectively, sharing at least 10 identically-named private methods (`_initUnlockMethod`, `_onPatternComplete`, `_tryBiometric`, `_unlock`, `_dismissKeyboard`, `onKeyfilePickError`, `initState`, `dispose`, plus shared `Function` typedefs). The ADR-020 keyboard-dismiss behavior is implemented twice, verbatim in intent, once in each file (`unlock_sheet.dart:155`/`:939`, `usb_unlock_sheet.dart:346`/`:670`) — a visible symptom of exactly the drift risk duplication creates: a future UX fix applied to one is easy to forget applying to the other. `create_container_sheet.dart`/`usb_create_container_sheet.dart` show the same pattern at smaller scale (4 shared method names, ~2,075 combined lines).

**Fix:** extract a shared `UnlockFlowController` (or mixin) parameterized on a small "source" abstraction (local URI vs. USB device) that owns the biometric/pattern/keyfile/keyboard-dismiss logic, leaving each sheet as a thinner widget over the shared controller. This is a real refactor (est. 3–5 days given the password-handling code deserves care, not a quick mechanical extraction) rather than a quick win, which is why its Effort score is 4 despite the clear win in Impact.

---

### TD-8 — `file_browser_screen.dart` is a 2,402-line god-widget
**Architecture debt.** The single largest file in the app by a wide margin (next largest is 1,543 lines). It's the most-touched screen in the app (every file-operation feature lands here), which compounds the cost of its size on every future change, review, and onboarding pass.

**Fix:** decompose along the seams already implied by the surrounding `features/browser/` structure (there's already a `widgets/` subfolder and a `viewer/` subfolder used elsewhere) — likely candidates: selection-mode state, the app-bar/toolbar building, and per-view-mode (list/grid/masonry) builders. Treat as a multi-PR effort with no behavior change per PR, verified against whatever test coverage exists (which is currently thin for this screen — pairs naturally with TD-5's spirit, though this file itself is Dart, not C++).

---

### TD-9 — Global suppression of "Cannot add event after closing" errors
**Code debt / risk of masking.** `configurePlatformIntegrations()` in `app_bootstrap.dart` sets:
```dart
PlatformDispatcher.instance.onError = (error, stack) {
  if (error.toString().contains('Cannot add event after closing')) return true;
  return false;
};
```
This is an app-wide substring match that silently absorbs *any* error containing that phrase, from *any* stream in the app, forever. It was almost certainly added to paper over one specific known stream-lifecycle bug (a `StreamController` being added to after `close()`), but as written it will just as happily hide a new, unrelated instance of the same class of bug introduced in a totally different feature later.

**Fix:** track down the specific stream(s) that were racing on close when this was added (search for `StreamController` usages near screen/session teardown is a reasonable start) and fix the lifecycle bug directly, narrowing or removing this global handler. If some suppression is still needed short-term, scope it to the specific controller/class rather than a global substring match.

---

### TD-10 — Lint configuration is the bare default
**Documentation/code debt.** `analysis_options.yaml` is exactly one line: `include: package:flutter_lints/flutter.yaml`. No project-specific rules are enabled — e.g. `unawaited_futures` would have caught nothing new (the codebase already uses `unawaited()` explicitly and correctly in `app_bootstrap.dart`), but rules like `avoid_print`, `always_declare_return_types`, or stricter null-safety casts would raise the floor for a codebase this size with only default linting today.

**Fix:** low-cost, incremental — add a handful of rules per quarter rather than all at once (a sudden strict ruleset on an existing 156-file codebase creates a wall of unrelated diffs). Start with `unawaited_futures` and `avoid_print` given the patterns already visible in the code.

---

### TD-11 — `docs/architecture.md` disappeared with nothing to catch it
**Documentation debt.** Confirmed via this session: ~50 comments across Dart/Kotlin/C++ cite `docs/architecture.md` by path and specific ADR number, but the file does not exist in this snapshot, and nothing (lint rule, CI check, pre-commit hook) verifies that a cited doc path actually resolves.

**Fix:** the immediate gap is closed by this session's reconstruction (`docs/architecture.md`, included alongside this report). Going forward, a cheap CI check — grep the tree for `docs/architecture.md` citations and fail if the file is absent — would have caught this the moment it happened rather than letting dozens of comments silently point at nothing.

**✅ Resolution:** the `architecture-doc-check` job in `.github/workflows/test.yml` (added for TD-2) does exactly this — greps Dart/Kotlin/C++ sources for `docs/architecture.md` citations and fails the build if the file is missing while citations exist. Deliberately not more ambitious than that (doesn't validate individual ADR numbers resolve to real table entries) — a cheap tripwire, not a documentation linter.

---

### TD-12 — `pointycastle` pinned a major version behind
**Dependency debt.** `pubspec.yaml` pins `pointycastle: ^3.6.2`; current published latest is `4.0.0`. Used only in `pattern_lock_view.dart` (app-lock pattern hashing) — not in the container-unlock crypto path, which is native (mbedTLS). Lower stakes than it would be if it touched the container crypto directly, but a major-version gap on a cryptographic primitives library is worth a deliberate look rather than an indefinite `^3.x` pin, especially since pointycastle's own changelog history includes past timing-attack fixes.

**Fix:** review the 4.0.0 changelog for breaking API changes against `pattern_lock_view.dart`'s usage, then bump. Small, bounded piece of work.

**✅ Resolution:** checked actual usage first — it's exactly one call site, `SHA256Digest().process(bytes)`, the most basic and long-stable shape of pointycastle's digest API. Bumped `pointycastle: ^3.6.2` → `^4.0.0` in `pubspec.yaml`. **Caveat:** `pubspec.lock` was intentionally left untouched — regenerating it correctly requires real dependency resolution (transitive deps included), which needs network access this sandboxed environment doesn't have. Run `flutter pub get` locally to regenerate the lock file and `flutter analyze`/`flutter test` to confirm before merging.

---

## What's *not* on this list (worth saying explicitly)

- **Dependency debt is otherwise light.** `flutter_secure_storage` is pinned to `10.3.1`, which is in fact current latest as of this audit — exact-pinning it (rather than `^10.3.1`) is a defensible choice for a security-sensitive storage dependency, not a smell.
- **No TODO/FIXME/HACK markers anywhere in the tree.** Either genuinely clean, or debt is being tracked out-of-band (an issue tracker this audit has no visibility into) rather than left as source comments — worth confirming which.
- **The ownership/locking design itself (native `VolumeState` mutexes, key zeroization on lock, fail-closed rename semantics) is unusually well-documented and deliberately engineered** — several of the ADRs recovered in the companion architecture doc exist specifically because a past bug was found and fixed with a comment explaining why, which is a good sign for how debt gets handled here in general. TD-1 and TD-6 are the exceptions to that pattern, not the norm.

---

## Phased remediation plan

Designed to run alongside normal feature work — nothing here needs a dedicated "debt sprint."

**Phase 0 (this week, <1 day total): ✅ executed.** TD-3 (rename fix — plus an additional native-lib issue found and fixed along the way), TD-2 (CI test job). Done together as planned, since TD-3's fix is worthless without TD-2 to run it.

**Phase 1 (next sprint, ~2–3 days): ✅ executed.** TD-1 (`ConcurrentHashMap` swap), TD-6 (`VaultBackend.skipsPerVolumeLock` property — turned out to be fixing dead code, not just a fragile pattern), TD-11's CI doc-citation check (folded into the same workflow as TD-2), TD-12 (pointycastle bump). All small, independent, low-risk, each removing a specific sharp edge. **None of this has been verified against a real build** (no network access in the environment these fixes were made in) — the next CI run against real infrastructure is the actual gate, not this document.

**Phase 2 (next 4–6 weeks, alongside feature work):** TD-4 (implement the described leak test properly), TD-9 (find and fix the real stream-lifecycle bug instead of the global suppression), TD-10 (incremental lint rule additions, a few per quarter).

**Phase 3 (larger, scheduled deliberately, 2–4 weeks each):** TD-8 (decompose `file_browser_screen.dart`) and TD-7 (unify the unlock/create-sheet duplication) — do these as their own tracked initiatives with no-behavior-change PRs, not squeezed into unrelated feature branches, given the size and the security sensitivity of the code (password handling) TD-7 touches.

**Standing program (not a phase — ongoing):** TD-5. Start with a feasibility spike (can the native lib be exercised in a JVM/host unit test without a full emulator?), then build outward format-by-format, starting with whichever format sees the most active feature work right now so the tests pay for themselves fastest. Track this as its own epic, not a backlog ticket, given Impact/Risk are both maxed.
