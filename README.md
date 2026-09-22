# Biome Bloome

A single-player ecosystem simulation built with Godot 4.7.2 stable and GDScript. Place individual rabbits, carrot patches, and berry bushes into one continuously running world, establish a viable colony, then unlock foxes and try to build a living predator/prey ecosystem without losing the rabbit lineage.

The [September gameplay follow-up](docs/V0.7_PLAYTEST_REPORT.md) documents stationary feeding/rest, fixed-step hopping, nursery guidance, and measured before/after playtests. The original [gameplay and simulation audit](docs/audits/2026-09-17/GAMEPLAY_SIMULATION_AUDIT.md) remains the reference for longer-term ecological work.

The [art and motion implementation](docs/ART_AND_MOTION_IMPLEMENTATION.md) adds a coordinated overhead illustration library, articulated rabbit/fox poses, smooth landing transitions and shared scenery depth. [Art direction and asset contracts](docs/ART_DIRECTION.md) describe how to extend it.

## Run

From this directory:

```sh
godot --path .
```

Or import/open `project.godot` in Godot 4.7.2 (or a compatible later Godot 4.x stable release) and press **F6/F5**. The project launches directly into the game.

## Controls

- Click an inventory card, then left-click an exact world location to place one item.
- The placement ring and action strip grade the site before you commit: green is rich, yellow is fair, orange is poor, and red is invalid. Plant guidance explains the terrain response; rabbit guidance counts food and nearby companions so isolated founders are easier to spot.
- Use **Remove food**, then click a Carrot patch or Berry bush to permanently discard it with **no refund**. The hovered patch is marked before you click. Each use removes one patch; **Esc** or **Cancel** exits. Available while paused, with no charge or unlock required.
- Use **Undo** within five real seconds to return the latest placement to the satchel. This timer also runs while the meadow is paused.
- After **The First Family**, earned **Transplant** charges can move an existing plant. Choose the plant, then its new home; it keeps 65% of its current biomass.
- With no inventory item selected, click any Rabbit or Fox to open its named field note. The note shows life stage, hunger, current activity, parents, young, feeding visits/hunts, and latest life event. **Follow** keeps the camera on that animal until you pan, zoom, close the note, or stop following.
- Right- or middle-drag to pan; WASD/arrow keys also pan.
- Mouse wheel zooms in/out.
- Use **Pause / 1× / 2× / 3×** in the lower-right; Space toggles pause.
- Supply arrivals automatically pause the meadow and open **Meadow Mail**. Choose a bundle with the mouse, arrow keys + Enter, or **1 / 2**.
- Press **E** or **Escape** during a supply choice to hide the rewards and inspect the paused ecosystem. Press it again—or use **Back to choices**—to return. Camera pan and zoom remain available while peeking, but the meadow cannot be changed.
- The top population strip summarizes rabbit forage health. Amber rings mark rabbits that cannot find food; coral rings mean they are starving.
- During relevant checkpoints, the Objective Lens gently marks the young Rabbit whose growth matters and each live nursery. A literal numbered plaque connects every recognized nursery to the HUD count; markers fade when the objective no longer uses that evidence.
- Press Escape to clear the current placement selection.
- Press **F3** for development debug mode; with no inventory item selected, click an animal to inspect its state and perception ranges.
- Restart requires two clicks within three seconds.
- Audio starts muted. Use the top-bar sound button to turn procedural meadow ambience and event cues on or off.

The ecosystem freezes while a supply bundle is being chosen or while the player peeks at the meadow, so the decision has no time pressure. After a choice, the game returns to the exact speed that was active when the supplies arrived (and stays paused if it was already paused). Supply and milestone checks otherwise use simulation time, so they pause and scale with the speed controls.

## Plant ecology

Rabbits settle at individual feeding positions, spend real time eating, then rest, look around, or shift aside for a neighbour. Danger interrupts these activities immediately. Hops share a simulation-clock phase with forward impulses; the entire animal lifts above a grounded shadow. Pause and 1×/3× therefore preserve the relationship between gait and travel. A feeding visit is counted once even if interrupted, rather than once per bite tick.

Food patches retain continuous biomass, but now expose a readable lifecycle: **Abundant → Healthy → Sparse → Depleted → Recovering → Healthy**. Once a patch is depleted, Rabbits abandon it until it has rebuilt a meaningful reserve; regeneration continues during that recovery window. Carrots recover quickly with low capacity, while Berry Bushes retain their slower, larger-capacity role. Hungry Rabbits see nearby usable food and can share that current vision through a connected social group, then each Rabbit takes the shortest reachable route from its own position. Placement beside reachable forage—or a dependable first meal—establishes a local home: sated Rabbits loaf nearby, ready adults gather there, offspring inherit it, and foraging or frightened Rabbits return. If local searching fails, hunger makes Rabbits remember prior patches and widen their search; only prolonged hungry commuting lets one resettle around distant forage, while a starving Rabbit may take a last-resort bite from recovering growth.

Rabbit reproduction is tied to renewable carrying capacity. A birth requires stocked local forage, enough meadow-wide regeneration to support another animal, and a real biomass/parent-energy investment. Reproduction therefore pauses before a food crash and resumes when the player adds productive plants; the population strip reports when forage is full. Eating immediately relieves some accumulated starvation debt, so a rescue meal is meaningfully recoverable instead of merely delaying death.

Fox hunts use coordinated prey claims and finite sprint stamina. Nearby Foxes prefer different reachable prey, use short closing bursts, learn modestly from failed pursuits, and become more persistent as hunger rises. Rabbits also have finite flee stamina: open-ground chases eventually tire them, while Thicket conserves their escape stamina and still reduces Fox movement/capture buildup. Severe hunger makes a Rabbit accept more predation risk rather than flee beside food until it starves. Fox reproduction requires a sustainable local prey-to-predator ratio.

Plant silhouettes communicate current food stock: exhausted Carrot Patches show disturbed earth and clipped stems with no edible root, exhausted Berry Bushes become cropped and fruitless, and both use bright new growth while recovering. A separate, permanent ground footprint communicates habitat quality—compact dry soil for a poor site and a broader green verge for a productive one—without changing with grazing.

## Six-act checkpoint progression

The run now unfolds through six mechanically distinct acts. Each teaches or tests one new layer, carries useful living work forward, and exposes no more than five HUD rows including its confirmation hold.

- **The First Meal** introduces Rabbits and Carrot Patches: place four Rabbits, help three different founders eat, and hold for 8 seconds. Berry Bushes and two starter bushes unlock.
- **The First Family** asks for two natural births and one young Rabbit that grows and eats. It is the only checkpoint that asks the player to prove the newborn-foraging lesson. Completing it unlocks Transplant and one charge.
- **Two Lasting Homes** combines two separated three-Rabbit nurseries with productive Carrot and Berry habitat. Completing it gives three Rabbit starters, two Carrot patches, and a Transplant charge for the next nursery.
- **A Nursery Network** carries the existing homes forward and asks for one meaningful expansion to three live nurseries. Completing it introduces two Foxes, unlocks Fox placement, and switches supplies to the food-web pool.
- **Hunt and Recover** records two hunts, two births, two different living hunters, and restoration of the Rabbit population present when the act opened. Hunts and births may happen in either order.
- **Living Balance** asks for two surviving nurseries, three recent births, three recent hunts, at least two Foxes and twelve Rabbits, five Rabbits per Fox, and no severe starvation in one 150-second living window. The third home provides a reserve when predators scatter a group. A short 4-second confirmation requires these conditions together.
- Every goal row has a stable `?` explainer, while `NEXT MOVE · UPDATES LIVE` remains the one reactive coaching surface.
- The same world expands after the first five acts from radius 360 → 744. Existing creatures, plants, histories, and lineages stay intact.
- After the nursery network, loss of Rabbit breeding viability can make the ecosystem Critical. The first collapse has one recovery-supply safety net; later collapses can end the run.
- Meadow Mail guarantees a Fox-containing choice when a two-Fox objective is active, fewer than two Foxes remain, and no replacement is already in the satchel. Required progression is never gated only by a random supply roll.
- A completed run can continue as a living sandbox epilogue or restart as a fresh ecosystem.

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
- `game/game_systems.gd` owns the fixed-step accumulator, inventory, milestone-aware supplies, speed, timed undo, limited Transplant, placement assessment, and the ecology story feed.
- `game/meadow_audio_director.gd` synthesizes original ambience plus placement, birth, feeding, hunt, reward, warning, recovery, and completion cues at runtime.
- `rendering/objective_lens.gd` diffs the director's player-safe semantic evidence projection and owns marker fades plus one-shot evidence feedback. It does not evaluate checkpoint rules.
- `rendering/world_view.gd` renders interpolated simulation state with original code-drawn terrain, plants, animals, Objective Lens primitives, and feedback.
- `rendering/animal_art.gd`, `habitat_art.gd` and `forage_art.gd` own the reusable illustrated assets; `animal_motion.gd` samples their simulation-clock poses.
- `ui/game_hud.gd` contains the compact checkpoint HUD, Meadow Moments feed, public animal field note, placement/tool strip, and development debug panel.
- `game/main.gd` connects input, camera, systems, presentation, and UI.

Simulation state does not depend on scene collisions or rendering FPS. Population labels are derived directly from the living individual entity collections.

## Tuning

All gameplay balance is centralized in [`config/game_config.gd`](config/game_config.gd):

- `rabbit` and `fox`: movement, perception, hunger, reproduction, starvation, lifespan
- Rabbit carrying-capacity, food-memory, emergency-search, and recovery tuning live beside the other `rabbit` values; Fox target competition and sprint/rest tuning live under `fox`
- `plants`: capacity, regeneration, lifecycle thresholds, and recovery release point
- `inventory`: starting hand
- `tools`: undo duration and retained biomass after Transplant
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

Run the focused animation and shared-depth regressions:

```sh
godot --headless --path . --script res://tests/animal_motion_runner.gd
godot --headless --path . --script res://tests/scene_depth_runner.gd
```

Capture the opening, expanded and close map views, followed by prescribed 1×/3× motion and pause fixtures:

```sh
godot --path . --script res://tests/asset_motion_visual_runner.gd
```

Captures write to `/private/tmp/biome-art-motion-2026-09-22`. These are visual fixtures, not a frame-rate benchmark.

Run the behavior suite:

```sh
godot --headless --path . --script res://tests/test_runner.gd
```

Run the five ecological scenario comparisons:

```sh
godot --headless --path . --script res://tests/scenario_runner.gd
```

Run the focused plant-lifecycle trials (sustainable use, overgrazing, natural redistribution, recovery, and no-alternative starvation):

```sh
godot --headless --path . --script res://tests/plant_ecology_runner.gd
```

Run the six-act progression, outcome-window, identity/lineage, tools, audio, reward, UI, and failure suite:

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

Run the three strategy contrasts (dump everything, deliberate nursery-network play, and predator overstock). Dense dumping must stall at the separated-home act, while deliberate play must traverse the live ecological arc through sufficient births and hunts:

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

The normal objective card shows no more than five compact goal rows, including `All goals together`. The final recent-outcome row displays births and hunts together without prescribing an order. `NEXT MOVE · UPDATES LIVE` is the only reactive coaching surface. Each row's `?` opens a fixed definition and a persistence label such as `LIVE · CAN RISE OR FALL`, `RECENT WINDOW · UPDATES LIVE`, or `SAVED · THIS CHECKPOINT`; `How progress works` explains the model as a whole. The public animal field note is always available; F3 separately exposes raw evaluator identities and timing, Critical timing, perception radii, habitat composition, targets, and routes.
