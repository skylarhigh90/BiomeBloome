# Asset and motion audit — 22 September 2026

**Verdict: prioritize a coherent art-and-animation pass.** The current assets and their integration are a major limit on how alive and convincing the game looks. This audit does not establish that assets cause most simulation problems, or that Godot is the limitation. Better drawings alone would leave several visible motion and depth problems intact.

The useful distinction is between **art**, **presentation code**, and **simulation behavior**. All three currently contribute. There is no evidence here to justify changing engines.

## Scope and evidence

Audited the current working tree, including its existing uncommitted changes. Inspected all three environment PNGs, texture imports, animal drawing, animation timing, terrain composition, camera scaling, and relevant simulation states. No production code or assets were changed by this audit.

**Concurrent-edit note:** source changed elsewhere in the workspace during the audit. Captures and `source_hashes.json` describe the earlier loaded revision. A final source review removed the now-resolved juvenile-size finding and confirmed the remaining art, gait, clock, depth and terrain findings. Activity checks and the transition probe were rerun against the later revision ([final activity results](evidence/activity-final.log), [final transition results](evidence/transitions-final.log), [final fingerprints](evidence/source_hashes_final.json)). The captures do not depict the later life-event UI or juvenile scaling.

Fresh captures use the actual main scene and WorldView renderer under Godot `4.7.2.stable.official.ed1daf0bf`, at 1280×800:

- [Opening with HUD](evidence/opening-hud.png), [opening map](evidence/opening-map.png), and [expanded map](evidence/expanded-map.png). Animals/plants were deliberately staged; expansion was set directly to radius 744 for comparison. These are presentation inspections, not completed playthroughs.
- [Motion clip](evidence/motion.mp4): 240 frames at a prescribed 30 Hz, first four seconds at 1× and next four at 3×. Uses live simulation with one rabbit, one fox, and one berry bush on controlled flat terrain. It captures rabbit travel/feeding/socializing and fox wandering; capture/hunt findings below come from code inspection. All 240 frames have distinct hashes ([validation](evidence/capture_validation.json)). This is not a frame-rate benchmark or ecology validation.
- [Capture telemetry](evidence/telemetry.jsonl) and [capture harness](evidence/capture.gd) include a stationary, paused fox observation.
- [Activity checks](evidence/activity.log): **12 passed, 0 failed**. These validate feeding/rest, interruption, spacing, simulation-clock replay and pause, transplant, and nursery guidance. Their pause assertion checks simulation state, not every rendered animation.
- [Stop-transition probe](evidence/transitions.log) and [probe source](evidence/transitions.gd) reproduce the rabbit landing issue below. [Source fingerprints](evidence/source_hashes.json) identify the audited files. Headless logs include macOS certificate/logging environment warnings; no activity assertion failed.

## Findings, in priority order

### 1. Animal art lacks the poses that make locomotion readable — high

There are **no rabbit or fox sprite sheets or rigs**. Both animals are drawn from circles and polygons in [world_view.gd](../../../rendering/world_view.gd#L794). Neither has articulated feet or legs. Rabbits receive whole-body lift and stretch; foxes receive no locomotion cycle, only tail sway and a hunting indicator ([fox drawing](../../../rendering/world_view.gd#L839)). A fox therefore moves as a largely rigid shape even when its simulation is behaving correctly.

Create readable propulsion/contact poses, including rabbit push-off, flight and landing, and fox walk/run. The solution can be sprites or a better procedural rig: importing bitmaps is not inherently required. The essential missing asset is an animation vocabulary, not simply a higher-resolution portrait.

### 2. The map and creatures use conflicting visual conventions — high

The grass and conifers are detailed painted textures; animals, berry bushes and thicket are mostly flat geometric shapes. Trees suggest an elevated side view, while animals are rotated through arbitrary headings as overhead symbols. The fresh screenshots show the mismatch at actual gameplay scale.

Choose a common perspective, palette, shading and detail density. If retaining continuous 360° body rotation, author genuinely overhead animals that remain convincing at every heading. If choosing elevated directional views, replace whole-image rotation with directional poses and stable ground pivots. A side-view sprite dropped into the current rotation logic would produce sideways/upside-down animals.

### 3. Scene layering makes creatures appear above tree canopies — high

[The draw order](../../../rendering/world_view.gd#L233) renders all decorative trees before all plants and animals. Details and animals have separate y-sorts; there is no shared depth order. Thus a rabbit standing behind a trunk still draws above the entire tree. Better tree artwork cannot correct this.

Use a common ordering based on ground anchors for upright props, plants and animals. Preserve visibility through selective canopy fading or another deliberate treatment. Shadows and flat ground marks should remain in ground passes.

Trees also exist only as renderer decoration. [Ground occupancy](../../../simulation/temperate_wilds_terrain.gd#L41) checks bounds and deep water, not trunks. If trees should be physically solid, selected trunk footprints need local avoidance. Do not turn an entire canopy or thicket into an obstacle: that could contradict refuge and routing mechanics.

### 4. Animal animation needs better timing and transitions — high/medium

**Rabbit stops can cut off a hop.** Stationary activities immediately zero motion and return ([simulation](../../../simulation/ecosystem_simulation.gd#L787)); the renderer immediately disables lift for these states ([rendering](../../../rendering/world_view.gd#L747)). The focused probe observed `return_home → socialize` at 6.8 simulation seconds with preceding speed **44.59 world units/s**, gait phase **0.460**, and calculated unscaled lift **4.136 units**, followed by zero lift. This is a reproducible transition discontinuity, not evidence that every stop looks bad. Add a brief landing/settle transition for normal stops while preserving immediate danger response.

**Fox motion uses a different clock.** Rabbit gait and chewing follow simulation time; fox tail sway follows `visual_clock`, advanced with unscaled frame delta ([visual-clock update; tail sway at line 844](../../../rendering/world_view.gd#L108)). Consequently the tail continues while paused and does not speed up with 3× travel. Ambient water or UI motion may intentionally continue, but locomotion needs a consistent simulation clock and speed relationship.

The paused capture confirms this: simulation time stays at 16.0 seconds and velocity at zero, while the calculated tail offset changes from 0.859 to 2.081 to −0.564 over one real second. Compare [first paused frame](evidence/paused-fox-252.png) and [last paused frame](evidence/paused-fox-282.png).

**Fox behavior has little presentation structure.** Hunting awards the meal and removes the prey immediately when capture succeeds ([capture logic](../../../simulation/ecosystem_simulation.gd#L949)). There is no pounce/feeding interval, and failed-pursuit recovery is primarily a hunt cooldown while the animal wanders. New action animations need explicit event/timing inputs. A short event-driven visual response may suffice; a real feeding delay would also change gameplay balance and should be treated separately.

### 5. Environment assets need cleanup and design for their displayed size — medium

- The [conifer atlas](../../../assets/environment/conifer_atlas.png) has visible bright green fringe pixels and baked gray ground/shadow patches. These make individual trees feel cut out. Clean the silhouette and establish one consistent shadow convention.
- Atlas splitting is correctly configured as 2×2. The 1254×1254 sheet produces **627×627 cells**, each drawn into a nominal **46×46 world-unit square** before size variation and zoom ([tree draw](../../../rendering/world_view.gd#L545)). Much painted detail is lost at that size. Author and judge the trees at their rendered size.
- Animals receive a 1.42 multiplier plus zoom compensation up to 1.58; trees receive neither ([scaling](../../../rendering/world_view.gd#L741)). As the camera pulls back, animals become larger relative to trees. Preserve readability, but set the intended relationship explicitly before producing new art.
- Mipmap generation and alpha-border fixing are already enabled in the texture import settings. Missing import flags and incorrect atlas slicing are not the main findings.

### 6. Ground composition is busy while habitat identity is weak — medium

One detailed meadow texture is repeated in four large quadrants ([ground](../../../rendering/world_view.gd#L260)). Woodland and thicket retain that grass beneath translucent washes; thicket foreground uses six translucent circles per patch ([cover](../../../rendering/world_view.gd#L575)). In the captures, detailed grass competes with small gameplay objects, while cover often reads as a tinted patch.

Use quieter base ground, a small coherent set of meadow/woodland-floor/thicket materials, and readable transition vegetation. Place these according to the existing terrain fields so the art communicates the simulation. Preserve visible fords and depleted/recovering food states. A single prettier map background would not reliably express those mechanics.

### 7. Expansion moves the boundary scenery — lower

The 84 exterior trees are positioned from the changing reveal radius ([boundary trees](../../../rendering/world_view.gd#L458)). They move outward during expansion. Stationary seeded scenery revealed progressively would better support the impression of one persistent habitat.

## Recommended next implementation

Build one small finished scene before commissioning/replacing a whole asset library: **one rabbit, one fox, one tree, one forage patch, and a meadow-to-cover edge**. Keep the existing simulation as its base.

1. Specify camera perspective, actual displayed sizes, ground pivots, shadows and required poses. Review at opening, expanded and maximum zoom.
2. Develop the animals' silhouettes and locomotion/action poses alongside simpler, matching environment art. Preserve the new juvenile scaling and clear food lifecycle appearances.
3. Connect animation to simulation phase/speed/facing/activity; handle ordinary stops; provide fox gait and capture feedback. Fix shared depth ordering and decide whether any trunks require avoidance.
4. Inspect hopping/walking, turns, stops, feeding, pursuit/capture, pause and 1×/3×, plus front/behind trees and entry into cover. Keep the passing stationary-feeding and replay behavior checks.
5. Expand the asset set only after this scene reads convincingly at gameplay scale.

The current rabbit interpolation, persistent facing, stationary feeding/rest and shared hop/travel phase are useful foundations. A concurrent update now also scales juveniles from 66% to adult size, and adds life-stage/event cues; the earlier identical-size finding is therefore resolved in the latest source. This audit recommends building on them. It does not quantify the percentage of problems caused by art, establish long-term ecosystem stability, or benchmark engine performance.

Reproduce from the project root:

```sh
godot --headless --path . --script res://tests/activity_runner.gd
godot --headless --path . --script res://docs/audits/2026-09-22/evidence/transitions.gd
godot --path . --script res://docs/audits/2026-09-22/evidence/capture.gd
```

The graphical harness writes PNG frames and telemetry to `/private/tmp/biome-asset-audit-2026-09-22`. The saved MP4 encodes `motion_%04d.png` at 30 fps. Production settings are altered only in the harness's in-memory scene.
