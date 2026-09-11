# dot-player-class

What a player is, as a document rather than as a scene.

Read the family-wide conventions in [`../../CLAUDE.md`](../../CLAUDE.md) first — no autoloads, `DotNodeRef` instead of scene paths, `DotResult` for anything fallible, `Dot`-prefixed class names, layered configuration, `describe()` on anything stateful. This file is only what is specific to classes.

## The one idea

**A class change is a request, recorded, that the next spawn honours.**

Everything else follows. It is why `request()` returns a `DotResult` rather than being a setter; why there is a `_pending` dictionary at all; why `apply_pending` returns the class being spawned as rather than `void`; and why a refusal carries a sentence instead of a boolean.

The reason is not tidiness. Changing class mid-fight changes health, speed and weapons while somebody is shooting at you, and the outcome is an exploit or a bug report depending on who wins. The class screen saying "you will respawn as a medic" is the feature.

The second idea is dot-user-avatar's and dot-loadout's, restated: **a dedicated server decides whether somebody may be a class without loading any content.** Every field in `DotPlayerClassDef` is a number or an id. The suite loads nothing, which is the check.

## Layout

```
addons/dot_player_class/
  core/
    dot_player_class_def.gd        one class, as numbers and ids
    dot_player_class_catalogue.gd  the set, and three presets
    dot_player_class_rules.gd      when a choice may be made and when it lands
  runtime/
    dot_player_class_manager.gd    current, pending, limits, entitlements, mirror
```

## `get_class_def`, not `get_class`

`Object.get_class()` exists, and GDScript takes a shadowing definition **without a warning** — the trap in `docs/gdscript-hazards.md` that cost a pity table its reset. The accessor is named for the thing it returns instead.

## Counting counts what people *are*

`count_on_team` deliberately ignores pending choices. Counting them would let two players both be refused the last sniper slot because each was counted against the other, and neither is a sniper yet.

The same function subtracts one when the asker already *is* the class in question, so re-requesting your own class is never refused for occupying its own slot. That sounds like an edge case and is the commonest one: a class screen that re-sends the current selection on every open.

## A pending choice can stop being legal

Between the request and the spawn, the slot can fill or the player can change side. `apply_pending` re-checks, drops the choice and fires `class_refused` — because a class screen claiming a change that is never going to happen is worse than being told no. The suite queues three players for two sniper slots and checks the third one finds out.

## Entitlement is checked by the game, never here

`entitled_fn` is a callable the game supplies. An addon that decided entitlement would be an addon a client could patch; the authority is dot-auth, a backbone, or a shop. `requires_entitlement` is only an id this addon carries.

The same principle as dot-user-avatar's: the addon validates *shape*, the platform validates *permission*.

## The presets are relations, not content

`team_shooter()` has six classes and every content id in it is empty. The point is that the heavy has twice the scout's health and two-thirds its speed — the relations are what a game tunes and what a project writing this from scratch has to discover. What a class *looks like* is dot-player-char's, resolved on a client.

## What this does not do

It does not apply anything. It never sets health, never touches a controller's speed, never equips a loadout. The game reads `def_of(key)` on spawn and does all three, because the order those happen in is a game's decision and getting it wrong here would be invisible.

It does not know what a spawn is either: `apply_pending` is called by whatever spawns, which is dot-spawn in most of these games and the match loop in the rest.
