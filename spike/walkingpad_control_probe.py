"""THROWAWAY SPIKE — can we drive the WalkingPad Z1 (KS-HD-*) belt from the Mac?

Sequence: connect, read speed range, then via the standard FTMS Control Point:
request control → start → 1.0 km/h → 2.0 km/h → stop. First WITHOUT the KingSmith
unlock frame; if the pad ignores or refuses control, again WITH it.

Safety (enforced in code): speed capped at 2.0 km/h, frames starting with 0xE8 refused
(OTA mode, brick risk), >= 400 ms between writes, STOP always sent in `finally`.
Someone must be standing on the pad. Close KS Fit and quit the Tapis Marche app first.

Usage: python -u spike/walkingpad_control_probe.py [--countdown 10] [--hold 8]
"""

import argparse
import asyncio
import sys
import time

from bleak import BleakClient, BleakScanner

TREADMILL_DATA = "00002acd-0000-1000-8000-00805f9b34fb"
SPEED_RANGE = "00002ad4-0000-1000-8000-00805f9b34fb"
CONTROL_POINT = "00002ad9-0000-1000-8000-00805f9b34fb"
MACHINE_STATUS = "00002ada-0000-1000-8000-00805f9b34fb"
SUPPLEMENT_NOTIFY = "24e2521c-f63b-48ed-85be-c5330b00fdf7"
SUPPLEMENT_WRITE = "24e2521c-f63b-48ed-85be-c5330d00fdf7"

MAX_SPEED_KMH = 2.0
MIN_WRITE_GAP_S = 0.4
RESULT = {1: "success", 2: "not supported", 3: "invalid parameter", 4: "operation failed", 5: "control not permitted"}
OPCODE = {0x00: "request control", 0x02: "set target speed", 0x07: "start", 0x08: "stop"}


def unlock_frame(name: str) -> bytes:
    """71 00 05 01 <LE32(last 4 chars of name) + 1> <sum mod 256>, per z1-walkingpad-mcp."""
    token = (int.from_bytes(name[-4:].encode("ascii"), "little") + 1) & 0xFFFFFFFF
    body = bytes([0x71, 0x00, 0x05, 0x01]) + token.to_bytes(4, "little")
    return body + bytes([sum(body) & 0xFF])


def log(msg):
    print(f"{time.strftime('%H:%M:%S')} {msg}", flush=True)


class Pad:
    def __init__(self, client):
        self.client = client
        self.last_write = 0.0
        self.speed = 0.0
        self.responses = asyncio.Queue()
        self.unlocked = asyncio.Event()

    async def write(self, char, frame: bytes, response: bool):
        assert frame[0] != 0xE8, "refusing OTA frame"
        wait = MIN_WRITE_GAP_S - (time.monotonic() - self.last_write)
        if wait > 0:
            await asyncio.sleep(wait)
        log(f"→ {char[4:8]} {frame.hex(' ')}")
        await self.client.write_gatt_char(char, frame, response=response)
        self.last_write = time.monotonic()

    async def command(self, frame: bytes, timeout=3.0):
        """Writes to the FTMS Control Point and waits for its indication; returns the result text or None."""
        while not self.responses.empty():
            self.responses.get_nowait()
        await self.write(CONTROL_POINT, frame, response=True)
        try:
            op, result = await asyncio.wait_for(self.responses.get(), timeout)
            text = RESULT.get(result, f"code {result}")
            log(f"← {OPCODE.get(op, hex(op))}: {text}")
            return text
        except asyncio.TimeoutError:
            log(f"← no answer to {OPCODE.get(frame[0], hex(frame[0]))} within {timeout}s")
            return None

    async def set_speed(self, kmh: float):
        kmh = min(kmh, MAX_SPEED_KMH)
        return await self.command(bytes([0x02]) + int(round(kmh * 100)).to_bytes(2, "little"))

    async def stop(self):
        return await self.command(bytes([0x08, 0x01]))

    async def wait_for_speed(self, predicate, timeout):
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            if predicate(self.speed):
                return True
            await asyncio.sleep(0.2)
        return False

    # notification handlers
    def on_treadmill(self, _, data):
        data = bytes(data)
        flags = int.from_bytes(data[0:2], "little")
        if not flags & 1:
            new = int.from_bytes(data[2:4], "little") / 100
            if new != self.speed:
                log(f"   belt speed {new:.2f} km/h")
            self.speed = new

    def on_control(self, _, data):
        data = bytes(data)
        if len(data) >= 3 and data[0] == 0x80:
            self.responses.put_nowait((data[1], data[2]))

    def on_status(self, _, data):
        log(f"   machine status {bytes(data).hex(' ')}")

    def on_supplement(self, _, data):
        data = bytes(data)
        log(f"   supplement {data.hex(' ')}")
        if data[:2] == b"\x71\x80":
            self.unlocked.set()


async def drive(pad: Pad, hold: float, label: str) -> bool:
    log(f"=== attempt {label} ===")
    granted = await pad.command(bytes([0x00]))
    if granted != "success":
        return False
    started = await pad.command(bytes([0x07]))
    if started != "success" and not await pad.wait_for_speed(lambda s: s > 0, 3):
        return False
    if not await pad.wait_for_speed(lambda s: s > 0, 10):
        log("belt did not start")
        return False
    await asyncio.sleep(2)  # let the motor settle (KingSmith quirk)
    for target in (1.0, 2.0):
        await pad.set_speed(target)
        reached = await pad.wait_for_speed(lambda s, t=target: abs(s - t) < 0.15, hold)
        log(f"target {target} km/h → {'reached' if reached else 'NOT reached'} (belt {pad.speed:.2f})")
        await asyncio.sleep(2)
    await pad.stop()
    stopped = await pad.wait_for_speed(lambda s: s == 0, 15)
    log(f"stop → {'belt stopped' if stopped else 'belt still moving'}")
    return True


async def main(args):
    log(f"scanning for KS-HD-*…")
    found = await BleakScanner.discover(timeout=15, return_adv=True)
    pick = next(((d, a) for d, a in found.values() if (a.local_name or d.name or "").startswith("KS-HD-")), None)
    if not pick:
        log("no KS-HD-* pad found (quit Tapis Marche / KS Fit, pad on?)")
        return 2
    device, adv = pick
    name = adv.local_name or device.name
    log(f"found {name}; unlock frame would be {unlock_frame(name).hex(' ')}")

    async with BleakClient(device) as client:
        pad = Pad(client)
        try:
            await client.start_notify(TREADMILL_DATA, pad.on_treadmill)
            await client.start_notify(CONTROL_POINT, pad.on_control)
            await client.start_notify(MACHINE_STATUS, pad.on_status)
            await client.start_notify(SUPPLEMENT_NOTIFY, pad.on_supplement)
            rng = await client.read_gatt_char(SPEED_RANGE)
            lo, hi, step = (int.from_bytes(rng[i:i + 2], "little") / 100 for i in (0, 2, 4))
            log(f"speed range {lo}–{hi} km/h, step {step}")

            for i in range(args.countdown, 0, -1):
                log(f"belt starts in {i}s — stay on the pad")
                await asyncio.sleep(1)

            if await drive(pad, args.hold, "WITHOUT unlock"):
                log("RESULT: control works without unlock")
                return 0
            await pad.write(SUPPLEMENT_WRITE, unlock_frame(name), response=False)
            try:
                await asyncio.wait_for(pad.unlocked.wait(), 3)
                log("pad answered 71 80: unlocked")
            except asyncio.TimeoutError:
                log("no 71 80 answer to the unlock frame")
            if await drive(pad, args.hold, "WITH unlock"):
                log("RESULT: control works after unlock")
                return 0
            log("RESULT: control refused both ways")
            return 1
        finally:
            if client.is_connected:
                log("safety stop")
                await pad.stop()


if __name__ == "__main__":
    p = argparse.ArgumentParser()
    p.add_argument("--countdown", type=int, default=10)
    p.add_argument("--hold", type=float, default=8)
    if "--selftest" in sys.argv:
        assert unlock_frame("KS-HD-Z1D").hex(" ") == "71 00 05 01 2e 5a 31 44 74", unlock_frame("KS-HD-Z1D").hex(" ")
        print("selftest ok:", unlock_frame("KS-HD-Z1E").hex(" "))
        sys.exit(0)
    try:
        sys.exit(asyncio.run(main(p.parse_args())))
    except Exception as e:
        log(f"error {type(e).__name__}: {e}")
        sys.exit(1)
