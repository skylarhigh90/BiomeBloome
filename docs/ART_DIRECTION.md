# Overhead woodland art

The live scene uses a small reusable illustration library so animal anatomy,
foliage, food and motion can be developed together at actual gameplay scale.

The camera looks down on the habitat. Animals face local +X and may turn through
any angle; foliage is authored from above. Cream rabbits and russet foxes sit
against muted sage meadow, cooler evergreen crowns and warmer low thicket.
Broad silhouettes and a few highlights carry the forms. Ground texture is quiet.

## Asset responsibilities

- `rendering/animal_art.gd` draws articulated bodies: paws, haunches, heads, ears
  and tails. It accepts a pose and never decides behavior or moves an animal.
- `rendering/animal_motion.gd` derives presentation poses from fixed-step state.
  Rabbit hops keep the existing motor phase; fox footfalls follow distance.
  Feeding and resting remain physically stationary while the body settles.
- `rendering/habitat_art.gd` supplies evergreen and low-cover variants. Geometry
  is authored as vectors and cached where grouped transparency is needed.
- `rendering/forage_art.gd` draws food abundance/recovery states. Habitat quality
  stays in the separate permanent ground footprint.
- `rendering/world_view.gd` owns camera compensation, ground shadows, shared
  depth ordering, canopy visibility and gameplay indicators.

These are production assets expressed in code, rather than external sprite
sheets. Their controlled geometry allows heading-independent articulation and
consistent silhouettes without importing many directional animation frames.

## Contracts

Animal coordinates use a ground-center pivot, with the nose along +X. The caller
owns the transform, shadow, juvenile scaling and hunger/selection indicators.
Art helpers must not modify simulation state. Body art uses the supplied
simulation presentation time; ambient scenery/UI may use the real-time clock.

Tree and shrub anchors stay in world coordinates through expansion. Their
shadows are separate ground elements. Foliage, plants and animals share one
ordering by ground Y; nearby crowns fade smoothly so animals remain observable.
Tree and thicket crowns are visual cover, not newly introduced solid obstacles.

Food artwork must preserve the existing ecology cues. Depleted carrots have no
orange roots, recovering carrots have fresh shoots, depleted berries are
fruitless and clipped, and recovering berries show foliage without fruit.
Abundance changes food silhouette; site quality changes the ground footprint.

## Review at gameplay scale

Check opening and expanded camera views, the maximum zoom, young and adult
animals, feeding, ordinary stops, danger interruption, pursuit/capture, pause,
and 1×/3×. Inspect a creature behind, within and in front of a canopy. A large
pose sheet is useful for anatomy, but it does not replace these scene checks.

The first implementation intentionally keeps the ecological motor and timing
rules intact. Capture has a brief visual response; it does not add a new feeding
delay or alter predation outcomes. Changes to those rules require separate
gameplay validation.
