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
- Press **E** or **Escape** during a supply choice to hide the rewards and inspect the paused ecosystem. Press it again—or use **Back to choices**—to return. Camera pan and zoom remain available while peeking, but the meadow cannot be changed.
- The top population strip summarizes rabbit forage health. Amber rings mark rabbits that cannot find food; coral rings mean they are starving.
- During relevant checkpoints, the Objective Lens gently marks evaluator-recognized offspring, remembered birthplaces, and live nurseries. A literal numbered plaque connects each recognized nursery to the HUD count; markers fade when the objective no longer uses that evidence.
- Press Escape to clear the current placement selection.
- Press **F3** for development debug mode; with no inventory item selected, click an animal to inspect its state and perception ranges.
- Restart requires two clicks within three seconds.

The ecosystem freezes while a supply bundle is being chosen or while the player peeks at the meadow, so the decision has no time pressure. After a choice, the game returns to the exact speed that was active when the supplies arrived (and stays paused if it was already paused). Supply and milestone checks otherwise use simulation time, so they pause and scale with the speed controls.

## Plant ecology

Food patches retain continuous biomass, but now expose a readable lifecycle: **Abundant → Healthy → Sparse → Depleted → Recovering → Healthy**. Once a patch is depleted, Rabbits abandon it until it has rebuilt a meaningful reserve; regeneration continues during that recovery window. Carrots recover quickly with low capacity, while Berry Bushes retain their slower, larger-capacity role. Hungry Rabbits see nearby usable food and can share that current vision through a connected social group, then each Rabbit takes the shortest reachable route from its own position. If that local search fails, hunger makes them remember prior patches and widen their search; a starving Rabbit may take a last-resort bite from recovering growth.

Rabbit reproduction is tied to renewable carrying capacity. A birth requires stocked local forage, enough meadow-wide regeneration to support another animal, and a real biomass/parent-energy investment. Reproduction therefore pauses before a food crash and resumes when the player adds productive plants; the population strip reports when forage is full. Eating immediately relieves some accumulated starvation debt, so a rescue meal is meaningfully recoverable instead of merely delaying death.

Fox hunts use coordinated prey claims and finite sprint stamina. Nearby Foxes prefer different reachable prey, use short closing bursts, learn modestly from failed pursuits, and become more persistent as hunger rises. Rabbits also have finite flee stamina: open-ground chases eventually tire them, while Thicket conserves their escape stamina and still reduces Fox movement/capture buildup. Severe hunger makes a Rabbit accept more predation risk rather than flee beside food until it starves. Fox reproduction requires a sustainable local prey-to-predator ratio.

Plant silhouettes communicate current food stock: exhausted Carrot Patches show disturbed earth and clipped stems with no edible root, exhausted Berry Bushes become cropped and fruitless, and both use bright new growth while recovering. A separate, permanent ground footprint communicates habitat quality—compact dry soil for a poor site and a broader green verge for a productive one—without changing with grazing.

## Focused checkpoint progression

The run unfolds through five longer ecological checkpoints. Every checkpoint has at most five visible goals, including its final hold, and almost all evidence starts from zero when that checkpoint opens.

- **A Colony Gathers** asks for four living rabbits, three distinct fed founders, and a 10-second hold.
- **A New Generation** starts fresh counters for four births, three young rabbits that grow and eat, and births in two separated areas, followed by a 16-second hold.
- **A Nursery Network** requires fresh raised young and fresh births across three areas while three live nurseries hold together for 20 seconds. Completing it unlocks two Foxes and the Web supply pool.
- **Predator–Prey Rhythm** starts with no inherited event credit: two distinct Foxes must complete **hunt → birth → hunt**, and a rabbit born after the opening hunt must grow and eat before a 22-second hold.
- **Living Ecosystem** may inherit the live nursery network, but its five-event food-web cycle—**hunt → birth → hunt → birth → hunt**—three birth areas, and three grown young all reset. The final hold lasts 30 seconds.
- Ordered cycles use one checklist row with step progress and the next event in the visible value, keeping even the final checkpoint to five rows.
- Every goal row has a `?` explainer that is available immediately and never changes with progress. Explainers say whether evidence is live, saved for the checkpoint, tied to a surviving animal, or locked only after a timed sequence completes.
- Extra births or hunts do not erase a valid ordered sequence, but unfinished sequences still expire.
- The same persistent world grows in four 96-unit reveals from radius 360 → 744. The camera follows each reveal while existing creatures and plants remain in place.
- After checkpoint 3, losing rabbit breeding viability can make the ecosystem Critical. The first collapse has one hidden supply safety net; later collapses can end the run.
- A completed run can continue as a sandbox epilogue or restart as a fresh ecosystem.

## V0.4 Temperate Wilds terrain

V0.4 terrain systems make placement geography part of that progression:

- Meadow is implicit open ground. Carrot Patches recover best there, but exposed colonies have little nearby cover.
- Woodland remains the terrain Foxes favor while roaming. Rabbits retain their weaker preference for open ground, while active feeding, fleeing, and hunting can override both tendencies.
- Thicket is low, dense refuge cover. Threatened Rabbits can choose a reachable patch; Fox movement and capture buildup are reduced inside it, but successful hunts remain possible. Berry Bushes recover best around mixed Woodland/Thicket margins rather than deep cover.
- One seeded Stream crosses the maximum world. Deep water rejects placement and blocks Rabbit/Fox movement; visible shallow fords provide the valid routes between banks. Expansion reveals more of the same Stream instead of generating new water.
- Food choice, prey choice, threat response, mating, reproduction food, newborn placement, and nursery evidence now use terrain reachability where straight-line distance would be misleading.

Normal play communicates these rules through movement, plant fullness, cover, banks, and crossings. Exact habitat samples and route state remain F3-only.

## Architecture

- `simulation/ecosystem_simulation.gd` owns individual entity state, fixed-step ecology, behavior, mortality, reproduction, and local spatial queries.
- `simulation/temperate_wilds_terrain.gd` is the shared simulation/rendering source for seeded Woodland and Thicket fields, Stream hydrology, habitat samples, occupancy, fords, and bounded ground routes.
- `simulation/spatial_hash.gd` rebuilds a lightweight local lookup each tick, avoiding all-to-all searches.
- `game/run_director.gd` owns milestones, current-run unlocks, ecological Critical/Game Over, completion, and the progression snapshot shown by the HUD.
- `game/game_systems.gd` owns the fixed-step accumulator, inventory, milestone-aware supplies, speed, and coordination with world expansion.
- `rendering/objective_lens.gd` diffs the director's player-safe semantic evidence projection and owns marker fades plus one-shot evidence feedback. It does not evaluate checkpoint rules.
- `rendering/world_view.gd` renders interpolated simulation state with original code-drawn terrain, plants, animals, Objective Lens primitives, and feedback.
- `ui/game_hud.gd` contains the compact game HUD and debug inspector.
- `game/main.gd` connects input, camera, systems, presentation, and UI.

Simulation state does not depend on scene collisions or rendering FPS. Population labels are derived directly from the living individual entity collections.

## Tuning

All gameplay balance is centralized in [`config/game_config.gd`](config/game_config.gd):

- `rabbit` and `fox`: movement, perception, hunger, reproduction, starvation, lifespan
- Rabbit carrying-capacity, food-memory, emergency-search, and recovery tuning live beside the other `rabbit` values; Fox target competition and sprint/rest tuning live under `fox`
- `plants`: capacity, regeneration, lifecycle thresholds, and recovery release point
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

Run the focused plant-lifecycle trials (sustainable use, overgrazing, natural redistribution, recovery, and no-alternative starvation):

```sh
godot --headless --path . --script res://tests/plant_ecology_runner.gd
```

Run the compound-checkpoint, spatial-evidence, reward, UI, and failure suite:

```sh
godot --headless --path . --script res://tests/progression_runner.gd
```

Run the focused V0.4 generation, placement, behavior, reachability, nursery-evidence, and route-budget suite:

```sh
godot --headless --path . --script res://tests/terrain_runner.gd
```

Run the V0.4 live terrain scenario trials (Open Meadow, nearby/poor Thicket refuge, Stream crossing, and across-water predator):

```sh
godot --headless --path . --script res://tests/terrain_playtest_runner.gd
```

Run the three strategy contrasts (dump everything, deliberate nursery-network play, and predator overstock). The deliberate strategy must reach the hard compound nursery arc in a recoverable state; exact full-run reachability is covered deterministically by the progression suite:

```sh
godot --headless --path . --script res://tests/playtest_runner.gd
```

Run the social-vision radius sweep, or override the radius for a deliberate live playtest:

```sh
godot --headless --path . --script res://tests/social_vision_runner.gd
godot --headless --path . --script res://tests/playtest_runner.gd deliberate 800 50
```

Run the checkpoint-reactive opening (compact start, then spread only when requested). The optional fourth argument is a harness-only Rabbit ceiling:

```sh
godot --headless --path . --script res://tests/playtest_runner.gd reactive 120 -1 24
```

Run the balance diagnostic (all variants, or append one name such as `current`):

```sh
godot --headless --path . --script res://tests/balance_probe.gd -- current
```

Run the long-form, multi-seed stability playthroughs (carrying capacity, forage intervention, and coordinated predators):

```sh
godot --headless --path . --script res://tests/ecosystem_stability_runner.gd
```

Run a project/scene smoke check:

```sh
godot --headless --path . --quit-after 180
```

For manual plant-state inspection through the real scene, camera, and 1280×800 viewport, run the non-headless visual harness with `states`, `expanded`, `habitat`, or `redistribution` and an output PNG path, for example:

```sh
godot --path . --script res://tests/plant_ecology_visual_runner.gd -- expanded /tmp/plant-expanded.png
```

## Debug mode

The normal objective card shows no more than five compact goal rows, including `All goals together`. An ordered predator cycle stays on one row; its value shows both completed steps and the next event. `NEXT MOVE · UPDATES LIVE` is the only reactive coaching surface. Each row's `?` opens a fixed definition and a persistence label such as `LIVE · CAN RISE OR FALL` or `SAVED · THIS CHECKPOINT`; `How progress works` explains the model as a whole. Press F3 during play for raw evaluator identities and timing, Critical timing, fixed tick rate, populations, seed, simulation time, and selected-animal state. Selection also visualizes relevant local perception radii, habitat composition, chosen refuge, current target, route waypoints, route/direct distance, and selected ford.
