# Biome Bloome

A single-player ecosystem simulation built with Godot 4.7.2 stable and GDScript. Place individual rabbits, carrot patches, and berry bushes into one continuously running world, establish a viable colony, then unlock foxes and try to build a living predator/prey ecosystem without losing the rabbit lineage.

## Run

From this directory:

```sh
godot --path .
```

Or import/open `project.godot` in Godot 4.7.2 (or a compatible later Godot 4.x stable release) and press **F6/F5**. The project launches directly into the game.

## Controls

- Click an inventory card, then left-click an exact world location to place one item.
- Right- or middle-drag to pan; WASD/arrow keys also pan.
- Mouse wheel zooms in/out.
- Use **Pause / 1× / 2× / 3×** in the lower-right; Space toggles pause.
- Supply arrivals automatically pause the meadow and open **Meadow Mail**. Choose a bundle with the mouse, arrow keys + Enter, or **1 / 2**.
- Press **E** or **Escape** during a supply choice to hide the rewards and inspect the paused ecosystem. Press it again—or use **Back to rewards**—to return. Camera pan and zoom remain available while peeking, but the meadow cannot be changed.
- The top population strip summarizes rabbit forage health. Amber rings mark rabbits that cannot find food; coral rings mean they are starving.
- Press Escape to clear the current placement selection.
- Press **F3** for development debug mode; with no inventory item selected, click an animal to inspect its state and perception ranges.
- Restart requires two clicks within three seconds.

The ecosystem freezes while a supply bundle is being chosen or while the player peeks at the meadow, so the decision has no time pressure. After a choice, the game returns to the exact speed that was active when the supplies arrived (and stays paused if it was already paused). Supply and milestone checks otherwise use simulation time, so they pause and scale with the speed controls.

## V0.3 progression

The run now unfolds through eight ecological checkpoints: founders finding forage, first new life, a surviving new generation, first hunt, post-predation renewal, two separated safe havens, two established predators, and a final living birth/hunt cycle.

- Minor checkpoints give compact confirmation; checkpoints 3, 5, and 7 are major meadow beats with expansion or staging rewards. Only final success opens a modal.
- Foxes unlock at **The Next Generation Takes Hold**, with an introduction pair and the Web supply pool.
- **Two Safe Havens** uses persistent spatial evidence: two separated rabbit groups must each have reachable forage. A connected stretched colony does not count.
- **Predators Find Their Place** tracks individual fox identity, so two distinct living foxes must each feed during that checkpoint while rabbits renew.
- **Living Ecosystem** requires a fresh birth → hunt → birth → hunt cycle. Once completed, that cycle stays latched while the final viable hold settles.
- The normal HUD describes goals qualitatively. Exact thresholds, event counters, windows, and stabilization timing are developer-debug information available with F3.
- Major completions expand the same persistent world from 360 → 505 → 650 → 795; existing creatures and plants remain in place.
- After checkpoint 3, losing rabbit breeding viability can make the ecosystem Critical. The first collapse has one hidden supply safety net; later collapses can end the run.
- A completed run can continue as a sandbox epilogue or restart as a fresh ecosystem.

## V0.4 Temperate Wilds terrain

V0.4 preserves that eight-checkpoint run and makes placement geography part of it:

- Meadow is implicit open ground. Carrot Patches recover best there, but exposed colonies have little nearby cover.
- Woodland remains the terrain Foxes favor while roaming. Rabbits retain their weaker preference for open ground, while active feeding, fleeing, and hunting can override both tendencies.
- Thicket is low, dense refuge cover. Threatened Rabbits can choose a reachable patch; Fox movement and capture buildup are reduced inside it, but successful hunts remain possible. Berry Bushes recover best around mixed Woodland/Thicket margins rather than deep cover.
- One seeded Stream crosses the maximum world. Deep water rejects placement and blocks Rabbit/Fox movement; visible shallow fords provide the valid routes between banks. Expansion reveals more of the same Stream instead of generating new water.
- Food choice, prey choice, threat response, mating, reproduction food, newborn placement, and Safe Haven evidence now use terrain reachability where straight-line distance would be misleading.

Normal play communicates these rules through movement, plant fullness, cover, banks, and crossings. Exact habitat samples and route state remain F3-only.

## Architecture

- `simulation/ecosystem_simulation.gd` owns individual entity state, fixed-step ecology, behavior, mortality, reproduction, and local spatial queries.
- `simulation/temperate_wilds_terrain.gd` is the shared simulation/rendering source for seeded Woodland and Thicket fields, Stream hydrology, habitat samples, occupancy, fords, and bounded ground routes.
- `simulation/spatial_hash.gd` rebuilds a lightweight local lookup each tick, avoiding all-to-all searches.
- `game/run_director.gd` owns milestones, current-run unlocks, ecological Critical/Game Over, completion, and the progression snapshot shown by the HUD.
- `game/game_systems.gd` owns the fixed-step accumulator, inventory, milestone-aware supplies, speed, and coordination with world expansion.
- `rendering/world_view.gd` renders interpolated simulation state with original code-drawn terrain, plants, animals, and feedback.
- `ui/game_hud.gd` contains the compact game HUD and debug inspector.
- `game/main.gd` connects input, camera, systems, presentation, and UI.

Simulation state does not depend on scene collisions or rendering FPS. Population labels are derived directly from the living individual entity collections.

## Tuning

All gameplay balance is centralized in [`config/game_config.gd`](config/game_config.gd):

- `rabbit` and `fox`: movement, perception, hunger, reproduction, starvation, lifespan
- `plants`: capacity, regeneration, attraction
- `inventory`: starting hand
- `supply`: interval, milestone-aware bundle pools, and first-collapse recovery bundle
- `progression.milestones`: ecological evidence, stabilization timing, rewards, unlocks, guidance, and expansion
- `progression.critical`: breeding viability, debounce, recovery settling, grace, and first rescue timing
- `world`: initial radius, expansion amount, maximum size, and forest generation
- `terrain.thicket`: patch generation, refuge thresholds, and Rabbit/Fox pursuit effects
- `terrain.stream`: seeded channel shape, water depth, widths, and ford placement
- `terrain.routing`: path sampling, waypoint arrival, and moving-target replan thresholds
- `terrain.food_suitability`: Carrot Meadow response and Berry margin/deep-cover response
- `simulation`: fixed timestep, seed, and spatial cell size

## Tests

Run the behavior suite:

```sh
godot --headless --path . --script res://tests/test_runner.gd
```

Run the five ecological scenario checks:

```sh
godot --headless --path . --script res://tests/scenario_runner.gd
```

Run the V0.3 checkpoint, spatial-evidence, reward, UI, and failure suite:

```sh
godot --headless --path . --script res://tests/progression_runner.gd
```

Run the focused V0.4 generation, placement, behavior, reachability, Safe Haven, and route-budget suite:

```sh
godot --headless --path . --script res://tests/terrain_runner.gd
```

Run the V0.4 live terrain scenario trials (Open Meadow, nearby/poor Thicket refuge, Stream crossing, and across-water predator):

```sh
godot --headless --path . --script res://tests/terrain_playtest_runner.gd
```

Run the three normal-tuning strategy playthroughs (dump everything, deliberate two-refuge play, and predator overstock):

```sh
godot --headless --path . --script res://tests/playtest_runner.gd
```

Run the balance diagnostic (all variants, or append one name such as `current`):

```sh
godot --headless --path . --script res://tests/balance_probe.gd -- current
```

Run a project/scene smoke check:

```sh
godot --headless --path . --quit-after 180
```

## Debug mode

The normal objective card shows qualitative ecological guidance and a teaser for what comes next. Press F3 during play for exact evidence counts, ordered-cycle progress, stability and Critical timing, plus fixed tick rate, populations, seed, simulation time, and selected-animal state. Selection also visualizes relevant local perception radii, habitat composition, chosen refuge, current target, route waypoints, route/direct distance, and selected ford.
