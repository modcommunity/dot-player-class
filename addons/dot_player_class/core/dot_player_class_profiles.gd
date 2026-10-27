class_name DotPlayerClassProfiles
extends RefCounted

## Loads [DotPlayerClassDef] from `class` profiles (cfg/addon/dot-player-class/class, cfg/game/<game>/class, cfg/server/...).
##
## A server owner edits a yml, not code. Ranges are the schema's, so an unsafe value is refused on load.

const ADDON := "dot-player-class"
const KIND := "class"


## Every def field a server may tune; ids and content references stay strings.
static func schema() -> Array:
	var f := DotProfileSet.field
	var inherit := {"min": -1.0, "max": 10.0}
	return [
		f.call("name", "string", ""),
		f.call("description", "string", ""),
		f.call("health", "float", 100.0, {"min": 1.0, "max": 100000.0}),
		f.call("armour", "float", 0.0, {"min": 0.0, "max": 100000.0}),
		f.call("armour_absorption", "float", 0.5, {"min": 0.0, "max": 1.0}),
		f.call("regen_per_second", "float", 0.0, {"min": 0.0, "max": 1000.0}),
		f.call("regen_delay_sec", "float", 5.0, {"min": 0.0, "max": 60.0}),
		f.call("speed", "float", 1.0, {"min": 0.05, "max": 10.0}),
		f.call("walk_speed_scale", "float", DotPlayerClassDef.INHERIT, {"min": -1.0, "max": 1.0}),
		f.call("sprint_speed_scale", "float", DotPlayerClassDef.INHERIT, {"min": -1.0, "max": 3.0}),
		f.call("crouch_speed_scale", "float", DotPlayerClassDef.INHERIT, {"min": -1.0, "max": 1.0}),
		f.call("stamina_drain", "float", DotPlayerClassDef.INHERIT, inherit),
		f.call("stamina_recover", "float", DotPlayerClassDef.INHERIT, inherit),
		f.call("stamina_resume_at", "float", DotPlayerClassDef.INHERIT, {"min": -1.0, "max": 1.0}),
		f.call("stamina_exhaust_delay", "float", DotPlayerClassDef.INHERIT, inherit),
		f.call("carry_limit", "float", DotPlayerClassDef.INHERIT, {"min": -1.0, "max": 1000.0}),
		f.call("jump_scale", "float", 1.0, {"min": 0.0, "max": 10.0}),
		f.call("knockback_scale", "float", 1.0, {"min": 0.0, "max": 10.0}),
		f.call("mass", "float", 80.0, {"min": 1.0, "max": 10000.0}),
		f.call("loadout", "string", ""),
		f.call("char", "string", ""),
		f.call("anims", "string", ""),
		f.call("voice", "string", ""),
		f.call("abilities", "list", []),
		f.call("teams", "list", []),
		f.call("limit", "int", 0, {"min": 0, "max": 1024}),
		f.call("entitlement", "string", ""),
		f.call("selectable", "bool", true),
	]


## Kind to schema for tools that validate profiles without a game (dot-profile's profile_check).
static func profile_schemas() -> Dictionary:
	return {KIND: {"schema": schema(), "children": {}}}


## A profile set for classes of [param game]; [param roots] overrides the config roots (tests).
static func make_set(game: String, roots: PackedStringArray = PackedStringArray()) -> DotProfileSet:
	var s := DotProfileSet.create(ADDON, game, KIND, schema())
	s.roots = roots
	return s


## Builds a def from a loaded profile; the keys are the schema's.
static func def_from_profile(profile: DotProfile) -> DotPlayerClassDef:
	var v := profile.values
	var c := DotPlayerClassDef.new()
	c.id = StringName(profile.id)
	c.display_name = str(v["name"]) if str(v["name"]) != "" else profile.id.capitalize()
	c.description = str(v["description"])
	c.max_health = float(v["health"])
	c.max_armour = float(v["armour"])
	c.armour_absorption = float(v["armour_absorption"])
	c.regen_per_second = float(v["regen_per_second"])
	c.regen_delay_sec = float(v["regen_delay_sec"])
	c.move_speed_scale = float(v["speed"])
	for field: String in DotPlayerClassDef.INHERITING:
		c.set(field, float(v[field]))
	c.jump_scale = float(v["jump_scale"])
	c.knockback_scale = float(v["knockback_scale"])
	c.mass = float(v["mass"])
	c.loadout_id = StringName(str(v["loadout"]))
	c.char_id = StringName(str(v["char"]))
	c.animation_set = StringName(str(v["anims"]))
	c.voice_set = StringName(str(v["voice"]))
	for a: Variant in v["abilities"]:
		c.abilities.append(StringName(str(a)))
	for t: Variant in v["teams"]:
		c.teams.append(StringName(str(t)))
	c.limit_per_team = int(v["limit"])
	c.requires_entitlement = StringName(str(v["entitlement"]))
	c.selectable = bool(v["selectable"])
	c.attributes = profile.extra.duplicate(true)
	return c


## Loads one class; the value of the result is a validated [DotPlayerClassDef].
static func load_def(profiles: DotProfileSet, id: String) -> DotResult:
	var res := profiles.load_profile(id)
	if not res.ok:
		return res
	var def := def_from_profile(res.value)
	var checked := def.validate()
	if not checked.ok:
		return checked
	return DotResult.success(def)


## Every loadable class as a catalogue; failures are appended to [param errors].
static func to_catalogue(profiles: DotProfileSet, errors: PackedStringArray = PackedStringArray()) -> DotPlayerClassCatalogue:
	var cat := DotPlayerClassCatalogue.new()
	for id in profiles.list_ids():
		var res := load_def(profiles, id)
		if res.ok:
			cat.classes.append(res.value)
		else:
			errors.append("%s: %s" % [id, res.error.message])
	var _built := cat.build() if not cat.classes.is_empty() else null
	return cat
