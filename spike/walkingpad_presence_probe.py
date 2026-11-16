"""THROWAWAY SPIKE — does the Z1 step counter move when nobody is on the belt?

Phases (spoken cues via macOS `say`): empty belt at 1 km/h → David steps on and walks →
David steps off → stop. Every Treadmill Data frame is logged with its phase so we can see
whether steps (KingSmith bit-13 extension) only count real footfalls.

Same safety as walkingpad_control_probe: 1 km/h only, no 0xE8, 400 ms spacing, stop in finally.
"""

import asyncio
import json
import subprocess
import sys
import time
from pathlib import Path

from bleak import BleakClient, BleakScanner

sys.path.insert(0, str(Path(__file__).resolve().parent))
from walkingpad_control_probe import (CONTROL_POINT, MACHINE_STATUS, TREADMILL_DATA,  # noqa: E402
                                      Pad, log)
from walkingpad_probe import parse_ftms_treadmill  # noqa: E402

VOICE = "Eddy (Français (France))"
PHASES = [("vide", 20, "Bande à vide. Reste à côté du tapis."),
          ("montee", 5, "Monte sur le tapis et marche."),
          ("marche", 20, None),
          ("descente", 5, "Descends du tapis maintenant."),
          ("vide-apres", 20, None)]
OUT = Path(__file__).resolve().parent.parent / "data" / f"presence-{time.strftime('%Y%m%d-%H%M%S')}.jsonl"


def say(text):
    log(f"🔊 {text}")
    subprocess.Popen(["say", "-v", VOICE, text])


class Recorder(Pad):
    phase = "avant"

    def __init__(self, client, out):
        super().__init__(client)
        self.out = out

    def on_treadmill(self, sender, data):
        super().on_treadmill(sender, data)
        rec = parse_ftms_treadmill(bytes(data))
        steps = int.from_bytes(bytes.fromhex(rec.get("extra_hex", "")), "little") if rec.get("extra_hex") else None
        row = {"t": round(time.time(), 2), "phase": self.phase, "speed": rec.get("speed_kmh"),
               "dist": rec.get("dist_m"), "elapsed": rec.get("time_s"), "steps": steps}
        self.out.write(json.dumps(row) + "\n")
        self.out.flush()
        log(f"   [{self.phase:10}] speed={row['speed']} steps={steps} dist={row['dist']} t={row['elapsed']}")


async def main():
    found = await BleakScanner.discover(timeout=15, return_adv=True)
    pick = next((d for d, a in found.values() if (a.local_name or d.name or "").startswith("KS-HD-")), None)
    if not pick:
        log("no KS-HD-* pad found")
        return 2
    OUT.parent.mkdir(exist_ok=True)
    with OUT.open("w") as out:
      async with BleakClient(pick) as client:
        pad = Recorder(client, out)
        try:
            await client.start_notify(TREADMILL_DATA, pad.on_treadmill)
            await client.start_notify(CONTROL_POINT, pad.on_control)
            await client.start_notify(MACHINE_STATUS, pad.on_status)
            say("Essai dans dix secondes. Reste à côté du tapis, sans monter.")
            await asyncio.sleep(10)
            if await pad.command(bytes([0x00])) != "success":
                log("control refused")
                return 1
            await pad.command(bytes([0x07]))
            await pad.wait_for_speed(lambda s: s > 0, 10)
            for name, seconds, cue in PHASES:
                pad.phase = name
                if cue:
                    say(cue)
                await asyncio.sleep(seconds)
            pad.phase = "arret"
            await pad.stop()
            await pad.wait_for_speed(lambda s: s == 0, 15)
            say("Terminé, merci.")
            log(f"frames written to {OUT}")
            return 0
        finally:
            if client.is_connected:
                log("safety stop")
                await pad.stop()


if __name__ == "__main__":
    try:
        sys.exit(asyncio.run(main()))
    except Exception as e:
        log(f"error {type(e).__name__}: {e}")
        sys.exit(1)
