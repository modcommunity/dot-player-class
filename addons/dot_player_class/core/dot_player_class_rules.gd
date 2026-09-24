@tool
class_name DotPlayerClassRules
extends DotConfig

## When a class may be chosen, when the choice takes effect, and what is enforced.

@export_group("Choosing")

## Whether players pick at all, or are simply given the default.
@export var allow_choice: bool = true

## Whether a choice may be made after a round has started.
@export var allow_midround_change: bool = true

## Whether per-class team limits are enforced.
##
## Off, a limit is decoration. On, class assignment has to be a request that can be
## refused — which is why [method DotPlayerClassManager.request] returns a [DotResult]
## rather than being a setter.
@export var enforce_limits: bool = true

## Whether a player may be refused a class their entitlement does not cover.
##
## The check itself is the game's, through [member DotPlayerClassManager.entitled_fn].
## This only decides whether it is consulted.
@export var enforce_entitlements: bool = true

@export_group("When it lands")

## Whether a change waits for the next spawn instead of applying immediately.
##
## [b]On, and this is the setting the whole addon is shaped around.[/b] Changing class
## mid-fight is changing your health, your speed and your weapons while somebody is
## shooting at you — which is either an exploit or a bug report, depending on who wins.
## The classic answer is that the choice is recorded and the next respawn honours it,
## and a class-select screen that says "you will respawn as a medic" is not a
## limitation, it is the feature.
@export var apply_on_respawn: bool = true

## Whether a change applies immediately when the chooser is already dead.
##
## On: a dead player has nothing to exploit, and making them wait for a second death is
## just confusing.
@export var apply_immediately_when_dead: bool = true

## Whether a pending choice survives a round ending.
@export var pending_survives_round: bool = true

@export_group("Resetting")

## Whether everybody is put back on the default class when a match ends.
@export var reset_on_match_end: bool = false

## Whether changing team clears the class.
##
## On when the two sides have different rosters: a class the new side cannot field is a
## class the player is silently not allowed to be, and clearing it is the honest answer.
@export var clear_on_team_change: bool = true


func env_prefix() -> String:
	return "DOT_PLAYER_CLASS_"


func cli_prefix() -> String:
	return "class-"


func validate() -> DotResult:
	if not allow_choice and not apply_on_respawn:
		# Legal, and meaningless: nobody chooses, so nothing is ever pending.
		DotLog.debug("player.class", "choice is off; apply_on_respawn has nothing to do")

	if enforce_entitlements and not allow_choice:
		DotLog.debug("player.class", "entitlements are enforced on a choice nobody makes")

	return DotResult.success(null)


# --- Presets ----------------------------------------------------------------

## Pick freely, land on the next spawn, limits enforced. The usual team shooter.
static func standard() -> DotPlayerClassRules:
	# Not this class's own name. A script that names itself in an expression, loaded after
	# its base, cuts Godot 4.7.2's exit teardown short and leaks every script loaded before
	# it. See docs/gdscript-hazards.md, "A script that names itself".
	return new()


## Pick freely and land immediately. A sandbox, a lobby, a practice server.
static func instant() -> DotPlayerClassRules:
	var r := new()
	r.apply_on_respawn = false
	r.enforce_limits = false
	return r


## Locked once the round is live. A competitive mode.
static func competitive() -> DotPlayerClassRules:
	var r := new()
	r.allow_midround_change = false
	r.enforce_limits = true
	r.apply_on_respawn = true
	r.reset_on_match_end = true
	return r


## No choosing at all. A game with one class, or one a mode assigns.
static func fixed() -> DotPlayerClassRules:
	var r := new()
	r.allow_choice = false
	r.allow_midround_change = false
	return r


static func presets() -> Dictionary:
	return {
		&"standard": standard,
		&"instant": instant,
		&"competitive": competitive,
		&"fixed": fixed,
	}


static func preset(p_id: StringName) -> DotPlayerClassRules:
	var table := presets()

	if not table.has(p_id):
		return null

	var fn: Callable = table[p_id]
	# Returned through the declared type rather than cast to this class by name; see the
	# note on the presets above.
	return fn.call()
