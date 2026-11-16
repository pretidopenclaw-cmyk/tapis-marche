# KingSmith WalkingPad Z1 (`KS-HD-Z1E`) — BLE notes

Observed on 2026-11-16 on a WalkingPad Z1 advertising as `KS-HD-Z1E`, from macOS (CoreBluetooth / bleak).
Probes are in [`spike/`](../spike); everything below was checked on the real device.

## TL;DR

- The pad speaks **standard Bluetooth FTMS** (service `0x1826`).
- On this unit, **no KingSmith unlock handshake is needed**, neither to read Treadmill Data nor to drive the belt.
  Other projects ([z1-walkingpad-mcp](https://github.com/slandau3/z1-walkingpad-mcp),
  [walkingpad-controller](https://github.com/mcdax/walkingpad-controller)) report that a `KS-HD-Z1D` ignores
  everything until the unlock frame is sent — firmware probably differs between units.
- The **step counter only counts real footfalls**: it stays flat on an empty moving belt, which makes it a usable
  "is someone walking?" signal.

## GATT table

| Service | Characteristics |
|---|---|
| `180A` Device Information | serial, software, hardware, firmware, manufacturer, model (read) |
| `FFF0` vendor | `FFF1` notify, `FFF2` write-no-response |
| `FFE0` vendor | `FFE1` notify, `FFE2` write-no-response |
| `1826` Fitness Machine | `2ACC` feature, `2ACD` Treadmill Data (notify), `2AD3` training status, `2AD4` speed range, `2AD5` incline range, `2AD7` HR range, `2AD9` Control Point (write + indicate), `2ADA` machine status |
| `24E2521C-F63B-48ED-85BE-C5330A00FDF7` KingSmith "supplement" | `…0B00FDF7` notify, `…0D00FDF7` write-no-response |
| `02F00000-…-FE00` vendor | `FF00`–`FF03` |

The vendor services stayed silent during passive listening.

## Treadmill Data (`0x2ACD`), 1 Hz

17-byte frames, flags `0x2484`:

| Bytes | Field | Notes |
|---|---|---|
| 0–1 | flags | bits 2, 7, 10, 13 set |
| 2–3 | instantaneous speed | uint16 LE, 0.01 km/h |
| 4–6 | total distance | uint24 LE, metres — **moves in 10 m steps** |
| 7–11 | energy | total kcal (uint16), per hour, per minute |
| 12–13 | elapsed time | uint16 LE, seconds (freezes while paused) |
| 14–16 | **steps** (KingSmith extension, flag bit 13) | uint24 LE |

Idle frame: `84 24 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00`.

Step counter, belt at 1.0 km/h: empty 20 s → +0 · walking 20 s → +22 · stepped off 20 s → +0.
The first step is counted 4–5 s after stepping on. Counters freeze during a 2-minute pause, and reset to 0 after an FTMS stop.

## Driving the belt (`0x2AD9`)

Plain FTMS Control Point, write with response, result as an indication `80 <opcode> <result>`:

| Command | Frame | Observed |
|---|---|---|
| Request control | `00` | `80 00 01` success |
| Start / resume | `07` | belt reaches 1.0 km/h in ≈ 4 s |
| Set target speed | `02` + uint16 LE (0.01 km/h) — 2.0 km/h = `02 c8 00` | reached in ≈ 1 s |
| Stop | `08 01` | belt at 0 in ≈ 4 s |

- Supported Speed Range (`0x2AD4`): `64 00 58 02 0a 00` → **1.0–6.0 km/h, step 0.1** (the official app only offers 0.5 steps).
- Machine Status (`0x2ADA`): `04` started, `05 xx xx` new target speed, `02 01` stopped (FTMS stop), `02 02` paused (remote stop).
- **The remote keeps working while an FTMS client holds control** (start, speed change and stop all tested).
- Only one BLE central can be connected at a time: KS Fit and this app exclude each other.

## Safety notes

- Never send frames starting with `0xE8` (reported OTA mode — brick risk).
- Keep ≥ 400 ms between writes and wait for each Control Point indication.
- Bound target speeds to the announced range.

## Unlock frame (not needed here, documented for completeness)

Per z1-walkingpad-mcp: `71 00 05 01 <LE32(last 4 chars of BLE name) + 1> <sum mod 256>` on `…0D00FDF7`.
For `KS-HD-Z1E`: `71 00 05 01 2e 5a 31 45 75`.
