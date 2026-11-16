# Journal automatique des marches — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A macOS menu bar app that auto-connects to David's WalkingPad Z1 (`KS-HD-Z1E`), records every walk locally and pushes each session plus a weekly recap to Notion.

**Architecture:** All logic lives in a local SwiftPM package `WalkingPadKit` (pure, unit-tested with `swift test`): FTMS frame decoding, session state machine, SQLite store, weekly summary, Notion API layer and sync. A thin XcodeGen app target `TapisMarche` wires CoreBluetooth, the menu bar UI, settings, Keychain and launch-at-login on top of it.

**Tech Stack:** Swift 6.2 (strict concurrency), SwiftUI `MenuBarExtra`, CoreBluetooth, GRDB 7 (SQLite), URLSession + Notion REST API `2025-09-03`, Swift Testing, XcodeGen, Xcode 26.3, macOS 15+.

**Spec:** `docs/superpowers/specs/2026-11-16-journal-marches-design.md`

## Global Constraints

- macOS deployment target 15.0; Swift language mode 6; build with Xcode 26.3.
- **BLE is read-only**: never write to any characteristic of the pad (no FTMS Control Point, no vendor service). Only subscribe to Treadmill Data `0x2ACD`.
- Pad discovery: service `0x1826`, advertised name prefix `KS-HD-`.
- Session rules (spec values): idle timeout **180 s** at speed 0 or without frames; data gap **> 10 s** without frames → increments across it not credited; discard sessions **< 120 s active AND < 100 m**; a session belongs to the local day/week of its **start**; weeks are ISO (Monday 00:00 → Sunday 23:59, local time zone).
- Notion token lives **only in the Keychain** (service `TapisMarche.notion`, account `token`), never in a file or UserDefaults.
- Notion is write-only: a session already synced (Notion page id stored locally) is never recreated.
- Signing: "Apple Development" identity, team `HFVC9G5X5R`; bundle id `ch.davidpreti.TapisMarche`; no App Sandbox; `LSUIElement = YES`.
- All UI copy in French, exactly as given in the spec's menu bar mockup.
- ub-mode gates (crapper / dryer / mutator) do not support Swift: apply the principles, skip the tools, say so in the log.
- Git: commit per task on the current branch, `git add <explicit paths>` only, never push.

## Review Focus

1. **Mac goes to sleep mid-walk** (no frames for hours, then wake): the session must close at its last moving sample, with nothing credited for the gap → test `tickAfterLongSleepClosesAtLastMovingSample` (Task 3).
2. **Pad sits connected in standby**, streaming speed-0 frames for hours: no session must ever be created from zero-only frames → test `zeroOnlyFramesNeverOpenASession` (Task 3).
3. **App crashes/relaunches mid-session or twice in a row**: recovery must not lose nor duplicate the session → test `recoverTwiceSavesOneSession` (Task 4).
4. **Notion token revoked / Notion down**: sessions stay pending, status shows the error, nothing is lost and nothing is duplicated on retry → tests `unauthorizedKeepsSessionsPending`, `retryAfterFailureCreatesExactlyOnePage` (Task 7).
5. **Late session for an already-recapped week** (Mac was off on Sunday): the recap is replaced, not duplicated → test `lateSessionReplacesExistingRecap` (Task 7).

---

## File Structure

```
WalkingPadKit/
  Package.swift
  Sources/WalkingPadKit/
    TreadmillSample.swift      # sample model
    FTMSTreadmillFrame.swift   # 0x2ACD decoding
    WalkSession.swift          # session + totals models
    SessionTracker.swift       # frames → sessions state machine
    SessionStore.swift         # GRDB persistence
    SessionRecovery.swift      # replay unclosed samples after relaunch
    WeeklySummary.swift        # aggregation, title, sparkline
    NotionPayloads.swift       # pure JSON builders
    NotionClient.swift         # HTTP layer (HTTPTransport protocol)
    NotionSync.swift           # pending sessions + recaps
  Tests/WalkingPadKitTests/
    FTMSTreadmillFrameTests.swift
    SessionTrackerTests.swift
    SessionStoreTests.swift
    WeeklySummaryTests.swift
    NotionClientTests.swift
    NotionSyncTests.swift
    FakeTransport.swift
App/
  Info.plist
  TapisMarcheApp.swift         # @main, MenuBarExtra
  AppModel.swift               # wiring, timers, live state
  PadConnection.swift          # CoreBluetooth
  MenuBarView.swift
  SettingsView.swift
  Keychain.swift
project.yml                    # XcodeGen
Makefile                       # test / build / install / run
```

---

### Task 1: Walking test (gate — needs David on the pad)

**Files:**
- Modify: `docs/superpowers/specs/2026-11-16-journal-marches-design.md` (add section « Résultats de la marche-test »)

**Interfaces:**
- Produces: confirmed byte layout of the bit-13 extension (steps), counter behaviour across a belt stop/restart, notification continuity over ≥ 10 min. Tasks 2–3 use these facts; if steps are absent, Task 2 decodes `steps = nil` and the « Pas » UI/Notion field is hidden (spec decision).

- [ ] **Step 1: Run the probe detached while David walks ≥ 10 min, with one stop and restart of the belt**

```bash
mkdir -p .jarvis-logs && nohup .venv/bin/python -u spike/walkingpad_probe.py --scan 20 --duration 900 > .jarvis-logs/probe-walk.log 2>&1 &
```
Prerequisite: pad on, KS Fit closed, phone Bluetooth off.

- [ ] **Step 2: Analyse the newest `data/spike-*.jsonl`**

Check and record: (a) `speed_kmh`, `dist_m`, `time_s` non-zero while walking; (b) `extra_hex` decoded as uint24 little-endian increases monotonically and roughly matches ~1,6–2 steps per metre; (c) what `dist_m`/`time_s`/steps do after the belt stop/restart (reset to 0 or continue); (d) no gap > 2 s between frames over the run.

- [ ] **Step 3: Write the findings into the spec and, if (b) or (c) differ from the assumptions, update the expected values of Tasks 2–3 in this plan**

- [ ] **Step 4: Commit**

```bash
git add docs/superpowers/specs/2026-11-16-journal-marches-design.md docs/superpowers/plans/2026-11-16-journal-marches.md
git commit -m "docs: record WalkingPad Z1 walking-test findings"
```

---

### Task 2: WalkingPadKit package + FTMS frame decoding

**Files:**
- Create: `WalkingPadKit/Package.swift`, `Sources/WalkingPadKit/TreadmillSample.swift`, `Sources/WalkingPadKit/FTMSTreadmillFrame.swift`
- Test: `Tests/WalkingPadKitTests/FTMSTreadmillFrameTests.swift`
- Modify: `.gitignore` (add `.build/`, `*.xcodeproj/`, `build/`)

**Interfaces:**
- Produces:
  ```swift
  public struct TreadmillSample: Equatable, Sendable, Codable {
      public var timestamp: Date
      public var speedKmh: Double
      public var distanceM: Int?
      public var elapsedS: Int?
      public var energyKcal: Int?
      public var steps: Int?
  }
  public enum FTMSDecodeError: Error, Equatable { case truncated(expected: Int, got: Int) }
  public enum FTMSTreadmillFrame {
      public static func decode(_ data: Data, at timestamp: Date) throws -> TreadmillSample
  }
  ```

- [ ] **Step 1: Create `Package.swift`** — swift-tools-version 6.0, platform `.macOS(.v15)`, library `WalkingPadKit`, dependency `https://github.com/groue/GRDB.swift` from `7.0.0` (used from Task 4), test target `WalkingPadKitTests`.

- [ ] **Step 2: Write the failing tests**

```swift
@Test func decodesIdleFrameFromRealPad() throws {
    let s = try FTMSTreadmillFrame.decode(Data(hex: "8424000000000000000000000000000000"), at: .init(timeIntervalSince1970: 0))
    #expect(s.speedKmh == 0 && s.distanceM == 0 && s.energyKcal == 0 && s.elapsedS == 0 && s.steps == 0)
}
@Test func decodesWalkingFrame() throws {
    // flags 0x2484: speed, distance(b2), energy(b7), elapsed(b10), KingSmith steps(b13)
    let s = try FTMSTreadmillFrame.decode(Data(hex: "84245e01fa00007800ffffff7800c80000"), at: .init(timeIntervalSince1970: 0))
    #expect(s.speedKmh == 3.5); #expect(s.distanceM == 250); #expect(s.energyKcal == 120)
    #expect(s.elapsedS == 120); #expect(s.steps == 200)
}
@Test func frameWithoutBit13HasNilSteps() throws {
    let s = try FTMSTreadmillFrame.decode(Data(hex: "84045e01fa00007800ffffff7800"), at: .init(timeIntervalSince1970: 0))
    #expect(s.steps == nil)
}
@Test func truncatedFrameThrows() {
    #expect(throws: FTMSDecodeError.truncated(expected: 17, got: 5)) {
        try FTMSTreadmillFrame.decode(Data(hex: "84245e01fa"), at: .init(timeIntervalSince1970: 0))
    }
}
```
(`Data(hex:)` is a test-only helper in the same file.)

- [ ] **Step 3: Run** `cd WalkingPadKit && swift test --filter FTMSTreadmillFrameTests` — Expected: FAIL (types not defined).

- [ ] **Step 4: Implement `FTMSTreadmillFrame.decode`** following the Bluetooth SIG FTMS Treadmill Data field order already proven in `spike/walkingpad_probe.py` (`parse_ftms_treadmill`), little-endian; bit 0 *clear* means speed present; skipped fields (avg speed, inclination, elevation, paces, energy/h, energy/min, HR, MET, remaining time, force/power) are consumed but not stored; bit 13 → steps uint24 LE. Compute the expected length from the flags first and throw `truncated` before reading.

- [ ] **Step 5: Run** the same command — Expected: 4 tests PASS.

- [ ] **Step 6: Commit** `git add .gitignore WalkingPadKit/Package.swift WalkingPadKit/Sources WalkingPadKit/Tests && git commit -m "feat: decode WalkingPad FTMS treadmill frames"`

---

### Task 3: SessionTracker

**Files:**
- Create: `Sources/WalkingPadKit/WalkSession.swift`, `Sources/WalkingPadKit/SessionTracker.swift`
- Test: `Tests/WalkingPadKitTests/SessionTrackerTests.swift`

**Interfaces:**
- Consumes: `TreadmillSample` (Task 2).
- Produces:
  ```swift
  public struct SessionTotals: Equatable, Sendable, Codable {
      public var activeSeconds: Int, distanceM: Int, steps: Int?, energyKcal: Int
      public var avgSpeedKmh: Double, maxSpeedKmh: Double
  }
  public struct WalkSession: Equatable, Sendable, Identifiable, Codable {
      public var id: UUID, start: Date, end: Date, totals: SessionTotals
  }
  public struct SessionTracker: Sendable {
      public init(idleTimeout: TimeInterval = 180, gapThreshold: TimeInterval = 10,
                  minActiveSeconds: Int = 120, minDistanceM: Int = 100)
      public var openSession: WalkSession? { get }      // live totals so far
      public mutating func ingest(_ sample: TreadmillSample) -> WalkSession?  // returns a session it just closed (kept only if above thresholds)
      public mutating func tick(now: Date) -> WalkSession?                    // closes on idle timeout without frames
  }
  ```

Rules (decide the algorithm):
- Open on first sample with `speedKmh > 0`; `start` = that sample's timestamp; `end` = last sample with speed > 0.
- `activeSeconds` = sum of intervals between consecutive samples where the earlier one had speed > 0, each interval counted only if ≤ `gapThreshold`.
- Counters (`distanceM`, `steps`, `energyKcal`): add `cur - prev` when `cur ≥ prev` and the interval ≤ `gapThreshold`; if `cur < prev` (reset) add `cur`; across a gap > `gapThreshold` add nothing (re-baseline).
- Close when speed has been 0 for ≥ `idleTimeout` (in `ingest`) or `now - lastSampleTime ≥ idleTimeout` (in `tick`). Discard (return nil) if `activeSeconds < 120 && distanceM < 100`.
- `avgSpeedKmh = distanceM / activeSeconds * 3.6` (0 if no active time); `steps` nil when every sample's steps is nil.

- [ ] **Step 1: Write the failing tests** (helper `walk(from:speeds:dist:steps:every:)` builds 1 Hz samples)

```swift
@Test func opensOnFirstMovingSample()                 // 0,0,3.5 → openSession.start == t2
@Test func shortPauseStaysInSameSession()             // walk 300 s, 120 s at 0, walk 300 s → one session, activeSeconds ≈ 600
@Test func threeMinutesIdleClosesAtLastMovingSample() // walk 300 s then 180 s at 0 → ingest returns session, end == last moving t
@Test func counterResetIsAddedNotSubtracted()         // dist 500 → 0 → 100 (1 s apart) → distanceM == 600
@Test func gapOverTenSecondsIsNotCredited()           // dist 100 at t, 900 at t+30 → distanceM == 100 up to gap, no +800
@Test func tinySessionIsDiscarded()                   // 60 s at 3 km/h, 50 m, then idle → returns nil
@Test func zeroOnlyFramesNeverOpenASession()          // 4 h of speed-0 frames → openSession == nil, no session returned
@Test func tickAfterLongSleepClosesAtLastMovingSample() // walk 600 s, then tick(now: last + 2 h) → session.end == last moving t, activeSeconds ≈ 600
@Test func stepsNilWhenPadNeverReportsThem()
```

- [ ] **Step 2: Run** `swift test --filter SessionTrackerTests` — Expected: FAIL.
- [ ] **Step 3: Implement** per the rules above.
- [ ] **Step 4: Run** — Expected: 9 PASS.
- [ ] **Step 5: Commit** `git commit -m "feat: turn treadmill frames into walk sessions"` (explicit paths).

---

### Task 4: SessionStore (GRDB) + crash recovery

**Files:**
- Create: `Sources/WalkingPadKit/SessionStore.swift`, `Sources/WalkingPadKit/SessionRecovery.swift`
- Test: `Tests/WalkingPadKitTests/SessionStoreTests.swift`

**Interfaces:**
- Consumes: `TreadmillSample`, `WalkSession`, `SessionTracker`.
- Produces:
  ```swift
  public struct RecapRecord: Equatable, Sendable { public var weekStart: Date, notionPageId: String, fingerprint: String }
  public final class SessionStore: Sendable {
      public init(path: String?) throws                     // nil → in-memory
      public func append(_ sample: TreadmillSample) throws
      public func samples(after: Date?) throws -> [TreadmillSample]
      public func save(_ session: WalkSession) throws        // upsert by id
      public func sessions(in interval: DateInterval) throws -> [WalkSession]  // by start
      public func unsyncedSessions() throws -> [WalkSession]
      public func markSynced(_ id: UUID, notionPageId: String) throws
      public func lastClosedSessionEnd() throws -> Date?
      public func pruneSamples(before: Date) throws
      public func recap(weekStart: Date) throws -> RecapRecord?
      public func saveRecap(_ r: RecapRecord) throws
  }
  public enum SessionRecovery {
      public static func recover(store: SessionStore, now: Date, tracker: SessionTracker = .init()) throws -> SessionTracker
      // replays samples after lastClosedSessionEnd, saves any session that closes (incl. tick(now)), returns the tracker holding a still-open session
  }
  ```
Schema: tables `sample(timestamp PK, json)`, `session(id PK, start, end, json, notionPageId NULL)`, `recap(weekStart PK, notionPageId, fingerprint)`. Use `DatabaseQueue`; DB file `~/Library/Application Support/TapisMarche/journal.sqlite` (path chosen by the app).

- [ ] **Step 1: Write the failing tests**

```swift
@Test func savedSessionRoundTrips()
@Test func unsyncedListsOnlySessionsWithoutNotionPage()   // save 2, markSynced 1 → unsynced.count == 1
@Test func sessionsInIntervalFilterByStart()
@Test func recoverClosesSessionLeftOpenByCrash()          // append 600 s walk, recover(now: last + 4 min) → 1 saved session
@Test func recoverTwiceSavesOneSession()                  // recover, recover again → sessions count == 1
@Test func recoverKeepsStillOpenSessionInTracker()        // recover(now: last + 30 s) → nothing saved, tracker.openSession != nil
@Test func pruneRemovesOnlyOlderSamples()
```

- [ ] **Step 2: Run** `swift test --filter SessionStoreTests` — Expected: FAIL.
- [ ] **Step 3: Implement.** `save` is an upsert that never clears an existing `notionPageId`.
- [ ] **Step 4: Run** — Expected: 7 PASS.
- [ ] **Step 5: Commit** `git commit -m "feat: persist samples and sessions with crash recovery"`.

---

### Task 5: WeeklySummary

**Files:**
- Create: `Sources/WalkingPadKit/WeeklySummary.swift`
- Test: `Tests/WalkingPadKitTests/WeeklySummaryTests.swift`

**Interfaces:**
- Consumes: `WalkSession`.
- Produces:
  ```swift
  public struct WeeklySummary: Equatable, Sendable {
      public var weekStart: Date, isoWeek: Int, sessionCount: Int
      public var activeSeconds: Int, distanceM: Int, steps: Int?
      public var perDayActiveSeconds: [Int]        // 7 entries, Monday first
      public struct BestDay: Equatable, Sendable { public var weekdayIndex: Int, activeSeconds: Int, distanceM: Int }
      public var bestDay: BestDay?
      public var previousWeekDistanceM: Int?
      public var fingerprint: String               // changes iff any included session changes
      public static func weekStart(containing: Date, calendar: Calendar) -> Date
      public static func make(sessions: [WalkSession], previousWeek: [WalkSession], weekStart: Date, calendar: Calendar) -> WeeklySummary
      public var title: String                     // French, see tests
      public static func sparkline(_ perDay: [Int]) -> String
  }
  ```
Calendar: ISO 8601, `firstWeekday = 2`, time zone `.current`, locale `fr_CH`.

- [ ] **Step 1: Write the failing tests**

```swift
@Test func titleWithinOneMonth()      // week of 2026-11-16 → "Semaine 47 — 16-22 nov."
@Test func titleAcrossTwoMonths()     // week of 2026-11-30 → "Semaine 49 — 30 nov.-6 déc."
@Test func sessionCrossingMidnightCountsOnStartDay()  // Sun 23:30 → Mon 00:40 → Sunday bucket, same week
@Test func bestDayIsLongestActiveDay()
@Test func sparklineScalesToMax()     // [0, 60, 120, 0, 0, 0, 0] → "·▄█····"
@Test func stepsNilWhenNoSessionHasSteps()
@Test func fingerprintChangesWhenASessionIsAdded()
```
Sparkline: `·` for 0, else level `ceil(v / max * 8) - 1` in `"▁▂▃▄▅▆▇█"`.

- [ ] **Step 2: Run** `swift test --filter WeeklySummaryTests` — Expected: FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** — Expected: 7 PASS.
- [ ] **Step 5: Commit** `git commit -m "feat: weekly walking summary"`.

---

### Task 6: Notion API layer (payloads + client)

**Files:**
- Create: `Sources/WalkingPadKit/NotionPayloads.swift`, `Sources/WalkingPadKit/NotionClient.swift`
- Test: `Tests/WalkingPadKitTests/NotionClientTests.swift`, `Tests/WalkingPadKitTests/FakeTransport.swift`

**Interfaces:**
- Consumes: `WalkSession`, `WeeklySummary`.
- Produces:
  ```swift
  public protocol HTTPTransport: Sendable { func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) }
  public enum NotionError: Error, Equatable { case unauthorized, rateLimited, http(status: Int, body: String), malformedResponse }
  public struct NotionConfig: Codable, Equatable, Sendable { public var dataSourceId: String, recapsPageId: String }
  public struct NotionClient: Sendable {
      public static let apiVersion = "2025-09-03"
      public init(token: String, transport: HTTPTransport)
      public func setUpWorkspace(parentPageId: String) async throws -> NotionConfig   // creates DB "Marches" + page "Récaps hebdo"
      public func createSessionPage(_ s: WalkSession, in config: NotionConfig, calendar: Calendar) async throws -> String
      public func createRecapPage(_ w: WeeklySummary, in config: NotionConfig) async throws -> String
      public func trashPage(_ pageId: String) async throws
  }
  public enum NotionPageId { public static func parse(_ urlOrId: String) -> String? }  // last 32 hex chars → dashed UUID form
  ```
Notion specifics: header `Notion-Version: 2025-09-03`, `Authorization: Bearer <token>`. Database create: `POST /v1/databases` with `parent: {type: page_id}`, `title`, `initial_data_source.properties`; read `data_sources[0].id`. Session page: `POST /v1/pages` with `parent: {type: "data_source_id", data_source_id}`. Properties (exact names): `Séance` (title, e.g. "lun. 16 nov. · 14:05"), `Date` (date, start day), `Début` / `Fin` (date-time), `Durée (min)`, `Distance (km)` (2 decimals), `Pas` (omitted when nil), `Vitesse moy. (km/h)`, `Vitesse max (km/h)`, `kcal` (numbers), `ID` (rich_text = session UUID). Recap page: child of `recapsPageId`, title = `summary.title`, blocks: one paragraph per line `5 séances · 7 h 40 de marche · 31,2 km · 41 380 pas`, `Meilleur jour : mardi (2 h 10, 9,1 km)`, a code block with the sparkline + `(lun → dim)`, `vs semaine précédente : +4,3 km` when known. Trash: `PATCH /v1/pages/{id}` `{"in_trash": true}`. Status 401 → `.unauthorized`, 429 → `.rateLimited`, other non-2xx → `.http`.

- [ ] **Step 1: Write the failing tests** (FakeTransport records requests and replays canned responses)

```swift
@Test func parsesPageIdFromNotionURL()   // "https://www.notion.so/Tapis-1a2b…(32 hex)" → "1a2b….-…" dashed
@Test func setUpWorkspaceCreatesDatabaseAndRecapsPage()  // 2 requests; returns dataSourceId from data_sources[0].id
@Test func sessionPageHasExactPropertiesAndParent()      // decode sent JSON: parent.data_source_id, "Distance (km)" == 1.25, "ID" == uuid
@Test func sessionPageOmitsStepsWhenNil()
@Test func recapPageUsesSummaryTitle()
@Test func everyRequestCarriesVersionAndBearer()
@Test func mapsStatusCodesToErrors()      // 401 → .unauthorized, 429 → .rateLimited, 500 → .http(500, …)
```

- [ ] **Step 2: Run** `swift test --filter NotionClientTests` — Expected: FAIL.
- [ ] **Step 3: Implement** (`URLSessionTransport` conforming to `HTTPTransport` lives in the same file, used by the app).
- [ ] **Step 4: Run** — Expected: 7 PASS.
- [ ] **Step 5: Commit** `git commit -m "feat: Notion API client for sessions and recaps"`.

---

### Task 7: NotionSync

**Files:**
- Create: `Sources/WalkingPadKit/NotionSync.swift`
- Test: `Tests/WalkingPadKitTests/NotionSyncTests.swift`

**Interfaces:**
- Consumes: `SessionStore`, `NotionClient`, `NotionConfig`, `WeeklySummary`.
- Produces:
  ```swift
  public struct SyncStatus: Equatable, Sendable { public var pending: Int, lastError: NotionError? }
  public actor NotionSync {
      public init(store: SessionStore, client: NotionClient, config: NotionConfig, calendar: Calendar)
      public func syncSessions() async -> SyncStatus      // stops at first error, keeps the rest pending
      public func syncRecaps(now: Date) async -> SyncStatus
      // for each finished week (weekStart + 7 d ≤ now) having ≥ 1 session:
      //   no RecapRecord → create; RecapRecord with different fingerprint → trash old page, create new, save record
  }
  ```

- [ ] **Step 1: Write the failing tests**

```swift
@Test func syncCreatesOnePagePerPendingSessionAndMarksThem()
@Test func secondSyncSendsNothing()
@Test func unauthorizedKeepsSessionsPending()            // 401 → status.pending == 2, lastError == .unauthorized, store unchanged
@Test func retryAfterFailureCreatesExactlyOnePage()     // 500 then 200 → exactly one POST /v1/pages succeeded per session overall
@Test func unfinishedWeekGetsNoRecap()
@Test func finishedWeekGetsRecapOnce()
@Test func lateSessionReplacesExistingRecap()           // recap exists, new session saved in that week → PATCH trash + POST create, record updated
```

- [ ] **Step 2: Run** `swift test --filter NotionSyncTests` — Expected: FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** the full suite `swift test` — Expected: all tests PASS.
- [ ] **Step 5: Commit** `git commit -m "feat: idempotent Notion sync for sessions and weekly recaps"`.

---

### Task 8: Menu bar app with live BLE connection

**Files:**
- Create: `project.yml`, `Makefile`, `App/Info.plist`, `App/TapisMarcheApp.swift`, `App/AppModel.swift`, `App/PadConnection.swift`, `App/MenuBarView.swift`

**Interfaces:**
- Consumes: `FTMSTreadmillFrame`, `SessionTracker`, `SessionStore`, `SessionRecovery`, `WeeklySummary`.
- Produces:
  ```swift
  enum PadState: Equatable { case absent, connecting, connected, released(until: Date) }
  @MainActor final class PadConnection: NSObject {   // CBCentralManagerDelegate, CBPeripheralDelegate
      var onState: (PadState) -> Void
      var onSample: (TreadmillSample) -> Void
      func start()                                    // scan 0x1826, name prefix "KS-HD-", connect, notify 0x2ACD, auto-reconnect 5 s after disconnect
      func release(for duration: TimeInterval)       // cancel connection, no scan until deadline
  }
  @MainActor @Observable final class AppModel {
      var padState: PadState; var liveSpeedKmh: Double?; var todaySteps: Int?
      var todayActiveSeconds: Int; var todayDistanceM: Int; var weekActiveSeconds: Int; var weekDistanceM: Int
      var recentSessions: [WalkSession]; var syncStatus: SyncStatus?
  }
  ```
`project.yml`: app target `TapisMarche`, macOS 15, local package dependency `WalkingPadKit`, `DEVELOPMENT_TEAM: HFVC9G5X5R`, `CODE_SIGN_IDENTITY: "Apple Development"`, `PRODUCT_BUNDLE_IDENTIFIER: ch.davidpreti.TapisMarche`. `Info.plist`: `LSUIElement = YES`, `NSBluetoothAlwaysUsageDescription = "Tapis Marche se connecte à ton WalkingPad pour enregistrer tes marches."`. Makefile targets: `test` (swift test in package), `project` (xcodegen), `build` (xcodebuild Release into `build/`), `install` (copy to `/Applications`), `run` (open the built app). AppModel: on launch `SessionRecovery.recover`, then per sample `store.append` + `tracker.ingest` (save closed session), 30 s timer `tracker.tick`, daily `pruneSamples(before: now - 7 d)`; log via `Logger(subsystem: "ch.davidpreti.TapisMarche", category: "pad")`. Menu copy exactly as the spec mockup (the Notion line stays hidden until Task 9).

- [ ] **Step 1: Generate and build** `make project build` — Expected: `** BUILD SUCCEEDED **`.
- [ ] **Step 2: Run detached and prove the connection** (pad on, KS Fit closed): `make run`, then `log show --last 2m --predicate 'subsystem == "ch.davidpreti.TapisMarche"'` — Expected: lines `connected KS-HD-Z1E` and `sample speed=…` at ~1 Hz.
- [ ] **Step 3: David walks 3 min, stops 3 min** — Expected log `session closed` and `sqlite3 ~/Library/Application\ Support/TapisMarche/journal.sqlite 'select count(*) from session'` → `1`; menu shows today's totals.
- [ ] **Step 4: Check « Libérer le tapis pour KS Fit (15 min) »** — Expected: log `released until …`, KS Fit can connect.
- [ ] **Step 5: Commit** `git commit -m "feat: menu bar app recording walks from the WalkingPad"` (explicit paths; `*.xcodeproj` stays ignored).

---

### Task 9: Settings, Notion setup, launch at login, end-to-end

**Files:**
- Create: `App/SettingsView.swift`, `App/Keychain.swift`
- Modify: `App/AppModel.swift`, `App/MenuBarView.swift`, `README.md` (setup section)

**Interfaces:**
- Consumes: `NotionClient`, `NotionPageId`, `NotionSync`, `NotionConfig`.
- Produces: `enum Keychain { static func read() -> String?; static func write(_ token: String) throws; static func delete() }` (service `TapisMarche.notion`, account `token`); `NotionConfig` persisted as JSON in UserDefaults key `notionConfig`.

Settings window: SecureField « Jeton d'intégration Notion », TextField « Page Notion parente (URL) », button « Connecter Notion » (runs `setUpWorkspace`, shows the error text on failure), Toggle « Lancer à l'ouverture de session » (`SMAppService.mainApp.register()/unregister()`). AppModel: after each closed session → `syncSessions()`; on failure retry after 60, 120, 300, 900 s (then every 900 s); at launch and every hour → `syncRecaps(now:)`. Menu line « Notion : à jour » / « Notion : 1 séance en attente » / « Notion : N séances en attente » (N ≥ 2) / « Notion : non configuré ».

- [ ] **Step 1: Build and install** `make build install` — Expected: `** BUILD SUCCEEDED **`, app in `/Applications`.
- [ ] **Step 2: End-to-end with David's real Notion** (David creates the internal integration and shares a parent page): connect in Settings — Expected: database « Marches » and page « Récaps hebdo » appear under the parent page.
- [ ] **Step 3: Sync proof** — the session from Task 8 appears as a row in « Marches » with the exact property names; menu shows « Notion : à jour ».
- [ ] **Step 4: Failure proof** — temporarily enter a wrong token, close a walk: menu shows « Notion : 1 séance en attente »; restore token → row appears once, no duplicate.
- [ ] **Step 5: Launch at login** — toggle on, `launchctl list | grep TapisMarche` shows the job after a logout/login (or confirm via System Settings › General › Login Items).
- [ ] **Step 6: Update README** (Notion setup, `make` targets, KS Fit release button), then commit `git commit -m "feat: Notion settings, sync loop and launch at login"`.
