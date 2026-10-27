# dot-player-class design

Why the addon is shaped the way it is. The one-line rules are in [CLAUDE.md](../CLAUDE.md).

## The one idea

**A class change is a request, recorded, that the next spawn honours.**

Everything else follows. It is why `request()` returns a `DotResult` rather than being a setter; why there is a `_pending` dictionary at all; why `apply_pending` returns the class being spawned as rather than `void`; and why a refusal carries a sentence instead of a boolean.

The reason is not tidiness. Changing class mid-fight changes health, speed and weapons while somebody is shooting at you, and the outcome is an exploit or a bug report depending on who wins. The class screen saying "you will respawn as a medic" is the feature.

The second idea is dot-user-avatar's and dot-loadout's, restated: **a dedicated server decides whether somebody may be a class without loading any content.** Every field in `DotPlayerClassDef` is a number or an id. The suite loads nothing, which is the check.

## `get_class_def`, not `get_class`

`Object.get_class()` exists, and GDScript takes a shadowing definition **without a warning**: the trap in [gdscript-hazards.md](../../../docs/gdscript-hazards.md) that cost a pity table its reset. The accessor is named for the thing it returns instead.

## Counting counts what people *are*

`count_on_team` deliberately ignores pending choices. Counting them would let two players both be refused the last sniper slot because each was counted against the other, and neither is a sniper yet.

The limit check subtracts one when the asker already *is* the class in question, so re-requesting your own class is never refused for occupying its own slot. That sounds like an edge case and is the commonest one: a class screen that re-sends the current selection on every open.

## A pending choice can stop being legal

Between the request and the spawn, the slot can fill or the player can change side. `apply_pending` re-checks, drops the choice and fires `class_refused`, because a class screen claiming a change that is never going to happen is worse than being told no. The suite queues three players for two sniper slots and checks the third one finds out.

## Entitlement is checked by the game, never here

`entitled_fn` is a callable the game supplies. An addon that decided entitlement would be an addon a client could patch; the authority is dot-auth, a backbone, or a shop. `requires_entitlement` is only an id this addon carries. The same principle as dot-user-avatar's: the addon validates *shape*, the platform validates *permission*.

## The presets are relations, not content

`team_shooter()` has six classes and every content id in it is empty. The point is that the heavy has about three times the scout's health and about half its speed: the relations are what a game tunes and what a project writing this from scratch has to discover. What a class *looks like* is dot-player-char's, resolved on a client. The other presets are `single()` and `asymmetric()`.

## What the manager does not do

It does not apply anything. It never sets health, never touches a controller's speed, never equips a loadout. The game reads `def_of(key)` on spawn and does all three, because the order those happen in is a game's decision and getting it wrong here would be invisible.

It does not know what a spawn is either: `apply_pending` is called by whatever spawns.

## `DotPlayerClassApply`: the seam, and why it is duck-typed

A class carries `max_health`, `max_armour`, regeneration, a move-speed scale, a jump scale, a knockback scale and a mass. Those belong to dot-combat and dot-player-controller, neither of which this addon depends on or wants to: a `DotPlayerClassDef` that named `DotHealth` would be a class document a dedicated server could not validate without installing a combat addon, which is the whole thing this addon promises not to need.

So the bridge writes through `Object.set` after `Object.get` has shown the field exists, the same way `DotTeamRoster.bind_match` drives dot-match. **No `DotHealth` or `DotFpsTunables` identifier appears in the file**, which is not a style point: a script that merely mentions a `class_name` the project does not have fails to parse and takes every script referencing it down with it.

It exists because games had each been about to write the same six lines and had instead written none: the manager decided who was what and emitted it, and the numbers on the document were read by nobody.

Two things the suite pins, because both are easy to get wrong:

- **The scales multiply, so applying one twice compounds.** 0.8 applied twice is 0.64, and a player who respawned four times would be at 0.41 of the speed with every number in the inspector looking deliberate. `to_movement` takes an untouched `base` to read from, which makes a respawn idempotent.
- **`reset_to_full` runs after the maximum is written, never before.** `reset` sets health to `max_health`, so resetting first and raising the maximum afterwards leaves a "full" player on the old class's number: visibly full, quietly short.

The suite stands it up against **stubs** rather than against the real classes, and that is the check rather than a convenience: this project installs dot-core and dot-player and nothing else, so if the bridge ever names one of those classes the suite stops compiling.

## Classes as dot-profile data

`DotPlayerClassProfiles` is the dot-profile schema for kind `class`, so an operator edits a yml (`cfg/server/game/<game>/class/<id>.yml`) instead of code, with the usual layers (defaults < addon < game < server < environment < command line, and the runtime layer). Walk, sprint and crouch scales, the four stamina numbers and `carry_limit` default to `DotPlayerClassDef.INHERIT` (-1): the class does not set them and the game's own tunable stands, which keeps one source per number (Zombie Zone's `ZzConfig` stays the default, the class only overrides). `move_speed_scale` (`speed` in the yml) multiplies the run speed. `to_movement` writes only the fields the class sets; `DotPlayerClassApply.carry_limit(def, fallback)` answers the capacity. Out-of-range values and unknown keys fail the load (the schema's), and `validate()` refuses a negative that is not -1. A change applies where the game re-reads the profile, normally the next spawn.


### Editing a class (server owner)

Copy only the keys you change into `cfg/server/game/<game>/class/<id>.yml`; the keys are `DotPlayerClassProfiles.schema()` and the full list with ranges is in dot-profile's `docs/profiles.md`. Ranges are enforced on load (unsafe values and unknown keys refuse the file, the shipped class stays), `-1` keeps the game's number, and a layer above the server file (environment, command line) wins. Checked by `examples/class_selftest`.

## Damage immunity

A class profile may list `immune: [fall, fire]` (damage type ids, or `all`); `DotPlayerClassDef.immune_to` carries it and `DotPlayerClassApply.to_immunity(def, immunity, entity)` writes it onto dot-combat's `DotDamageImmunity` at spawn, which the resolver consults first. Empty by default, so no game changes. It is an ordinary schema field, so the workbench class editor shows it as a list. A class with none clears the entity's entry, so a respawn does not keep the old class's immunities.
