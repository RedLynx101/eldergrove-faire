# Eldergrove Faire: Roadmap

Last updated: 2026-09-24 · M1-M4 done. Next: M5 (controls, problems, staff and people). Plan runs to M8
(custom coasters).

## Decisions

| Question | Decision |
|---|---|
| GPU rendering | **Yes**, tools installed, but Bend's CUDA path cannot run under WSL2 (no concurrent managed memory). The CPU restructure reached the target on its own. |
| Pricing model | **Both at once:** park entry fee *and* per-ride/shop prices, each settable (either can be 0). |
| Queues | **Full RCT-style queue paths:** a queue tool, visible lines of guests, one queue per ride entrance. |
| Terrain slopes | **Not for now.** Flat terraces with cliffs. |
| Game mode | **Both:** sandbox and scenarios with goals. |
| Milestone order | Performance → riders + art → economy + UI → controls + problems + staff → content → structure → custom coasters. |
| Controls | WASD and the arrows move the camera, always; coaster building gets its own construction window (M8) instead of the W/A/D/Q/Z keys. |
| Placing things | Every tool shows a ghost of what it would place, tinted green where it can go and red where it can't, with the cost. |
| Coaster crashes | None. A failed test reports where and why instead. A ride can be edited only while closed, and opened only when valid (circuit complete, tested); the safety laws are about open rides. |
| Frame rate | 60 fps at the default zoom and window size; dynamic resolution keeps the rest smooth. |
| Children | Yes, as individual guests (smaller; they prefer gentle rides). No families or groups for now. |
| Working through M8 | Straight through, without stopping between milestones. Small design calls are made along the way and recorded in "Calls made along the way" below. |
| Ride exits | Any path tile touching the ride is its exit, marked with an exit arch; the queue's front tile gets an entrance arch. Riders step off toward the exit. |
| Complete rides | A ride runs only with both an entrance (queue) and an exit (path); a warning shows until then. Shops need neither. |
| Ride cycles | Each ride has its own cycle (load, run, unload) with minimum and maximum waits. |
| Sound | Yes: our own procedurally generated sounds and old-style music, made in code like the art. |
| Version control | Git repo at `Desktop/CMU/Random/eldergrove-faire`, private GitHub repo `RedLynx101/eldergrove-faire`. Commit after every spike and milestone. |

## Calls made along the way
Small design decisions made while working, listed here so they can be revisited.

## Done: M1, the vertical slice
Isometric fantasy map, paths, terrain editing, 4 enchanted tree kinds, Dragon Carousel, Arcane Spire, Potion
Stall, Troll Tavern, pre-built Wyrm Coaster with block signals and a track editor, guests with needs and
lookahead pathfinding, ledger economy, HUD/toolbar, save/load, custom C frame effect. Six laws proven.

## Done: M2, a steady 60 fps
**Result:** the live window holds 60 fps at 1024×640 with 700 guests (16.7 ms frames, paced), and runs at
77-80 fps uncapped (12.5-13.3 ms, `PARK_NOPACE=1`). All six laws still check; the save round-trip passes.

What it took:
1. **Profiling (`perf`, `tools/prof.sh`):** 38% of frame time was reference counting and freeing, and 26% was
   re-partitioning drawable lists at every quadtree level.
2. **Cell/tile rasterizer:** the frame is cut once per 64-px cell and once per 16-px tile. Lists handed down
   the tree are only matched (borrows, no counts), kept entries are copied from their fields, and tiles render
   with straight-line code instead of forking down to pixels. Frame time 21-27 ms → 8.4 ms.
3. **Pipelined frames:** the window effect fills and shows on a helper thread (`io_work`), while a forked
   computation simulates and draws the next frame on the worker pool. Costs one frame (~17 ms) of input
   latency.
4. **GPU: not possible under WSL.** Bend's CUDA runtime needs concurrent managed memory, which WSL2 does
   not provide (`CU_DEVICE_ATTRIBUTE_CONCURRENT_MANAGED_ACCESS = 0` on the RTX 3070 Ti here), so `!` falls
   back to the CPU. It would need native Linux. clang 19 vs 14 made no measurable difference for CPU builds.

Measure it yourself: `PARK_PROF=1 ./park --live 700 1500` (add `PARK_NOPACE=1` for the uncapped rate).
Still open: zoom levels and a larger window.

## Done: M3, riders you can see, queues, and the art pass
**Result:** guests visibly ride every ride and wait in real queue lines; two more laws are proven (eight in
all); the live window holds 60 fps with 700 guests (8-9 ms frames uncapped, faster than after M2).

- **Seats and boarding:** carousel and spire 8 seats, shops 4, each coaster train 6. Each tick one pass
  (`Boards.plan`) seats whoever is ready, in order. Guest updates, ticket sales and drawing all read that one
  plan; a rider's seat lives in their `dir` field.
- **Riders drawn in their own class, tunic and skin:** carousel dragons (the back half passes behind the
  pole), riders around the spire's ring (behind the tower at the back), coaster trains with ids (guests board
  the train in the station and leave when that train returns), buyers at shop counters.
- **Queue paths** (tool `U`, 12 gold a tile): a queue tile beside a ride is its entrance. Guests heading for a
  ride with a queue steer to its entrance, board only there, and wait for a seat. They join a line only at its
  free end (a lone tile, or the end away from the ride), keep half a tile apart, and riders leave onto a path
  beside the ride. Rope rails close every side except along the line, to the ride, and at the free end.
- **Terrain:** path curbs on open edges, shoreline foam, cliff lips (bright turf, dark overhang, hanging
  roots), grass blades and tufts.
- **Guests:** four-way facing (front and back views), a four-frame walk with a bob and a swinging hand,
  carried potions and tankards, thought bubbles (hungry, thirsty, queasy, tired, cross, delighted).
- **Rides:** twisted brass poles, a scalloped valance and twinkling lamps on the carousel; sparkles around the
  spire's orb; a framed potion sign; a hanging tankard sign at the tavern.
- **Trees and mushrooms:** shaded, clustered oak crowns with sway and shadows, frosted moonpine tiers,
  domed glowcaps with pulsing spots and gills, faceted crystals.
- **Laws 7 and 8:** **capacity_respected** (the boarding plan never seats anyone at or past the ride's seat
  count) and **riders_conserved** (nobody leaves the park from a ride). `Seat.free` became a chain of steps
  that each test `k < cap`, which made the first proof short. Not proven yet: that no two guests are planned
  into the same seat.
- **Speed:** tile lookups in the map's quadtree now walk into just the one child they need, which removed
  most of the reference-count work in the simulation (sim 3 ms → 1.2 ms a frame with 700 guests). The path
  search stops once it arrives, and ride entrances are worked out once a tick.

Known limits: guests who give up while queuing step off the line sideways; queues longer than the path
search's 12 steps are walked by feel (still in order, since a line offers only forward or back).

## Done: M4, ride cycles, economy, UI and sound
**Result:** rides run whole cycles through real entrances and exits; the park has windows for rides, guests,
the park and its finances; guests judge prices and say what they think; the park has its own synthesized
music and sounds; thirteen laws are proven. Commits `424e0d0` .. `44237a5`.

1. **Ride cycles and exits.** The carousel and spire load (from the queue's front), run start to finish,
   unload everyone toward the exit, and load again; loading ends when full, or when the first rider has
   waited the maximum, never before the minimum. The coaster's station unloads a returning train before
   loading it. A ride runs only with an entrance (a queue beside it, green arch) and an exit (a path beside
   it, red arch), else a warning blinks over it; shops need neither. Guests leave a queue only at its free
   end, quitters walk back out, and guests skip lines that are too long.
2. **Windows.** Up to four at once, dragged by the title bar, closed with X or Esc. Inspect tool (the
   default, key I; or right-click with any tool).
   - **Ride window:** open/close, price, riders and queue, minimum and maximum waits, customers, income,
     age, and ratings.
   - **Guest window:** a name from their id and class ("Sir Halvard of Wyvern Hill"), what they are doing,
     thoughts, needs, gold, and what they carry.
   - **Park window** (P): the park rating, guests, entry fee, and a guest graph.
   - **Finances window** (F): this month and last by category, profit, and loans.
3. **Ratings.** Excitement, intensity and nausea: fixed for the carousel and spire, worked out from the
   track for the coaster (turns, drops, height, length). Guests prefer exciting rides, skip ones wilder than
   their own taste, enjoy a ride by its excitement and come off queasy by its nausea.
4. **Economy.** Ledger kinds for tickets, food, drinks, entry fees, upkeep, construction, refunds, loans and
   interest, booked by month. Entry fee 0-40 (fewer guests come when it is steep, more when the park is
   well rated); park rating 0-999 from happiness, open rides and nausea; loans of 1000 at 1/80 a month.
5. **Guests who judge prices.** A ride is worth its excitement to a guest, a potion more the thirstier they
   are, a meal more the hungrier. Too dear: they skip it, think "not paying that for the X", and remember.
   They also think a ride was great, or too intense, and get fed up with long queues; fresh thoughts show in
   their bubble.
6. **Laws.** board_only_when_loading, ride_until_unloading, seats_unique, purchase_is_transfer and
   prices_bounded, all proven, thirteen in all.
7. **Sound.** An original organ waltz (32 bars of 3/4, oom-pah accompaniment) and synthesized effects:
   coins, a ride bell, the spire's wind, lift clacks, the coaster's roar, the crowd's murmur, a month chime,
   and UI clicks, thumps and buzzes. It is all made in `sound.bend`, sample by sample, and played through
   PulseAudio (`pacat`). M toggles the music, N the effects.
8. **Found and fixed on the way:**
   - A queue deadlock seen over a long run: shop-bound guests could enter queues and lock the line. With
     the fix, riders over 20000 ticks rose several times over (coaster 35 to 291).
   - Most of M4's frame cost, which was reference counting on the shared map root from the new queue
     rules. Free-end flags now live in the tiles, sales come from the boarding plan, and queue lengths are
     counted every 16 ticks.
   - The spire's orb now draws behind its riders.

**Performance:** on the same machine at the same moment, a full frame (sim, scene and raster) with 700 guests
costs about what M3's did. The machine was far slower late on 2026-09-23 than earlier that day (M3's own
build went from 8-9 ms to 25-29 ms uncapped), so the absolute frame rate needs re-measuring on a quiet
machine: `PARK_PROF=1 ./park --live 700 1500`.

**Known limits:**
- A crowd can still bunch at a short queue's free end.
- Guests may pick a ride whose queue is on the far side of the park.
- There is no music volume control besides on/off.

## M5: Controls, problems, staff and people (next)
Spikes, in order:

1. **Controls and camera.** WASD (and the arrows) move the camera. Zoom in and out, in three steps (close,
   normal, far) with the mouse wheel or Page Up / Page Down. Every tool shows a **ghost preview** of what it
   would place under the mouse: green where it can go, red where it can't, with the cost beside it. That
   covers paths, queues, terrain, trees, rides at their full footprint, and demolish (which highlights what
   would go).
2. **Readable thoughts.** Redraw the thought icons at a size that reads. The hunger bubble is the worst: its
   white bone vanishes on the white bubble and leaves a brown cross. Every bubble gets a clear picture with a
   dark outline, and the guest window names each thought in words (it already does).
3. **Mess.** Guests drop litter; nauseous guests are sick after intense rides. Dirty paths lower happiness
   and the park rating. Path furniture: bins, benches (they restore energy) and lamps.
4. **The Privy.** Toilets, and a bathroom need.
5. **Breakdowns.** Rides lose reliability with age and break down; riders get stuck and unhappy until a
   repair.
6. **Staff**, hired from a staff window, with wages (through the ledger) and patrol areas:
   - Brownies (handymen) sweep litter, empty bins and water flowers.
   - Dwarven Tinkers (mechanics) inspect and repair rides.
   - Watch Knights (security) deter vandals, who smash benches and lamps.
   - Bards (entertainers) cheer guests up.
7. **More people.** More guest variants:
   - new folk: halflings, gnomes, orcs;
   - more outfits: nobles, merchants, pilgrims;
   - hats, hair, beards and cloaks;
   - children (smaller, and they prefer gentle rides).
   Staff wear their own uniforms.
8. **The interface, revamped:**
   - the toolbar grouped into categories (paths, terrain, scenery, rides, shops, staff) with hover
     tooltips;
   - a consistent window style;
   - an options window: window size (1024×640, 1280×800, 1600×1000), pixel scale, and dynamic resolution
     (the drawn resolution drops when the frame rate falls below 60, and comes back when it recovers);
   - music and effects volume.
9. Laws: **litter_accounted** (litter appears only when a guest drops it or is sick, and disappears only when
   a Brownie sweeps it or a bin takes it) and **wages_booked** (every wage goes through the ledger).

## M6: More to build
- **Rides:** Griffin Swing (swinging ship), Wheel of Stars (Ferris wheel), Lich's Crypt (haunted dark ride),
  Golem Bumpers (dodgems), Hedge Labyrinth (maze), Dragon's Eyrie (observation tower), Wizard's Whirl
  (top spin), Mermaid Flume (log flume).
- **Shops:** Healer's Tent (first aid), Wisp Seller (balloons), Enchanted Ices.
- **Scenery:** castle walls, statues, fountains, flower beds, fences. Scenery raises the park rating.
- **Stairs and bridges.** The path tool builds stairs between terrace heights by itself, as does the queue
  tool. A bridge tool raises paths over water, lower paths and track, on supports that match the theme. The
  land stays terraced (no slopes).

## M7: Structure
- Scenarios with goals and awards, alongside sandbox mode (a main menu to choose).
- Research that unlocks rides over time.
- Weather and a day/night cycle, with lanterns and fireflies at night.
- Buying land and construction rights.
- Crowds past 700: guests share per-ride route maps instead of each searching paths themselves.

## M8: Custom coasters
- **A construction window,** built carefully for ease of use:
  - piece buttons, grouped: straight, gentle and steep slopes, small and large turns, banked turns, lift
    hill, brakes, block brakes, station;
  - direction and bank toggles;
  - a live ghost of the next piece, green if it fits and red if not, with the height shown;
  - cost per piece, undo last piece, and a "close the circuit" hint when the track nears its start.
  - Keyboard shortcuts on the buttons (never WASD, which stays the camera).
- **Coasters anywhere:** several per park, each with its station where you put it, and a choice of coaster
  types: the Wyrm (wooden), a Dwarven Minecart, a Griffin Flyer (inverted). Set trains, cars per train,
  and the lift speed.
- **Testing, as in RCT2:** a new coaster must be tested before it can open. Empty trains run the circuit and
  the ride window fills in what they measured: maximum speed, length, drops, highest point, G-forces, air
  time, then excitement, intensity and nausea. A track that fails (a train can't make a hill) says where.
- **Follow cam:** a Follow button in ride, guest and staff windows. The camera rides along with a coaster
  car or a ride vehicle, or trails a guest or staff member; any camera key lets go.
- Laws extended to every coaster: coaster_on_circuit and no_collisions for each track, and a new one,
  **open_only_tested** (a coaster is open only if its track is a closed circuit and a test run completed).
  Editing closes a ride first; no crashes (a failed test reports the problem).

## Laws
Proven: money_conserved, headcount_conserved, needs_bounded, coaster_on_circuit, no_collisions,
save_load_roundtrip, capacity_respected, riders_conserved.
Proven in M4: board_only_when_loading, ride_until_unloading, seats_unique, purchase_is_transfer,
prices_bounded (thirteen in all).
Planned: litter_accounted and wages_booked (M5); open_only_tested, and coaster_on_circuit and no_collisions
extended to every coaster (M8).
Proof maintenance rule: keep the code field-wise (each park field updated by its own function) so
existing proofs survive new features.

## GPU setup (run these in the WSL Ubuntu terminal)
```bash
curl -fsSL https://apt.llvm.org/llvm.sh | sudo bash -s 19
wget https://developer.download.nvidia.com/compute/cuda/repos/wsl-ubuntu/x86_64/cuda-keyring_1.1-1_all.deb
sudo dpkg -i cuda-keyring_1.1-1_all.deb && sudo apt-get update
sudo apt-get install -y cuda-toolkit-12-6
sudo apt-get install -y linux-tools-generic   # optional: perf, for profiling
```
Bend finds `clang-19` on the PATH by itself and CUDA at `/usr/local/cuda`.
