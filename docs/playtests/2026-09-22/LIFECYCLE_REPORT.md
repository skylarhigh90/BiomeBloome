# Lifecycle feedback playtest

The long, unexplained wait is reproducible. In seed **240821**, four founders with five nearby carrots had no young before Fern died of old age at **174.9 simulated seconds**. A newborn followed at **175.0 seconds**. Their food could sustain the existing population, but its regrowth could not support another rabbit. Looking well fed did not imply that a birth was possible.

The new diagnosis identifies this as **“More nearby forage needed”** and explains that waiting alone cannot increase regrowth capacity.

## Does acting on the explanation help?

Two runs used the same seed, placements, inventory, and default rules:

| Action | First birth | First founder death |
| --- | ---: | ---: |
| Leave the opening unchanged | 175.0 s | 174.9 s, old age |
| At 30 s, follow the forage hint and place one earned berry bush near the home | 30.9 s | 174.9 s, old age |

The second run spent **one of the two berry bushes awarded by The First Meal**. The normal placement preview rated its site “Rich habitat” at 128% of standard capacity. No extra inventory, rabbit placement, lifespan changes, or forced reproduction was used. A birth arrived **144.1 simulated seconds sooner**, before any founder loss. The four founders' eventual ages of death were identical between the two runs.

The hint therefore provides an effective player action in this reproduced case. This is evidence of clearer, actionable feedback, not a measurement of human enjoyment.

## What the player can learn while waiting

The unassisted seed's sampled founder diagnoses were:

| Simulated time | Diagnosis |
| --- | --- |
| 10 s | Three founders building meal reserves; one waiting for a ready companion |
| 30 s | All four blocked by nearby forage regrowth capacity |
| 60 s | All four still blocked by nearby forage regrowth capacity |
| 120 s | All four still blocked by nearby forage regrowth capacity |

These are live reproductive gates, not a random birth timer. Terrain changes plant productivity, so counting five food patches is insufficient to predict another rabbit.

## Five natural openings

Each run placed only the four starting rabbits and five starting carrots in a tight group. All positions passed ordinary inventory placement checks. Later supplies were claimed to resume time, but none of that stock was placed. Each run observed 290 simulated seconds with the shipped ecological rules.

| Seed | First birth | Natural births | Natural deaths | Founder deaths |
| --- | ---: | ---: | ---: | ---: |
| 240817 | 13.3 s | 10 | 7 | 4 |
| 240818 | 11.1 s | 14 | 8 | 4 |
| 240819 | 16.6 s | 10 | 7 | 4 |
| 240820 | 12.2 s | 8 | 6 | 4 |
| 240821 | 175.0 s | 4 | 4 | 4 |

All 32 losses were old age. Every loss retained the animal's identity and actual cause after removal and emitted a named death story. All 20 founder deaths were preceded by an elder warning **42.6–56.5 simulated seconds** earlier (14.2–18.8 real seconds at 3× speed). Every natural birth emitted its named story. These openings do not exercise starvation or predation; those need separate targeted checks.

A control run on seed 240817 without repeated inspector diagnosis reads produced the exact same birth/death event signature and final animal positions as the observed run. Reading the new explanation did not change that run's ecology.

## Reproduction and evidence

    godot --headless --path . --script res://tests/lifecycle_playtest_runner.gd -- res://docs/playtests/2026-09-22/lifecycle-openings.json
    godot --headless --path . --script res://tests/lifecycle_playtest_runner.gd -- res://docs/playtests/2026-09-22/lifecycle-hint-response.json 240821 respond

- [Five opening runs and control comparison](lifecycle-openings.json): complete event history, founder status transitions, warning lead times, and reproduction signatures; zero assertion failures.
- [Same-seed hint response](lifecycle-hint-response.json): exact action, inventory cost, placement assessment, events, and 10/30/60/120-second probes; zero assertion failures.
- [Runner](../../../tests/lifecycle_playtest_runner.gd): uses real GameSystems inventory placement and fixed-step simulation.

The same natural opening is also rendered with the actual GameHUD and WorldView:

- [30 seconds: four founders blocked by forage capacity](lifecycle-visuals/08-natural-opening-blocked.png).
- [31 seconds: named newborns after placing one berry bush](lifecycle-visuals/09-natural-opening-after-hint.png).
- [Capture telemetry](lifecycle-visuals/natural-opening.json) and [graphical runner](../../../tests/lifecycle_opening_visual_runner.gd).

These two natural-opening screenshots use the real initial inventory and natural simulation. The other visual fixtures deliberately stage lifecycle states or checkpoint layouts and should not be mistaken for natural opening evidence.

## Implemented feedback

- The family overview and rabbit field note explain the current birth blocker: maturity, hunger, meal reserves, recovery, companions, and local or meadow-wide forage. Healthy hunger no longer claims a birth is possible.
- First Family's next move uses that diagnosis. It no longer tells a player with four founders and an empty rabbit satchel to place a fifth rabbit, or to wait when forage capacity requires action.
- Newborns appear smaller and visibly grow. Named birth and death labels last six real seconds, independently of simulation speed. Up to six simultaneous labels are shown to limit overlap.
- Elders receive a clock badge and a named advance warning. Food distress also produces a named warning. Death notices distinguish old age, starvation, and fox hunts.
- A selected animal's field note becomes a memorial after death. The latest loss stays accessible, and the Life journal retains the latest 128 events. An open journal keeps its displayed entries stable while the meadow continues; reopening refreshes them.

This pass changes feedback and presentation, without changing reproduction thresholds, food productivity, lifespan, or mortality rules.

## Additional validation

All five focused suites passed: **58 behavior, 40 progression, 12 activity, 29 lifecycle simulation, and 17 lifecycle feedback checks** (156 total). These include actual reproduction-gate agreement, preserved random state, natural age versus starvation causes, undo exclusion, paused-placement diagnosis refresh, memorial retention, and stable journal navigation.

The default three-strategy full playtest also passed. Deliberate play completed all six milestones at **546.8 simulated seconds** and continued into the sandbox, matching the prior pass's completion time. Dense placement still stopped at the separated-home requirement; excessive predator placement still risked collapse.

Rendered checks used the real main scene for controlled fixtures and the actual HUD/world renderer for the natural opening. Layout checks passed at **1280×800, 1024×768, and 800×768**, including the compact First Family layout. Visual inspection confirmed readable newborn labels, the elder clock, a named old-age loss, the preserved memorial, and journal navigation.

- [Elder warning and clock](lifecycle-visuals/03-elder-warning.png)
- [Named death and retained field note](lifecycle-visuals/04-named-death.png)
- [Life journal](lifecycle-visuals/06-life-journal.png)
- [Compact First Family layout](lifecycle-visuals/09-narrow-family.png)

Godot still emits the existing headless log/certificate warnings and resource-leak warnings at runner shutdown. The checks above passed; this work does not resolve those separate harness/cleanup issues. Human replay is still needed to judge how naturally the new information is noticed during play.
