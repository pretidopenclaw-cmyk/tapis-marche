# Tapis Marche

A macOS menu bar app for the **KingSmith WalkingPad Z1** under-desk treadmill — no KS Fit app needed.

- **Auto-start speed** — whenever the belt starts (remote, Mac or Raycast), it switches to your preferred speed (2.0 km/h by default).
- **Stops when you step off** — no step counted for 10 s while the belt is moving → the belt stops.
- **Control from the Mac** — menu bar, `tapismarche://` links, and ready-made **Raycast** commands (bind them to hotkeys).
- **Walking journal** — every walk is recorded locally (SQLite) and pushed to a **Notion** database, with a weekly recap page.
- **Live menu bar** — `🚶 2,0 km/h · 4 210 pas`, today's and this week's totals.

The UI is in French (it was built for a French-speaking user); the code and docs are in English.

> Built in an afternoon with Claude Code. Tested on a WalkingPad Z1 advertising as `KS-HD-Z1E`.
> Other `KS-HD-*` models speak the same FTMS protocol but are untested. **Use at your own risk** — this app moves a
> treadmill belt. Not affiliated with KingSmith.

## How it talks to the pad

Standard Bluetooth **FTMS**, nothing proprietary: Treadmill Data (`0x2ACD`) for speed, distance, time and the
KingSmith step counter; Control Point (`0x2AD9`) for start, stop and target speed.
On the tested unit **no vendor unlock handshake was needed**. Protocol notes and captures:
[`docs/walkingpad-z1-protocol.md`](docs/walkingpad-z1-protocol.md).

Safety rules enforced in code: the app never starts the belt on its own, speeds are clamped to the pad's
announced range (and to 0.5–6.0 km/h), commands are spaced ≥ 400 ms apart, and no `0xE8` frame can ever be built.

## Build

Requirements: macOS 15+, Xcode 26+, [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```bash
make test      # 107 unit tests (WalkingPadKit, swift test)
make build     # generates the Xcode project and builds build/Build/Products/Release/TapisMarche.app
make install   # copies it to /Applications
make run
```

Builds are ad-hoc signed by default. To keep Bluetooth permission and Keychain access across rebuilds, sign with
your own certificate in a git-ignored `Local.mk`:

```make
DEVELOPMENT_TEAM := ABCDE12345
CODE_SIGN_IDENTITY := Apple Development
```

Close KS Fit on your phone: the pad accepts a single Bluetooth connection.

## Notion (optional)

1. Create an internal integration at <https://www.notion.so/profile/integrations> and copy its secret.
2. On the Notion page that will hold the journal: `…` › Connections › add the integration; copy the page link.
3. Menu › Réglages… › paste the secret and the link › « Connecter Notion ».
   The app creates a « Marches » database and a « Récaps hebdo » page. The secret is stored in the macOS Keychain only.

## Raycast and links

```bash
open -g "tapismarche://demarrer"      # start
open -g "tapismarche://arreter"       # stop
open -g "tapismarche://vitesse/2.5"   # set speed (2,5 works too)
open -g "tapismarche://plus-vite"     # +0.5 km/h
open -g "tapismarche://moins-vite"    # −0.5 km/h
```

Raycast › Settings › Extensions › Script Commands › Add Directories › this repo's [`raycast/`](raycast) folder.
Then assign hotkeys from Raycast (⌘K › Configure Command).

## Project layout

| Path | What |
|---|---|
| `WalkingPadKit/` | pure, tested logic: FTMS decoding and commands, session tracking, SQLite journal, AutoPilot, Notion sync |
| `App/` | the menu bar app: CoreBluetooth, SwiftUI menu and settings, Keychain, links |
| `raycast/` | Raycast Script Commands |
| `spike/` | throwaway Python probes used to reverse-engineer the pad (bleak) |
| `docs/superpowers/` | design docs and implementation plans (in French) |

## License

[MIT](LICENSE)
