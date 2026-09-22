# Audit evidence, 17 September 2026

[Full audit](../GAMEPLAY_SIMULATION_AUDIT.md). The audit made no gameplay/configuration changes. Harnesses are audit instrumentation, not proposed production code.

## Start here

- [A–F population curves](population_curves.png): five complete seeds per scenario, 1,800 simulation seconds each. [Vector version](population_curves.svg).
- [Matched controls and exploratory layouts](control_curves.png): five seeds each for cover removal and prey pairing; one seed each for richer and compact layouts. [Vector version](control_curves.svg).
- [Resource stock curves](resource_curves.png): fraction of initial food capacity remaining through each primary trial.
- [Rabbit motion plot](rabbit_motion.png): Dandelion's first 120 simulation seconds, from the compact opening's actual main-scene telemetry. This remains valid independently of the early capture problems below.
- [Rabbit sequence](rabbit_sequence.jpg), [hunt sequence](hunt_sequence.jpg), and [wide habitat sequence](overview_sequence.jpg): crops from verified fresh captures, labelled with actual simulation timestamps. The spacing between panels varies; they are observation examples, not constant-rate animation.
- [Progression recording](progression_observation.mp4) and [predator recording](predator_observation.mp4): actual rendered main scene, encoded from sampled captures at simulation-time pace. These are not frame-rate benchmarks. Audio is omitted. Capture metadata and telemetry are in [observation data](observations.zip).
- [Aggregated trial results](summary.json), [motion measurements](motion_metrics.json), [raw trial archive](raw_trials.zip), and [initial source fingerprints](source_hashes.json), [final fingerprints](source_hashes_final.json), and [final source snapshot](audited_source.zip).

## Methods and limits

The population archive contains **42 completed 30-minute trials**: A–F × five seeds, E_open and F_pairs × five seeds, B_rich and B_compact × one seed. The seeds are 240817, 9327, 401, 9031 and 17117. CSVs sample every five simulation seconds; JSON summaries include exact initial positions, births/deaths, peaks, extinction times and final resource budgets; JSONL files log individual birth/death events. Extinction time -1 means no extinction during the run, or no starting fox population in A. The `capacity` CSV column is the model's calculated sustainable rabbit count, not a physical habitat-area measurement. `meals` in observation telemetry counts bite ticks, not complete feeding bouts.

Normal aging, hunger, reproduction and default population caps are retained in ecological experiments. There are no continuing supplies or player intervention. Generated terrain and individual randomness both vary by seed. E/E_open intentionally use flat ground and create identical plants before adding E's thickets, holding cached productivity constant. F_pairs moves the same six founders into three pairs at alternate food stations. Rich/compact follow-ups are exploratory single-seed results. Incomplete second seeds were discarded, not counted as successful or failed runs.

Actual progression observations use the normal main scene, inventory and existing playtest placement strategy, without the test runner's substituted lower animal caps. The deliberate strategy reached checkpoint 4, A Nursery Network. A separate 1,800-second headless progression replay remained there; progression completion and human usability are not established. The rendered predator case is separately initialized with 18 food patches, 24 rabbits and two foxes at radius 600. Its sandbox HUD has stale objective rows because the existing `set_goals([])` call triggers a typed-array error; the animal simulation continues. Its “Field notes complete” text does not mean the audit completed progression normally.

Early macOS captures sometimes retained a stale background-window texture. One opening driver also failed to dismiss the mail panel visually after choosing supplies. Those frames are excluded from the provided recordings and contact sheets. Final drivers explicitly draw a SubViewport containing the real main scene before reading the texture, and fresh captures were checked through image hashes and changing entity positions. The progression recording covers 0.2–296.2 simulation seconds, following Fern for the first 120; the predator recording covers 0.2–180.2, following Russet VI for the first 90. Both then switch to wider observation. [Verified capture and motion metrics](verified_observation_metrics.json) include the fresh-frame hash checks. Temporary process suspension during isolated CPU benchmarks adds real elapsed time, but not simulated events; recordings are timed from the capture CSVs, not that elapsed wall time. Sparse capture cadence and expensive capture work make these unsuitable for judging normal rendered FPS or fine sub-frame gait smoothness. Motion conclusions also use the actual drawing and motor code and fixed-step telemetry.

CPU timings in the population summaries were gathered with overlapping audit work and **are not performance benchmarks**. Dedicated benchmark logs are in raw_trials.zip. For those runs, other audit Godot processes were temporarily suspended. The load harness has 10 warm-up and 150 measured 0.1-second steps, generated terrain, radius 940, and reproduction disabled to focus on a bounded population load; captures can still reduce counts. Two dispersed runs and one dense run are reported, with variation preserved. The profiling subclass wraps existing methods without changing their logic. Its nested terrain/route timings overlap rabbit/fox timings.

## Reproduction

The [harnesses directory](harnesses) preserves the actual scripts used. These are intentionally outside the normal game/test entry points. They contain this audit's absolute scratch/output paths; adapt those paths for another machine. `profile.gd` also preloads the scratch copy of `profiled_sim.gd`. `analyze.py` needs NumPy and Matplotlib and contains the report output path. No new production dependency was added.

From the project root, with Godot installed, the original population invocation was:

```sh
mkdir -p /private/tmp/biome-audit-20260917
cp docs/audits/2026-09-17/evidence/harnesses/*.gd /private/tmp/biome-audit-20260917/
godot --headless --path "$PWD" --script /private/tmp/biome-audit-20260917/scenarios.gd -- B 1800 240817
```

Omit the final seed to run all five. Supported scenarios are A, B, C, D, E, F, E_open, F_pairs, B_rich and B_compact. Use a separate scratch directory and update the `output` variable if retaining previous scratch results. The immutable report archive is the reference result. The main scene observation drivers require graphical Godot, pre-created output directories matching their `directory` variable, and no `--headless`. The fox diagnostic reads the completed B layout summaries from scratch.

The executable identified itself as **4.7.2.stable.official.ed1daf0bf**, with Compatibility/OpenGL on Apple M4 for graphical runs. Reproduction claims are limited to the same source/configuration/build; cross-platform deterministic lockstep has not been established.

## Existing checks

The behaviour suite passed **58 assertions**, terrain **13**, and plant-ecology scenarios passed. Their logs are included in raw_trials.zip. Some test harnesses emit ObjectDB/resource shutdown-leak warnings. The sandbox HUD runtime error is a separate observed defect; no fix was made. The source fingerprints can verify which working-tree files were inspected; the pre-existing working tree was not clean, so a Git commit alone would not identify the audited implementation.

Final fingerprints matched **76 of 77** initial files. `game/meadow_audio_director.gd` changed during the session without an audit edit. The simulation, config, renderer, UI and existing test files matched their initial fingerprints. The final snapshot contains the later audio file; this audit makes no audio-quality conclusions.
