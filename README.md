This is the **player class** asset for TMC's **Dot** collection. It is what a player *is* — health, speed, what they carry, what they can do — as a bounded document a dedicated server can check without loading any content at all.

This collection of assets provides modular building blocks for creating games and applications within the TMC ecosystem, ensuring consistency and interoperability across all `dot-*` assets. This includes core functionality, networking, authentication, cloud integration, and more.

**These assets are COMPLETELY OPEN SOURCE**. You are free to use, modify, and distribute them under the terms of the MIT license. The only thing not open source is the back-end web infrastructure. So if you opt into using your own authentication backend instead of integrating with TMC, you will need to build and integrate your own back-end infrastructure.

## From Maintainer & WARNING
This asset, along with all the others, was built initially with **Claude Code** and will continue to be maintained and extended using it. This is because I (`gamemann`) cannot build the entire TMC platform alone (I wish I could lol).

**Please treat this as partially tested.** Every asset has its own headless test suite and those suites pass, but very little of this has been in front of real players yet. Expect rough edges, and please report anything you run into.

I intend on reviewing code, testing, and editing documentation regularly. If you're interested in helping out, please let me know!

## A class change lands on your next spawn, not mid-fight

This is the whole shape of the addon.

Changing class while somebody is shooting at you changes your health, your speed and your weapons in the middle of a gunfight — which is either an exploit or a bug report, depending on who wins. So a request is **recorded**, and the next spawn honours it:

```gdscript
classes.request("ada", &"medic")     # ok, but not yet
classes.pending_of("ada")            # &"medic"
classes.class_of("ada")              # still &"assault"

# On spawn:
var spawning_as := classes.apply_pending("ada")   # &"medic"
```

A class-select screen that says *"you will respawn as a medic"* is not a limitation; it is the feature. A player who is already dead gets the change immediately, because a dead player has nothing to exploit and making them wait for a second death is just confusing.

## Install

Copy `addons/dot_player_class/`, `addons/dot_player/` and `addons/dot_core/` into your project and enable all three in *Project → Project Settings → Plugins*.

Requires Godot 4.7 or newer.

## Use

```gdscript
var classes := DotPlayerClassManager.new()
classes.catalogue = DotPlayerClassCatalogue.team_shooter()
classes.rules     = DotPlayerClassRules.standard()
classes.team_fn   = func(key): return teams.team_of(key)
classes.alive_fn  = func(key): return roster.get_record(key).alive
add_child(classes)
classes.setup()

var res := classes.request("ada", &"sniper")
if not res.ok:
    hud.say(res.error.message)   # "Your side already has 2 Sniper."
```

## Everything is a number or an id

A server has to be able to say *"no, you cannot be that"* without loading a mesh, an animation set or a weapon scene — the same requirement that shaped dot-user-avatar and dot-loadout, for the same reason: a server running a match should not have to ship every piece of content anybody owns.

So a class **names** its loadout, its model, its animation set and its abilities. It does not contain them. Resolution from an id to actual content happens on a client, through a catalogue, through dot-cloud. The self-test loads nothing, which is the check on that promise.

## Refusals say why

Every door in is a `DotResult`, because every refusal has a sentence a player needs to read:

| | |
| --- | --- |
| `limit_per_team` | "Your side already has 2 Sniper." The answer to a team of nine snipers. |
| `teams` | "Breacher is not available to your side." |
| `requires_entitlement` | "You do not have Heavy." The check itself is the **game's** — an addon that decided entitlement would be one a client could patch. |
| `allow_midround_change` | "Classes are locked once the round has started." |

`options_for(key)` returns every class with `available`, `why`, `taken` and `limit` — which is the difference between a greyed-out button and a greyed-out button with a tooltip.

## What is in the box

| | |
| --- | --- |
| `DotPlayerClassDef` | One class. Health, armour and its absorption, movement multipliers, mass, content ids, abilities, team restrictions, limits, entitlement. |
| `DotPlayerClassCatalogue` | The set. Three presets: `single`, `team_shooter` (six classes, tuned as *relations*), `asymmetric`. |
| `DotPlayerClassRules` | When a choice may be made and when it lands. Four presets. A `DotConfig`, so it layers. |
| `DotPlayerClassManager` | Current class, pending class, limits, entitlements, and a mirror for clients. |

`DotPlayerClassCatalogue.single()` exists on purpose. A game with no classes that models itself as having *no catalogue* makes every consumer branch on whether classes exist; one class makes health, speed and the loadout id come from the same place they do in every other mode.

## The armour arithmetic is here

```gdscript
var hit := def.absorb(50.0, current_armour)
health -= hit["health_damage"]
armour  = hit["armour_left"]
```

In this file rather than in dot-combat because the numbers that decide it are in this file, and a game doing the arithmetic itself is a game where the class screen and the damage model disagree about what 150 armour means.

## Licence

MIT. See [LICENSE](LICENSE).
