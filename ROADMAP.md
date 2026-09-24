# Eldergrove Faire: Roadmap

Last updated: 2026-09-23 · Milestone 1 (vertical slice) done.

## Decisions

| Question | Decision |
|---|---|
| GPU rendering | **Yes.** Install CUDA 12 toolkit + clang 19 in WSL (see below). CPU restructure first either way. |
| Pricing model | **Both at once:** park entry fee *and* per-ride/shop prices, each settable (either can be 0). |
| Queues | **Full RCT-style queue paths:** a queue tool, visible lines of guests, one queue per ride entrance. |
| Terrain slopes | **Not for now.** Flat terraces with cliffs. |
| Game mode | **Both:** sandbox and scenarios with goals. |
| Milestone order | Performance → riders + art → economy + UI → problems + staff → content → structure. |
| Version control | Git repo at `Desktop/CMU/Random/eldergrove-faire`, private GitHub repo `RedLynx101/eldergrove-faire`. Commit after every spike and milestone. |

## Done: M1, the vertical slice
Isometric fantasy map, paths, terrain editing, 4 enchanted tree kinds, Dragon Carousel, Arcane Spire, Potion
Stall, Troll Tavern, pre-built Wyrm Coaster with block signals and a track editor, guests with needs and
lookahead pathfinding, ledger economy, HUD/toolbar, save/load, custom C frame effect. Six laws proven.

## M2: Rendering at a steady 60 fps
Every rider and art detail costs frame time, so this comes first.

**Findings so far:** a frame takes ~21 ms on 20 threads vs ~42 ms on 1, and stops speeding up at ~4 threads.
Tested and ruled out: fork granularity (fork depths 3/4/5 make no difference), frame freeing, compute scaling
(pure compute scales 11x, allocation 8.5x). The cause is shared data: a boxed record read by many cores
costs an atomic reference count per read (~3 µs, scales 4.6x). Bend's own 3D demo avoids exactly this: plain
scalar records in registers, drawables binned into 64-px cells on the host, one GPU bang.

1. Per-stage frame timers, plus `perf` if installed, to pin down the remaining serial/contended hotspot.
2. **CPU restructure:** bin drawables into 64-px cells as flat scalar data. Render each cell with flat loops and
   no shared boxed data in the hot path. Reuse the previous frame's memory. Overlap the next sim tick with the
   window blit.
3. **GPU path:** render the cells on the RTX 3070 Ti with one bang per frame, following Bend's shader guide.
4. Stretch: zoom levels, larger window.

**Done when:** ≥60 fps live at 1024×640 with 700 guests; all laws still check.

## M3: Riders you can see, plus the art pass
- **Ride cycles:** load, run, unload, with seat capacity. Seats remember which guest sits in them. Riders are
  drawn seated with their own class, outfit and skin colours.
  - Carousel: 8 dragons, each carrying its rider.
  - Arcane Spire: riders on the ring as it rises and drops.
  - Coaster: guests queue at the station, board a real train, ride the full circuit, and get off where they
    started. Trains carry their riders' looks.
  - Shops: guests stand at the counter while buying.
- **Queue paths** land here with the ride entrances (see Decisions).
- **Trees:** clustered foliage with 3-tone shading, rim light and dithering, visible branches, soft ground
  shadows, gentle wind sway.
- **Mushrooms:** gills, textured stem, shaded spots, faint bioluminescent glow.
- **Crystals:** facets and glints.
- **Paths, water, cliffs:** paths get edges that join their neighbours, water gets shoreline foam, cliffs get an
  overhanging lip. Grass gets tufts, and flowers get less confetti-like.
- **Guests:** 4-way facing, better walk cycle, carried items (potions, glowing wisps), occasional thought bubbles.
- **Ride detail:** carousel poles, scalloped canopy and lights; animated Spire runes; shop signage.
- New laws: **capacity_respected** (a ride never carries more riders than it has seats) and
  **riders_conserved** (everyone who boards gets off).

## M4: Economy and UI
- **Ride window** (click a ride): open/close, price +/−, riders, income, upkeep, age, reliability, and
  excitement/intensity/nausea ratings.
- **Coaster ratings** calculated from the track: speed, drops, turns, length.
- **Park window:** park entry fee and ride pricing (both allowed), park rating, guest count graph.
- **Finances window:** monthly income and costs by category (tickets, food, drinks, entry fees, upkeep, wages,
  construction, loan interest, marketing), plus loans with interest.
- **Price sensitivity:** guests weigh value against price, refuse overpriced rides, and think "too expensive".
  Needs change what things are worth (a thirsty guest pays more for a potion).
- **Guest window:** name ("Sir Aldric of Thornwall"), thoughts, needs bars, gold, items.
- New laws: **purchase_is_transfer** (a purchase moves exactly the price from guest to park) and
  **prices_bounded**. Wages and loans are already covered by money_conserved.

## M5: Problems and staff
- Litter, plus vomit from nauseous guests after intense rides. Cleanliness affects happiness and park rating.
- Path furniture: bins, benches (restore energy), lamps.
- Toilets: the "Privy". A bathroom need is added.
- Guests getting lost; vandalism.
- Breakdowns: rides lose reliability with age and break down; guests get stuck and unhappy.
- Staff, with wages and patrol areas:
  - Brownies (handymen): sweep litter, empty bins, water flowers.
  - Dwarven Tinkers (mechanics): inspect and repair rides.
  - Watch Knights (security): deter vandals.
  - Bards (entertainers): cheer guests up.

## M6: More to build
- **Rides:** Griffin Swing (swinging ship), Wheel of Stars (Ferris wheel), Lich's Crypt (haunted dark ride),
  Golem Bumpers (dodgems), Hedge Labyrinth (maze), Dragon's Eyrie (observation tower), Wizard's Whirl
  (top spin), Mermaid Flume (log flume).
- **Shops:** Healer's Tent (first aid), Wisp Seller (balloons), Enchanted Ices.
- **Scenery:** castle walls, statues, fountains, flower beds, fences. Scenery raises the park rating.
- **Coasters:** more than one per park, a station anywhere, banked turns and steeper drops.

## M7: Structure
- Scenarios with goals and awards, alongside sandbox mode.
- Research that unlocks rides over time.
- Weather and a day/night cycle, with lanterns and fireflies at night.
- Buying land and construction rights.

## Laws
Proven: money_conserved, headcount_conserved, needs_bounded, coaster_on_circuit, no_collisions,
save_load_roundtrip.
Planned: capacity_respected, riders_conserved (M3); purchase_is_transfer, prices_bounded (M4).
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
