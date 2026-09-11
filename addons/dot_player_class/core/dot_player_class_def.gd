@tool
class_name DotPlayerClassDef
extends Resource

## One playable class: what it has, what it can do, and who may take it.
##
## [b]Everything here is a number or an id, and that is the whole design.[/b] A
## dedicated server has to be able to say "no, you cannot be that" without loading a
## mesh, an animation set or a weapon scene — the same requirement that shaped
## dot-user-avatar and dot-loadout, and for the same reason: a server running a match
## should not have to ship every piece of content anybody owns.
##
## So a class names its loadout, its model and its abilities; it does not contain them.
## Resolution from an id to actual content happens on a client, through a catalogue,
## through dot-cloud.

## The name everything else uses. [code]&"medic"[/code], [code]&"scout"[/code].
@export var id: StringName = &""

@export var display_name: String = ""

## One line for a class-select screen.
@export_multiline var description: String = ""

@export_group("Health")

## Starting and maximum health.
@export_range(1.0, 100000.0, 1.0) var max_health: float = 100.0

## Starting armour, if the game has any.
@export_range(0.0, 100000.0, 1.0) var max_armour: float = 0.0

## Fraction of incoming damage armour absorbs while it lasts.
@export_range(0.0, 1.0, 0.01) var armour_absorption: float = 0.5

## Health regenerated per second, after [member regen_delay_sec] without damage.
@export_range(0.0, 1000.0, 0.1) var regen_per_second: float = 0.0

@export_range(0.0, 60.0, 0.1) var regen_delay_sec: float = 5.0

@export_group("Movement")

## Multiplier on ground speed. Read by a controller; this addon never moves anything.
@export_range(0.05, 10.0, 0.01) var move_speed_scale: float = 1.0

## Multiplier on jump height.
@export_range(0.0, 10.0, 0.01) var jump_scale: float = 1.0

## Multiplier on how hard explosions and impacts push this class about.
@export_range(0.0, 10.0, 0.01) var knockback_scale: float = 1.0

## Kilograms, for anything that cares: a lift, a pressure plate, a vehicle's capacity.
@export_range(1.0, 10000.0, 1.0) var mass: float = 80.0

@export_group("Content ids")

## The dot-loadout document this class starts with.
@export var loadout_id: StringName = &""

## The dot-player-char-model or -sprite id this class looks like.
@export var char_id: StringName = &""

## The dot-player-char-animations set to drive.
@export var animation_set: StringName = &""

## dot-audio ids for a voice, by situation. Open-ended on purpose.
@export var voice_set: StringName = &""

## Ability ids a game resolves however it likes.
##
## Not scripts, not scenes: a server deciding whether a class is legal must not load
## one, and an ability that is a [Script] here is an ability a server has to compile.
@export var abilities: Array[StringName] = []

@export_group("Availability")

## Which teams may take it. Empty means all of them.
@export var teams: Array[StringName] = []

## How many of this class one side may field at once. Zero is unlimited.
##
## The classic answer to a team of nine snipers, and the reason class assignment has to
## be a request that can be refused rather than a property somebody sets.
@export_range(0, 1024, 1) var limit_per_team: int = 0

## An entitlement id a player must hold. Empty means anybody.
##
## Checked by the game against dot-auth or dot-user; this addon only carries the id,
## because an addon that decided entitlement would be an addon a client could patch.
@export var requires_entitlement: StringName = &""

## Whether this class can be picked at all. For one a mode disables.
@export var selectable: bool = true

@export_group("Anything else")

## Open-ended per-class data, the way [code]DotTeamDef.attributes[/code] is.
@export var attributes: Dictionary = {}


static func make(
	p_id: StringName,
	p_health: float = 100.0,
	p_speed: float = 1.0
) -> DotPlayerClassDef:
	var c := DotPlayerClassDef.new()
	c.id = p_id
	c.display_name = String(p_id).capitalize()
	c.max_health = p_health
	c.move_speed_scale = p_speed
	return c


func validate() -> DotResult:
	if id == &"":
		return DotResult.fail(DotError.CODE_INVALID, "A class with no id cannot be asked for.")

	if max_health <= 0.0:
		return DotResult.fail(
			DotError.CODE_INVALID,
			"'%s' has %0.1f health, so it is dead the moment it spawns." % [String(id), max_health]
		)

	if armour_absorption > 0.0 and max_armour <= 0.0:
		# Not an error: a class that gains armour from a pickup starts with none and
		# absorbs when it has some. Worth saying, because the other reading — somebody
		# set absorption and forgot the armour — is more common.
		DotLog.debug(
			"player.class",
			"a class absorbs damage with armour and starts with none",
			{"class": String(id)}
		)

	return DotResult.success(null)


## Whether a side may field this class at all.
func allows_team(team: StringName) -> bool:
	if not selectable:
		return false

	if teams.is_empty() or team == &"":
		return true

	return teams.has(team)


func has_ability(ability: StringName) -> bool:
	return abilities.has(ability)


func attribute(key: String, fallback: Variant = null) -> Variant:
	return attributes.get(key, fallback)


## Effective damage after armour, and how much armour is left.
##
## Here rather than in dot-combat because the numbers that decide it are here, and a
## game doing the arithmetic itself is a game where the class screen and the damage
## model disagree about what 150 armour means.
func absorb(damage: float, armour: float) -> Dictionary:
	if armour <= 0.0 or armour_absorption <= 0.0:
		return {"health_damage": damage, "armour_left": armour}

	var absorbed := minf(armour, damage * armour_absorption)
	return {
		"health_damage": maxf(0.0, damage - absorbed),
		"armour_left": maxf(0.0, armour - absorbed),
	}


func to_dict() -> Dictionary:
	return {
		"id": String(id),
		"name": display_name,
		"health": max_health,
		"armour": max_armour,
		"speed": move_speed_scale,
		"loadout": String(loadout_id),
		"char": String(char_id),
		"anims": String(animation_set),
		"voice": String(voice_set),
		"limit": limit_per_team,
		"teams": _strings(teams),
		"abilities": _strings(abilities),
		"selectable": selectable,
	}


static func from_dict(d: Dictionary) -> DotPlayerClassDef:
	var c := DotPlayerClassDef.new()
	c.id = StringName(str(d.get("id", "")))
	c.display_name = str(d.get("name", String(c.id).capitalize()))
	c.max_health = float(d.get("health", 100.0))
	c.max_armour = float(d.get("armour", 0.0))
	c.move_speed_scale = float(d.get("speed", 1.0))
	c.loadout_id = StringName(str(d.get("loadout", "")))
	c.char_id = StringName(str(d.get("char", "")))
	c.animation_set = StringName(str(d.get("anims", "")))
	c.voice_set = StringName(str(d.get("voice", "")))
	c.limit_per_team = int(d.get("limit", 0))
	c.selectable = bool(d.get("selectable", true))

	for t: Variant in d.get("teams", []):
		c.teams.append(StringName(str(t)))

	for a: Variant in d.get("abilities", []):
		c.abilities.append(StringName(str(a)))

	return c


func describe() -> String:
	return "%s: %.0f hp%s, speed %.2f%s%s" % [
		String(id),
		max_health,
		"" if max_armour <= 0.0 else " / %.0f armour" % max_armour,
		move_speed_scale,
		"" if limit_per_team == 0 else ", max %d per side" % limit_per_team,
		"" if selectable else ", not selectable",
	]


func _strings(list: Array[StringName]) -> Array:
	var out: Array = []
	for s in list:
		out.append(String(s))
	return out


func _to_string() -> String:
	return "DotPlayerClassDef(%s)" % describe()
