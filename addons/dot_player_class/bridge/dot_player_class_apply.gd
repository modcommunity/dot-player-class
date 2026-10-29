class_name DotPlayerClassApply
extends RefCounted

## Writes a class's numbers onto health and movement tunables, duck-typed.
##
## Fields are set through [method Object.set] after checking they exist, so no `DotHealth`
## identifier appears here: naming a `class_name` the project lacks fails the parse.
## [codeblock]
## var def := classes.def_of(key)
## DotPlayerClassApply.to_health(def, player.health)
## DotPlayerClassApply.to_movement(def, player.controller.tunables)
## [/codeblock]

const CHANNEL := "player.class.apply"

## Class field to tunables field, written only when the class sets it.
const MOVEMENT_FIELDS := [
	["walk_speed_scale", "walk_speed_scale"], ["sprint_speed_scale", "sprint_speed_scale"],
	["crouch_speed_scale", "crouch_speed_scale"], ["stamina_drain", "stamina_drain"],
	["stamina_recover", "stamina_recover"], ["stamina_resume_at", "stamina_resume_at"],
	["stamina_exhaust_delay", "stamina_exhaust_delay"],
]


## Writes the health half onto anything shaped like a health component.
## [param reset_to_full] calls `reset(tick)` afterwards; off by default, since a mid-life
## class change that healed would be an exploit. Returns the number of fields written.
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

	# After the maximum: `reset` fills to `max_health`, so resetting first leaves the old number.
	if reset_to_full and health.has_method("reset"):
		health.call("reset", tick)

	if written == 0:
		DotLog.debug(CHANNEL, "no health fields matched", {"class": _id_of(def)})

	return written


## Writes the movement half onto anything shaped like a tunables object.
## Scales multiply the value read from [param base] (default the target itself); a base
## stops a second application compounding (0.8 twice is 0.64).
static func to_movement(def: Object, tunables: Object, base: Object = null) -> int:
	if def == null or tunables == null:
		return 0

	var source: Object = base if base != null else tunables
	var written := 0

	written += _scale(def, "move_speed_scale", source, tunables, "max_speed")
	written += _scale(def, "jump_scale", source, tunables, "jump_height")
	written += _copy(def, tunables, "mass", "mass")

	# A field at -1 (DotPlayerClassDef.INHERIT) is the game's own value and is left alone.
	for pair: Array in MOVEMENT_FIELDS:
		var v: Variant = def.get(pair[0])
		if v != null and float(v) >= 0.0 and _has_property(tunables, pair[1]):
			tunables.set(pair[1], float(v))
			written += 1

	if written == 0:
		DotLog.debug(CHANNEL, "no movement fields matched", {"class": _id_of(def)})

	return written


## The class's carry capacity, or [param fallback] when it keeps the game's.
static func carry_limit(def: Object, fallback: float) -> float:
	if def == null:
		return fallback
	var v: Variant = def.get("carry_limit")
	return float(v) if v != null and float(v) >= 0.0 else fallback


## The knockback multiplier, 1.0 when the class has none. Multiplied at hit time, not written.
static func knockback_scale(def: Object) -> float:
	if def == null:
		return 1.0

	var value: Variant = def.get("knockback_scale")
	return float(value) if value != null else 1.0


## Writes the class's damage immunities for [param entity] onto anything with
## `set_immune(entity, kinds)`; none clears the entry. Returns the number written.
static func to_immunity(def: Object, immunity: Object, entity: int) -> int:
	if def == null or immunity == null or not immunity.has_method("set_immune"):
		return 0

	var kinds: Variant = def.get("immune_to")
	var list: Array = kinds if kinds is Array else []
	immunity.call("set_immune", entity, list)
	return list.size()


static func _copy(from: Object, to: Object, from_field: String, to_field: String) -> int:
	var value: Variant = from.get(from_field)

	if value == null:
		return 0

	# `get` answers null for an absent property too, so check the property list instead.
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
