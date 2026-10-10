# Changelog

## 1.3 (9 October 2026)

### New
- **Place names are colour coded**: Orgrimmar red, Undercity purple, Grom'gol green, Kargath orange-brown, Thunder Bluff tan, Sparkwater light blue, Revantusk teal, Ratchet gold and Booty Bay pink. A far end renamed with `/ob name` shows in white.
- **Rows are sorted by what happens soonest**: the next arrival, departure or time to fly is at the top. "Departing" and "fly now" rows go first, and rows with no timer go last.

### Fixed
- The Ratchet boat's "fly now" stayed up until the boat sailed, even when it was far too late to make it. It now shows for 10 seconds after your time to fly, then moves on to the next sailing you can still make.

## 1.2.1 (9 October 2026)

### Fixed
- A transport still at its dock after its scheduled departure showed "here now" in green. It now shows **departing** in yellow, since it is about to pull away.
- When it was time to fly for the Ratchet boat, the row jumped straight to the next sailing. It now stays on the current boat and shows **fly now** (counting down to when it sails) until that boat has left Ratchet, then moves on to the next one. A bell on that row now says "fly to Ratchet now".

## 1.2 (8 October 2026)

### New
- **Rows read "start -> end"**, for example `Orgrimmar -> Undercity`, and the timer is for the start. The separate "zeppelin" / "boat" label is gone from the rows (it is still in the tooltip).
- **Right-click a row to reverse it**, for example `Undercity -> Orgrimmar`, timed at Undercity.
- **Routes for where you are.** By default the window only shows routes with an end in your zone, each already reversed to start from your end. Click the window title (or `/ob all`) to switch to all routes. Somewhere with no routes, opening the window by hand shows the last place's routes.
- **New route: Grom'gol <-> Undercity zeppelin.** Its cycle is worked out from earlier sightings; its Undercity end is learned on the first ride from Grom'gol.
- **Both ends of every route are timed.** Built-in far-end timings measured on rides: Undercity, Grom'gol, Kargath, Thunder Bluff, Revantusk and Booty Bay.
- **Far ends are learned by riding**, with no recording needed: a transport that stands still for 20 s away from its home dock is treated as docked at the far end.
- **The window opens by itself at either end of any route**, and while a tracked transport is in view (for example during a crossing).
- Built-in cycle lengths now come from about 5 hours of sightings, so a new copy's first sightings line up with a long baseline.

### Fixed
- Far-end learning failed while `/ob debug on` was recording.
- The built-in baseline was ignored when the first thing seen in a session was a transport leaving rather than arriving.

### Changed
- `/ob name` renames the far end of a route.
- `/ob zone` now means "auto-show only at route ends".

## 1.1 (8 October 2026)

### New
- **Ratchet <-> Booty Bay boat**, shown in Orgrimmar as when to fly (`fly 4:55 sails 6:40`) to make the next sailing. `/ob travel <seconds>` sets your travel time to the Ratchet dock (default 175 s).
- **Resizable window**: drag the dots in the bottom-right corner, or `/ob scale <0.6 to 2>`.
- **Footer names the route with the oldest data** and how long ago it was seen.
- **`/ob disallow <name>`** removes a place from the auto-show list. Place names now match regardless of capitals or quotes.
- **`/ob debug on` / `off`** records transport positions for mapping new routes. `REC` shows in the window while it runs.

### Changed
- A single sighting that does not fit the schedule no longer resets a route's history; a second agreeing sighting is needed.
- The addon is at the top of the repository, so it installs correctly from a launcher's git address. The DLL is a separate download.

## 1.0 (8 October 2026)

- First release, as TurtleTransit, renamed OctoBus the same day: arrival timers for the Orgrimmar zeppelins and the Sparkwater boat, with bells, a minimap icon and automatic calibration from sightings.
