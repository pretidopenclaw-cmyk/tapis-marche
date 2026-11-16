# Pilotage du tapis — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let Tapis Marche drive the WalkingPad Z1 belt: preferred speed on every start, stop when David steps off, start/stop/speed from the menu, from `tapismarche://` links and from Raycast.

**Architecture:** Pure, tested logic in `WalkingPadKit` (FTMS command encoding/decoding, an `AutoPilot` state machine, URL parsing); the app adds an FTMS Control Point channel to `PadConnection` and wires menu, settings, URL handling and notifications. Raycast gets plain Script Commands that open the links.

**Tech Stack:** Swift 6.2, SwiftUI `MenuBarExtra`, CoreBluetooth, UserNotifications, Swift Testing, XcodeGen; Raycast Script Commands (bash).

**Spec:** `docs/superpowers/specs/2026-11-16-pilotage-tapis-design.md` (extends `2026-11-16-journal-marches-design.md`).

## Global Constraints

- Writes allowed **only** to FTMS Control Point `0x2AD9`, and only the opcodes `0x00` request control, `0x07` start, `0x02` set target speed (uint16 LE, 0.01 km/h), `0x08 0x01` stop. Never a frame whose first byte is `0xE8`.
- At least **400 ms** between two writes; wait for the `80 <op> <result>` indication.
- Speed always clamped to the range read from `0x2AD4` (Z1E: **1.0–6.0 km/h, step 0.1**) and rounded to the step.
- The app **never emits `start` on its own**; `start` only comes from the menu or a link.
- AutoPilot values: settle **2 s**, start grace **15 s**, no-step timeout **10 s**, reconnect window **30 s**; « Plus/Moins vite » = **± 0.5 km/h**; default preferred speed **2.0 km/h**.
- Pending link command: waits **≤ 10 s** for a connection, latest replaces previous, then dropped with notification « Tapis introuvable ».
- URL scheme `tapismarche`, hosts: `demarrer`, `arreter`, `vitesse/<km/h>`, `plus-vite`, `moins-vite`.
- French UI copy as given in the spec; ub-mode gates skipped (no Swift support); commit per task, explicit paths, never push.

## Review Focus

1. **Remote stops working while the app holds control** → Task 1 decides held vs on-demand control before any app code.
2. **French decimal in a link** (`tapismarche://vitesse/2,5`) → accepted like `2.5` → test `speedAcceptsFrenchDecimalComma` (Task 3).
3. **Plus/Moins vite at the range edges** → clamps to 6.0 / 1.0, never stops the belt → test `fasterAndSlowerClampToRange` (Task 2).
4. **Slow walking (a step every few seconds)** → never auto-stopped → test `slowWalkingNeverStops` (Task 3).
5. **Accidental start with nobody on the belt** → stopped within 25 s → test `emptyBeltAfterStartStopsWithinTwentyFiveSeconds` (Task 3).

---

### Task 1: Remote vs app control (hardware gate — David on the pad)

**Files:**
- Create: `spike/walkingpad_remote_probe.py` (throwaway, reuses `Pad`, `log` from `walkingpad_control_probe.py`, spoken cues like `walkingpad_presence_probe.py`)
- Modify: spec, section « Résultats » (append)

- [ ] **Step 1: Write the probe**: connect, `requestControl`, then spoken cues: « Démarre le tapis avec la télécommande » (wait 20 s, log belt speed/status), « Change la vitesse à la télécommande » (20 s), « Arrête avec la télécommande » (20 s). The probe only observes (no command besides `requestControl`); safety `stop` in `finally`.
- [ ] **Step 2: Run it** (quit the app first, relaunch after). Expected log: belt speed > 0 after the remote start, speed change, then 0.
- [ ] **Step 3: Record the outcome in the spec** and the ledger: remote works while control held → **held control** (Task 4 keeps it per connection); remote ignored → **on-demand control** (Task 4 sends `requestControl` before each command).
- [ ] **Step 4: Commit** `spike/walkingpad_remote_probe.py` + spec: `spike: remote vs app control on the Z1`.

---

### Task 2: FTMS control messages

**Files:**
- Create: `WalkingPadKit/Sources/WalkingPadKit/PadCommand.swift`
- Test: `WalkingPadKit/Tests/WalkingPadKitTests/PadCommandTests.swift`

**Interfaces — Produces:**
```swift
public struct SpeedRange: Equatable, Sendable {
    public var minKmh: Double, maxKmh: Double, stepKmh: Double
    public static let z1 = SpeedRange(minKmh: 1.0, maxKmh: 6.0, stepKmh: 0.1)
    public init?(data: Data)                       // 0x2AD4: 3 × uint16 LE in 0.01 km/h
    public func clamp(_ kmh: Double) -> Double     // bounded + rounded to step
}
public enum PadCommand: Equatable, Sendable {
    case requestControl, start, stop, setSpeed(Double)
    public func frame(in range: SpeedRange) -> Data
}
public enum ControlResult: Equatable, Sendable {
    case success, notSupported, invalidParameter, operationFailed, controlNotPermitted, unknown(UInt8)
}
public struct ControlResponse: Equatable, Sendable {
    public var opcode: UInt8, result: ControlResult
    public init?(data: Data)                       // 80 <op> <result>, else nil
}
```

- [ ] **Step 1: Failing tests**
```swift
@Test func framesMatchTheValidatedSpike()   // requestControl→00, start→07, stop→08 01, setSpeed(2.0)→02 c8 00, setSpeed(1.0)→02 64 00
@Test func speedRangeDecodesTheZ1()         // SpeedRange(data: Data(hex: "640058020a00")) == .z1  (100, 600, 10 in 0.01 km/h)
@Test func fasterAndSlowerClampToRange()    // z1.clamp(6.5)==6.0, clamp(0.5)==1.0, clamp(2.04)==2.0, clamp(2.06)==2.1
@Test func noFrameEverStartsWithE8()        // all four commands, several speeds: frame.first != 0xE8
@Test func controlResponseDecodes()         // "800001"→(0x00,.success), "800205"→(0x02,.controlNotPermitted), "7180"→nil
```
- [ ] **Step 2: Run** `cd WalkingPadKit && swift test --filter PadCommandTests` → FAIL (types missing).
- [ ] **Step 3: Implement** in `PadCommand.swift`.
- [ ] **Step 4: Run** → 5 PASS; full `swift test` green.
- [ ] **Step 5: Commit** `feat: encode FTMS control commands for the Z1`.

---

### Task 3: AutoPilot and link commands

**Files:**
- Create: `WalkingPadKit/Sources/WalkingPadKit/AutoPilot.swift`, `WalkingPadKit/Sources/WalkingPadKit/PadURLCommand.swift`
- Test: `WalkingPadKit/Tests/WalkingPadKitTests/AutoPilotTests.swift`, `WalkingPadKit/Tests/WalkingPadKitTests/PadURLCommandTests.swift`

**Interfaces — Consumes:** `TreadmillSample`, `PadCommand`. **Produces:**
```swift
public struct AutoPilotSettings: Equatable, Sendable, Codable {
    public var preferredSpeedEnabled = true, preferredSpeedKmh = 2.0, autoStopEnabled = true
}
public struct AutoPilot: Sendable {
    public init(settings: AutoPilotSettings)
    public var settings: AutoPilotSettings
    public private(set) var lastAutoStop: Date?
    public mutating func connected(at: Date)                          // (re)connection
    public mutating func observe(_ sample: TreadmillSample) -> [PadCommand]
}
public enum PadURLCommand: Equatable, Sendable {
    case start, stop, speed(Double), faster, slower
    public init(url: URL) throws(PadURLError)
    public func padCommand(currentSpeedKmh: Double, range: SpeedRange) -> PadCommand  // faster/slower = ±0.5, clamped
}
public enum PadURLError: Error, Equatable { case unknownCommand(String), unreadableSpeed(String) }
```
AutoPilot rules (spec « Design » + decisions): a start is a 0 → > 0 speed transition seen on a connection; the first frame after `connected(at:)` is never a start, **except** when a start was seen < 30 s before and its preferred speed was not yet applied. Preferred speed: once per start, ≥ 2 s after the start, only if `|speed − preferred| ≥ 0.05`. Auto-stop: speed > 0, steps reported, ≥ 15 s since the later of start / connection, and no step increase for ≥ 10 s → one `stop`; reset when speed returns to 0. Never emits `.start`.

- [ ] **Step 1: Failing tests** (helper `frames(from:speed:steps:)` builds 1 Hz samples)
```swift
@Test func remoteStartGetsPreferredSpeedAfterSettle()        // 0 then 1.0 from t=10: nothing at t=11, [.setSpeed(2.0)] at t=12, nothing after
@Test func noOverrideAfterManualChange()                    // after apply, frames at 3.5 → []
@Test func alreadyAtPreferredSpeedSendsNothing()
@Test func preferredSpeedDisabledSendsNothing()
@Test func connectingToRunningBeltIsNotAStart()             // connected(t); frames at 2.5 → never setSpeed
@Test func reconnectRightAfterStartStillAppliesSpeed()      // start at t, connected(t+5), 1.0 frames → setSpeed(2.0)
@Test func stepOffStopsAfterTenSecondsWithoutSteps()        // walk 30 s (steps +1/s) then flat → [.stop] exactly 10 s after last step, once
@Test func noStopDuringStartGrace()                         // start, steps flat → no stop before start+15
@Test func emptyBeltAfterStartStopsWithinTwentyFiveSeconds()
@Test func slowWalkingNeverStops()                          // a step every 4 s for 5 min → no stop
@Test func graceRestartsOnReconnect()                       // flat steps, connected(t) mid-run → no stop before t+15
@Test func autoStopDisabledOrNoStepsNeverStops()
@Test func neverEmitsStart()                                // across all scenarios above
```
```swift
@Test func parsesEveryLink()                 // tapismarche://demarrer→.start, arreter→.stop, vitesse/2.5→.speed(2.5), plus-vite→.faster, moins-vite→.slower
@Test func speedAcceptsFrenchDecimalComma()  // vitesse/2,5 → .speed(2.5)
@Test func rejectsUnknownOrUnreadable()      // tapismarche://danser → .unknownCommand, vitesse/vite → .unreadableSpeed
@Test func fasterSlowerFromCurrentSpeed()    // faster at 2.0 → .setSpeed(2.5); slower at 1.2 → .setSpeed(1.0)
```
- [ ] **Step 2: Run** `swift test --filter "AutoPilotTests|PadURLCommandTests"` → FAIL.
- [ ] **Step 3: Implement** both files.
- [ ] **Step 4: Run** full `swift test` → all PASS.
- [ ] **Step 5: Commit** `feat: AutoPilot (preferred speed, step-off stop) and link commands`.

---

### Task 4: Control channel in the app

**Files:**
- Modify: `App/PadConnection.swift`

**Interfaces — Consumes:** `PadCommand`, `ControlResponse`, `SpeedRange`. **Produces** (on `PadConnection`):
```swift
var onConnected: (Date) -> Void
private(set) var speedRange: SpeedRange          // .z1 until 0x2AD4 is read
func send(_ command: PadCommand)                 // queued, ≥ 400 ms apart, one in flight awaiting its indication (timeout 3 s)
var isReady: Bool { get }                        // connected and Control Point discovered
```
Discover `0x2AD9` (enable indications) and `0x2AD4` (read) alongside `0x2ACD`; on ready: read range, then `requestControl` if Task 1 chose held control; on `controlNotPermitted`: `requestControl` then the same command, once. Log every write and result (`control → 02 c8 00`, `control ← success`).

- [ ] **Step 1: Build** `make build` → `** BUILD SUCCEEDED **`.
- [ ] **Step 2: Commit** `feat: FTMS control channel in PadConnection`.

---

### Task 5: Menu, settings, links, notifications

**Files:**
- Modify: `App/AppModel.swift`, `App/MenuBarView.swift`, `App/SettingsView.swift`, `App/TapisMarcheApp.swift`, `project.yml` (`CFBundleURLTypes` scheme `tapismarche`)
- Create: `App/AppDelegate.swift` (receives `application(_:open:)`)

AppModel: owns `AutoPilot` (settings persisted in UserDefaults key `autoPilot`), feeds it every sample, sends its commands; `connection.onConnected` → `autoPilot.connected(at:)`. `perform(_ link: PadURLCommand)`: if `isReady` send now, else keep as the single pending command and drop it after 10 s with a `UNUserNotification` « Tapis introuvable ». Menu: « Démarrer le tapis » (belt stopped) / « Arrêter le tapis » (moving), « Plus vite », « Moins vite », disabled unless ready and not released; line « Arrêt auto à HH:mm : personne sur le tapis » when `lastAutoStop` is today. Settings: Toggle « Vitesse au démarrage » + Stepper 1.0–6.0 step 0.1; Toggle « Arrêter quand je descends ».

- [ ] **Step 1: Build** `make build` → `** BUILD SUCCEEDED **`; `make install`, relaunch.
- [ ] **Step 2: Live — menu start** (David on the pad): « Démarrer le tapis » → log `control → 07`, belt 1.0 then `control → 02 c8 00` ≈ 2 s later, belt 2.00.
- [ ] **Step 3: Live — step off**: David steps off → log `control → 08 01` ≈ 10 s after his last step; menu shows « Arrêt auto à … ».
- [ ] **Step 4: Live — link**: `open -g "tapismarche://vitesse/2,5"` while walking → belt 2.50; app quit then `open -g tapismarche://demarrer` → belt starts once connected (≤ 10 s).
- [ ] **Step 5: Commit** `feat: belt control from menu and tapismarche:// links`.

---

### Task 6: Raycast commands and docs

**Files:**
- Create: `raycast/tapis-demarrer.sh`, `raycast/tapis-arreter.sh`, `raycast/tapis-vitesse.sh`, `raycast/tapis-plus-vite.sh`, `raycast/tapis-moins-vite.sh` (executable)
- Modify: `README.md` (section « Piloter le tapis » : menu, liens, Raycast setup, suggested hotkeys ⌥⌘↑ / ⌥⌘↓)

Each script: `#!/bin/bash`, `@raycast.schemaVersion 1`, `@raycast.title` (« Démarrer le tapis », « Arrêter le tapis », « Vitesse du tapis », « Tapis plus vite », « Tapis moins vite »), `@raycast.mode silent`, `@raycast.icon 🚶`, `@raycast.packageName Tapis Marche`; `tapis-vitesse.sh` adds `@raycast.argument1 {"type":"text","placeholder":"km/h"}`; body `open -g "tapismarche://…"`.

- [ ] **Step 1: Check** `for f in raycast/*.sh; do bash -n "$f" && grep -q '@raycast.schemaVersion 1' "$f"; done && echo ok` → `ok`; `raycast/tapis-arreter.sh` stops a running belt (log `control → 08 01`).
- [ ] **Step 2: Live — Raycast** (David adds the directory, runs « Démarrer le tapis »): belt starts, then 2 km/h.
- [ ] **Step 3: Commit** `feat: Raycast script commands for the treadmill`.
