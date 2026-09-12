class_name DotPlayerClassApply
extends RefCounted

## Writes a class's numbers onto the things that actually use them.
##
## [b]The seam that was missing, and the reason it is a bridge rather than a method on
## [DotPlayerClassDef].[/b] A class carries `max_health`, `max_armour`, regeneration, a
## move-speed scale, a jump scale, a knockback scale and a mass — and those belong to
## dot-combat and dot-player-controller, neither of which this addon depends on or wants
## to. A `DotPlayerClassDef` that named `DotHealth` would be a class document a dedicated
## server could not validate without installing a combat addon, which is the whole thing
## this addon promises not to need.
##
## So it is duck-typed, exactly the way [code]DotTeamRoster.bind_match[/code] drives
## dot-match and [code]DotWeaponPlayer[/code] reaches dot-player: fields are written
## through [method Object.set] after [method Object.get] has shown they exist. No
## [code]DotHealth[/code] or [code]DotFpsTunables[/code] identifier appears anywhere in
## this file, so a project with neither installed still compiles it — which is not a
## style point: a script that merely MENTIONS a `class_name` the project does not have
## fails to parse and takes every script referencing it down with it.
##
## [b]Why this exists at all: five games were each about to write the same six lines, and
## every one of them had instead written none.[/b] The class manager decided who was what
## and emitted it, and the numbers on the document reached nothing — a value produced
## correctly and consumed by nothing, which is this family's most repeated shape.
##
## [codeblock]
## var def := classes.def_of(key)
## DotPlayerClassApply.to_health(def, player.health)
## DotPlayerClassApply.to_movement(def, player.controller.tunables)
## [/codeblock]

const CHANNEL := "player.class.apply"


## Writes the health half onto anything shaped like a health component.
##
## Recognised fields: `max_health`, `max_armour`, `regen_per_second`, `regen_delay_sec`.
## Anything the target does not have is skipped rather than being an error — a game with
## a simpler health model is not a game doing something wrong.
##
## [param reset_to_full] calls `reset(tick)` afterwards when the target has one, which is
## what makes a class change land as a full bar rather than as a bar that is suddenly
## over its own maximum. Off by default, because a mid-life class change that healed you
## is an exploit in every game that has one.
##
## Returns the number of fields written, so a caller can log "applied nothing" rather
## than believing it worked.
static func to_health(
	def: Object, health: Object, reset_to_full: bool = false, tick: int = 0
) -> int:
	if def == null or health == null:
		return 0

	var written := 0

	written += _copy(def, health, "max_health", "max_health")
	written += _copy(def, health, "max_armour", "max_armour")
	written += _copy(def, health, "regen_per_second", "regen_per_second")
	written += _copy(def, health, "regen_delay_sec", "regen_delay_sec")

	# [b]After the maximum, never before.[/b] `reset` sets health to `max_health`, so
	# resetting first and then raising the maximum leaves a "full" player on the old
	# class's number — visibly full, quietly missing the difference.
	if reset_to_full and health.has_method("reset"):
		health.call("reset", tick)

	if written == 0:
		DotLog.debug(CHANNEL, "no health fields matched", {"class": _id_of(def)})

	return written


## Writes the movement half onto anything shaped like a tunables object.
##
## [b]Scales, not values, and that is what makes it composable.[/b] A class says "80% of
## the speed", not "5.6 m/s" — so a server that changes `sv_maxspeed`, a style that
## halves air acceleration and a class that is slow all still multiply rather than one
## of them silently winning. The base is read from [param base] when one is given, which
## is what stops a second application compounding: applying a 0.8 scale twice to the
## same object is 0.64, and that is the bug this parameter exists to prevent.
##
## Recognised fields: `max_speed`, `jump_height`, `mass`.
static func to_movement(def: Object, tunables: Object, base: Object = null) -> int:
	if def == null or tunables == null:
		return 0

	var source: Object = base if base != null else tunables
	var written := 0

	written += _scale(def, "move_speed_scale", source, tunables, "max_speed")
	written += _scale(def, "jump_scale", source, tunables, "jump_height")
	written += _copy(def, tunables, "mass", "mass")

	if written == 0:
		DotLog.debug(CHANNEL, "no movement fields matched", {"class": _id_of(def)})

	return written


## The knockback multiplier, for a game that has one. Returns 1.0 when the class has none.
##
## Not written anywhere, because knockback is applied at the moment of a hit rather than
## held on a component — so there is nothing to write it onto and a caller multiplies by
## it instead.
static func knockback_scale(def: Object) -> float:
	if def == null:
		return 1.0

	var value: Variant = def.get("knockback_scale")
	return float(value) if value != null else 1.0


# --- The duck typing --------------------------------------------------------

static func _copy(from: Object, to: Object, from_field: String, to_field: String) -> int:
	var value: Variant = from.get(from_field)

	if value == null:
		return 0

	# `get` on an absent property answers null, which is also a legitimate value for a
	# property that exists — so the target is checked with its own property list rather
	# than by comparing against null, which would write a field that is not there and
	# lose it silently.
	if not _has_property(to, to_field):
		return 0

	to.set(to_field, value)
	return 1


static func _scale(
	def: Object, scale_field: String, source: Object, to: Object, field: String
) -> int:
	var scale: Variant = def.get(scale_field)

	if scale == null or not _has_property(to, field) or not _has_property(source, field):
		return 0

	to.set(field, float(source.get(field)) * float(scale))
	return 1


static func _has_property(target: Object, field: String) -> bool:
	for entry: Dictionary in target.get_property_list():
		if String(entry.get("name", "")) == field:
			return true

	return false


static func _id_of(def: Object) -> String:
	var id: Variant = def.get("id")
	return String(id) if id != null else "<unnamed>"
