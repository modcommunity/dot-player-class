extends Node

## Exercises dot-player-class with no content, no spawns and no match.
##
## Which is the point: the promise this addon makes is that a dedicated server can
## decide whether somebody may be a class without loading a mesh, an animation set or a
## weapon, and a suite that loads nothing is the check on that promise.
##
## [codeblock]
## godot --headless --path . res://examples/class_selftest.tscn
## [/codeblock]

const SECTIONS := 7
const CHECKS := 120

var _passed := 0
var _failed := 0
var _section_count := 0

var _teams: Dictionary = {}
var _alive: Dictionary = {}
var _owned: Dictionary = {}
var _live := false


func _ready() -> void:
	DotLog.set_level(DotLog.Level.ERROR)
	_run()


func _run() -> void:
	_line("dot-player-class self-test")
	_line("")

	_test_defs()
	_test_catalogue()
	_test_rules()
	_test_assignment()
	_test_pending()
	_test_limits_and_entitlements()
	_test_teams_and_mirror()

	_line("")
	_line("%d sections, %d passed, %d failed" % [_section_count, _passed, _failed])

	if _section_count != SECTIONS:
		_line("ERROR: %d of %d sections ran." % [_section_count, SECTIONS])
		get_tree().quit(1)
		return

	if _passed + _failed != CHECKS:
		_line(
			"ERROR: %d checks ran, %d expected. A section aborted part-way."
			% [_passed + _failed, CHECKS]
		)
		get_tree().quit(1)
		return

	get_tree().quit(1 if _failed > 0 else 0)


func _manager(
	cat: DotPlayerClassCatalogue = null,
	rules: DotPlayerClassRules = null
) -> DotPlayerClassManager:
	var m := DotPlayerClassManager.new()
	m.catalogue = cat if cat != null else DotPlayerClassCatalogue.team_shooter()
	m.rules = rules if rules != null else DotPlayerClassRules.new()
	m.register_service = false
	m.team_fn = func(key: String) -> StringName: return StringName(str(_teams.get(key, "")))
	m.alive_fn = func(key: String) -> bool: return bool(_alive.get(key, false))
	m.live_fn = func() -> bool: return _live
	m.entitled_fn = func(key: String, ent: StringName) -> bool:
		return bool(_owned.get("%s/%s" % [key, String(ent)], false))
	add_child(m)
	var _res := m.setup()
	return m


# --- Definitions ------------------------------------------------------------

func _test_defs() -> void:
	_section("a class definition")

	var c := DotPlayerClassDef.make(&"medic", 110.0, 1.15)
	_check(c.validate().ok, "validates")
	_check(c.display_name == "Medic", "with a name derived from the id")
	_check(c.allows_team(&"blue"), "and is open to every side by default")

	c.teams = [&"blue"]
	_check(c.allows_team(&"blue"), "a restricted class admits its own side")
	_check(not c.allows_team(&"red"), "and refuses the other")
	_check(
		c.allows_team(&""),
		"and a game with no sides at all is admitted, rather than locked out of every "
		+ "class it restricted"
	)

	c.selectable = false
	_check(not c.allows_team(&"blue"), "an unselectable class admits nobody")
	c.selectable = true

	var dead := DotPlayerClassDef.make(&"ghost", 0.0)
	_check(
		not dead.validate().ok,
		"a class with no health is refused: it is dead the moment it spawns"
	)
	_check(not DotPlayerClassDef.new().validate().ok, "and so is one with no id")

	c.abilities = [&"heal_beam"]
	_check(c.has_ability(&"heal_beam"), "abilities are ids")
	_check(not c.has_ability(&"fly"), "and an unknown one is not one")

	c.attributes = {"announcer": "medic_down"}
	_check(str(c.attribute("announcer", "")) == "medic_down", "attributes read back")
	_check(str(c.attribute("nope", "x")) == "x", "with a default for an unknown one")

	# Armour arithmetic, which lives here so the class screen and the damage model
	# cannot disagree about what 150 armour means.
	var armoured := DotPlayerClassDef.make(&"heavy", 250.0)
	armoured.max_armour = 100.0
	armoured.armour_absorption = 0.5

	var hit := armoured.absorb(50.0, 100.0)
	_check(is_equal_approx(float(hit["health_damage"]), 25.0), "armour halves a hit")
	_check(is_equal_approx(float(hit["armour_left"]), 75.0), "and is spent doing it")

	var bare := armoured.absorb(50.0, 0.0)
	_check(
		is_equal_approx(float(bare["health_damage"]), 50.0),
		"and with no armour left the whole hit lands"
	)

	var big := armoured.absorb(500.0, 10.0)
	_check(
		is_equal_approx(float(big["armour_left"]), 0.0),
		"a hit bigger than the armour strips it"
	)
	_check(
		is_equal_approx(float(big["health_damage"]), 490.0),
		"and the rest gets through — armour cannot absorb more than it has"
	)

	var wire := DotPlayerClassDef.from_dict(c.to_dict())
	_check(wire.id == &"medic", "a definition survives a round trip")
	_check(wire.teams == c.teams, "with its team list")
	_check(wire.abilities == c.abilities, "and its abilities")
	_check(c.describe().contains("medic"), "and it describes itself")


func _test_catalogue() -> void:
	_section("a catalogue")

	var single := DotPlayerClassCatalogue.single(150.0)
	_check(single.build().ok, "the single-class catalogue builds")
	_check(single.ids().size() == 1, "with one class")
	_check(
		is_equal_approx(single.get_class_def(&"default").max_health, 150.0),
		"carrying the health it was given"
	)
	_check(
		single.fallback_for(&"") != null,
		"and a game with no classes still has one, so nothing downstream branches on "
		+ "whether classes exist"
	)

	var shooter := DotPlayerClassCatalogue.team_shooter()
	_check(shooter.build().ok, "the team-shooter catalogue builds")
	_check(shooter.ids().size() == 6, "with six classes")
	_check(
		shooter.get_class_def(&"heavy").max_health
		> shooter.get_class_def(&"scout").max_health * 2.0,
		"and the relations are the point: the heavy has more than twice the scout's "
		+ "health"
	)
	_check(
		shooter.get_class_def(&"heavy").move_speed_scale
		< shooter.get_class_def(&"scout").move_speed_scale,
		"and less than its speed"
	)
	_check(shooter.get_class_def(&"sniper").limit_per_team == 2, "the sniper is limited")
	_check(shooter.fallback_for(&"").id == &"assault", "and the default is the baseline")

	var asym := DotPlayerClassCatalogue.asymmetric()
	_check(asym.build().ok, "the asymmetric catalogue builds")
	_check(asym.ids_for_team(&"attackers").size() == 2, "attackers have two classes")
	_check(asym.ids_for_team(&"defenders").size() == 2, "and defenders two others")
	_check(
		asym.fallback_for(&"defenders").teams.has(&"defenders"),
		"and a side's fallback is one that side can actually be"
	)

	var dup := DotPlayerClassCatalogue.new()
	dup.classes = [DotPlayerClassDef.make(&"a"), DotPlayerClassDef.make(&"a")]
	_check(not dup.build().ok, "two classes with one name are refused")

	var bad_default := DotPlayerClassCatalogue.new()
	bad_default.classes = [DotPlayerClassDef.make(&"a")]
	bad_default.default_class = &"missing"
	_check(
		not bad_default.build().ok,
		"a default that is not in the catalogue is refused: everybody who never picks "
		+ "would be assigned a class that does not exist"
	)

	var broken := DotPlayerClassCatalogue.new()
	broken.classes = [DotPlayerClassDef.make(&"a", 0.0)]
	_check(not broken.build().ok, "and so is a catalogue holding an invalid class")
	_check(not DotPlayerClassCatalogue.new().build().ok, "or no classes at all")

	_check(DotPlayerClassCatalogue.presets().size() == 3, "three presets")
	_check(DotPlayerClassCatalogue.preset(&"single") != null, "resolving by name")
	_check(DotPlayerClassCatalogue.preset(&"nope") == null, "and nothing otherwise")
	_check(shooter.describe_lines().size() == 7, "a catalogue describes itself")


func _test_rules() -> void:
	_section("rules")

	var r := DotPlayerClassRules.new()
	_check(r.validate().ok, "the defaults validate")
	_check(
		r.apply_on_respawn,
		"and defer a change to the next spawn — changing class mid-fight changes your "
		+ "health, your speed and your weapons while somebody is shooting at you"
	)
	_check(
		r.apply_immediately_when_dead,
		"unless you are already dead, where there is nothing to exploit"
	)

	_check(DotPlayerClassRules.instant().apply_on_respawn == false, "a sandbox is instant")
	_check(
		not DotPlayerClassRules.competitive().allow_midround_change,
		"a competitive mode locks mid-round"
	)
	_check(not DotPlayerClassRules.fixed().allow_choice, "and a fixed one lets nobody pick")
	_check(DotPlayerClassRules.presets().size() == 4, "four presets")
	_check(DotPlayerClassRules.preset(&"instant") != null, "resolving by name")
	_check(r.env_prefix() == "DOT_PLAYER_CLASS_", "with the family's config layering")


# --- Assignment -------------------------------------------------------------

func _test_assignment() -> void:
	_section("assignment")

	_teams.clear()
	_alive.clear()
	var m := _manager()

	var changes: Array = []
	m.class_changed.connect(func(key: String, from: StringName, to: StringName) -> void:
		changes.append([key, String(from), String(to)])
	)

	_check(m.add("ada").ok, "somebody is added")
	_check(m.class_of("ada") == &"assault", "onto the catalogue's default")
	_check(changes.size() == 1, "with a signal")
	_check(m.add("ada").ok, "adding them again is not an error")
	_check(changes.size() == 1, "and changes nothing")

	_check(m.def_of("ada").id == &"assault", "their definition reads back")
	_check(m.keys() == PackedStringArray(["ada"]), "and the roster lists them")

	_check(m.force("ada", &"medic").ok, "a class can be forced")
	_check(m.class_of("ada") == &"medic", "and lands immediately")
	_check(not m.force("ada", &"nonexistent").ok, "an unknown class is refused")
	_check(m.force("ada", &"medic").ok, "forcing the same class again is a no-op")

	m.remove("ada")
	_check(m.class_of("ada") == &"", "somebody can be removed")
	_check(m.keys().is_empty(), "leaving nobody")

	m.queue_free()


func _test_pending() -> void:
	_section("a change that waits")

	_teams.clear()
	_alive.clear()
	var m := _manager()

	var pendings: Array = []
	m.class_pending.connect(func(key: String, to: StringName, _now: StringName) -> void:
		pendings.append([key, String(to)])
	)

	var _a := m.add("ada")
	_alive["ada"] = true

	var res := m.request("ada", &"medic")
	_check(res.ok, "a live player's request succeeds")
	_check(
		m.class_of("ada") == &"assault",
		"and does not land yet, because they are in a fight"
	)
	_check(m.pending_of("ada") == &"medic", "it is pending")
	_check(m.has_pending("ada"), "which the manager says")
	_check(pendings.size() == 1, "with a signal a class screen can render")

	_check(
		m.apply_pending("ada") == &"medic",
		"and the next spawn honours it, returning what they spawn as so the spawn path "
		+ "does not have to ask twice"
	)
	_check(m.class_of("ada") == &"medic", "which lands")
	_check(not m.has_pending("ada"), "and clears the pending choice")
	_check(m.apply_pending("ada") == &"medic", "applying nothing is harmless")

	_alive["ada"] = false
	var dead := m.request("ada", &"scout")
	_check(dead.ok, "a dead player's request succeeds")
	_check(
		m.class_of("ada") == &"scout",
		"and lands immediately — a dead player has nothing to exploit and making them "
		+ "wait for a second death is confusing"
	)

	_alive["ada"] = true
	var _p := m.request("ada", &"heavy")
	m.cancel_pending("ada")
	_check(not m.has_pending("ada"), "a pending choice can be cancelled")
	_check(m.class_of("ada") == &"scout", "leaving the current class alone")

	var _same := m.request("ada", &"scout")
	_check(
		not m.has_pending("ada"),
		"requesting the class you already are clears any pending choice rather than "
		+ "queuing a change to yourself"
	)

	# The instant rules.
	var instant := _manager(null, DotPlayerClassRules.instant())
	var _ia := instant.add("bob")
	_alive["bob"] = true
	var _ir := instant.request("bob", &"heavy")
	_check(instant.class_of("bob") == &"heavy", "a sandbox applies immediately")

	# Mid-round locking.
	var comp := _manager(null, DotPlayerClassRules.competitive())
	var _ca := comp.add("mel")
	_live = true
	var locked := comp.request("mel", &"medic")
	_check(not locked.ok, "a competitive mode refuses a mid-round change")
	_check(locked.error.message.contains("round"), "and says why")
	_live = false
	_check(comp.request("mel", &"medic").ok, "and allows it between rounds")

	m.queue_free()
	instant.queue_free()
	comp.queue_free()


func _test_limits_and_entitlements() -> void:
	_section("limits and entitlements")

	_teams.clear()
	_alive.clear()
	_owned.clear()

	var m := _manager()
	var refusals: Array = []
	m.class_refused.connect(func(key: String, to: StringName, why: String) -> void:
		refusals.append([key, String(to), why]))

	for key in ["a", "b", "c"]:
		_teams[key] = "blue"
		var _r := m.add(key)

	_check(m.request("a", &"sniper").ok, "the first sniper is allowed")
	_check(m.request("b", &"sniper").ok, "the second is too")
	_check(m.count_on_team(&"blue", &"sniper") == 2, "two of them now")

	var third := m.request("c", &"sniper")
	_check(
		not third.ok,
		"and the third is refused, which is the answer to a team of nine snipers"
	)
	_check(third.error.message.contains("2"), "naming the limit")
	_check(refusals.size() == 1, "with a signal a client can show")

	_check(
		m.request("a", &"sniper").ok,
		"re-requesting the class you already are is not refused for occupying its own "
		+ "slot"
	)

	_teams["c"] = "red"
	_check(m.request("c", &"sniper").ok, "and the other side has its own two slots")

	var no_limits := _manager(null, DotPlayerClassRules.instant())
	for key in ["p", "q", "r"]:
		_teams[key] = "blue"
		var _r2 := no_limits.add(key)
		var _s := no_limits.request(key, &"sniper")
	_check(
		no_limits.count_on_team(&"blue", &"sniper") == 3,
		"a server that does not enforce limits does not"
	)

	# Entitlements.
	var paid := DotPlayerClassCatalogue.team_shooter()
	paid.get_class_def(&"heavy").requires_entitlement = &"heavy_unlock"
	var e := _manager(paid)
	_teams["zoe"] = "blue"
	var _ez := e.add("zoe")

	var unowned := e.request("zoe", &"heavy")
	_check(not unowned.ok, "a class you do not own is refused")
	_owned["zoe/heavy_unlock"] = true
	_check(
		e.request("zoe", &"heavy").ok,
		"and allowed once you do — with the check itself the game's, because an addon "
		+ "that decided entitlement would be one a client could patch"
	)

	e.rules.enforce_entitlements = false
	_owned.clear()
	_check(e.request("zoe", &"heavy").ok, "a server can stop consulting them entirely")

	# What a class screen draws.
	# `c` is on red and already a sniper there, so every class is open to them. `b` is
	# on blue and is one of blue's two snipers, so blue's sniper slot is full for
	# anybody else. Two fixed players rather than a loop with a break: a check whose
	# number of assertions depends on the data is a check that can quietly not run.
	_teams["d"] = "blue"
	var _d := m.add("d")
	var options := m.options_for("d")
	_check(options.size() == 6, "the option list covers every class")

	var sniper_row: Dictionary = {}
	for o in options:
		if StringName(str(o["id"])) == &"sniper":
			sniper_row = o

	_check(not sniper_row.is_empty(), "including the one that is full")
	_check(not bool(sniper_row["available"]), "which is marked unavailable")
	_check(
		str(sniper_row["why"]) != "",
		"with a reason attached, which is the difference between a greyed-out button "
		+ "and a greyed-out button with a tooltip"
	)
	_check(int(sniper_row["taken"]) == 2, "and the count a screen needs to draw '2 / 2'")
	_check(int(sniper_row["limit"]) == 2, "with the limit beside it")

	var assault_row: Dictionary = {}
	for o in options:
		if StringName(str(o["id"])) == &"assault":
			assault_row = o

	_check(bool(assault_row["available"]), "an open class is marked available")
	_check(bool(assault_row["current"]), "and the one they are on says so")

	m.queue_free()
	no_limits.queue_free()
	e.queue_free()


func _test_teams_and_mirror() -> void:
	_section("teams, matches and mirrors")

	_teams.clear()
	_alive.clear()

	var asym := DotPlayerClassCatalogue.asymmetric()
	var m := _manager(asym)

	_teams["ada"] = "attackers"
	var _a := m.add("ada")
	_check(m.class_of("ada") == &"raider", "a player gets a class their side can field")

	_teams["ada"] = "defenders"
	m.note_team_changed("ada")
	_check(
		m.class_of("ada") == &"guard",
		"and changing side moves them off a class the new side cannot be — a class you "
		+ "are silently not allowed to be is worse than an honest reassignment"
	)

	var keep := _manager(asym)
	keep.rules.clear_on_team_change = false
	_teams["bob"] = "attackers"
	var _b := keep.add("bob")
	_teams["bob"] = "defenders"
	keep.note_team_changed("bob")
	_check(
		keep.class_of("bob") == &"raider",
		"unless the game would rather leave it alone"
	)

	# Match end.
	var reset := _manager(null, DotPlayerClassRules.competitive())
	var _r := reset.add("mel")
	var _f := reset.force("mel", &"heavy")
	reset.note_match_end()
	_check(
		reset.class_of("mel") == &"assault",
		"a competitive match puts everybody back on the default when it ends"
	)

	var keeps := _manager()
	var _k := keeps.add("kit")
	var _kf := keeps.force("kit", &"heavy")
	keeps.note_match_end()
	_check(keeps.class_of("kit") == &"heavy", "and a casual one does not")

	# A pending choice that stops being legal before it lands.
	var limited := _manager()
	for key in ["s1", "s2", "s3"]:
		_teams[key] = "blue"
		var _l := limited.add(key)
		_alive[key] = true

	var _q := limited.request("s1", &"sniper")
	var _q2 := limited.request("s2", &"sniper")
	var _q3 := limited.request("s3", &"sniper")
	_check(limited.has_pending("s3"), "three players queue for two sniper slots")

	_check(limited.apply_pending("s1") == &"sniper", "the first gets one")
	_check(limited.apply_pending("s2") == &"sniper", "the second gets the other")
	_check(
		limited.apply_pending("s3") != &"sniper",
		"and the third does not — the slot filled between the request and the spawn"
	)
	_check(
		not limited.has_pending("s3"),
		"with the dead choice dropped, because a class screen claiming a change that "
		+ "will never happen is worse than being told no"
	)

	# Mirroring.
	var client := DotPlayerClassManager.new()
	client.authoritative = false
	client.register_service = false
	client.catalogue = DotPlayerClassCatalogue.team_shooter()
	client.rules = DotPlayerClassRules.new()
	add_child(client)

	_check(client.apply_wire(limited.to_wire()).ok, "classes travel to a client")
	_check(client.class_of("s1") == &"sniper", "and land")
	_check(not client.request("s1", &"medic").ok, "a mirror grants nothing")
	_check(not client.force("s1", &"medic").ok, "and forces nothing")
	_check(not client.add("new").ok, "and adds nobody")
	_check(
		not limited.apply_wire({}).ok,
		"and the authoritative one is not told what it decided"
	)

	m.queue_free()
	keep.queue_free()
	reset.queue_free()
	keeps.queue_free()
	limited.queue_free()
	client.queue_free()


# --- Harness ---------------------------------------------------------------

func _section(title: String) -> void:
	_section_count += 1
	_line("")
	_line("-- %s" % title)


func _check(condition: bool, what: String) -> void:
	if condition:
		_passed += 1
		_line("   ok   %s" % what)
	else:
		_failed += 1
		_line("  FAIL  %s" % what)


func _line(text: String) -> void:
	print(text)
