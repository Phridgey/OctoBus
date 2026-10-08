# OctoBus

Arrival timers for the zeppelins at the Orgrimmar towers, the Sparkwater Port boat, and the Ratchet to Booty Bay boat, for the vanilla 1.12.1 client (tested on OctoWow / Turtle WoW).

A small minimap icon opens a window listing every transport with a live timer: how long until it **leaves** if it is docked, or how long until it **docks** if it is away. For the Ratchet boat it shows when to **fly** from Orgrimmar to make the next sailing. Click a transport to put a bell on it and get a chat message shortly before it arrives (or, for the Ratchet boat, shortly before you need to fly).

OctoBus needs one extra file, `ZepSense.dll`, which you install by hand in the game folder. Your launcher can install the addon but not the DLL. See [Install](#install).

## What you see

| Window element | Meaning |
|---|---|
| Green check | Transport is docked now. The timer counts down to departure ("leaves"). |
| Red X | Transport is away. The timer counts down to docking ("docks"). |
| `~` before a time | An estimate from stored data. It goes away once you see the transport dock or leave. |
| `fly 4:55 sails 6:40` | Ratchet boat only: leave Orgrimmar in 4:55 to be on the Ratchet dock before it sails in 6:40. If you can no longer make a sailing, it shows the next one. |
| Bell on a row | Alerts are on for that route (click a row to toggle). |
| Footer | The transport whose data is oldest, e.g. `oldest data: Undercity zeppelin, seen 3 h ago`. It turns orange after 5 days, as a hint to go and see it again. |
| Dots, bottom-right corner | Drag to make the window bigger or smaller. |

Routes tracked (with built-in starting values, which refine themselves as you play): the Undercity, Grom'gol, Kargath and Thunder Bluff zeppelins, the Sparkwater Port boat (hide it with `/ob boat`), and the Ratchet boat. You can rename the place part of any route with `/ob name`.

## Requirements

1. **`ZepSense.dll`**, a small client DLL that exposes one Lua function, `ZepTransports()`, which returns the position of every zeppelin/boat the client currently has loaded. The addon cannot see transports without it. Without the DLL it shows built-in estimates only (marked `~`).
2. A client setup that loads DLLs listed in `dlls.txt`.

## Install

Installing takes two parts. The addon can be installed by your launcher; the DLL always has to be set up by hand.

### Part 1: the addon

- **With a launcher:** add this repository's git address (`https://github.com/Phridgey/OctoBus.git`).
- **By hand:** download this repository as a ZIP (green "Code" button, then "Download ZIP"), unzip it, rename the folder to `OctoBus` and put it in `Interface\AddOns\`. The folder must contain `OctoBus.toc` directly.

### Part 2: the DLL (manual, the launcher does not do this)

1. Download `ZepSense.dll` from the [Releases page](https://github.com/Phridgey/OctoBus/releases/latest).
2. Put it in the game folder, next to `WoW.exe`.
3. Open `dlls.txt` in the game folder and add a line `ZepSense.dll`.
4. Start the game fully (a `/reload` is not enough the first time the DLL is added).
5. Check it worked: open the window (`/ob` or the minimap icon). If the top-right corner says **"no DLL: estimates only"**, the DLL is not loaded (see [Troubleshooting](#troubleshooting)). If that note is absent, everything is working. There is nothing else to set up: the timers correct themselves each time you see a transport dock.

The DLL only reads transport positions that the client has already loaded; it does not send anything anywhere. Its source is `ZepSense_src/ZepSense_v5.c` (built with `i686-w64-mingw32-gcc -O2 -shared -static-libgcc -Wl,--kill-at -s`). As with any client DLL, use it at your own risk and check your server's rules.

Saved data lives in `WTF\...\SavedVariables\OctoBus.lua`.

## Using it

- **Minimap icon**: click to show/hide the window anywhere; drag to move it around the minimap edge.
- **Auto-show**: the window opens by itself in Orgrimmar and Durotar, and while the Ratchet boat is in view (on its dock and for the whole crossing). It hides elsewhere. The icon toggle always works manually. Add more auto-show places with `/ob allow <zone or sub-zone>` (capitals do not matter; `/ob where` shows the names), remove one with `/ob disallow <name>`, or turn the behaviour off with `/ob zone`.
- **Bells**: click a transport row to toggle a bell. Belled routes print a chat message `/ob alert` seconds (default 45) before arrival. Nothing is printed to chat for routes without a bell.
- **Move and size the window**: drag it to move it; drag the dots in the bottom-right corner (or use `/ob scale`) to resize it. `/ob lock` locks position and size; `/ob resetpos` puts the window and icon back at their default place and size.

## How the timing works

Each route runs on a fixed cycle. Once the addon sees one transport arrive, it can predict every later arrival, even while the transport is out of view (transports are only sent to your client when they are near you, so they drop out of range for part of each trip).

- **Automatic calibration**: any arrival you watch near the towers calibrates that route. The first time takes two sightings, later refreshes take one. The cycle length is refined as more arrivals are seen, and the dock-time (how long a transport waits) is learned too.
- **`/ob calibrate`** (optional): watches every transport on purpose. Stand between the two towers where you can see the docks, do not `/reload`, and wait; rows are marked complete as each route is confirmed. A transport being out of view for a while is normal. If nothing at all has been seen after about 10 minutes, move closer to the towers. `/ob calibrate stop` cancels.
- Transports are not reported from deep inside the city (bank / auction house area), so calibrate near the towers.
- **One odd sighting does not wipe a route's history.** A sighting that does not fit the schedule is set aside; the schedule only starts over (for example after a server restart) when a second sighting agrees with it.

### The Ratchet boat

The Ratchet boat cannot be seen from Orgrimmar, so its row is always an estimate (`~`) built from the last time someone with the addon was at Ratchet. Its built-in timing was measured on two rides (cycle 364.07 s, 64 s at the dock). Every time you are at Ratchet with the boat in view, the timing is corrected and the cycle refined, so predictions stay accurate for longer the more visits it has seen.

`fly` is the boat's departure from Ratchet minus your travel time from Orgrimmar to the dock. Set your own with `/ob travel <seconds>` (default 175: enough for a slower mount, with some time to spare; time your own trip from take-off at the Orgrimmar flight master to standing on the boat).

## Commands

`/ob` (also `/transit` and `/zep`)

| Command | What it does |
|---|---|
| `/ob` | Show / hide the window (works anywhere) |
| `/ob list` | Print all timers in chat |
| `/ob alert <sec>` | Bell alerts fire this many seconds before arrival (default 45, `0` = off) |
| `/ob chat`, `/ob sound`, `/ob flash` | Toggle that alert type (chat on by default; sound and screen flash off) |
| `/ob zone` | Toggle "auto-show only in Orgrimmar / Durotar" |
| `/ob allow <name>` | Also auto-show in this zone or sub-zone |
| `/ob disallow <name>` | Take a place off that list |
| `/ob allowclear` | Remove all the extra auto-show places |
| `/ob where` | Print your zone / sub-zone and whether the window auto-shows here |
| `/ob boat` | Show / hide the Sparkwater Port boat |
| `/ob shape square\|round\|auto` | Minimap icon placement. `auto` reads your minimap shape (tell it explicitly if you use a square minimap addon and the icon sits wrong) |
| `/ob travel <sec>` | Your travel time from Orgrimmar to the Ratchet dock, used for `fly` |
| `/ob scale <n>` | Window size, 0.6 to 2 (same as dragging the bottom-right corner) |
| `/ob lock` | Lock / unlock the window position and size |
| `/ob resetpos` | Put the window and icon back in their default spots and size |
| `/ob name <n> <text>` | Rename route number `n` (numbers from `/ob list`) |
| `/ob period <n> <sec>` | Set a route's cycle length by hand |
| `/ob calibrate` | Watch all transports on purpose (see above); `/ob calibrate stop` cancels |
| `/ob reset` | Forget everything learned and go back to built-in values |
| `/ob debug` | Print once whether the DLL is answering and the raw data it returns (prints only, records nothing) |
| `/ob debug on` / `off` | For working out new routes only; not needed in normal use. Records every transport the DLL reports to the saved file, which grows quickly, so always turn it off again. `REC` shows in the window while it runs. |

## Troubleshooting

- **"no DLL: estimates only"**: the DLL is not loaded. Check that `ZepSense.dll` is in the game folder and listed in `dlls.txt`, then fully restart the game. `/ob debug` shows the state.
- **Times have a `~` and never confirm**: walk toward the towers and wait for an arrival, or run `/ob calibrate`.
- **`/ob` does nothing or prints a start-up error**: the addon reports its own load errors in chat; copy the message when reporting a bug.
- **Window did not auto-show**: use `/ob where` to see your zone and sub-zone names, then `/ob allow <name>` if you want it there.
- **Ratchet times look wrong**: it has probably been a long time, or there was a server restart, since anyone with the addon saw it. Visit Ratchet with the window open and wait for the boat to dock.
- **Everything looks off after a big server change** (new route timings): `/ob reset`, then calibrate again.
