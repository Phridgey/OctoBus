# TurtleTransit

Arrival timers for the zeppelins at the Orgrimmar towers, plus the Sparkwater Port boat, for the vanilla 1.12.1 client (tested on OctoWow / Turtle WoW).

A small minimap icon opens a window listing every transport with a live timer: how long until it **leaves** if it is docked, or how long until it **docks** if it is away. Click a transport to put a bell on it and get a chat message shortly before it arrives.

TurtleTransit is a standalone addon. It does not need pfUI or any other addon.

## What you see

| Window element | Meaning |
|---|---|
| Green check | Transport is docked now. The timer counts down to departure ("leaves"). |
| Red X | Transport is away. The timer counts down to docking ("docks"). |
| `~` before a time | An estimate from stored data. It goes away once you see the transport dock or leave. |
| Bell on a row | Alerts are on for that route (click a row to toggle). |
| Footer | Calibration state, e.g. `baseline established: 3m (last seen 2h ago)`. It turns orange when the data is over 5 days old, as a hint to walk past the towers. |

Routes tracked (with built-in starting values, which refine themselves as you play): Undercity, Grom'gol, Kargath, Thunder Bluff, and the Sparkwater Port boat (hide it with `/tt boat`). You can rename any route with `/tt name`.

## Requirements

1. **`ZepSense.dll`**, a small client DLL that exposes one Lua function, `ZepTransports()`, which returns the position of every zeppelin/boat the client currently has loaded. The addon cannot see transports without it. Without the DLL it shows built-in estimates only (marked `~`).
2. A client setup that loads DLLs listed in `dlls.txt`.

## Install

1. Copy the `TurtleTransit` folder to `Interface\AddOns\`.
2. Copy `ZepSense.dll` to the game folder (next to `WoW.exe`).
3. Add a line `ZepSense.dll` to `dlls.txt` in the game folder.
4. Start the game fully (a `/reload` is not enough the first time the DLL is added).
5. Type `/tt debug`. It should say the DLL function is present and show raw transport data when transports are in range.

The DLL only reads transport positions that the client has already loaded; it does not send anything anywhere. A prebuilt copy is in `dll/ZepSense.dll`; the source is `dll/ZepSense_v5.c` (built with `i686-w64-mingw32-gcc -O2 -shared -static-libgcc -Wl,--kill-at -s`). As with any client DLL, use it at your own risk and check your server's rules.

Saved data lives in `WTF\...\SavedVariables\TurtleTransitDB.lua`.

## Using it

- **Minimap icon**: click to show/hide the window anywhere; drag to move it around the minimap edge.
- **Auto-show**: the window opens by itself in Orgrimmar and Durotar and hides elsewhere. The icon toggle always works manually. Add more auto-show places with `/tt allow <zone or sub-zone>` (use `/tt where` to see the exact names), or turn the behaviour off with `/tt zone`.
- **Bells**: click a transport row to toggle a bell. Belled routes print a chat message `/tt alert` seconds (default 45) before arrival. Nothing is printed to chat for routes without a bell.
- **Move the window**: drag it; `/tt lock` locks it in place; `/tt resetpos` puts the window and icon back.

## How the timing works

Each route runs on a fixed cycle. Once the addon sees one transport arrive, it can predict every later arrival, even while the transport is out of view (transports are only sent to your client when they are near you, so they drop out of range for part of each trip).

- **Automatic calibration**: any arrival you watch near the towers calibrates that route. The first time takes two sightings, later refreshes take one. The cycle length is refined as more arrivals are seen, and the dock-time (how long a transport waits) is learned too.
- **`/tt calibrate`** (optional): watches every transport on purpose. Stand between the two towers where you can see the docks, do not `/reload`, and wait; rows are marked complete as each route is confirmed. A transport being out of view for a while is normal. If nothing at all has been seen after about 10 minutes, move closer to the towers. `/tt calibrate stop` cancels.
- Transports are not reported from deep inside the city (bank / auction house area), so calibrate near the towers.

## Commands

`/tt` (also `/transit` and `/zep`)

| Command | What it does |
|---|---|
| `/tt` | Show / hide the window (works anywhere) |
| `/tt list` | Print all timers in chat |
| `/tt alert <sec>` | Bell alerts fire this many seconds before arrival (default 45, `0` = off) |
| `/tt chat`, `/tt sound`, `/tt flash` | Toggle that alert type (chat on by default; sound and screen flash off) |
| `/tt zone` | Toggle "auto-show only in Orgrimmar / Durotar" |
| `/tt allow <name>` | Also auto-show in this zone or sub-zone |
| `/tt allowclear` | Remove the extra auto-show places |
| `/tt where` | Print your zone / sub-zone and whether the window auto-shows here |
| `/tt boat` | Show / hide the Sparkwater Port boat |
| `/tt shape square\|round\|auto` | Minimap icon placement. `auto` reads your minimap shape (tell it explicitly if you use a square minimap addon and the icon sits wrong) |
| `/tt lock` | Lock / unlock the window position |
| `/tt resetpos` | Put the window and icon back in their default spots |
| `/tt name <n> <text>` | Rename route number `n` (numbers from `/tt list`) |
| `/tt period <n> <sec>` | Set a route's cycle length by hand |
| `/tt calibrate` | Watch all transports on purpose (see above); `/tt calibrate stop` cancels |
| `/tt reset` | Forget everything learned and go back to built-in values |
| `/tt debug` | Show whether the DLL is answering and the raw data it returns |

## Troubleshooting

- **"no DLL: estimates only"**: the DLL is not loaded. Check that `ZepSense.dll` is in the game folder and listed in `dlls.txt`, then fully restart the game. `/tt debug` shows the state.
- **Times have a `~` and never confirm**: walk toward the towers and wait for an arrival, or run `/tt calibrate`.
- **`/tt` does nothing or prints a start-up error**: the addon reports its own load errors in chat; copy the message when reporting a bug.
- **Window did not auto-show**: use `/tt where` to see your zone and sub-zone names, then `/tt allow <name>` if you want it there.
- **Everything looks off after a big server change** (new route timings): `/tt reset`, then calibrate again.
