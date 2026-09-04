# Player guidance UX audit

## Outcome

The checkpoint card now separates three different player needs:

1. **What the checkpoint is asking for** — title, plain-language summary, and complete goal list.
2. **What a term means** — a fixed `?` explainer on every goal, available before that goal is reached.
3. **What to do next** — one reactive `NEXT MOVE · UPDATES LIVE` instruction.

This prevents changing ecosystem state from changing the explanation a player is reading.

## Findings

### Unclear terms were used as labels before they were defined

`Five-step living rhythm` sounded thematic but did not describe the evaluator. Its actual rule is an ordered food-web cycle: **fox hunt → rabbit birth → fox hunt → rabbit birth → fox hunt**. The row is now named `Food-web cycle`, the full order appears in the checkpoint summary and row explainer, its configured four-minute window is disclosed, and the row's live value says which event comes next.

### One surface was doing two incompatible jobs

The old presentation put a reactive recommendation next to a generic `Need a hint?` action. When a nursery count rose or fell, the recommendation returned to nursery recovery. That behavior is useful for coaching, but it made the interface feel as if the rules themselves had changed.

The new hierarchy labels reactive coaching honestly. Definitions live in a separate goal-explainer state selected by the player, and that selection persists while goal values fluctuate.

### Tooltip-only detail excluded touch and keyboard-led play

The next ordered event previously existed only in a tooltip. It is now visible in the row value. Every definition is also reachable through a focusable `?` button, so hover is an enhancement rather than the only discovery path.

### The checklist hid why some completed goals later became incomplete

Progress has several persistence models but presented them identically:

- `LIVE · CAN CHANGE` — current population and nursery evidence can rise or fall.
- `LIVING CREDIT · CAN FALL` — the credited animal must still be alive.
- `SAVED · THIS CHECKPOINT` — recorded births and birth areas persist until the checkpoint ends.
- `TIMED ORDER · LOCKS WHEN COMPLETE` — a sequence can expire while unfinished, then remains complete once finished.
- `TOGETHER · TIMER RESETS` — the hold runs only while every other row is complete.

Each goal's explainer now states the relevant model explicitly.

### “Hold” did not describe the player's responsibility

The row is renamed `All goals together`. Its explainer makes the reset behavior explicit without exposing hidden evaluator constants.

## Revised checkpoint journey

- On arrival, the player sees the entire completion contract, including the exact final-cycle order.
- The current best action is clearly marked as live and may change as the ecosystem changes.
- The player can open any row's definition at any time, even while an earlier row is incomplete.
- The chosen definition stays open through subsequent HUD refreshes and live-count fluctuations.
- The checkpoint-wide guide explains the difference between live and saved progress.
- Objective Lens markers remain the world-space proof for births, birth areas, young rabbits, and current nurseries.

## Copy rule for future checkpoints

Do not add a goal unless it has all of the following:

- A concrete noun or event-based row label.
- A visible current/target or next-event value.
- A stable, player-facing explanation.
- An explicit persistence label.
- A next action that can be generated independently from the explanation.
