"""THROWAWAY SPIKE — read-only probe of a KingSmith WalkingPad over BLE.

Scans, identifies the protocol family (legacy WiLink fe00/fe01/fe02 or FTMS 0x1826),
dumps the GATT table, then streams live data. Never sends a motor command:
in WiLink mode it only writes the status query (f7 a2) and the last-run query (f7 a7);
in FTMS mode it writes nothing at all.

Usage: python -u spike/walkingpad_probe.py [--scan 15] [--duration 180]
"""

import argparse
import asyncio
import json
import re
import sys
import time
from pathlib import Path

from bleak import BleakClient, BleakScanner

FE01 = "0000fe01-0000-1000-8000-00805f9b34fb"  # WiLink notify
FE02 = "0000fe02-0000-1000-8000-00805f9b34fb"  # WiLink write
FTMS_SERVICE = "00001826-0000-1000-8000-00805f9b34fb"
TREADMILL_DATA = "00002acd-0000-1000-8000-00805f9b34fb"

ASK_STATS = bytes([0xF7, 0xA2, 0x00, 0x00, 0xA2, 0xFD])
ASK_LAST_RUN = bytes([0xF7, 0xA7, 0xAA, 0xFF, 0x50, 0xFD])

NAME_PATTERN = re.compile(r"walking|^ks-|kingsmith", re.IGNORECASE)
BELT_STATES = {0: "idle", 1: "running", 5: "standby", 9: "starting"}

DATA_DIR = Path(__file__).resolve().parent.parent / "data"


def u24(b, i):
    return (b[i] << 16) | (b[i + 1] << 8) | b[i + 2]


def parse_wilink(b):
    if len(b) >= 17 and b[0] == 0xF8 and b[1] == 0xA2:
        return {
            "kind": "live",
            "belt_state": BELT_STATES.get(b[2], b[2]),
            "speed_kmh": b[3] / 10,
            "manual_mode": b[4],
            "time_s": u24(b, 5),
            "dist_m": u24(b, 8) * 10,
            "steps": u24(b, 11),
        }
    if len(b) >= 17 and b[0] == 0xF8 and b[1] == 0xA7:
        return {"kind": "last_run", "time_s": u24(b, 8), "dist_m": u24(b, 11) * 10, "steps": u24(b, 14)}
    return None


def parse_ftms_treadmill(b):
    """Bluetooth SIG FTMS Treadmill Data (0x2ACD). Unknown trailing bytes kept raw."""
    flags = int.from_bytes(b[0:2], "little")
    i, out = 2, {"kind": "ftms", "flags": f"{flags:016b}"}

    def take(n, signed=False):
        nonlocal i
        v = int.from_bytes(b[i:i + n], "little", signed=signed)
        i += n
        return v

    if not flags & 0x0001:
        out["speed_kmh"] = take(2) / 100
    if flags & 0x0002:
        out["avg_speed_kmh"] = take(2) / 100
    if flags & 0x0004:
        out["dist_m"] = take(3)
    if flags & 0x0008:
        out["incline_pct"] = take(2, True) / 10
        take(2, True)
    if flags & 0x0010:
        take(2)
        take(2)
    if flags & 0x0020:
        take(1)
    if flags & 0x0040:
        take(1)
    if flags & 0x0080:
        out["kcal"] = take(2)
        take(2)
        take(1)
    if flags & 0x0100:
        out["hr"] = take(1)
    if flags & 0x0200:
        take(1)
    if flags & 0x0400:
        out["time_s"] = take(2)
    if flags & 0x0800:
        take(2)
    if flags & 0x1000:
        take(2, True)
        take(2, True)
    if i < len(b):
        out["extra_hex"] = b[i:].hex()  # KingSmith steps extension (bit 13) lands here
    return out


async def find_pad(scan_s):
    print(f"[scan] {scan_s}s…", flush=True)
    found = await BleakScanner.discover(timeout=scan_s, return_adv=True)
    candidates = []
    for dev, adv in found.values():
        name = adv.local_name or dev.name or ""
        uuids = [u.lower() for u in adv.service_uuids]
        hit = NAME_PATTERN.search(name) or any(u.startswith(("0000fe00", "00001826")) for u in uuids)
        if name:
            print(f"  {'>>' if hit else '  '} {name!r:30} {dev.address} rssi={adv.rssi} uuids={uuids}", flush=True)
        if hit:
            candidates.append((adv.rssi, dev, name))
    candidates.sort(key=lambda c: c[0], reverse=True)
    return candidates[0] if candidates else None


def dump_gatt(client):
    print("[gatt]", flush=True)
    chars = {}
    for svc in client.services:
        print(f"  service {svc.uuid} ({svc.description})", flush=True)
        for ch in svc.characteristics:
            chars[ch.uuid.lower()] = ch
            print(f"     char {ch.uuid} {ch.properties} ({ch.description})", flush=True)
    return chars


async def run(args):
    pick = await find_pad(args.scan)
    if not pick:
        print("[fail] no WalkingPad-like device found (is it on? KS Fit closed?)", flush=True)
        return 2
    rssi, dev, name = pick
    print(f"[pick] {name} {dev.address} rssi={rssi}", flush=True)

    DATA_DIR.mkdir(exist_ok=True)
    out_path = DATA_DIR / f"spike-{time.strftime('%Y%m%d-%H%M%S')}.jsonl"
    out = out_path.open("w")

    def record(rec, raw):
        rec |= {"t": round(time.time(), 2), "raw": raw.hex()}
        out.write(json.dumps(rec) + "\n")
        out.flush()
        print(f"[data] {json.dumps(rec)}", flush=True)

    async with BleakClient(dev) as client:
        print(f"[conn] connected={client.is_connected}", flush=True)
        chars = dump_gatt(client)

        if FE01 in chars and FE02 in chars:
            print("[mode] legacy WiLink protocol", flush=True)

            def on_fe01(_, data):
                rec = parse_wilink(bytes(data))
                record(rec or {"kind": "unknown"}, bytes(data))

            await client.start_notify(FE01, on_fe01)
            await client.write_gatt_char(FE02, ASK_LAST_RUN)
            deadline = time.time() + args.duration
            while time.time() < deadline and client.is_connected:
                await client.write_gatt_char(FE02, ASK_STATS)
                await asyncio.sleep(1)
        elif TREADMILL_DATA in chars:
            print("[mode] FTMS (read-only, no unlock handshake attempted)", flush=True)

            def make_handler(uuid):
                def handler(_, data):
                    data = bytes(data)
                    rec = parse_ftms_treadmill(data) if uuid == TREADMILL_DATA else {"kind": "notify", "char": uuid}
                    record(rec, data)
                return handler

            for uuid, ch in chars.items():
                if "notify" in ch.properties:
                    try:
                        await client.start_notify(uuid, make_handler(uuid))
                        print(f"[sub] {uuid}", flush=True)
                    except Exception as e:  # spike: report and keep going
                        print(f"[sub-fail] {uuid}: {e}", flush=True)
            await asyncio.sleep(args.duration)
        else:
            print("[mode] unknown — GATT dumped above, nothing subscribed", flush=True)

    out.close()
    print(f"[done] records in {out_path}", flush=True)
    return 0


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--scan", type=float, default=15)
    p.add_argument("--duration", type=float, default=180)
    args = p.parse_args()
    try:
        sys.exit(asyncio.run(run(args)))
    except Exception as e:
        print(f"[error] {type(e).__name__}: {e}", flush=True)
        sys.exit(1)


if __name__ == "__main__":
    main()
