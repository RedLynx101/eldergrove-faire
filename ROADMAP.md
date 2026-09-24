# Eldergrove Faire: Roadmap

Last updated: 2026-09-23 · M1 and M2 done; M3 riders and tree/mushroom art done, queues and polish next.

## Decisions

| Question | Decision |
|---|---|
| GPU rendering | **Yes**, tools installed, but Bend's CUDA path cannot run under WSL2 (no concurrent managed memory). The CPU restructure reached the target on its own. |
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

## M3: Riders you can see, plus the art pass (in progress)
**Done:**
- **Seats and boarding:** carousel and spire 8 seats, shops 4, each coaster train 6. Each tick one pass
  (`Boards.plan`) seats whoever is ready, in order, so no seat is shared and no ride overfills. Guest updates,
  ticket sales and drawing all read that one plan; a rider's seat lives in their `dir` field.
- **Riders drawn in their own class, tunic and skin:**
  - Carousel: 8 dragons, each carrying its rider; the back half passes behind the centre pole.
  - Arcane Spire: riders around the ring as it rises and drops; the back ones behind the tower.
  - Coaster: trains have ids. Guests board only the train loading in the station, ride the whole circuit,
    and get off when that same train returns. Two riders per car.
  - Shops: buyers stay visible at the counter.
- **Trees:** elder oaks with clustered, five-tone shaded crowns, dithered edges, branches, bark, a wind sway
  and soft shadows; moonpines with serrated, frosted tiers.
- **Mushrooms:** domed glowcaps with highlights, dense pulsing spots, gills and a fibrous stem, sometimes
  with a small one beside them. **Crystals:** facets, a rocky base, twinkling tips.
- Performance kept: 60 fps live with 700 guests (11.0-11.5 ms frames uncapped).

**Still open in M3:**
- **Queue paths** with ride entrances (see Decisions). Guests currently wait at the ride's edge.
- **Paths, water, cliffs:** joined path edges, shoreline foam, overhanging cliff lips, grass tufts.
- **Guests:** 4-way facing, a better walk cycle, carried items, thought bubbles.
- **Ride detail:** carousel poles and lights, scalloped canopy, shop signage.
- New laws: **capacity_respected** and **riders_conserved**. The seat plan was built to make them provable
  (one pass, one plan), but they need bit-mask reasoning that isn't written yet.

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
Planned: capacity_respected, riders_conserved (M3, open); purchase_is_transfer, prices_bounded (M4).
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
