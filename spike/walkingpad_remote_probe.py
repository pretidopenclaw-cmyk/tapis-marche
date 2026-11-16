"""THROWAWAY SPIKE — does the Z1 remote still work while the Mac holds FTMS control?

Takes control (request control only), then asks David out loud to start, change speed and
stop with the remote, and logs what the belt does. Sends no movement command;
safety stop in `finally`.
"""

import asyncio
import subprocess
import sys
from pathlib import Path

from bleak import BleakClient, BleakScanner

sys.path.insert(0, str(Path(__file__).resolve().parent))
from walkingpad_control_probe import CONTROL_POINT, MACHINE_STATUS, TREADMILL_DATA, Pad, log  # noqa: E402

VOICE = "Eddy (Français (France))"
STEPS = [("Démarre le tapis avec la télécommande.", 20),
         ("Change la vitesse avec la télécommande.", 20),
         ("Arrête le tapis avec la télécommande.", 20)]


def say(text):
    log(f"🔊 {text}")
    subprocess.Popen(["say", "-v", VOICE, text])


async def main():
    found = await BleakScanner.discover(timeout=15, return_adv=True)
    device = next((d for d, a in found.values() if (a.local_name or d.name or "").startswith("KS-HD-")), None)
    if not device:
        log("no KS-HD-* pad found")
        return 2
    async with BleakClient(device) as client:
        pad = Pad(client)
        try:
            await client.start_notify(TREADMILL_DATA, pad.on_treadmill)
            await client.start_notify(CONTROL_POINT, pad.on_control)
            await client.start_notify(MACHINE_STATUS, pad.on_status)
            log(f"control: {await pad.command(bytes([0x00]))}")
            say("Le Mac a pris le contrôle du tapis. Prends la télécommande.")
            await asyncio.sleep(6)
            speeds = []
            for cue, seconds in STEPS:
                say(cue)
                await asyncio.sleep(seconds)
                speeds.append(pad.speed)
                log(f"after « {cue} » belt speed = {pad.speed:.2f}")
            started, changed, stopped = speeds[0] > 0, speeds[1] not in (0, speeds[0]), speeds[2] == 0
            log(f"RESULT: remote start={'yes' if started else 'NO'} speed change={'yes' if changed else 'NO'} "
                f"stop={'yes' if stopped else 'NO'} while control held")
            say("Terminé, merci.")
            return 0
        finally:
            if client.is_connected and pad.speed > 0:
                log("safety stop")
                await pad.stop()


if __name__ == "__main__":
    try:
        sys.exit(asyncio.run(main()))
    except Exception as e:
        log(f"error {type(e).__name__}: {e}")
        sys.exit(1)
