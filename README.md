# Eldergrove Faire

A high-fantasy theme park sim in the spirit of RollerCoaster Tycoon 2, written
in [Bend 2](https://github.com/bendlang/bend). Every pixel of art is drawn by
code (no image files), every sound is synthesized by code (no audio files),
and the rules of the park are machine-checked laws.

## Run it (WSL Ubuntu)

Bend runs on Linux and macOS, so on Windows everything runs through WSL. In WSL the project is at
`/mnt/c/Users/NoahH/Desktop/CMU/Random/eldergrove-faire`, also linked as `~/parkbend`.

```bash
cd ~/parkbend
./b.sh build main.bend park      # ~40 s: Bend compiles to one C file
./park                            # play
bend PROOF.bend                   # check every law: prints "All terms check."
```

From Windows PowerShell: `wsl -d Ubuntu -- bash -lc "cd ~/parkbend && ./park"`

See [ROADMAP.md](ROADMAP.md) for the plan and decisions.

Dev modes:
- `./park --shot out.ppm TICKS [TOOL] [CAMX CAMY]` renders one frame headlessly
  (`python3 tools/ppm2png.py out.ppm out.png` to view).
- `./park --bench FRAMES WARMUP [MODE] [CROWD]` times frames (mode 0 full, 1 sim, 2 scene).
- `./park --live CROWD WARMUP` plays with CROWD extra guests after WARMUP ticks.
- `./park --savetest TICKS` saves a busy park to disk, loads it and compares.
- `./park --uitest` clicks through a ride window headlessly and reports what changed.
- `./park --people out.ppm` draws every folk and outfit on one sheet.
- `./park --rides out.ppm T` draws the M6 rides T ticks into a run, every seat taken.
- `./park --scen K MONTHS` plays scenario K (0 sandbox, 1-3) a month at a time and reports it.
- `./park --wav out.wav SECONDS` records the music with every effect in turn;
  `python3 tools/wavcheck.py out.wav out.png` prints its levels and draws it. `PARK_MUTE=1` plays nothing.
- `--shot` takes an optional 6th argument, a window to show (kind * 256 + ride; 256 is the carousel's), and a 7th, the zoom (0 normal, 1 close, 2 far).
- Environment: `PARK_OPT=n` starts with options n (bits: 0-1 window size, 2 whole pixels, 3 dynamic
  resolution off), `PARK_PROF=1` prints frame timings, `PARK_NOPACE=1` removes the 60 Hz cap,
  `PARK_DUMP=out.ppm` writes the 300th shown frame. `tools/prof.sh ./park ...` profiles with perf.

## Controls

| Key | Action |
|---|---|
| Arrow keys / W A S D | Move the camera |
| Mouse wheel / Page Up, Page Down | Zoom in and out (close, normal, far) |
| Click / drag | Use the tool on a tile (or pick a tab or tool in the bar) |
| I | Inspect tool (the default): click a guest or a ride to open its window |
| Right-click | Open a ride's window, whatever the tool |
| P / F / K | The park, finances and staff windows (or the PARK, FINANCES and STAFF buttons) |
| M / N | Music on or off / sound effects on or off |
| O | Options: window size, stretched or whole pixels, dynamic resolution, music and effects volume |
| 1 - 6 | Open a toolbar tab: paths and furniture, land, scenery, gentle rides, thrill rides, shops. Press again for its next tool |
| X | Demolish |
| U | Queue line (12 gold a tile) |
| R | Next tree kind (oak, moonpine, glowcap, crystal) / coaster direction |
| Space | Pause; `+` / `-` speed (up to 3x) |
| F5 / F9 | Save / load `eldergrove.sav` |
| Esc | Close the front window (with none open: quit) |

Guests ride visibly: carousel and spire hold 8 riders, shops serve 4 at a
time, and each coaster train seats 6. Coaster riders board the train loading
in the station and stay aboard for the whole circuit.

Guests face the way they walk, carry what they buy (potions, tankards of
ale), and now and then show what they think in a bubble: hungry, thirsty,
queasy, tired, cross, delighted, in need of the privy, or disgusted by a
filthy path.

Rides need a door in and a door out. The entrance is a queue tile (U) beside
the ride, marked by a green arch; guests walk the line single file, join it
only at its free end (the tile away from the ride), and leave it only there.
The exit is any path tile beside the ride, marked by a red arch; riders step
off onto it. A ride without both shows a blinking warning and doesn't run
(shops need neither). For the coaster, both go beside its station.

The carousel and spire run in cycles: they load until full (or until the
first rider has waited long enough), run start to finish with no one getting
on or off, unload everyone, then load again. The coaster's station unloads a
returning train before loading it. Hover over a ride to see its state.

A ride's window: open or close it, set its price, see riders and queue, set
its minimum and maximum loading waits, and read its customers, income, age
and ratings. Excitement, intensity and nausea are fixed for the carousel and
spire and worked out from the track for the coaster (turns, drops, height,
length). Guests prefer exciting rides, skip rides wilder than they like
(each adventurer has their own taste), enjoy a ride by its excitement, and
come off queasy by its nausea. Drag windows by their title bar; up to four stay open.

The park window shows the park rating, guests and their happiness, the entry
fee (0-40 gold, paid at the gate; a steep fee turns guests away, a good
rating draws them), and the guest count over the last four months. The
finances window shows this month and last month by category (ride tickets,
food, drinks, entry fees, upkeep, construction, refunds, loan interest) and
the profit, and borrows or repays 1000 gold at a time (interest: 1/80 of the
loan a month, owing at most 20000).

Guests judge prices: a ride is worth its excitement to them, a potion is
worth more the thirstier they are, a meal the hungrier. A guest who wanted
something too dear skips it, thinks "not paying that for the Troll Tavern",
and remembers. They also think a ride was great, or too intense, and get fed
up with long queues; fresh thoughts show in their bubble. A guest's window
(click them) shows their name ("Sir Halvard of Wyvern Hill"), what they are
doing, their thoughts, needs, gold and what they carry.

Sound: an original organ waltz with an oom-pah accompaniment plays over the
park, and the park answers with its own sounds: coins when gold comes in, a
bell when a ride starts, a rush of wind as the spire rises, the lift hill's
clacks and the coaster's roar, the crowd's murmur (louder with more guests),
a chime each month, and clicks, thumps and buzzes for building. It is all
made in `sound.bend` a sample at a time; `snd.c` plays it through PulseAudio
(`pacat`, which WSLg provides), or stays silent if there is no pacat.

Every building tool shows a ghost of what it would place under the mouse:
green where it can go, red where it can't, with its cost beside the mouse.

The toolbar: inspect and demolish on the left, then five tabs, then the open
tab's tools. Paths and furniture: path, queue line, litter bin, bench,
lantern. Land: raise, lower. Scenery: enchanted trees. Rides: Dragon
Gentle rides: Dragon Carousel, Wheel of Stars, Hedge Labyrinth, Dragon's Eyrie, Golem Bumpers, Lich's
Crypt. Thrill rides: Arcane Spire, Griffin Swing, Wizard's Whirl, Mermaid Flume, Wyrm Coaster. Shops:
Potion Stall, Troll Tavern, Privy,
Healer's Tent (for queasy guests), Wisp Seller, Enchanted Ices.
Scenery: enchanted trees, statues, fountains, flower beds, castle walls and fences (walls and fences join
up); decorations raise the park rating. Hover a button to see its name on the strip above the bar.

Paths a level apart join by stairs by themselves, so a path can climb the terraces one level per tile.
The path tool also builds over water: a plank bridge with rails.

Days turn to night and back (about half a minute a day): lanterns and ride lights glow, fireflies come
out. Some days it rains, and fewer guests come.

The game opens on a main menu: sandbox, or one of three scenarios with a goal and a deadline (Misty
Hollow, The Dragon's Debt, The Grand Tourney); a window says when a scenario is won or lost. Awards come
now and then at the turn of a month. The park window funds research (none, steady, lavish), which unlocks rides and scenery one at a time in
scenarios; locked tools show a padlock. Buy Land (land tab) opens up the wild forest at the park's edge.

Mess: guests drop wrappers when they finish what they carry, and very queasy
guests are sick. Both lie on the path until swept (Brownies, coming in M5's
staff spike), dirty paths wear guests' happiness down and lower the park
rating, and guests say so ("this path is filthy"). A litter bin beside the
path catches what guests finish near it, 15 pieces until full. Tired guests
sit on benches to get their energy back. Lanterns light the way.

Guests need the privy now and then, sooner after a potion. A guest who
needs it heads for the nearest Privy first, thinks "I need the privy" in a
bubble, and grows miserable if there is none. Rides leave riders queasy by
their nausea rating; the feeling builds up over several rides and wears off
slowly, and a very queasy guest may be sick on the path.

Rides wear out. The ride window shows reliability; a worn ride breaks down
more often. A broken ride stops where it is, with its riders stuck aboard
(growing cross) until it is repaired; a wrench sign and smoke mark it, and
the message bar says so.

Staff, hired and let go in the staff window (K), each for a monthly wage:
Brownies sweep litter, empty bins and mend smashed furniture; Dwarven
Tinkers hurry to rides that break down and repair them; Watch Knights
patrol, and miserable guests won't smash benches, bins or lanterns while one
is near; Bards play, cheering up the guests around them. Each has a post
(one of the rides) to patrol near. Staff wear their own uniforms and carry
their tools: broom, hammer, spear, lute.

The crowd: wizards, knights, elves, dwarves, halflings, gnomes, orcs and
commoners, some bearded or in straw hats; nobles in capes, merchants with
packs, pilgrims with staffs; and children, who keep to the gentler rides.

Coaster tool (key 4, third tool): `Enter` opens or closes the coaster; while closed, `T`
ahead, `G`/`H` turn, `Y` up, `B` down, `L` lift hill, `Backspace` removes the
last piece (WASD always moves the camera). It opens only once the track closes back on its station. One
coaster per park for now (the Wyrm Coaster comes pre-built).

## Files

| File | What |
|---|---|
| `core.bend` | The simulation: map (a quadtree), guests, rides, economy, coaster track and block signals. Pure. Every change goes through `Park.step`. |
| `save.bend` | Save format: continuation-style encoder, stack-machine decoder. |
| `art.bend` | All the art: terrain, trees, rides, guests, the coaster, UI icons. |
| `sound.bend` | The synthesizer: the waltz (tables from `tools/gentune.py`), the effects, the mix. |
| `snd.c` | A sound effect for Bend: a sample ring played through `pacat`. |
| `font.bend` | An original 3x5 pixel font (generated by `tools/genfont.py`). |
| `main.bend` | Renderer (parallel quadtree rasterizer), UI, input, the app loop. |
| `win_frame.c` | A custom frame effect: Base's Linux window with a parallel blit that fills each quadtree square at once, run on a helper thread so the next frame is computed meanwhile. |
| `LAWS.bend` | The laws (human-owned). |
| `PROOF.bend` | Their proofs. |

## The laws

1. **money_conserved**: after any step the park's gold is its gold before with that step's ledger applied.
2. **headcount_conserved**: guests after + guests who left = guests before + guests who arrived.
3. **needs_bounded**: every guest's hunger, thirst, energy, nausea and happiness stay within 0..255.
4. **coaster_on_circuit**: an open coaster's track always closes back on its station.
5. **no_collisions**: a block holds at most one train, and the block signals never lose or duplicate one.
6. **save_load_roundtrip**: loading a save gives back exactly the park that was saved.
7. **capacity_respected**: the boarding plan (the only way anyone gets a seat) never seats a guest at or past their ride's seat count.
8. **riders_conserved**: nobody leaves the park from a ride: a guest riding at the start of a tick is still in the park after it.
9. **board_only_when_loading**: the boarding plan seats guests only on rides that are loading (a cycling ride between runs, the coaster's train standing in the station after unloading, or a shop).
10. **ride_until_unloading**: a rider stays aboard until their ride unloads.
11. **seats_unique**: the boarding plan never gives one seat to two guests.
12. **purchase_is_transfer**: a guest who boards (or buys) pays exactly the price: their gold after is their gold before less the price the ledger adds to the park.
13. **prices_bounded**: ride prices stay within 0..20 gold and the entry fee within 0..40, whatever step happens.

Laws 1-4 and 13 quantify over every possible `Park.step` (tick, build, track edit),
so they hold for anything a player or the clock can do.
Laws 7-12 hold for every possible input to the boarding plan, a rider's
tick, or a boarding.
