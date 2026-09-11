class_name DotPlayerClassManager
extends Node

## Who is what class, who has asked to become something else, and when that lands.
##
## [b]The pending change is the whole addon.[/b] Changing class mid-fight changes your
## health, your speed and your weapons while somebody is shooting at you, which is
## either an exploit or a bug report depending on who wins the fight. So a request is
## [i]recorded[/i] and the next spawn honours it, and the class-select screen saying
## "you will respawn as a medic" is the feature rather than a limitation.
##
## Everything is a [DotResult], because every refusal here has a sentence attached that
## a player needs to read: the side is full of snipers, you do not own that one, the
## round has started.

const CHANNEL := "player.class"

const SERVICE := &"dot_player_class_manager"

## Somebody's class actually changed.
signal class_changed(key: String, from: StringName, to: StringName)

## Somebody's choice was recorded and will land on their next spawn.
signal class_pending(key: String, to: StringName, current: StringName)

## A request was refused, with a sentence. See the note on refusals in the README.
signal class_refused(key: String, to: StringName, why: String)

@export var authoritative: bool = true

@export var catalogue: DotPlayerClassCatalogue = null

@export var rules: DotPlayerClassRules = null

@export var register_service: bool = true

## `func(key: String) -> StringName`. Which side somebody is on.
##
## Left unset, everybody is on no side, which makes every class available and every
## limit global. Correct for a game with no teams; a game with teams should supply it.
var team_fn: Callable = Callable()

## `func(key: String) -> bool`. Whether somebody is in the world.
var alive_fn: Callable = Callable()

## `func(key: String, entitlement: StringName) -> bool`. Whether they may have it.
##
## The check is the game's on purpose. An addon that decided entitlement would be an
## addon a client could patch; the authority is dot-auth, or a backbone, or a shop.
var entitled_fn: Callable = Callable()

## `func() -> bool`. Whether a round is under way, for the mid-round rule.
var live_fn: Callable = Callable()

var _current: Dictionary = {}
var _pending: Dictionary = {}


func _ready() -> void:
	if catalogue == null:
		catalogue = DotPlayerClassCatalogue.single()

	if rules == null:
		rules = DotPlayerClassRules.new()

	if register_service and authoritative:
		DotRegistry.register(SERVICE, self)


func setup() -> DotResult:
	if catalogue == null:
		catalogue = DotPlayerClassCatalogue.single()

	if rules == null:
		rules = DotPlayerClassRules.new()

	var built := catalogue.build()

	if not built.ok:
		return built.wrap("This class catalogue was not installed")

	return rules.validate()


# --- Membership -------------------------------------------------------------

## Puts somebody on the fallback class. Idempotent.
func add(key: String) -> DotResult:
	if not authoritative:
		return _refuse_mirror("add")

	if _current.has(key):
		return DotResult.success(_current[key])

	var fallback := catalogue.fallback_for(_team(key))

	if fallback == null:
		return DotResult.fail(
			DotError.CODE_STATE, "The catalogue has no class anybody can be."
		)

	_current[key] = fallback.id
	class_changed.emit(key, &"", fallback.id)
	return DotResult.success(fallback.id)


func remove(key: String) -> void:
	_current.erase(key)
	_pending.erase(key)


## What somebody is right now.
func class_of(key: String) -> StringName:
	return _current.get(key, &"")


## What they will be next time they spawn, or [code]&""[/code].
func pending_of(key: String) -> StringName:
	return _pending.get(key, &"")


func has_pending(key: String) -> bool:
	return _pending.has(key)


## The definition somebody is currently playing, or null.
func def_of(key: String) -> DotPlayerClassDef:
	return catalogue.get_class_def(class_of(key))


func keys() -> PackedStringArray:
	var out := PackedStringArray()

	for key: Variant in _current.keys():
		out.append(String(key))

	out.sort()
	return out


## How many of a class are on a side right now.
##
## Counts what people [i]are[/i], not what they have asked to be. Counting pending
## choices would let two players both be refused the last sniper slot because each was
## counted against the other, and neither is a sniper yet.
func count_on_team(team: StringName, class_id: StringName) -> int:
	var n := 0

	for key in keys():
		if _current.get(key, &"") == class_id and _team(key) == team:
			n += 1

	return n


# --- Choosing ---------------------------------------------------------------

## A player asking to be something. The only door in.
##
## Returns success with the class that is now [i]pending[/i] when the change is
## deferred, and success with the class that is now current when it is immediate. The
## caller can tell the two apart with [method has_pending], and both are successes
## because both mean "yes" from the player's point of view.
func request(key: String, class_id: StringName, tick: int = 0) -> DotResult:
	if not authoritative:
		return _refuse_mirror("request")

	if not _current.has(key):
		var added := add(key)
		if not added.ok:
			return added

	var why := _refusal(key, class_id)

	if why != "":
		class_refused.emit(key, class_id, why)
		return DotResult.fail(DotError.CODE_FORBIDDEN, why)

	var current: StringName = _current[key]

	if current == class_id:
		_pending.erase(key)
		return DotResult.success(class_id)

	var immediate := not rules.apply_on_respawn

	if not immediate and rules.apply_immediately_when_dead and not _alive(key):
		# A dead player has nothing to exploit, and making them wait for a second death
		# is confusing rather than fair.
		immediate = true

	if immediate:
		return force(key, class_id)

	_pending[key] = class_id
	DotLog.debug(CHANNEL, "class pending", {
		"key": key, "to": String(class_id), "tick": tick
	})
	class_pending.emit(key, class_id, current)
	return DotResult.success(class_id)


## Sets a class regardless of the rules. For a console command or a game mode.
func force(key: String, class_id: StringName) -> DotResult:
	if not authoritative:
		return _refuse_mirror("force")

	if not catalogue.has_class(class_id):
		return DotResult.fail(
			DotError.CODE_INVALID, "No such class: '%s'." % String(class_id)
		)

	var from: StringName = _current.get(key, &"")

	if from == class_id:
		_pending.erase(key)
		return DotResult.success(class_id)

	_current[key] = class_id
	_pending.erase(key)

	DotLog.info(CHANNEL, "class changed", {
		"key": key, "from": String(from), "to": String(class_id)
	})
	class_changed.emit(key, from, class_id)
	return DotResult.success(class_id)


## Applies a pending choice. Call on every spawn, before the class is read.
##
## Returns the class the player is spawning as, pending or not, so a spawn path can use
## the return value rather than calling this and then asking again.
func apply_pending(key: String) -> StringName:
	if not _pending.has(key):
		return class_of(key)

	var wanted: StringName = _pending[key]
	var why := _refusal(key, wanted)

	if why != "":
		# The slot filled up between the request and the spawn, or the player changed
		# side. Dropping it silently would leave a class-select screen claiming a
		# change that is never going to happen.
		_pending.erase(key)
		class_refused.emit(key, wanted, why)
		DotLog.debug(CHANNEL, "pending class no longer allowed", {"key": key, "why": why})
		return class_of(key)

	var _res := force(key, wanted)
	return class_of(key)


## Clears a pending choice without applying it.
func cancel_pending(key: String) -> void:
	_pending.erase(key)


## Called when somebody changes side.
func note_team_changed(key: String) -> void:
	if not authoritative or not _current.has(key):
		return

	_pending.erase(key)

	if not rules.clear_on_team_change:
		return

	var def := def_of(key)
	var team := _team(key)

	if def != null and def.allows_team(team):
		return

	var fallback := catalogue.fallback_for(team)

	if fallback != null:
		var _res := force(key, fallback.id)


## Called when a match ends.
func note_match_end() -> void:
	if not authoritative:
		return

	if not rules.pending_survives_round:
		_pending.clear()

	if not rules.reset_on_match_end:
		return

	for key in keys():
		var fallback := catalogue.fallback_for(_team(key))
		if fallback != null:
			var _res := force(key, fallback.id)


# --- Reading ----------------------------------------------------------------

## The classes somebody could actually pick right now, with the reason for each no.
##
## What a class-select screen draws. Returning the refusals as well as the ids is the
## difference between a greyed-out button and a greyed-out button with a tooltip.
func options_for(key: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var team := _team(key)

	for class_id in catalogue.ids():
		var def := catalogue.get_class_def(class_id)
		var why := _refusal(key, class_id)

		out.append({
			"id": class_id,
			"name": def.display_name,
			"description": def.description,
			"available": why == "",
			"why": why,
			"current": class_of(key) == class_id,
			"pending": pending_of(key) == class_id,
			"taken": count_on_team(team, class_id),
			"limit": def.limit_per_team,
		})

	return out


func describe_lines() -> PackedStringArray:
	var out := PackedStringArray()
	out.append("classes: %d players, %d pending%s" % [
		_current.size(), _pending.size(), "" if authoritative else " [mirror]"
	])

	for key in keys():
		out.append("  %-16s %s%s" % [
			key,
			String(class_of(key)),
			"" if not has_pending(key) else " -> %s" % String(pending_of(key)),
		])

	return out


func describe() -> String:
	return "DotPlayerClassManager(%d players, %d pending)" % [_current.size(), _pending.size()]


# --- Mirroring --------------------------------------------------------------

func to_wire() -> Dictionary:
	var rows: Dictionary = {}

	for key in keys():
		rows[key] = String(_current[key])

	return {"classes": rows}


func apply_wire(payload: Dictionary) -> DotResult:
	if authoritative:
		return DotResult.fail(
			DotError.CODE_FORBIDDEN, "An authoritative class manager is not told."
		)

	var rows: Variant = payload.get("classes", {})

	if not (rows is Dictionary):
		return DotResult.fail(DotError.CODE_PARSE, "A class payload has no assignments.")

	_current.clear()

	for key: Variant in (rows as Dictionary).keys():
		_current[String(key)] = StringName(str((rows as Dictionary)[key]))

	return DotResult.success(_current.size())


# --- Internals --------------------------------------------------------------

## Why somebody may not be a class, or "" if they may.
func _refusal(key: String, class_id: StringName) -> String:
	if not catalogue.has_class(class_id):
		return "There is no class called '%s'." % String(class_id)

	var def := catalogue.get_class_def(class_id)

	if not def.selectable:
		return "%s is not available in this mode." % def.display_name

	if not rules.allow_choice:
		return "This server assigns classes; it does not let you pick one."

	var team := _team(key)

	if not def.allows_team(team):
		return "%s is not available to your side." % def.display_name

	if not rules.allow_midround_change and _is_live() and _current.has(key):
		return "Classes are locked once the round has started."

	if rules.enforce_entitlements and def.requires_entitlement != &"":
		if not entitled_fn.is_valid() or not bool(
			entitled_fn.call(key, def.requires_entitlement)
		):
			return "You do not have %s." % def.display_name

	if rules.enforce_limits and def.limit_per_team > 0:
		var taken := count_on_team(team, class_id)

		# Already being it does not count against the limit: re-requesting your own
		# class must not be refused because you are occupying the slot.
		if _current.get(key, &"") == class_id:
			taken -= 1

		if taken >= def.limit_per_team:
			return "Your side already has %d %s." % [def.limit_per_team, def.display_name]

	return ""


func _team(key: String) -> StringName:
	return StringName(str(team_fn.call(key))) if team_fn.is_valid() else &""


func _alive(key: String) -> bool:
	return bool(alive_fn.call(key)) if alive_fn.is_valid() else false


func _is_live() -> bool:
	return bool(live_fn.call()) if live_fn.is_valid() else false


func _refuse_mirror(what: String) -> DotResult:
	return DotResult.fail(
		DotError.CODE_FORBIDDEN,
		"A mirrored class manager decides nothing; it is told. ('%s')" % what
	)
