@tool
class_name DotPlayerClassCatalogue
extends Resource

## Every class a session has, and the presets that cover the usual shapes.

const CHANNEL := "player.class"

@export var id: StringName = &""

@export var classes: Array[DotPlayerClassDef] = []

## The class somebody gets if they never pick one. Empty means the first selectable.
@export var default_class: StringName = &""

var _by_id: Dictionary = {}
var _built: bool = false


func build() -> DotResult:
	_by_id.clear()

	if classes.is_empty():
		return DotResult.fail(DotError.CODE_INVALID, "A catalogue with no classes.")

	for c in classes:
		if c == null:
			return DotResult.fail(DotError.CODE_INVALID, "A null class in the catalogue.")

		var valid := c.validate()

		if not valid.ok:
			return valid.wrap("This catalogue was not built")

		if _by_id.has(c.id):
			return DotResult.fail(
				DotError.CODE_INVALID,
				"Two classes are called '%s'." % String(c.id),
				"Every lookup would answer about the second one, silently."
			)

		_by_id[c.id] = c

	if default_class != &"" and not _by_id.has(default_class):
		return DotResult.fail(
			DotError.CODE_INVALID,
			"The default class '%s' is not in the catalogue." % String(default_class),
			"Everybody who never picks would be assigned a class that does not exist."
		)

	_built = true
	return DotResult.success(null)


func _ensure_built() -> void:
	if not _built or _by_id.size() != classes.size():
		var res := build()
		if not res.ok:
			DotLog.error(CHANNEL, "catalogue unusable", {"why": res.error.message})


func has_class(class_id: StringName) -> bool:
	_ensure_built()
	return _by_id.has(class_id)


func get_class_def(class_id: StringName) -> DotPlayerClassDef:
	_ensure_built()
	return _by_id.get(class_id, null)


func ids() -> Array[StringName]:
	_ensure_built()
	var out: Array[StringName] = []

	for c in classes:
		if c != null:
			out.append(c.id)

	return out


## The ids a given side may take.
func ids_for_team(team: StringName) -> Array[StringName]:
	_ensure_built()
	var out: Array[StringName] = []

	for c in classes:
		if c != null and c.allows_team(team):
			out.append(c.id)

	return out


## What somebody gets when they never choose.
##
## Never null for a built catalogue: the declared default, or the first selectable
## class, or — if a mode has disabled every one of them — the first class at all.
## Returning null would push the problem into a spawn path that has nothing to do with
## class selection, which is where it would be debugged.
func fallback_for(team: StringName = &"") -> DotPlayerClassDef:
	_ensure_built()

	if default_class != &"" and _by_id.has(default_class):
		var declared: DotPlayerClassDef = _by_id[default_class]
		if declared.allows_team(team):
			return declared

	for c in classes:
		if c != null and c.allows_team(team):
			return c

	for c in classes:
		if c != null:
			return c

	return null


func describe_lines() -> PackedStringArray:
	_ensure_built()
	var out := PackedStringArray()
	out.append("classes (%s): %d" % [String(id), classes.size()])

	for c in classes:
		if c != null:
			out.append("  " + c.describe())

	return out


func describe() -> String:
	return "DotPlayerClassCatalogue(%s, %d)" % [String(id), classes.size()]


func _to_string() -> String:
	return describe()


# --- Presets ----------------------------------------------------------------

## One class, no choices. A deathmatch, a timer server, a sandbox.
##
## [b]Worth having even though it sounds pointless.[/b] A game with no classes that
## models itself as having no catalogue makes every consumer branch on whether classes
## exist; one class makes the health, the speed and the loadout id come from the same
## place they do in every other mode.
static func single(p_health: float = 100.0) -> DotPlayerClassCatalogue:
	var cat := DotPlayerClassCatalogue.new()
	cat.id = &"single"

	var only := DotPlayerClassDef.make(&"default", p_health, 1.0)
	only.display_name = "Player"
	only.description = "The only class."

	cat.classes = [only]
	cat.default_class = &"default"
	var _res := cat.build()
	return cat


## The six-way shape a team shooter converges on, as numbers rather than as content.
##
## The point is the [i]relations[/i] — the heavy has twice the health and two-thirds the
## speed, the scout is the reverse — because those are what a game tunes and what a
## project writing this from scratch has to discover. Every content id is empty: the
## catalogue names what a class is like, and a game names what it looks like.
static func team_shooter() -> DotPlayerClassCatalogue:
	var cat := DotPlayerClassCatalogue.new()
	cat.id = &"team_shooter"

	var assault := DotPlayerClassDef.make(&"assault", 125.0, 1.0)
	assault.description = "The baseline. Everything else is described relative to it."
	assault.max_armour = 50.0

	var scout := DotPlayerClassDef.make(&"scout", 85.0, 1.35)
	scout.description = "Fast and fragile. Takes ground; cannot hold it."
	scout.jump_scale = 1.2
	scout.knockback_scale = 1.4
	scout.mass = 60.0

	var heavy := DotPlayerClassDef.make(&"heavy", 250.0, 0.7)
	heavy.description = "Slow and hard to move. Holds ground; cannot take it."
	heavy.max_armour = 100.0
	heavy.knockback_scale = 0.5
	heavy.mass = 130.0
	heavy.limit_per_team = 2

	var medic := DotPlayerClassDef.make(&"medic", 110.0, 1.15)
	medic.description = "Keeps other people alive, and regenerates alone."
	medic.regen_per_second = 4.0
	medic.regen_delay_sec = 3.0
	medic.abilities = [&"heal_beam"]

	var engineer := DotPlayerClassDef.make(&"engineer", 110.0, 0.95)
	engineer.description = "Builds. Everything it builds is somebody else's problem."
	engineer.abilities = [&"build", &"repair"]
	engineer.limit_per_team = 2

	var sniper := DotPlayerClassDef.make(&"sniper", 90.0, 0.9)
	sniper.description = "Range. A team of nine of these is why limits exist."
	sniper.abilities = [&"scope"]
	sniper.limit_per_team = 2

	cat.classes = [assault, scout, heavy, medic, engineer, sniper]
	cat.default_class = &"assault"
	var _res := cat.build()
	return cat


## Two sides with different rosters, for an asymmetric mode.
static func asymmetric(
	attackers: StringName = &"attackers",
	defenders: StringName = &"defenders"
) -> DotPlayerClassCatalogue:
	var cat := DotPlayerClassCatalogue.new()
	cat.id = &"asymmetric"

	var raider := DotPlayerClassDef.make(&"raider", 120.0, 1.1)
	raider.teams = [attackers]
	raider.description = "Attacks. Faster, and there are more of them."

	var breacher := DotPlayerClassDef.make(&"breacher", 160.0, 0.9)
	breacher.teams = [attackers]
	breacher.limit_per_team = 1
	breacher.abilities = [&"breach"]

	var guard := DotPlayerClassDef.make(&"guard", 150.0, 0.95)
	guard.teams = [defenders]
	guard.description = "Defends. Tougher, and outnumbered."
	guard.max_armour = 75.0

	var watcher := DotPlayerClassDef.make(&"watcher", 100.0, 1.0)
	watcher.teams = [defenders]
	watcher.abilities = [&"cameras"]
	watcher.limit_per_team = 1

	cat.classes = [raider, breacher, guard, watcher]
	cat.default_class = &"raider"
	var _res := cat.build()
	return cat


static func presets() -> Dictionary:
	return {
		&"single": Callable(DotPlayerClassCatalogue, "single"),
		&"team_shooter": Callable(DotPlayerClassCatalogue, "team_shooter"),
		&"asymmetric": Callable(DotPlayerClassCatalogue, "asymmetric"),
	}


static func preset(p_id: StringName) -> DotPlayerClassCatalogue:
	var table := presets()

	if not table.has(p_id):
		return null

	var fn: Callable = table[p_id]
	return fn.call() as DotPlayerClassCatalogue
