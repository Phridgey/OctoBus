# OctoBus

Arrival timers for the zeppelins at the Orgrimmar towers, plus the Sparkwater Port boat, for the vanilla 1.12.1 client (tested on OctoWow / Turtle WoW).

A small minimap icon opens a window listing every transport with a live timer: how long until it **leaves** if it is docked, or how long until it **docks** if it is away. Click a transport to put a bell on it and get a chat message shortly before it arrives.

OctoBus is a standalone addon. It does not need pfUI or any other addon.

## What you see

| Window element | Meaning |
|---|---|
| Green check | Transport is docked now. The timer counts down to departure ("leaves"). |
| Red X | Transport is away. The timer counts down to docking ("docks"). |
| `~` before a time | An estimate from stored data. It goes away once you see the transport dock or leave. |
| Bell on a row | Alerts are on for that route (click a row to toggle). |
| Footer | Calibration state, e.g. `baseline established: 3m (last seen 2h ago)`. It turns orange when the data is over 5 days old, as a hint to walk past the towers. |

Routes tracked (with built-in starting values, which refine themselves as you play): Undercity, Grom'gol, Kargath, Thunder Bluff, and the Sparkwater Port boat (hide it with `/ob boat`). You can rename any route with `/ob name`.

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
5. Type `/ob debug`. It should say the DLL function is present and show raw transport data when transports are in range.

The DLL only reads transport positions that the client has already loaded; it does not send anything anywhere. Its source is `ZepSense_src/ZepSense_v5.c` (built with `i686-w64-mingw32-gcc -O2 -shared -static-libgcc -Wl,--kill-at -s`). As with any client DLL, use it at your own risk and check your server's rules.

Saved data lives in `WTF\...\SavedVariables\OctoBus.lua`.

## Using it

- **Minimap icon**: click to show/hide the window anywhere; drag to move it around the minimap edge.
- **Auto-show**: the window opens by itself in Orgrimmar and Durotar and hides elsewhere. The icon toggle always works manually. Add more auto-show places with `/ob allow <zone or sub-zone>` (use `/ob where` to see the exact names), or turn the behaviour off with `/ob zone`.
- **Bells**: click a transport row to toggle a bell. Belled routes print a chat message `/ob alert` seconds (default 45) before arrival. Nothing is printed to chat for routes without a bell.
- **Move the window**: drag it; `/ob lock` locks it in place; `/ob resetpos` puts the window and icon back.

## How the timing works

Each route runs on a fixed cycle. Once the addon sees one transport arrive, it can predict every later arrival, even while the transport is out of view (transports are only sent to your client when they are near you, so they drop out of range for part of each trip).

- **Automatic calibration**: any arrival you watch near the towers calibrates that route. The first time takes two sightings, later refreshes take one. The cycle length is refined as more arrivals are seen, and the dock-time (how long a transport waits) is learned too.
- **`/ob calibrate`** (optional): watches every transport on purpose. Stand between the two towers where you can see the docks, do not `/reload`, and wait; rows are marked complete as each route is confirmed. A transport being out of view for a while is normal. If nothing at all has been seen after about 10 minutes, move closer to the towers. `/ob calibrate stop` cancels.
- Transports are not reported from deep inside the city (bank / auction house area), so calibrate near the towers.

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
| `/ob allowclear` | Remove the extra auto-show places |
| `/ob where` | Print your zone / sub-zone and whether the window auto-shows here |
| `/ob boat` | Show / hide the Sparkwater Port boat |
| `/ob shape square\|round\|auto` | Minimap icon placement. `auto` reads your minimap shape (tell it explicitly if you use a square minimap addon and the icon sits wrong) |
| `/ob lock` | Lock / unlock the window position |
| `/ob resetpos` | Put the window and icon back in their default spots |
| `/ob name <n> <text>` | Rename route number `n` (numbers from `/ob list`) |
| `/ob period <n> <sec>` | Set a route's cycle length by hand |
| `/ob calibrate` | Watch all transports on purpose (see above); `/ob calibrate stop` cancels |
| `/ob reset` | Forget everything learned and go back to built-in values |
| `/ob debug` | Show whether the DLL is answering and the raw data it returns |

## Troubleshooting

- **"no DLL: estimates only"**: the DLL is not loaded. Check that `ZepSense.dll` is in the game folder and listed in `dlls.txt`, then fully restart the game. `/ob debug` shows the state.
- **Times have a `~` and never confirm**: walk toward the towers and wait for an arrival, or run `/ob calibrate`.
- **`/ob` does nothing or prints a start-up error**: the addon reports its own load errors in chat; copy the message when reporting a bug.
- **Window did not auto-show**: use `/ob where` to see your zone and sub-zone names, then `/ob allow <name>` if you want it there.
- **Everything looks off after a big server change** (new route timings): `/ob reset`, then calibrate again.
