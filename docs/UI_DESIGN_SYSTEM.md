# Biome Bloom supporting UI design system

This is the reference for interface around the biome simulation. It keeps the simulation visually dominant while making guidance, state, inventory, and controls comfortably readable at the 1280×800 base viewport.

## Architecture and audit

Before this pass, `GameHUD` built the entire interface in one script. There was no shared Godot `Theme` or reusable UI component. Labels received local font sizes and colors, panels and buttons built local `StyleBoxFlat` instances, and repeated values varied by a few pixels or color steps. Containers were used in several places, but inventory cards and parts of the reward sheet relied on manual child positions. Layout positions responded to viewport dimensions; typography did not because project stretch was disabled.

The canonical UI layer is now:

- `ui/theme/biome_theme.gd`: semantic color, typography, spacing, radius, surface, button, progress, and state definitions. `BiomeTheme.create()` returns the Godot `Theme` inherited by the full HUD.
- `ui/components/hud_stat.gd`: icon plus prominent numeric value.
- `ui/components/hud_status.gd`: category, primary status, and optional secondary status.
- `ui/components/instruction_callout.gd`: optional stand-alone contextual callout; it is not nested inside the checkpoint shell.
- `ui/components/checkpoint_progress.gd`: compact scan-first goal rows with population glyphs, optional hint details, and hold progress.
- `ui/components/inventory_card.gd`: placement item with icon, title, quantity, selection, hover/focus, and unavailable states.
- `ui/components/reward_choice_card.gd`: container-backed reward manifest with role, shortcut badge, and contents.
- `ui/components/icon_text_button.gd`: container-backed button content for an icon and semantic label, used by the reward peek action.
- `ui/game_hud.gd`: gameplay composition and state binding. It chooses semantic variations and updates content; it should not define a second visual language.

The HUD remains runtime-built because its contents and unlock set are dynamic. Reusable custom `Control` scripts provide the component boundary that a reusable scene would provide, while the shared `Theme` provides inheritance and interaction states.

### Ownership boundary

- `BiomeTheme` is the only production owner of font sizes, text colors, `StyleBoxFlat` construction, corner radii, borders, shadows, surface treatments, and button interaction states.
- Reusable controls own their internal container composition, minimum-size contract, and content/state API. They consume theme variations and spacing tokens; they do not invent local visual tokens.
- `GameHUD` owns gameplay-derived copy, state binding, semantic variation selection, top-level responsive placement/sizing, and short entrance animations. It does not build local StyleBoxes or apply font, color, or StyleBox overrides.

This boundary is deliberately small. A new variation should live in the Theme when it represents a reusable visual meaning; a new component is warranted only when a repeated or compound control has a stable content contract.

## Typography

| Semantic role | Godot variation | Size | Use |
| --- | --- | ---: | --- |
| Display | `Display` | 40 | Rare reward or major state headings |
| H1 | `HeadingOne` | 28 | Checkpoint and screen titles |
| H2 | `HeadingTwo` | 24 | Major panel titles |
| H3 | `HeadingThree` | 20 | Card and local component titles |
| Body large | `BodyLarge` | 18 | Primary instructions and emphasized feedback |
| Body | `Body` / `BodySecondary` | 16 | Readable supporting copy |
| Label | `LabelStrong` / `LabelSecondary` | 14 | HUD statuses, controls, short metadata |
| Caption | `Caption` | 13 | Genuinely secondary hints only |
| Eyebrow | `Eyebrow` / `EyebrowAccent` | 13 | Uppercase category, checkpoint, and action labels |
| Numeric | `Numeric` / `NumericOnDark` | 24 | Population and inventory quantities |

Use a semantic role, not a nearby custom size. Importance comes from role, contrast, placement, and whitespace together.

State-bearing text uses explicit variations at the same role: `LabelSuccess`, `LabelWarning`, `LabelDanger`, `CaptionSuccess`, `CaptionWarning`, `CaptionAccent`, and `HeadingOneDanger`. On-dark and debug copy likewise use `TextOnDark`, `EyebrowOnDark`, and `DebugText`. `_make_label` accepts only a semantic string role and asserts on unknown roles; numeric size compatibility is not supported.

## Color tokens

| Role | Value |
| --- | --- |
| Text primary | `#213d34` |
| Text secondary | `#526b62` |
| Text muted | `#718078` |
| Text on dark | `#fff9e9` |
| Surface primary | `#f4ecd8` |
| Surface secondary | `#ebe4d1` |
| Surface elevated | `#fff9e9` |
| HUD dark | `rgba(19, 43, 34, 0.96)` |
| HUD light | `rgba(245, 235, 209, 0.94)` |
| Forest / deep forest | `#294b3d` / `#17362d` |
| Moss / grass / leaf | `#6e9957` / `#93b879` / `#b9d99b` |
| Action accent | `#e5ad45` |
| Information | `#4f8f92` on `#d8e9e6` |
| Success | `#4f7f52` |
| Warning | `#c8872f` |
| Danger | `#d96d52` on `#f7d4c4` |

Alpha variants for borders, shadows, scrims, and HUD surfaces belong in `BiomeTheme`; do not create another almost-identical cream or green in a component.

## Spacing and shape

Spacing tokens are 4 (`tiny`), 8 (`small`), 12 (`medium`), 16 (`large`), 24 (`section`), and 32 (`major`). Standard panel content padding is 16×12. Components can use 24 or 32 only to separate meaningful sections.

Radius tokens are 8 (`small`), 12 (`control`), 18 (`card`), 22 (`panel`), and 28 (`pill`). Borders are normally one subtle line; selection/focus uses a stronger two-pixel accent. Elevation uses a short soft shadow, with larger shadows reserved for modal/elevated surfaces.

## Surfaces

- `SurfaceStandard`: primary cream supporting panel.
- `SurfaceElevated`: bright modal, reward, or completion surface.
- `SurfaceHUD`: dark translucent HUD tray.
- `SurfaceHUDLight`: light translucent stat pill.
- `SurfaceInformation`: cool supply/status surface.
- `SurfaceCallout`: warm stand-alone instruction or warning callout; never a nested checkpoint card.
- `SurfaceDanger`: ecosystem-critical message.
- `SurfaceToast` / `SurfaceToastMajor`: short feedback with tiered emphasis.
- `SurfaceDebug`: development-only exact evaluator detail.
- `SurfaceRewardSheet` / `SurfaceRewardSeal`: the reward modal and its circular identity mark.
- `SurfacePeekHUD`: compact paused-meadow status while reward choices are hidden.

An accent surface communicates meaning; it is not decoration to add arbitrarily.

## Components and states

`BiomeHUDStat` is used for rabbit and fox populations. `BiomeHUDStatus` is used for rabbit forage state. `BiomeCheckpointProgress` sits directly in the cream checkpoint shell and owns the `DO THIS`, `KEEP`, and `FINISH` sections, population glyphs, hold bar, and next-action footer. `BiomeInstructionCallout` remains available for a genuinely separate contextual callout, not as a card inside another card. `BiomeInventoryCard` is used by every unlocked placement item. `BiomeRewardChoiceCard` owns each reward manifest, including its shortcut badge and container layout. `BiomeIconTextButton` owns compound icon-plus-label button content. The supply timer, reward sheet, toast, modal, and compact speed controls consume shared Theme variations.

Buttons define default, hover, pressed, focus, and disabled states centrally. Reward cards use `RewardChoiceButton` and briefly switch to `RewardChoiceButtonChosen` before the reward sheet exits; no card receives focus when the sheet opens. Compact speed controls add a selected variation. Inventory cards add selected and unavailable variants; exhausted inventory uses unavailable styling and muted art. New-unlock animation is intentionally not implemented yet, but should decorate the inventory component rather than fork it.

### Checkpoint information architecture

The checkpoint shell is intentionally scan-first. It keeps the checkpoint eyebrow, title, short summary, and one compact row per goal. Ordered cycles render as literal event rows—for example, `Fox kills a rabbit` and `Rabbit is born`—without adding another section. A concise `TRY THIS` next action is available below the rows, while `Need a hint?` opens optional explanatory detail for players who want more context. The hold bar remains as a quiet visual cue below the rows.

Every rule that can stop checkpoint completion is visible in the row itself. Quantitative rows use a compact current/target format with the unit at the end, such as `0/6 rabbits`, `1/2 foxes`, or `0/4 sec`. Maximum thresholds retain their meaning with a trailing `max`, such as `4/20% max`. Rabbit/Fox hunger remain short, color-coded `Fed`, `Hungry`, and `Starving` states, while tooltips and the optional hint can provide exact details when needed. Population and animal-specific rows retain the rabbit or fox glyph for fast recognition; F3 remains reserved for raw evaluator diagnostics.

`GameHUD` renders the structured `goals` returned by `GameSystems.current_objective_progress()` and adds the final hold row. The progression layer remains the source of truth for task labels, targets, completion, and semantic warning state. Evidence includes:

| Evidence contract | Checklist status |
| --- | --- |
| `founders_fed` | living founders fed / configured founder target |
| `rabbit_birth` | natural births / configured birth target |
| `born_rabbit_fed` | surviving young rabbits fed / configured target |
| `distinct_foxes_fed` | distinct living foxes fed / configured target |
| `safe_havens` | current viable havens / configured minimum groups |
| `separated_birth_zones` | separated birthplaces / configured target |
| `prey_per_fox` | current rabbits per living fox / configured target |
| `ordered_cycle` | one indexed row per literal fox-kill or rabbit-birth step |
| species health | separate Rabbit/Fox `Fed`, `Hungry`, or `Starving` live state |
| rabbit trend | recent loss percentage / configured maximum percentage |

Critical uses living rabbits / configured recovery population; completion uses completed checkpoints; sandbox uses continuous observation. These are presentation mappings over structured state, not duplicate progression rules or decorative counters.

## Responsive behavior

The project uses a 1280×800 canvas base, `canvas_items` stretch, and `expand` aspect handling. At 1440×900 the UI scales proportionally. At 1920×1080, the base height remains coherent while extra horizontal room is exposed, keeping the simulation central and preventing giant panels. HUD groups use viewport-relative placement and minimum sizes; internal text uses containers and wrapping.

## Rules for future UI

1. Choose an existing typography, surface, button, and spacing role before creating anything new.
2. Add a semantic variant only when the distinction communicates state or priority.
3. Compose complex controls from Theme variations and containers. Do not manually position ordinary compound child controls.
4. Keep critical gameplay copy at Body (16) or larger. Caption and eyebrow roles are secondary, never a way to force text to fit.
5. Use numeric styling for quantities and counters, and make the value more prominent than its category.
6. Put interaction styling in the Theme or reusable component, not in gameplay refresh code.
7. Test new HUD work at 1280×800, 1440×900, and 1920×1080, including long copy, unavailable items, and selected/focus states.
8. Keep checkpoints list-first: task on the left, value/status on the right, and recognizable animal art where it improves scanning. Do not restore a single oversized metric or card-in-card instruction surface.

### Permitted geometry exceptions

Manual geometry remains only where it expresses screen orchestration or motion rather than ordinary component layout:

- `_layout_interface()` places the top-level objective, population, supply, inventory, speed, toast, critical, reward, peek, debug, and ending roots against the current viewport.
- Inventory refresh resizes the outer satchel root to the number of unlocked cards; the cards and all satchel content remain container-managed.
- Reward-sheet and toast entrance animations set a temporary root position, pivot, scale, and modulate before tweening to the responsive target.
- `EntityGlyph` and `RewardBurst` own illustration/draw geometry; glyph minimum sizes are part of their visual contract.

These exceptions must not spread into label, badge, card, objective-row, toast-content, or button-content placement. Those structures use Containers.

## Validation and deliberate limits

Rendered validation covered 1280×800, 1440×900, and 1920×1080. The first render exposed touching top-panel shadows and truncated inventory names; the status group was given a minimum gap and inventory cards were widened so `Carrot patch` and `Berry bush` remain intact. Hardening captures additionally covered selected and unavailable inventory, reward focus, hover and disabled states, the paused-meadow peek HUD, critical messaging, and deliberately long objective copy.

The checklist checkpoint iteration was rendered with an early checkpoint and a dense predator checkpoint. The 360px shell stays content-sized, right-aligned statuses remain readable, rabbit/fox glyphs provide quick population cues, and the dense state does not overlap the population or inventory controls. Automated progression coverage verifies every structured checkpoint goal maps into a live checklist row.

Migration completion removed all 16 numeric production `_make_label` calls, the numeric compatibility helper, all 19 local color overrides, all 10 local StyleBox overrides, and the three `GameHUD._flat_style` references. Production `GameHUD` and components now contain zero font-size, color, or StyleBox override calls and zero StyleBox constructors. All remaining StyleBox, corner, border, and shadow declarations are centralized in `BiomeTheme`. Compound reward, shortcut-badge, peek-button, checkpoint, and inventory-selection layout is container-backed. The 17 remaining direct geometry assignments are 14 responsive root-position branches, one dynamic inventory-root width, and two entrance-animation positions, all covered by the exceptions above.

Deferred opportunities: bundle and license a distinctive storybook font; add a short newly-unlocked inventory treatment; and add narrow/mobile breakpoints if a sub-1030-wide target enters scope. None changes simulation, terrain, art direction, camera behavior, or gameplay rules.
