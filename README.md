# Biome Bloome

A first-playable, single-player ecosystem simulation built with Godot 4.7.2 stable and GDScript. Place individual rabbits, foxes, grass, and berry bushes into one continuously running world, then observe local feeding, fleeing, hunting, reproduction, starvation, supplies, objectives, and gradual map growth.

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
- Press Escape to clear the current placement selection.
- Press **F3** for development debug mode; with no inventory item selected, click an animal to inspect its state and perception ranges.
- Restart requires two clicks within three seconds.

The ecosystem keeps simulating while a supply bundle is being chosen. Supply, objective, and expansion clocks use simulation time, so they pause and scale with the speed controls.

## Architecture

- `simulation/ecosystem_simulation.gd` owns individual entity state, fixed-step ecology, behavior, mortality, reproduction, and local spatial queries.
- `simulation/spatial_hash.gd` rebuilds a lightweight local lookup each tick, avoiding all-to-all searches.
- `game/game_systems.gd` owns the fixed-step accumulator, inventory, supplies, objectives, speed, and expansion.
- `rendering/world_view.gd` renders interpolated simulation state with original code-drawn terrain, plants, animals, and feedback.
- `ui/game_hud.gd` contains the compact game HUD and debug inspector.
- `game/main.gd` connects input, camera, systems, presentation, and UI.

Simulation state does not depend on scene collisions or rendering FPS. Population labels are derived directly from the living individual entity collections.

## Tuning

All gameplay balance is centralized in [`config/game_config.gd`](config/game_config.gd):

- `rabbit` and `fox`: movement, perception, hunger, reproduction, starvation, lifespan
- `plants`: capacity, regeneration, attraction
- `inventory`: starting hand
- `supply`: interval and bundle pool
- `objectives`: sequential targets and stability durations
- `world`: initial radius, expansion timing/amount, maximum size, forest generation
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

Run a project/scene smoke check:

```sh
godot --headless --path . --quit-after 180
```

## Debug mode

Press F3 during play. The overlay shows fixed tick rate, actual population and plant counts, seed, simulation time, and selected-animal state. Selection also visualizes relevant local perception radii and current target.
