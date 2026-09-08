extends SceneTree
## Structural checks on the sim-ignored ability metadata in sim/content.gd:
## 1) every ABILITIES entry has tags from TAGS and a role from ROLES
## 2) every "+" form carries its base's tags/role
## 3) ARCHETYPES cores and package requirements reference real ids
## 4) every draftable ability is in some archetype core, or is mobility/utility
## 5) base_id() round-trips; archetypes_for(DRAFT_POOL) = the package-free set
## 5b) Block D6 evolve forks: every upgrade id is "<base>+<word>" (a forked
##    base) or "<base>+" (a package base, not forked); Content.variants_of is
##    derived from an ABILITIES scan and agrees with one done here, a base has
##    1 or 2 variants (2 for each of the fifteen forked bases, 1 for each of
##    the nine package bases), a variant carries its base's tags and role
##    exactly (cost deliberately NOT checked - a fork may keep the base cost
##    where its sibling cut it), Content.variant_for is a pure parity index
##    into variants_of, every row has an ABILITY_DESC line, and every new D6
##    key/op is declared in OP_KEYS and carried by a shipped row
## 7) SHOP_COSTS prices every shrine service (press, forge, reroll) with an
##    int >= 1, SHOP_REROLL_CAP is an int >= 1 and SHOP_REROLL_STEP an int >= 0
##    (Block D2); every base ITEMS id has a "+" form (the press can upcycle
##    anything the world hands out)
## 8) the effect grammar (docs/PROGRESSION_REVIEW.md 6.3, Block C1a): every
##    effect dict keeps to the closed op/rider vocabulary, the riders keep to
##    the closed predicate and count sets, and the data tables
##    (Content.TERRAIN / REACTIONS / STATUSES / SURGE_DEFAULT) are complete and
##    self-consistent. A self-test feeds the same lint deliberately bad rows
##    (they must be rejected) and the Block C2 rider rows from the review
##    (they must pass), so this check cannot rot into "accepts everything".
##    Block D1: an ability row's "surge" dict keeps to the closed SURGE_KEYS
##    set, every value an int, and every stat key (anything but "cost") must
##    exist on at least one effect of the row (a surge that touches nothing is
##    a data error); "surge" is a row key, never an effect key. plant_origin
##    {kind} joins the op vocabulary with kind closed to Content.TERRAIN.
## 9) grafts as data (Block C3, section D): every GRAFTS row has name, desc,
##    tags from TAGS, a "price" int >= 1 (the shrine's per-graft price, read by
##    Game.shop_cost("graft", id)) and exactly one of stat / mod / hooks; stat
##    and mod keys come from closed sets; hook rows name a HOOK_KINDS kind, carry
##    non-empty effects from the effect vocabulary plus the positional hook
##    ops, an int cap_per_turn, and never an op that grants shield or thorns
##    (the stall surface). Same self-test discipline: bad fixtures rejected,
##    the four rule grafts accepted.
## 10) mutators as data (Block C4): every MUTATORS row has a name, a desc and a
##    config dict whose keys come from Content.MUTATOR_CONFIG_KEYS (the closed
##    set Game._mut reads), typed per key: pool_ban an array of ABILITIES base
##    ids, the booleans bool, the rest int. Same self-test discipline.
## 12) Block D3 - enemies read terrain: every ENEMIES "avoid" entry is a
##     TERRAIN kind (closed), ENEMY_AVOID_COST is an int >= 1, SCREENED_INTENTS
##     is a non-empty subset of INTENT_TYPES, and TERRAIN "screens" is a
##     required bool. Same self-test discipline: one bad fixture per shape.
## 13) Block D4 - the affinity-slotted draft: DRAFT_SLOTS is a non-empty
##     Array of DRAFT_SLOT_ROLES entries (the closed role set), DRAFT_SLOT_ROLES
##     and DRAFT_SLOT_REPORTS are non-empty duplicate-free String lists, and
##     AFFINITY_IGNORED_TAGS is a duplicate-free PROPER subset of TAGS. It now
##     means "these tags do not define a build" and gates TWO slots (the
##     affinity set drops the tags, the upgrade slot drops a + form whose base
##     carries only them), so the list swallowing the whole vocabulary would
##     leave nothing defining a build and silently turn both slots into
##     lotteries - and so would a loadout kit made only of ignored-tag
##     abilities, which is checked against LOADOUTS here. Same self-test
##     discipline: one bad fixture per shape.
## Run: godot --headless --path . --script tests/test_content.gd

const Content := preload("res://sim/content.gd")

# --- effect-grammar vocabulary (section 8) ------------------------------------
## Every op Game._apply_effect implements, mapped to the keys that op reads.
## An effect dict may carry these, "op", and the rider keys below - nothing
## else, so a typo fails the lint instead of silently no-opping in play.
const OP_KEYS := {
	"lance": ["dmg", "clear_smog_bonus", "ignite", "pierce"],
	"grow_radius": ["radius"],
	"pull": ["dist", "dmg"],
	"pull_line": ["dist", "dmg"],
	"wash_push": ["push", "collision_dmg"],
	"wash_all": ["push", "collision_dmg"],
	"push_line": ["dist", "clear_smoke"],
	"push_all": ["dist"],
	"dash_dir": [],
	"create_terrain": ["kind", "ttl"],
	"clear_smoke": ["radius"],
	"teleport": [],
	"plant_origin": ["kind"],
	"grow_wall": ["ttl"],
	"shield": ["amount"],
	"thorns": ["dmg", "turns"],
	"anchor": ["turns"],
	"undim": ["amount"],
	"aoe_status": ["status", "turns", "radius", "center"],
	"aoe_damage": ["dmg", "radius", "ignite", "ignite_ttl"],
	"convert_radius": ["radius", "kind", "ttl"],
	"apply_status": ["status", "turns"],
	"damage": ["dmg"],
	"status_target": ["status", "turns", "who"],
}
## Optional keys any effect may carry. "surge" is an ability-row key only
## (Game._surges reads adef["surge"], never an effect's), so on an effect it
## fails as a stray key.
const RIDER_KEYS := ["if", "per", "bonus", "then"]
## Closed key set of an ability row's "surge" dict (Block D1): "cost" is the
## price delta Game.ability_cost applies to a cost-2+ cast on growth, the rest
## are the numeric effect keys a stat surge may add to (Game._apply_effect).
const SURGE_KEYS := ["cost", "dmg", "push", "collision_dmg", "radius", "dist", "turns", "ttl"]
## Ops whose damage runs through Game._bonus_dmg.
const BONUS_OPS := ["aoe_damage", "lance", "damage", "wash_push", "wash_all", "push_line", "push_all", "pull", "pull_line"]
## Ops that read the parent outcome and are therefore legal only inside "then".
const THEN_ONLY_OPS := ["status_target"]
const STATUS_OPS := ["aoe_status", "apply_status", "status_target"]
const WHO_VALUES := ["affected", "on_planted"]
## Closed values of the Block D6 aoe_status "center" key: the tile the radius
## is measured from ("self" = the tender, the default and the pre-D6 rule).
const CENTER_VALUES := ["self", "target"]
## Block D6 vocabulary: every new effect key, and the op that reads it. The
## budget is closed - a key here must be read by Game._apply_effect AND
## carried by at least one shipped ABILITIES row, or it is dead vocabulary
## (checked in section 14 below).
const D6_NEW_KEYS := {
	"pierce": "lance",
	"center": "aoe_status",
	"ignite_ttl": "aoe_damage",
	"kind": "convert_radius",
	"ttl": "convert_radius",
}
const D6_NEW_OPS := ["pull_line"]
## The fifteen base-pool abilities Block D6 forks into two variants each; the
## nine package abilities keep their single "+" form.
const D6_FORKED_BASES := [
	"solar_lance", "seed_bomb", "vine_whip", "water_jet", "mycelium_dash",
	"root_wall", "pollen_burst", "sun_flare", "thorn_shield", "overgrowth",
	"sap_snare", "grow_spike", "bramble_coat", "anchor_roots", "moss_filter",
]
const IF_PREDS := ["target_on", "target_adjacent", "self_on", "dim", "casts_this_turn_min"]
const IF_PREDS_THEN := ["outcome", "outcome_crossed"]  # then-effect "if" only
const OUTCOME_COUNTERS := ["hit", "ignited", "pushed", "collided", "converted", "planted", "washed", "statused"]
const PER_COUNTS := ["growth_adjacent_target", "fire_within_self", "oil_in_line", "enemies_adjacent_target"]
const PER_KEYS := ["count", "radius", "cap", "add"]
const PER_RADIUS_COUNTS := ["fire_within_self"]  # the only count Game._rider_per radius-limits
## Keys every Content.TERRAIN row must carry (Game reads each one).
const TERRAIN_REQUIRED := [
	"corruption", "shields_core", "flammable", "washable", "bloom", "ttl", "decays",
	"enter_dmg_player", "enter_dmg_enemy", "enter_src", "tick_dmg_player", "tick_dmg_enemy",
	"blocks", "blocks_beam", "heal", "burns_to", "convertible", "screens",
]
## TERRAIN keys that must be bools (Game reads them through bool()); "screens"
## is the Block D3 smoke-screen flag Game._screened reads.
const TERRAIN_BOOL_KEYS := ["corruption", "shields_core", "flammable", "washable", "decays", "blocks", "blocks_beam", "convertible", "screens"]
## "cooldown" stays optional: only the rows that want stagger-style
## immunity (root, since Block C1b) carry one, but where it appears it
## must be a positive int - a 0 or a float would silently disable it.
const STATUS_REQUIRED := ["stack", "blocks", "tick_dmg", "cap"]
# --- grafts as data (section 9) ------------------------------------------------
## Closed stat keys Game._graft_stat sums, and mod keys Game._graft_mod reads.
## regen_on_growth is the conditional half of regen: Game._begin_player_turn
## adds it only while the tender stands on growth. No shipped row uses it; the
## key exists so a conditional alternative to solar_core can be measured.
const GRAFT_STAT_KEYS := ["bank_cap", "shield_cap", "regen", "regen_on_growth", "growth_heal", "cleanse_bloom"]
const GRAFT_MOD_KEYS := ["floor_start_shield", "oil_cast_discount"]
## Positional ops only the hook dispatcher (Game._hook_effect) implements.
const HOOK_OP_KEYS := {
	"damage_at": ["dmg"],
	"status_at": ["status", "turns"],
	"terrain_at": ["kind"],
}
## Ops a hook row may never carry: shield and thorns credit are the stall
## vector BALANCE.md documents, so no graft hook grants them.
const HOOK_FORBIDDEN_OPS := ["shield", "thorns"]
const HOOK_ROW_KEYS := ["on", "effects", "cap_per_turn", "if"]
const GRAFT_ROW_KEYS := ["name", "desc", "tags", "price", "stat", "mod", "hooks"]

## Every enemy intent type Game._execute_intent can be handed; a status may
## only block one of these (or "*", every intent).
const INTENT_TYPES := [
	"idle", "fuse", "summon", "ooze", "stoke", "drag", "move", "gum", "drain",
	"attack", "advance", "slam", "dredge", "quake", "flood", "gather", "ignite_all",
]


func _init() -> void:
	var failures: Array = []

	# 1) tags / role vocabulary
	for aid in Content.ABILITIES.keys():
		var adef: Dictionary = Content.ABILITIES[aid]
		if not adef.has("tags") or not (adef["tags"] is Array) or adef["tags"].is_empty():
			failures.append("%s: missing or empty tags" % aid)
		else:
			for t in adef["tags"]:
				if not Content.TAGS.has(t):
					failures.append("%s: tag '%s' not in TAGS" % [aid, t])
		if not adef.has("role") or not Content.ROLES.has(adef["role"]):
			failures.append("%s: role '%s' not in ROLES" % [aid, str(adef.get("role", "<none>"))])

	# 2) "+" forms mirror their base
	var plus_count := 0
	for aid in Content.ABILITIES.keys():
		var base: String = Content.base_id(aid)
		if base == aid:
			continue
		plus_count += 1
		if not Content.ABILITIES.has(base):
			failures.append("%s: base '%s' missing from ABILITIES" % [aid, base])
			continue
		var adef: Dictionary = Content.ABILITIES[aid]
		var bdef: Dictionary = Content.ABILITIES[base]
		if adef.get("tags", []) != bdef.get("tags", []):
			failures.append("%s: tags %s differ from base %s" % [aid, str(adef.get("tags")), str(bdef.get("tags"))])
		if adef.get("role", "") != bdef.get("role", ""):
			failures.append("%s: role '%s' differs from base '%s'" % [aid, str(adef.get("role")), str(bdef.get("role"))])

	# 3) archetype references
	var core_ids := {}
	for arch_id in Content.ARCHETYPES.keys():
		var arch: Dictionary = Content.ARCHETYPES[arch_id]
		for key in ["name", "core", "requires"]:
			if not arch.has(key):
				failures.append("archetype %s: missing '%s'" % [arch_id, key])
		if arch.get("core", []).is_empty():
			failures.append("archetype %s: empty core" % arch_id)
		for aid in arch.get("core", []):
			core_ids[aid] = true
			if not Content.ABILITIES.has(aid):
				failures.append("archetype %s: core id '%s' not in ABILITIES" % [arch_id, aid])
			elif Content.base_id(aid) != aid:
				failures.append("archetype %s: core id '%s' is a '+' form" % [arch_id, aid])
		var req: Dictionary = arch.get("requires", {})
		for pkg in req.get("packages", []):
			if not Content.PACKAGES.has(pkg):
				failures.append("archetype %s: required package '%s' not in PACKAGES" % [arch_id, pkg])

	# 4) coverage of draftable abilities
	var draftable: Array = Content.DRAFT_POOL.duplicate()
	for pkg in Content.PACKAGES.keys():
		for aid in Content.PACKAGES[pkg]:
			if not draftable.has(aid):
				draftable.append(aid)
	var uncovered: Array = []
	for aid in draftable:
		if core_ids.has(aid):
			continue
		uncovered.append(aid)
		var role: String = str(Content.ABILITIES[aid].get("role", ""))
		if role != "mobility" and role != "utility":
			failures.append("%s (role %s) appears in no archetype core" % [aid, role])
	var bad_targets: Array = []
	for aid in Content.ABILITIES:
		var t := String(Content.ABILITIES[aid].get("target", ""))
		if not Content.TARGET_SHAPES.has(t):
			bad_targets.append("%s: target '%s' not in TARGET_SHAPES" % [aid, t])
	failures.append_array(bad_targets)
	var shapes := {}
	for aid in Content.ABILITIES:
		shapes[String(Content.ABILITIES[aid]["target"])] = true
	print("target shapes: %d of %d in use (%s)" % [
		shapes.size(), Content.TARGET_SHAPES.size(), ", ".join(shapes.keys())])
	print("abilities: %d (%d '+' forms), archetypes: %d, draftable: %d" % [
		Content.ABILITIES.size(), plus_count, Content.ARCHETYPES.size(), draftable.size()])
	print("uncovered by any archetype core (mobility/utility allowed): %s" % str(uncovered))

	# 5) base_id round-trips
	for aid in Content.ABILITIES.keys():
		var base: String = Content.base_id(aid)
		if base.find("+") >= 0:
			failures.append("base_id(%s) = '%s' still carries '+'" % [aid, base])
		if Content.base_id(base) != base:
			failures.append("base_id not idempotent on '%s'" % aid)
		# Block D6: an upgrade id is "<base>+<word>" (the word ^[a-z]+$, never
		# a second "+"), so the pre-D6 "aid == base + \"+\"" shape is gone
		if aid != base and not _valid_variant_id(String(aid), base):
			failures.append("base_id(%s) = '%s' does not round-trip" % [aid, base])

	# 5b) Block D6 evolve forks: variants_of / is_upgrade / variant_for
	failures.append_array(_lint_variants())

	# 6) archetypes_for(DRAFT_POOL) is exactly the package-free set, in key order
	var expected: Array = []
	for arch_id in Content.ARCHETYPES.keys():
		if Content.ARCHETYPES[arch_id]["requires"].get("packages", []).is_empty():
			expected.append(arch_id)
	var got: Array = Content.archetypes_for(Content.DRAFT_POOL)
	if got != expected:
		failures.append("archetypes_for(DRAFT_POOL) = %s, expected %s" % [str(got), str(expected)])
	# every package-gated archetype becomes available once its package is in the pool
	for arch_id in Content.ARCHETYPES.keys():
		var pkgs: Array = Content.ARCHETYPES[arch_id]["requires"].get("packages", [])
		if pkgs.is_empty():
			continue
		var pool: Array = Content.DRAFT_POOL.duplicate()
		for pkg in pkgs:
			if Content.PACKAGES.has(pkg):
				pool.append_array(Content.PACKAGES[pkg])
		if not Content.archetypes_for(pool).has(arch_id):
			failures.append("archetypes_for(pool + %s) lacks %s" % [str(pkgs), arch_id])
	print("archetypes_for(DRAFT_POOL): %s" % str(got))

	# 7) shop price list and item upcycle coverage; the reroll sink's data
	#    (Block D2): a base price >= 1, a cap >= 1 and a step >= 0, all ints
	for svc in ["heal", "ability", "graft", "item", "press", "forge", "reroll"]:
		if not Content.SHOP_COSTS.has(svc) or not (Content.SHOP_COSTS[svc] is int) or int(Content.SHOP_COSTS[svc]) <= 0:
			failures.append("SHOP_COSTS lacks a positive int price for '%s'" % svc)
	if not (Content.SHOP_REROLL_CAP is int) or Content.SHOP_REROLL_CAP < 1:
		failures.append("SHOP_REROLL_CAP must be an int >= 1, got %s" % str(Content.SHOP_REROLL_CAP))
	if not (Content.SHOP_REROLL_STEP is int) or Content.SHOP_REROLL_STEP < 0:
		failures.append("SHOP_REROLL_STEP must be an int >= 0, got %s" % str(Content.SHOP_REROLL_STEP))
	var base_items := 0
	# ITEMS keep the plain "+" convention - the shrine press is not the Block
	# D6 ability forge and item rows are NOT forked - so ends_with("+") and
	# trim_suffix("+") stay correct on an item id and only on an item id
	for iid in Content.ITEMS.keys():
		if String(iid).ends_with("+"):
			if not Content.ITEMS.has(String(iid).trim_suffix("+")):
				failures.append("item '%s' has no base form" % iid)
			continue
		base_items += 1
		if not Content.ITEMS.has(iid + "+"):
			failures.append("item '%s' has no '+' form for the press" % iid)
	print("shop costs: %s; reroll cap %d step %d; items: %d base, %d total" % [
		str(Content.SHOP_COSTS), Content.SHOP_REROLL_CAP, Content.SHOP_REROLL_STEP, base_items, Content.ITEMS.size()])

	# 8) effect grammar: content rows, data tables, and the lint's own self-test
	failures.append_array(_lint_effects(Content.ABILITIES))
	failures.append_array(_lint_tables())
	failures.append_array(_lint_selftest())
	print("effect grammar: %d ability rows over %d ops; terrain %d, reactions %d, statuses %d" % [
		Content.ABILITIES.size(), OP_KEYS.size(), Content.TERRAIN.size(),
		Content.REACTIONS.size(), Content.STATUSES.size()])

	# 9) grafts as data: the live table, then the lint's own self-test
	failures.append_array(_lint_grafts(Content.GRAFTS))
	failures.append_array(_lint_graft_selftest())
	var shape := {"stat": 0, "mod": 0, "hooks": 0}
	for gid in Content.GRAFTS:
		for k in shape:
			if Content.GRAFTS[gid].has(k):
				shape[k] += 1
	var prices: Array = []
	for gid in Content.GRAFTS:
		prices.append("%s %d" % [gid, int(Content.GRAFTS[gid].get("price", -1))])
	print("grafts: %d rows (%d stat, %d mod, %d hooks); hook kinds %d, depth max %d, step cap %d" % [
		Content.GRAFTS.size(), shape["stat"], shape["mod"], shape["hooks"],
		Content.HOOK_KINDS.size(), Content.HOOK_DEPTH_MAX, Content.HOOK_STEP_CAP])
	print("graft prices (+%d per owned): %s" % [Content.GRAFT_PRICE_STEP, ", ".join(prices)])

	# 10) mutators as data: the live table, then the lint's own self-test
	failures.append_array(_lint_mutators(Content.MUTATORS))
	failures.append_array(_lint_mutator_selftest())
	var mut_keys := {}
	for mid in Content.MUTATORS:
		for k in Content.MUTATORS[mid].get("config", {}):
			mut_keys[k] = true
	print("mutators: %d rows over %d of %d config keys" % [
		Content.MUTATORS.size(), mut_keys.size(), Content.MUTATOR_CONFIG_KEYS.size()])

	# 11) loadouts as data (Block A): the live table, then the lint's own self-test
	failures.append_array(_lint_loadouts(Content.LOADOUTS))
	failures.append_array(_lint_loadout_selftest())
	if Content.LOADOUTS.get("tender", {}).get("kit", []) != Content.STARTING_KIT:
		failures.append("loadout tender: kit %s != STARTING_KIT %s" % [
			str(Content.LOADOUTS.get("tender", {}).get("kit")), str(Content.STARTING_KIT)])
	var free_loadouts: Array = Content.loadouts_for([])
	var all_loadouts: Array = Content.loadouts_for(Content.PACKAGES.keys())
	if free_loadouts.is_empty() or free_loadouts[0] != "tender":
		failures.append("loadouts_for([]) = %s, expected tender first" % str(free_loadouts))
	if all_loadouts != Content.LOADOUTS.keys():
		failures.append("loadouts_for(every package) = %s, expected every row" % str(all_loadouts))
	for lid in Content.LOADOUTS:
		var pkgs: Array = Content.LOADOUTS[lid].get("requires", {}).get("packages", [])
		if free_loadouts.has(lid) != pkgs.is_empty():
			failures.append("loadouts_for([]) %s %s (requires %s)" % [
				"has" if free_loadouts.has(lid) else "lacks", lid, str(pkgs)])
	print("loadouts: %d rows, %d package-free (%s)" % [
		Content.LOADOUTS.size(), free_loadouts.size(), str(free_loadouts)])

	# 12) Block D3: enemies read terrain - the live tables, then the lint's own self-test
	failures.append_array(_lint_enemy_avoid(Content.ENEMIES))
	failures.append_array(_lint_avoid_cost(Content.ENEMY_AVOID_COST))
	failures.append_array(_lint_screened_intents(Content.SCREENED_INTENTS))
	failures.append_array(_lint_d3_selftest())
	var avoiders: Array = []
	var screens: Array = []
	for kind in Content.ENEMIES:
		if not Content.ENEMIES[kind].get("avoid", []).is_empty():
			avoiders.append("%s %s" % [kind, str(Content.ENEMIES[kind]["avoid"])])
	for kind in Content.TERRAIN:
		# the lint above rejects a non-bool screens value; do not throw on it here
		if Content.TERRAIN[kind].get("screens", false) is bool and Content.TERRAIN[kind].get("screens", false):
			screens.append(kind)
	print("enemies: %d rows, %d with an avoid list (%s); avoid cost %d; screened intents %s; screening terrain %s" % [
		Content.ENEMIES.size(), avoiders.size(), ", ".join(avoiders), Content.ENEMY_AVOID_COST,
		str(Content.SCREENED_INTENTS), str(screens)])

	# 13) Block D4: the draft slot tables, then the lint's own self-test
	failures.append_array(_lint_draft_slots(Content.DRAFT_SLOTS, Content.DRAFT_SLOT_ROLES))
	failures.append_array(_lint_name_list("DRAFT_SLOT_ROLES", Content.DRAFT_SLOT_ROLES))
	failures.append_array(_lint_name_list("DRAFT_SLOT_REPORTS", Content.DRAFT_SLOT_REPORTS))
	failures.append_array(_lint_ignored_tags(Content.AFFINITY_IGNORED_TAGS, Content.TAGS))
	failures.append_array(_lint_loadout_affinity())
	failures.append_array(_lint_d4_selftest())
	print("draft slots: %s (roles %s, reports %s); affinity ignores %s" % [
		str(Content.DRAFT_SLOTS), str(Content.DRAFT_SLOT_ROLES), str(Content.DRAFT_SLOT_REPORTS),
		str(Content.AFFINITY_IGNORED_TAGS)])

	if failures.is_empty():
		print("content: OK")
		quit(0)
	else:
		for f in failures:
			print("FAIL: %s" % f)
		print("content: %d failure(s)" % failures.size())
		quit(1)


# --- 8) effect-grammar lint ---------------------------------------------------

## Lints every effect dict of an ABILITIES-shaped table. Returns the failure
## strings (each one starts with the ability id) rather than printing, so the
## self-test below can run it on fixtures.
func _lint_effects(abilities: Dictionary) -> Array:
	var out: Array = []
	for aid in abilities.keys():
		var adef: Dictionary = abilities[aid]
		if adef.has("surge"):
			out.append_array(_lint_surge("%s: surge" % aid, adef["surge"], adef.get("effects", [])))
		var effs = adef.get("effects", [])
		if not (effs is Array) or (effs as Array).is_empty():
			out.append("%s: missing or empty effects" % aid)
			continue
		for i in range((effs as Array).size()):
			out.append_array(_lint_effect(effs[i], "%s effect %d" % [aid, i], false))
	return out


## One effect dict. `in_then` is true for the members of a parent "then" list:
## they may use the outcome predicates and the then-only ops, and may not carry
## a "then" of their own.
func _lint_effect(eff, where: String, in_then: bool) -> Array:
	var out: Array = []
	if not (eff is Dictionary):
		return ["%s: effect is not a dictionary" % where]
	var op := String(eff.get("op", ""))
	if not OP_KEYS.has(op):
		return ["%s: unknown op '%s'" % [where, op]]
	if THEN_ONLY_OPS.has(op) and not in_then:
		out.append("%s: op '%s' reads the parent outcome and is then-only" % [where, op])
	var own: Array = OP_KEYS[op]
	for k in eff:
		var key := String(k)
		if key == "op" or own.has(key) or RIDER_KEYS.has(key):
			continue
		out.append("%s: key '%s' is not part of op '%s' %s" % [where, key, op, str(own)])
	if STATUS_OPS.has(op) and not Content.STATUSES.has(String(eff.get("status", ""))):
		out.append("%s: status '%s' not in Content.STATUSES" % [where, str(eff.get("status", ""))])
	if op == "status_target" and not WHO_VALUES.has(String(eff.get("who", "affected"))):
		out.append("%s: who '%s' not in %s" % [where, str(eff.get("who")), str(WHO_VALUES)])
	if (op == "create_terrain" or op == "plant_origin") and not Content.TERRAIN.has(String(eff.get("kind", ""))):
		out.append("%s: %s kind '%s' not in Content.TERRAIN" % [where, op, str(eff.get("kind", ""))])
	# grow_radius always draws the plus, so its radius is honoured from 1 up
	if op == "grow_radius" and not (eff.get("radius", 0) is int and int(eff.get("radius", 0)) >= 1):
		out.append("%s: grow_radius radius must be an int >= 1" % where)
	out.append_array(_lint_d6_keys(eff, op, where))
	if eff.has("if"):
		out.append_array(_lint_if(eff["if"], "%s if" % where, in_then))
	if eff.has("per"):
		out.append_array(_lint_per(eff["per"], op, "%s per" % where))
	if eff.has("bonus"):
		out.append_array(_lint_bonus(eff["bonus"], op, "%s bonus" % where))
	if eff.has("then"):
		if in_then:
			out.append("%s: nested then" % where)
		elif not (eff["then"] is Array) or (eff["then"] as Array).is_empty():
			out.append("%s: then must be a non-empty array of effects" % where)
		else:
			var subs: Array = eff["then"]
			for i in range(subs.size()):
				out.append_array(_lint_effect(subs[i], "%s then %d" % [where, i], true))
	return out


## Block D6 key vocabulary, checked wherever an effect is linted:
##   pierce      lance only, a bool
##   center      aoe_status only, a CENTER_VALUES string
##   ignite_ttl  aoe_damage only, an int >= 1
##   kind        convert_radius only, a Content.TERRAIN key, and NEVER a
##               corruption row: a player-made corruption tile is a bloom
##               faucet and, because _act_cleanse credits `greened`
##               unconditionally, a green-gate faucet too
##   ttl         convert_radius only, an int >= 1; required when `kind` names
##               a decaying kind whose table ttl is 0 (roots - its TERRAIN row
##               leaves the length to the creator), rejected without a `kind`
## (OP_KEYS already rejects each key on the wrong op; this is the value half.)
func _lint_d6_keys(eff: Dictionary, op: String, where: String) -> Array:
	var out: Array = []
	if op == "lance" and eff.has("pierce") and not (eff["pierce"] is bool):
		out.append("%s: pierce must be a bool" % where)
	if op == "aoe_status" and not CENTER_VALUES.has(String(eff.get("center", "self"))):
		out.append("%s: center '%s' not in %s" % [where, str(eff.get("center")), str(CENTER_VALUES)])
	if op == "aoe_damage" and eff.has("ignite_ttl") \
			and not (eff["ignite_ttl"] is int and int(eff["ignite_ttl"]) >= 1):
		out.append("%s: ignite_ttl must be an int >= 1" % where)
	if op == "convert_radius":
		if eff.has("ttl") and not eff.has("kind"):
			out.append("%s: convert_radius ttl without a kind is dead data" % where)
		if eff.has("ttl") and not (eff["ttl"] is int and int(eff["ttl"]) >= 1):
			out.append("%s: convert_radius ttl must be an int >= 1" % where)
		if eff.has("kind"):
			var ck := String(eff["kind"])
			if not Content.TERRAIN.has(ck):
				out.append("%s: convert_radius kind '%s' not in Content.TERRAIN" % [where, ck])
			elif bool(Content.TERRAIN[ck].get("corruption", false)):
				out.append("%s: convert_radius kind '%s' is corruption - no variant may create corruption" % [where, ck])
			elif bool(Content.TERRAIN[ck].get("decays", false)) and int(Content.TERRAIN[ck].get("ttl", 0)) == 0 \
					and not eff.has("ttl"):
				out.append("%s: convert_radius kind '%s' decays with a table ttl of 0 and needs its own ttl" % [where, ck])
	return out


## An "if" list: predicate dicts from the closed set, AND-ed. `allow_outcome`
## is true only for the "if" of a then-effect, the one place where the parent
## outcome exists (a "bonus" is judged per enemy with no outcome in hand, so
## its own predicates never get it either).
func _lint_if(preds, where: String, allow_outcome: bool) -> Array:
	var out: Array = []
	if not (preds is Array) or (preds as Array).is_empty():
		return ["%s: must be a non-empty array of predicate dicts" % where]
	for pred in preds:
		if not (pred is Dictionary):
			out.append("%s: predicate is not a dictionary" % where)
			continue
		for k in pred:
			var key := String(k)
			var v = pred[k]
			if IF_PREDS_THEN.has(key):
				if not allow_outcome:
					out.append("%s: predicate '%s' is legal only inside a then-effect's if" % [where, key])
					continue
			elif not IF_PREDS.has(key):
				out.append("%s: unknown predicate '%s' %s" % [where, key, str(IF_PREDS + IF_PREDS_THEN)])
				continue
			match key:
				"target_on", "target_adjacent":
					if not (v is Array) or (v as Array).is_empty():
						out.append("%s: %s wants a non-empty array of terrain kinds" % [where, key])
					else:
						for kind in v:
							if not Content.TERRAIN.has(String(kind)):
								out.append("%s: %s kind '%s' not in Content.TERRAIN" % [where, key, str(kind)])
				"self_on", "outcome_crossed":
					if not Content.TERRAIN.has(String(v)):
						out.append("%s: %s kind '%s' not in Content.TERRAIN" % [where, key, str(v)])
				"dim", "casts_this_turn_min":
					if not (v is int):
						out.append("%s: %s wants an int, got %s" % [where, key, str(v)])
				"outcome":
					if not OUTCOME_COUNTERS.has(String(v)):
						out.append("%s: outcome '%s' is not an outcome counter %s" % [where, str(v), str(OUTCOME_COUNTERS)])
	return out


## A "per" rider: a closed count, an optional radius only where the sim reads
## one, an int cap, and adds that name keys the op itself reads.
func _lint_per(per, op: String, where: String) -> Array:
	if not (per is Dictionary):
		return ["%s: per must be a dictionary" % where]
	var out: Array = []
	for k in per:
		if not PER_KEYS.has(String(k)):
			out.append("%s: unknown key '%s' %s" % [where, str(k), str(PER_KEYS)])
	var count := String(per.get("count", ""))
	if not PER_COUNTS.has(count):
		out.append("%s: count '%s' not in %s" % [where, count, str(PER_COUNTS)])
	if per.has("radius") and not PER_RADIUS_COUNTS.has(count):
		out.append("%s: radius applies only to %s" % [where, str(PER_RADIUS_COUNTS)])
	if not (per.get("cap", 0) is int):
		out.append("%s: cap must be an int" % where)
	var add = per.get("add", {})
	if not (add is Dictionary) or (add as Dictionary).is_empty():
		out.append("%s: add must be a non-empty dictionary" % where)
	else:
		var own: Array = OP_KEYS.get(op, [])
		for k in add:
			if not own.has(String(k)):
				out.append("%s: add key '%s' is not a key of op '%s' %s" % [where, str(k), op, str(own)])
			if not (add[k] is int):
				out.append("%s: add['%s'] must be an int" % [where, str(k)])
	return out


## A "bonus" rider: flat damage on an op whose hits run through _bonus_dmg.
func _lint_bonus(bonus, op: String, where: String) -> Array:
	if not (bonus is Dictionary):
		return ["%s: bonus must be a dictionary" % where]
	var out: Array = []
	if not BONUS_OPS.has(op):
		out.append("%s: op '%s' never reads a bonus (only %s do)" % [where, op, str(BONUS_OPS)])
	for k in bonus:
		if String(k) != "dmg" and String(k) != "if":
			out.append("%s: unknown key '%s' (dmg, if)" % [where, str(k)])
	if not (bonus.get("dmg", 0) is int):
		out.append("%s: dmg must be an int" % where)
	if bonus.has("if"):
		out.append_array(_lint_if(bonus["if"], "%s if" % where, false))
	return out


## A surge dict: keys from SURGE_KEYS, every value an int, and when `effects`
## (the row's effect list) is given, every stat key must appear on at least one
## effect of the row - top level or inside a then - or the surge is dead data.
## SURGE_DEFAULT is linted without effects (it belongs to no row).
func _lint_surge(where: String, surge, effects = null) -> Array:
	if not (surge is Dictionary):
		return ["%s: surge must be a dictionary" % where]
	var out: Array = []
	for k in surge:
		var key := String(k)
		if not SURGE_KEYS.has(key):
			out.append("%s: unknown key '%s' (not in %s)" % [where, key, str(SURGE_KEYS)])
			continue
		if not (surge[k] is int):
			out.append("%s: %s must be an int" % [where, key])
		if key != "cost" and effects is Array and not _effects_carry(effects, key):
			out.append("%s: stat key '%s' touches no effect of the row" % [where, key])
	return out


## Whether any effect in `effects` (or a member of its then-list) carries `key`.
static func _effects_carry(effects: Array, key: String) -> bool:
	for eff in effects:
		if not (eff is Dictionary):
			continue
		if eff.has(key):
			return true
		var subs = eff.get("then", [])
		if subs is Array:
			for sub in subs:
				if sub is Dictionary and sub.has(key):
					return true
	return false


## The data tables themselves: complete TERRAIN rows, REACTIONS that reference
## real kinds through exactly one trigger, STATUSES that block real intents.
func _lint_tables() -> Array:
	var out: Array = []
	for kind in Content.TERRAIN.keys():
		var row: Dictionary = Content.TERRAIN[kind]
		for key in TERRAIN_REQUIRED:
			if not row.has(key):
				out.append("TERRAIN %s: missing '%s'" % [kind, key])
		var burns := String(row.get("burns_to", ""))
		if burns != "" and not Content.TERRAIN.has(burns):
			out.append("TERRAIN %s: burns_to '%s' not in TERRAIN" % [kind, burns])
		if bool(row.get("decays", false)) and int(row.get("ttl", 0)) < 0:
			out.append("TERRAIN %s: decays with a negative ttl" % kind)
		out.append_array(_lint_terrain_bools(kind, row))
		# convert_radius turns corruption into growth or (Block D6, the
		# `kind` key) into another non-corruption kind, so a convertible row
		# that is not corruption would still be dead data. The reverse -
		# converting INTO corruption - is rejected by _lint_d6_keys.
		if row.has("convertible") and not (row["convertible"] is bool):
			out.append("TERRAIN %s: convertible must be a bool" % kind)
		elif bool(row.get("convertible", false)) and not bool(row.get("corruption", false)):
			out.append("TERRAIN %s: convertible without corruption" % kind)
	var seen := {}
	for row in Content.REACTIONS:
		var rid := String(row.get("id", ""))
		if rid == "" or seen.has(rid):
			out.append("REACTIONS: missing or duplicate id '%s'" % rid)
		seen[rid] = true
		if not Content.TERRAIN.has(String(row.get("from", ""))):
			out.append("REACTIONS %s: from '%s' not in TERRAIN" % [rid, str(row.get("from", ""))])
		var triggers := 0
		for trig in ["adjacent", "on_expire", "on_wash"]:
			if row.has(trig):
				triggers += 1
		if triggers != 1:
			out.append("REACTIONS %s: wants exactly one trigger (adjacent | on_expire | on_wash), has %d" % [rid, triggers])
		if row.has("adjacent") and not Content.TERRAIN.has(String(row["adjacent"])):
			out.append("REACTIONS %s: adjacent '%s' not in TERRAIN" % [rid, str(row["adjacent"])])
		var result := String(row.get("result", ""))
		if result != "" and not Content.TERRAIN.has(result):
			out.append("REACTIONS %s: result '%s' not in TERRAIN" % [rid, result])
		if not (row.get("enabled", null) is bool):
			out.append("REACTIONS %s: enabled must be a bool" % rid)
	for sname in Content.STATUSES.keys():
		var st: Dictionary = Content.STATUSES[sname]
		for key in STATUS_REQUIRED:
			if not st.has(key):
				out.append("STATUSES %s: missing '%s'" % [sname, key])
		var stack := String(st.get("stack", ""))
		if stack != "max" and stack != "add":
			out.append("STATUSES %s: stack '%s' is not max|add" % [sname, stack])
		var blocks: Array = st.get("blocks", [])
		for b in blocks:
			if String(b) != "*" and not INTENT_TYPES.has(String(b)):
				out.append("STATUSES %s: blocks '%s', which is not an enemy intent type" % [sname, str(b)])
		if not blocks.is_empty() and String(st.get("blocked_event", "")) == "":
			out.append("STATUSES %s: blocks %s without a blocked_event" % [sname, str(blocks)])
		if st.has("cooldown") and not (st["cooldown"] is int and int(st["cooldown"]) > 0):
			out.append("STATUSES %s: cooldown must be a positive int" % sname)
	out.append_array(_lint_surge("SURGE_DEFAULT", Content.SURGE_DEFAULT))
	# burns_to (read by Content.counts_as_corruption) and the enabled on_expire
	# REACTIONS row (what the sim actually writes at burnout) must agree, or the
	# pending-corruption count silently diverges from play
	for kind in Content.TERRAIN:
		var burns2 := String(Content.TERRAIN[kind].get("burns_to", ""))
		var expire_result := ""
		var expire_rows := 0
		for row2 in Content.REACTIONS:
			if String(row2.get("from", "")) == kind and row2.has("on_expire") and bool(row2.get("enabled", false)):
				expire_rows += 1
				expire_result = String(row2.get("result", ""))
		if expire_rows > 1:
			out.append("REACTIONS: %d enabled on_expire rows for '%s' (want at most one)" % [expire_rows, kind])
		if burns2 != expire_result:
			out.append("TERRAIN %s: burns_to '%s' disagrees with the enabled on_expire REACTIONS result '%s'" % [kind, burns2, expire_result])
	return out


# --- 5b) Block D6 evolve forks ------------------------------------------------

## Is `aid` a well-formed upgrade id for `base`? Two legal shapes, and only
## these - Content.base_id cuts at the first "+", so anything else would fold
## onto a base while reading as something the table never named:
##   "<base>+<word>"  a Block D6 fork variant, word ^[a-z]+$, no second "+"
##   "<base>+"        the plain package upgrade (the nine PACKAGES abilities
##                    are not forked and keep their single "+" row)
## Which shape a given base must use is checked per base in _lint_variants.
static func _valid_variant_id(aid: String, base: String) -> bool:
	if not aid.begins_with(base + "+"):
		return false
	var word: String = aid.substr(base.length() + 1)
	if word.find("+") >= 0:
		return false
	if word.is_empty():
		return true  # the plain package "+" form
	for i in word.length():
		var c: String = word[i]
		if c < "a" or c > "z":
			return false
	return true


## Block D6: the fork machinery as data.
##   - every variant id is "<base>+<word>" and its base is in ABILITIES
##   - Content.variants_of is DERIVED (a scan of ABILITIES), so it agrees
##     exactly with a scan done here - never a hand-maintained second list
##   - a base has 1 or 2 variants, never more: exactly 2 for each of the
##     fifteen forked base-pool abilities, exactly 1 for each of the nine
##     package abilities, and >= 1 for every DRAFT_POOL and PACKAGES base
##   - a variant carries its base's tags and role EXACTLY (cost is
##     deliberately not checked: five B rows keep the base cost where A cut
##     it, and two sit at the base cost where A is cheaper)
##   - Content.is_upgrade agrees with base_id, and variant_for is a pure
##     parity index into variants_of with no rng
##   - every ABILITIES row, variants included, has an ABILITY_DESC line
##   - every new Block D6 key/op is carried by at least one shipped row
func _lint_variants() -> Array:
	var out: Array = []
	var scanned := {}
	for aid in Content.ABILITIES.keys():
		var key := String(aid)
		var base: String = Content.base_id(key)
		if Content.is_upgrade(key) != (base != key):
			out.append("is_upgrade(%s) disagrees with base_id" % key)
		if base == key:
			continue
		if not Content.ABILITIES.has(base):
			out.append("variant %s: base '%s' missing from ABILITIES" % [key, base])
			continue
		if not _valid_variant_id(key, base):
			out.append("variant %s: id is not '<base>+<word>' with word ^[a-z]+$" % key)
		var adef: Dictionary = Content.ABILITIES[key]
		var bdef: Dictionary = Content.ABILITIES[base]
		if adef.get("tags", []) != bdef.get("tags", []):
			out.append("variant %s: tags %s differ from base %s" % [key, str(adef.get("tags")), str(bdef.get("tags"))])
		if adef.get("role", "") != bdef.get("role", ""):
			out.append("variant %s: role '%s' differs from base '%s'" % [key, str(adef.get("role")), str(bdef.get("role"))])
		if not scanned.has(base):
			scanned[base] = []
		scanned[base].append(key)
	# variants_of is derived, not a stored list: it must reproduce the scan
	for base in scanned:
		var got: Array = Content.variants_of(String(base))
		if got != scanned[base]:
			out.append("variants_of(%s) = %s, table scan says %s" % [base, str(got), str(scanned[base])])
		if got.size() > 2:
			out.append("variants_of(%s) has %d entries (1 or 2)" % [base, got.size()])
		# variant_for is parity over that list, and nothing else
		for parity in range(0, 8):
			var want: String = String(got[parity % got.size()])
			if Content.variant_for(String(base), parity) != want:
				out.append("variant_for(%s, %d) = '%s', expected '%s'" % [
					base, parity, Content.variant_for(String(base), parity), want])
	for base in D6_FORKED_BASES:
		var fv: Array = Content.variants_of(String(base))
		if fv.size() != 2:
			out.append("forked base %s has %d variants, expected 2" % [base, fv.size()])
		for v in fv:
			# a forked base never keeps the plain "<base>+" key: every one of
			# its variants is named, so no id in the game both ends with "+"
			# and is an ability
			if String(v) == String(base) + "+":
				out.append("forked base %s still carries the plain '+' key" % base)
	for pkg in Content.PACKAGES.keys():
		for aid in Content.PACKAGES[pkg]:
			var pv: Array = Content.variants_of(String(aid))
			if pv != [String(aid) + "+"]:
				out.append("package base %s has variants %s, expected ['%s+'] (packages are not forked)" % [
					aid, str(pv), aid])
	for aid in Content.DRAFT_POOL:
		if Content.variants_of(String(aid)).is_empty():
			out.append("draft pool base %s has no upgrade variant" % aid)
	if Content.variant_for("no_such_ability", 3) != "":
		out.append("variant_for on a base with no variant must return ''")
	# every row, variants included, has a description line
	for aid in Content.ABILITIES.keys():
		if not Content.ABILITY_DESC.has(aid):
			out.append("ABILITY_DESC has no line for '%s'" % aid)
	# the D6 vocabulary budget is closed AND spent: every new key and op is
	# carried by a shipped row (dead vocabulary is a data error)
	var key_users := {}
	var op_users := {}
	for aid in Content.ABILITIES.keys():
		for eff in Content.ABILITIES[aid].get("effects", []):
			var op := String(eff.get("op", ""))
			if D6_NEW_OPS.has(op):
				op_users[op] = true
			for k in D6_NEW_KEYS:
				if eff.has(k) and String(D6_NEW_KEYS[k]) == op:
					key_users[k] = true
	for k in D6_NEW_KEYS:
		if not key_users.has(k):
			out.append("Block D6 key '%s' (op %s) is carried by no shipped row" % [k, str(D6_NEW_KEYS[k])])
		if not OP_KEYS.get(String(D6_NEW_KEYS[k]), []).has(k):
			out.append("Block D6 key '%s' is not declared on op '%s' in OP_KEYS" % [k, str(D6_NEW_KEYS[k])])
	for op in D6_NEW_OPS:
		if not op_users.has(op):
			out.append("Block D6 op '%s' is used by no shipped row" % op)
		if not OP_KEYS.has(op):
			out.append("Block D6 op '%s' is not in OP_KEYS" % op)
	var forked := 0
	for base in scanned:
		if scanned[base].size() == 2:
			forked += 1
	print("variants: %d bases carry an upgrade (%d forked into 2, %d package singles); ABILITY_DESC %d rows" % [
		scanned.size(), forked, scanned.size() - forked, Content.ABILITY_DESC.size()])
	return out


## Rows the lint MUST reject, one violation each; the id is the failure prefix.
## Kept here rather than in content so the check never needs a broken game.
const BAD_ROWS := {
	"xa_unknown_op": {"effects": [{"op": "melt", "dmg": 1}]},
	"xb_stray_key": {"effects": [{"op": "damage", "dmg": 1, "radius": 2}]},
	"xb2_grow_radius_zero": {"effects": [{"op": "grow_radius", "radius": 0}]},
	"xc_status_name": {"effects": [{"op": "apply_status", "status": "curse", "turns": 1}]},
	"xd_terrain_kind": {"effects": [{"op": "create_terrain", "kind": "lava", "ttl": 2}]},
	"xe_pred_name": {"effects": [{"op": "damage", "dmg": 1, "if": [{"target_near": ["oil"]}]}]},
	"xf_pred_kind": {"effects": [{"op": "damage", "dmg": 1, "if": [{"target_on": ["lava"]}]}]},
	"xg_outcome_outside_then": {"effects": [{"op": "damage", "dmg": 1, "if": [{"outcome": "hit"}]}]},
	"xh_outcome_counter": {"effects": [{"op": "damage", "dmg": 1, "then": [
		{"op": "status_target", "status": "stun", "turns": 1, "if": [{"outcome": "melted"}]}]}]},
	"xi_per_count": {"effects": [{"op": "damage", "dmg": 1, "per": {"count": "stars", "cap": 2, "add": {"dmg": 1}}}]},
	"xj_per_radius": {"effects": [{"op": "damage", "dmg": 1, "per": {
		"count": "oil_in_line", "radius": 2, "cap": 2, "add": {"dmg": 1}}}]},
	"xk_per_add_key": {"effects": [{"op": "damage", "dmg": 1, "per": {
		"count": "oil_in_line", "cap": 2, "add": {"push": 1}}}]},
	"xl_bonus_op": {"effects": [{"op": "shield", "amount": 2, "bonus": {"dmg": 1}}]},
	"xm_bonus_key": {"effects": [{"op": "damage", "dmg": 1, "bonus": {"dmg": 1, "chance": 50}}]},
	"xn_bonus_outcome": {"effects": [{"op": "damage", "dmg": 1, "bonus": {"dmg": 1, "if": [{"outcome": "hit"}]}}]},
	"xo_nested_then": {"effects": [{"op": "damage", "dmg": 1, "then": [
		{"op": "status_target", "status": "stun", "turns": 1, "then": [{"op": "damage", "dmg": 1}]}]}]},
	"xp_then_only_op": {"effects": [{"op": "status_target", "status": "stun", "turns": 1}]},
	"xq_who": {"effects": [{"op": "grow_radius", "radius": 1, "then": [
		{"op": "status_target", "status": "root", "turns": 1, "who": "everyone"}]}]},
	"xr_surge": {"surge": {"cost": "free"}, "effects": [{"op": "damage", "dmg": 1}]},
	"xs_no_effects": {"effects": []},
	# Block D1 surge lint
	"xt_surge_key": {"surge": {"chance": 1}, "effects": [{"op": "damage", "dmg": 1}]},
	"xu_surge_untouched": {"surge": {"radius": 1}, "effects": [{"op": "damage", "dmg": 1}]},
	"xv_surge_float": {"surge": {"dmg": 1.5}, "effects": [{"op": "damage", "dmg": 1}]},
	"xw_surge_on_effect": {"effects": [{"op": "damage", "dmg": 1, "surge": {"dmg": 1}}]},
	"xx_plant_origin_kind": {"effects": [{"op": "teleport"}, {"op": "plant_origin", "kind": "lava"}]},
	"xy_plant_origin_key": {"effects": [{"op": "plant_origin", "kind": "growth", "ttl": 2}]},
	# Block D6 vocabulary: one fixture per bad shape
	"y1_pierce_not_bool": {"effects": [{"op": "lance", "dmg": 2, "clear_smog_bonus": 0,
		"ignite": true, "pierce": 1}]},
	"y2_pierce_wrong_op": {"effects": [{"op": "damage", "dmg": 1, "pierce": true}]},
	"y3_center_value": {"effects": [{"op": "aoe_status", "status": "stun", "turns": 1,
		"radius": 2, "center": "enemy"}]},
	"y4_center_wrong_op": {"effects": [{"op": "aoe_damage", "dmg": 1, "radius": 2, "center": "target"}]},
	"y5_ignite_ttl_zero": {"effects": [{"op": "aoe_damage", "dmg": 1, "radius": 2,
		"ignite": true, "ignite_ttl": 0}]},
	"y6_ignite_ttl_wrong_op": {"effects": [{"op": "lance", "dmg": 2, "clear_smog_bonus": 0,
		"ignite": true, "ignite_ttl": 4}]},
	"y7_convert_kind_unknown": {"effects": [{"op": "convert_radius", "radius": 1, "kind": "lava"}]},
	"y8_convert_kind_corruption": {"effects": [{"op": "convert_radius", "radius": 1, "kind": "oil"}]},
	"y9_convert_decaying_no_ttl": {"effects": [{"op": "convert_radius", "radius": 1, "kind": "roots"}]},
	"ya_convert_ttl_no_kind": {"effects": [{"op": "convert_radius", "radius": 1, "ttl": 3}]},
	"yb_convert_ttl_zero": {"effects": [{"op": "convert_radius", "radius": 1, "kind": "roots", "ttl": 0}]},
	"yc_pull_line_key": {"effects": [{"op": "pull_line", "dist": 2, "dmg": 2, "radius": 1}]},
}

## Rows the lint MUST accept: the Block C2 rider rows exactly as the review
## writes them, plus a surge row and the two counts C2 does not use.
const GOOD_ROWS := {
	"ga_grow_spike": {"effects": [{"op": "damage", "dmg": 3, "per": {
		"count": "growth_adjacent_target", "cap": 2, "add": {"dmg": 1}}}]},
	"gb_sun_flare": {"effects": [{"op": "aoe_damage", "dmg": 2, "radius": 2, "ignite": true,
		"bonus": {"dmg": 1, "if": [{"target_on": ["fire"]}]}}]},
	"gc_water_jet": {"effects": [{"op": "wash_push", "push": 2, "collision_dmg": 2, "then": [
		{"op": "status_target", "status": "root", "turns": 1, "if": [{"outcome": "collided"}]}]}]},
	"gd_vine_whip": {"effects": [{"op": "pull", "dist": 2, "dmg": 2, "then": [
		{"op": "status_target", "status": "stun", "turns": 1, "if": [{"outcome_crossed": "fire"}]}]}]},
	"ge_seed_bomb": {"effects": [{"op": "grow_radius", "radius": 1, "then": [
		{"op": "status_target", "status": "root", "turns": 1, "who": "on_planted"}]}]},
	"gf_surge_lance": {"surge": {"cost": -2}, "effects": [{"op": "lance", "dmg": 2,
		"clear_smog_bonus": 0, "ignite": true, "per": {"count": "oil_in_line", "cap": 3, "add": {"dmg": 1}},
		"if": [{"self_on": "growth"}, {"dim": 0, "casts_this_turn_min": 1}]}]},
	"gg_fire_within": {"effects": [{"op": "aoe_damage", "dmg": 1, "radius": 2, "per": {
		"count": "fire_within_self", "radius": 2, "cap": 4, "add": {"dmg": 1}}}]},
	"gh_enemies_adjacent": {"effects": [{"op": "damage", "dmg": 1, "per": {
		"count": "enemies_adjacent_target", "cap": 2, "add": {"dmg": 1}}, "bonus": {"dmg": 1,
		"if": [{"target_adjacent": ["growth", "roots"]}]}}]},
	# Block D1: the surged rows as shipped, plus a stat key that only a then carries
	"gi_grow_spike_surge": {"surge": {"dmg": 1}, "effects": [{"op": "damage", "dmg": 3, "per": {
		"count": "growth_adjacent_target", "cap": 1, "add": {"dmg": 1}}}]},
	"gj_water_jet_surge": {"surge": {"push": 1, "collision_dmg": 1}, "effects": [
		{"op": "wash_push", "push": 2, "collision_dmg": 2}]},
	"gk_sun_flare_surge": {"surge": {"cost": -1, "radius": 1}, "effects": [{"op": "aoe_damage",
		"dmg": 1, "radius": 2, "ignite": true, "bonus": {"dmg": 1, "if": [{"target_on": ["fire"]}]}}]},
	"gl_seed_bomb_plus_surge": {"surge": {"radius": 1}, "effects": [{"op": "grow_radius", "radius": 1, "then": [
		{"op": "status_target", "status": "root", "turns": 1, "who": "on_planted"}]}]},
	"gm_surge_then_only": {"surge": {"turns": 1}, "effects": [{"op": "grow_radius", "radius": 1, "then": [
		{"op": "status_target", "status": "root", "turns": 1, "who": "on_planted"}]}]},
	"gn_spore_trail": {"effects": [{"op": "teleport"}, {"op": "plant_origin", "kind": "growth"}]},
	# Block D6: the six new vocabulary items as shipped
	"go_pierce": {"effects": [{"op": "lance", "dmg": 2, "clear_smog_bonus": 0,
		"ignite": true, "pierce": true}]},
	"gp_pull_line": {"effects": [{"op": "pull_line", "dist": 2, "dmg": 2,
		"bonus": {"dmg": 1, "if": [{"target_on": ["fire"]}]}}]},
	"gq_center": {"effects": [{"op": "aoe_status", "status": "stun", "turns": 1,
		"radius": 2, "center": "target"}]},
	"gr_ignite_ttl": {"effects": [{"op": "aoe_damage", "dmg": 1, "radius": 2,
		"ignite": true, "ignite_ttl": 4}]},
	"gs_convert_kind_ttl": {"effects": [{"op": "convert_radius", "radius": 1, "kind": "roots", "ttl": 3}]},
	"gt_convert_default": {"effects": [{"op": "convert_radius", "radius": 2}]},
}


## The lint checking itself: every BAD_ROWS id must be named by at least one
## failure, and GOOD_ROWS must come back clean.
func _lint_selftest() -> Array:
	var out: Array = []
	var bad: Array = _lint_effects(BAD_ROWS)
	for aid in BAD_ROWS.keys():
		var caught := false
		for f in bad:
			if String(f).begins_with(String(aid)):
				caught = true
		if not caught:
			out.append("lint self-test: '%s' is a deliberate violation the lint accepted" % aid)
	var good: Array = _lint_effects(GOOD_ROWS)
	for f in good:
		out.append("lint self-test: rider fixture rejected: %s" % f)
	print("effect-grammar self-test: %d bad rows -> %d failures; %d rider rows -> %d failures" % [
		BAD_ROWS.size(), bad.size(), GOOD_ROWS.size(), good.size()])
	return out


# --- 9) grafts-as-data lint ---------------------------------------------------

## Lints a GRAFTS-shaped table; failure strings start with the graft id.
func _lint_grafts(grafts: Dictionary) -> Array:
	var out: Array = []
	for gid in grafts.keys():
		var row = grafts[gid]
		if not (row is Dictionary):
			out.append("%s: row is not a dictionary" % gid)
			continue
		for k in row:
			if not GRAFT_ROW_KEYS.has(String(k)):
				out.append("%s: unknown key '%s' %s" % [gid, str(k), str(GRAFT_ROW_KEYS)])
		for key in ["name", "desc"]:
			if not (row.get(key, null) is String) or String(row.get(key, "")) == "":
				out.append("%s: missing or empty '%s'" % [gid, key])
		var tags = row.get("tags", null)
		if not (tags is Array) or (tags as Array).is_empty():
			out.append("%s: missing or empty tags" % gid)
		else:
			for t in tags:
				if not Content.TAGS.has(t):
					out.append("%s: tag '%s' not in TAGS" % [gid, str(t)])
		# price is required and closed to ints >= 1: the shrine prices every
		# offer from its own row, so a row without one has no price at all
		if not row.has("price"):
			out.append("%s: missing 'price' (int >= 1)" % gid)
		elif not (row["price"] is int):
			out.append("%s: price must be an int, got %s" % [gid, str(row["price"])])
		elif int(row["price"]) < 1:
			out.append("%s: price %d must be >= 1" % [gid, int(row["price"])])
		var shapes := 0
		for shape in ["stat", "mod", "hooks"]:
			if row.has(shape):
				shapes += 1
		if shapes != 1:
			out.append("%s: wants exactly one of stat | mod | hooks, has %d" % [gid, shapes])
		if row.has("stat"):
			var stat = row["stat"]
			if not (stat is Dictionary) or (stat as Dictionary).is_empty():
				out.append("%s: stat must be a non-empty dictionary" % gid)
			else:
				for k in stat:
					if not GRAFT_STAT_KEYS.has(String(k)):
						out.append("%s: stat key '%s' not in %s" % [gid, str(k), str(GRAFT_STAT_KEYS)])
					if not (stat[k] is int):
						out.append("%s: stat['%s'] must be an int" % [gid, str(k)])
		if row.has("mod"):
			var mod = row["mod"]
			if not (mod is Dictionary) or (mod as Dictionary).is_empty():
				out.append("%s: mod must be a non-empty dictionary" % gid)
			else:
				for k in mod:
					if not GRAFT_MOD_KEYS.has(String(k)):
						out.append("%s: mod key '%s' not in %s" % [gid, str(k), str(GRAFT_MOD_KEYS)])
					if not (mod[k] is int):
						out.append("%s: mod['%s'] must be an int" % [gid, str(k)])
		if row.has("hooks"):
			var hooks = row["hooks"]
			if not (hooks is Array) or (hooks as Array).is_empty():
				out.append("%s: hooks must be a non-empty array of rows" % gid)
			else:
				for i in range((hooks as Array).size()):
					out.append_array(_lint_hook_row(hooks[i], "%s hook %d" % [gid, i]))
	return out


## One hook row: {on: HOOK_KINDS kind, effects: non-empty, cap_per_turn?: int,
## if?: predicates}. Effects are effect-vocabulary dicts (linted as top-level
## effects: no then-only ops, no outcome predicates) or positional hook ops;
## HOOK_FORBIDDEN_OPS are rejected anywhere in the row, then-lists included.
func _lint_hook_row(row, where: String) -> Array:
	var out: Array = []
	if not (row is Dictionary):
		return ["%s: hook row is not a dictionary" % where]
	for k in row:
		if not HOOK_ROW_KEYS.has(String(k)):
			out.append("%s: unknown key '%s' %s" % [where, str(k), str(HOOK_ROW_KEYS)])
	if not Content.HOOK_KINDS.has(String(row.get("on", ""))):
		out.append("%s: on '%s' not in Content.HOOK_KINDS %s" % [where, str(row.get("on", "")), str(Content.HOOK_KINDS)])
	if row.has("cap_per_turn") and not (row["cap_per_turn"] is int and int(row["cap_per_turn"]) >= 0):
		out.append("%s: cap_per_turn must be a non-negative int" % where)
	if row.has("if"):
		out.append_array(_lint_if(row["if"], "%s if" % where, false))
	var effs = row.get("effects", null)
	if not (effs is Array) or (effs as Array).is_empty():
		return out + ["%s: effects must be a non-empty array" % where]
	for i in range((effs as Array).size()):
		var eff = effs[i]
		var ew := "%s effect %d" % [where, i]
		if not (eff is Dictionary):
			out.append("%s: effect is not a dictionary" % ew)
			continue
		var op := String(eff.get("op", ""))
		if HOOK_OP_KEYS.has(op):
			var own: Array = HOOK_OP_KEYS[op]
			for k in eff:
				if String(k) != "op" and not own.has(String(k)):
					out.append("%s: key '%s' is not part of hook op '%s' %s" % [ew, str(k), op, str(own)])
			for k in own:
				if not eff.has(k):
					out.append("%s: hook op '%s' needs '%s'" % [ew, op, k])
			if op == "status_at" and not Content.STATUSES.has(String(eff.get("status", ""))):
				out.append("%s: status '%s' not in Content.STATUSES" % [ew, str(eff.get("status", ""))])
			if op == "terrain_at" and not Content.TERRAIN.has(String(eff.get("kind", ""))):
				out.append("%s: terrain_at kind '%s' not in Content.TERRAIN" % [ew, str(eff.get("kind", ""))])
			if (op == "damage_at" and not (eff.get("dmg", 0) is int)) or (op == "status_at" and not (eff.get("turns", 0) is int)):
				out.append("%s: hook op '%s' wants int amounts" % [ew, op])
			continue
		out.append_array(_lint_effect(eff, ew, false))
		out.append_array(_forbidden_ops(eff, ew))
	return out


## Every op in `eff` and its then-list that a hook may not grant.
func _forbidden_ops(eff: Dictionary, where: String) -> Array:
	var out: Array = []
	var op := String(eff.get("op", ""))
	if HOOK_FORBIDDEN_OPS.has(op):
		out.append("%s: op '%s' grants shield/thorns credit, forbidden in a hook" % [where, op])
	if eff.get("then", null) is Array:
		for i in range((eff["then"] as Array).size()):
			var sub = eff["then"][i]
			if sub is Dictionary:
				out.append_array(_forbidden_ops(sub, "%s then %d" % [where, i]))
	return out


## Graft rows the lint MUST reject, one violation each.
const BAD_GRAFTS := {
	"ya_no_name": {"desc": "x", "tags": ["fire"], "price": 4, "stat": {"regen": 1}},
	"yb_no_desc": {"name": "x", "tags": ["fire"], "price": 4, "stat": {"regen": 1}},
	"yc_bad_tag": {"name": "x", "desc": "x", "tags": ["lava"], "price": 4, "stat": {"regen": 1}},
	"yd_no_tags": {"name": "x", "desc": "x", "tags": [], "price": 4, "stat": {"regen": 1}},
	"ye_no_shape": {"name": "x", "desc": "x", "tags": ["fire"], "price": 4},
	"yf_two_shapes": {"name": "x", "desc": "x", "tags": ["fire"], "price": 4, "stat": {"regen": 1}, "mod": {"floor_start_shield": 1}},
	"yg_stat_key": {"name": "x", "desc": "x", "tags": ["fire"], "price": 4, "stat": {"luck": 1}},
	"yh_stat_float": {"name": "x", "desc": "x", "tags": ["fire"], "price": 4, "stat": {"regen": 1.5}},
	"yi_mod_key": {"name": "x", "desc": "x", "tags": ["fire"], "price": 4, "mod": {"discount": 1}},
	"yj_hook_kind": {"name": "x", "desc": "x", "tags": ["fire"], "price": 4, "hooks": [{"on": "sneeze", "effects": [{"op": "damage_at", "dmg": 1}]}]},
	"yk_hook_no_effects": {"name": "x", "desc": "x", "tags": ["fire"], "price": 4, "hooks": [{"on": "ignite", "effects": []}]},
	"yl_hook_shield": {"name": "x", "desc": "x", "tags": ["bark"], "price": 4, "hooks": [{"on": "cleanse", "effects": [{"op": "shield", "amount": 1}]}]},
	"ym_hook_thorns": {"name": "x", "desc": "x", "tags": ["bark"], "price": 4, "hooks": [{"on": "shield_break", "effects": [{"op": "thorns", "dmg": 1, "turns": 2}]}]},
	"yn_hook_then_shield": {"name": "x", "desc": "x", "tags": ["bark"], "price": 4, "hooks": [{"on": "kill", "effects": [
		{"op": "damage", "dmg": 1, "then": [{"op": "shield", "amount": 1}]}]}]},
	"yo_hook_cap_float": {"name": "x", "desc": "x", "tags": ["fire"], "price": 4, "hooks": [{"on": "ignite", "effects": [{"op": "damage_at", "dmg": 1}], "cap_per_turn": 2.5}]},
	"yp_hook_unknown_op": {"name": "x", "desc": "x", "tags": ["fire"], "price": 4, "hooks": [{"on": "ignite", "effects": [{"op": "melt_at", "dmg": 1}]}]},
	"yq_hook_op_key": {"name": "x", "desc": "x", "tags": ["fire"], "price": 4, "hooks": [{"on": "ignite", "effects": [{"op": "damage_at", "dmg": 1, "radius": 2}]}]},
	"yr_hook_status": {"name": "x", "desc": "x", "tags": ["water"], "price": 4, "hooks": [{"on": "staggered", "effects": [{"op": "status_at", "status": "curse", "turns": 1}]}]},
	"ys_hook_terrain": {"name": "x", "desc": "x", "tags": ["growth"], "price": 4, "hooks": [{"on": "kill", "effects": [{"op": "terrain_at", "kind": "lava"}]}]},
	"yt_hook_row_key": {"name": "x", "desc": "x", "tags": ["fire"], "price": 4, "hooks": [{"on": "ignite", "effects": [{"op": "damage_at", "dmg": 1}], "chance": 50}]},
	"yu_hook_then_only": {"name": "x", "desc": "x", "tags": ["fire"], "price": 4, "hooks": [{"on": "kill", "effects": [{"op": "status_target", "status": "stun", "turns": 1}]}]},
	"yv_hook_if_pred": {"name": "x", "desc": "x", "tags": ["fire"], "price": 4, "hooks": [{"on": "ignite", "effects": [{"op": "damage_at", "dmg": 1}], "if": [{"outcome": "hit"}]}]},
	"yw_row_key": {"name": "x", "desc": "x", "tags": ["fire"], "price": 4, "cost": 4, "stat": {"regen": 1}},
	"yx_no_price": {"name": "x", "desc": "x", "tags": ["fire"], "stat": {"regen": 1}},
	"yy_price_float": {"name": "x", "desc": "x", "tags": ["fire"], "price": 4.5, "stat": {"regen": 1}},
	"yz_price_zero": {"name": "x", "desc": "x", "tags": ["fire"], "price": 0, "stat": {"regen": 1}},
}

## Graft rows the lint MUST accept: the four C3 rule grafts as the review
## writes them, a hook row with an `if` and a plain effect-vocabulary op, and
## a regen_on_growth stat row (the key exists for the solar_core probe).
const GOOD_GRAFTS := {
	"ha_ember_sap": {"name": "x", "desc": "x", "tags": ["fire"], "price": 4,
		"hooks": [{"on": "ignite", "effects": [{"op": "damage_at", "dmg": 1}], "cap_per_turn": 3}]},
	"hb_undertow": {"name": "x", "desc": "x", "tags": ["water", "displace", "control"], "price": 4,
		"hooks": [{"on": "staggered", "effects": [{"op": "status_at", "status": "root", "turns": 1}]}]},
	"hc_compost": {"name": "x", "desc": "x", "tags": ["growth"], "price": 4,
		"hooks": [{"on": "kill", "effects": [{"op": "terrain_at", "kind": "growth"}]}]},
	"hd_oil_tithe": {"name": "x", "desc": "x", "tags": ["fire", "water", "economy"], "price": 4, "mod": {"oil_cast_discount": 1}},
	# the conditional regen key: no shipped row uses it, the lint accepts it
	"hf_regen_on_growth": {"name": "x", "desc": "x", "tags": ["growth", "sun"], "price": 8, "stat": {"regen_on_growth": 1}},
	"he_hook_if_effect": {"name": "x", "desc": "x", "tags": ["fire"], "price": 4,
		"hooks": [{"on": "cleanse", "effects": [{"op": "aoe_damage", "dmg": 1, "radius": 1, "ignite": false}],
			"if": [{"target_adjacent": ["oil"]}], "cap_per_turn": 0}]},
}


func _lint_graft_selftest() -> Array:
	var out: Array = []
	var bad: Array = _lint_grafts(BAD_GRAFTS)
	for gid in BAD_GRAFTS.keys():
		var caught := false
		for f in bad:
			if String(f).begins_with(String(gid)):
				caught = true
		if not caught:
			out.append("graft lint self-test: '%s' is a deliberate violation the lint accepted" % gid)
	var good: Array = _lint_grafts(GOOD_GRAFTS)
	for f in good:
		out.append("graft lint self-test: rule-graft fixture rejected: %s" % f)
	print("graft lint self-test: %d bad rows -> %d failures; %d good rows -> %d failures" % [
		BAD_GRAFTS.size(), bad.size(), GOOD_GRAFTS.size(), good.size()])
	return out


# --- 10) mutator lint -----------------------------------------------------------

const MUTATOR_BOOL_KEYS := ["shop", "kit_ban", "draft_upgrades_only", "open_pool", "shop_reroll"]
const MUTATOR_ARRAY_KEYS := ["pool_ban"]


## Lints a MUTATORS-shaped table; failure strings start with the mutator id.
func _lint_mutators(muts: Dictionary) -> Array:
	var out: Array = []
	for mid in muts:
		var row = muts[mid]
		var where := "mutator %s" % str(mid)
		if not (row is Dictionary):
			out.append("%s: row is not a Dictionary" % where)
			continue
		for k in ["name", "desc"]:
			if not (row.get(k, null) is String) or String(row[k]).is_empty():
				out.append("%s: missing or empty %s" % [where, k])
		if not (row.get("config", null) is Dictionary):
			out.append("%s: missing config dict" % where)
			continue
		var cfg: Dictionary = row["config"]
		if cfg.is_empty():
			out.append("%s: empty config (a mutator must change something)" % where)
		for k in cfg:
			if not Content.MUTATOR_CONFIG_KEYS.has(k):
				out.append("%s: config key '%s' is not in MUTATOR_CONFIG_KEYS" % [where, str(k)])
				continue
			var v = cfg[k]
			if MUTATOR_ARRAY_KEYS.has(k):
				if not (v is Array) or v.is_empty():
					out.append("%s: config %s must be a non-empty Array" % [where, k])
				else:
					for aid in v:
						# Block D6: a variant id is "<base>+<word>", so the base
						# test is Content.is_upgrade, never ends_with("+")
						if not (aid is String) or not Content.ABILITIES.has(aid) or Content.is_upgrade(String(aid)):
							out.append("%s: config %s entry %s is not a base ability id" % [where, k, str(aid)])
			elif MUTATOR_BOOL_KEYS.has(k):
				if not (v is bool):
					out.append("%s: config %s must be a bool" % [where, k])
			elif not (v is int):
				out.append("%s: config %s must be an int" % [where, k])
		for k in row:
			if not ["name", "desc", "config"].has(k):
				out.append("%s: unknown row key '%s'" % [where, str(k)])
	return out


const BAD_MUTATORS := {
	"no_name": {"desc": "x", "config": {"kit_max": 3}},
	"no_desc": {"name": "x", "config": {"kit_max": 3}},
	"no_config": {"name": "x", "desc": "x"},
	"empty_config": {"name": "x", "desc": "x", "config": {}},
	"bad_key": {"name": "x", "desc": "x", "config": {"kit_cap": 3}},
	"float_value": {"name": "x", "desc": "x", "config": {"kit_max": 3.0}},
	"bool_as_int": {"name": "x", "desc": "x", "config": {"shop": 0}},
	"ban_not_array": {"name": "x", "desc": "x", "config": {"pool_ban": "solar_lance"}},
	"ban_unknown_id": {"name": "x", "desc": "x", "config": {"pool_ban": ["laser_lance"]}},
	"ban_plus_form": {"name": "x", "desc": "x", "config": {"pool_ban": ["solar_lance+noon"]}},
	"extra_row_key": {"name": "x", "desc": "x", "config": {"kit_max": 3}, "hooks": []},
}
const GOOD_MUTATORS := {
	"scalar": {"name": "x", "desc": "x", "config": {"kit_max": 4, "max_hp_delta": -1, "bank_cap": 0}},
	"flags": {"name": "x", "desc": "x", "config": {"shop": false, "draft_upgrades_only": true, "draft_offers": 5}},
	"ban": {"name": "x", "desc": "x", "config": {"pool_ban": ["solar_lance", "seed_bomb"], "kit_ban": true}},
}


func _lint_mutator_selftest() -> Array:
	var out: Array = []
	var bad: Array = _lint_mutators(BAD_MUTATORS)
	for mid in BAD_MUTATORS.keys():
		var hit := false
		for f in bad:
			if String(f).begins_with("mutator %s" % mid):
				hit = true
		if not hit:
			out.append("mutator lint self-test: bad fixture '%s' was accepted" % mid)
	var good: Array = _lint_mutators(GOOD_MUTATORS)
	for f in good:
		out.append("mutator lint self-test: good fixture rejected: %s" % f)
	print("mutator lint self-test: %d bad rows -> %d failures; %d good rows -> %d failures" % [
		BAD_MUTATORS.size(), bad.size(), GOOD_MUTATORS.size(), good.size()])
	return out


# --- 11) loadout lint -----------------------------------------------------------

const LOADOUT_ROW_KEYS := ["name", "desc", "kit", "protect", "requires"]
const LOADOUT_KIT_SIZE := 3


## Lints a LOADOUTS-shaped table; failure strings start with the loadout id.
## A row needs name, desc, a kit of exactly three known base ability ids with
## exactly one role == "mobility" id and seed_bomb among them, protect a
## subset of the kit, and requires.packages all known PACKAGES ids.
func _lint_loadouts(loadouts: Dictionary) -> Array:
	var out: Array = []
	for lid in loadouts:
		var row = loadouts[lid]
		var where := "loadout %s" % str(lid)
		if not (row is Dictionary):
			out.append("%s: row is not a Dictionary" % where)
			continue
		for k in ["name", "desc"]:
			if not (row.get(k, null) is String) or String(row[k]).is_empty():
				out.append("%s: missing or empty %s" % [where, k])
		var kit = row.get("kit", null)
		if not (kit is Array) or kit.size() != LOADOUT_KIT_SIZE:
			out.append("%s: kit must be an Array of %d ids, got %s" % [where, LOADOUT_KIT_SIZE, str(kit)])
			kit = [] if not (kit is Array) else kit
		var mobility := 0
		var seen := {}
		for aid in kit:
			if not (aid is String) or not Content.ABILITIES.has(aid):
				out.append("%s: kit id %s not in ABILITIES" % [where, str(aid)])
				continue
			if Content.base_id(aid) != aid:
				out.append("%s: kit id '%s' is a '+' form" % [where, aid])
			if seen.has(aid):
				out.append("%s: kit repeats '%s'" % [where, aid])
			seen[aid] = true
			if String(Content.ABILITIES[aid].get("role", "")) == "mobility":
				mobility += 1
		if mobility != 1:
			out.append("%s: kit holds %d mobility abilities, need exactly 1" % [where, mobility])
		if not kit.has("seed_bomb"):
			out.append("%s: kit lacks seed_bomb" % where)
		var protect = row.get("protect", null)
		if not (protect is Array):
			out.append("%s: protect must be an Array" % where)
		else:
			for aid in protect:
				if not kit.has(aid):
					out.append("%s: protect id %s is not in the kit" % [where, str(aid)])
		var req = row.get("requires", null)
		if not (req is Dictionary):
			out.append("%s: requires must be a Dictionary" % where)
		else:
			for k in req:
				if k != "packages":
					out.append("%s: unknown requires key '%s'" % [where, str(k)])
			var pkgs = req.get("packages", [])
			if not (pkgs is Array):
				out.append("%s: requires.packages must be an Array" % where)
			else:
				for pkg in pkgs:
					if not Content.PACKAGES.has(pkg):
						out.append("%s: required package '%s' not in PACKAGES" % [where, str(pkg)])
		for k in row:
			if not LOADOUT_ROW_KEYS.has(k):
				out.append("%s: unknown row key '%s'" % [where, str(k)])
	return out


const BAD_LOADOUTS := {
	"no_name": {"desc": "x", "kit": ["solar_lance", "seed_bomb", "mycelium_dash"], "protect": [], "requires": {}},
	"no_desc": {"name": "x", "kit": ["solar_lance", "seed_bomb", "mycelium_dash"], "protect": [], "requires": {}},
	"two_ids": {"name": "x", "desc": "x", "kit": ["seed_bomb", "mycelium_dash"], "protect": [], "requires": {}},
	"four_ids": {"name": "x", "desc": "x", "kit": ["solar_lance", "seed_bomb", "mycelium_dash", "vine_whip"], "protect": [], "requires": {}},
	"unknown_id": {"name": "x", "desc": "x", "kit": ["laser_lance", "seed_bomb", "mycelium_dash"], "protect": [], "requires": {}},
	"plus_form": {"name": "x", "desc": "x", "kit": ["solar_lance+noon", "seed_bomb", "mycelium_dash"], "protect": [], "requires": {}},
	"no_mobility": {"name": "x", "desc": "x", "kit": ["solar_lance", "seed_bomb", "vine_whip"], "protect": [], "requires": {}},
	"two_mobility": {"name": "x", "desc": "x", "kit": ["updraft", "seed_bomb", "mycelium_dash"], "protect": [], "requires": {}},
	"no_seed_bomb": {"name": "x", "desc": "x", "kit": ["solar_lance", "vine_whip", "mycelium_dash"], "protect": [], "requires": {}},
	"repeat_id": {"name": "x", "desc": "x", "kit": ["seed_bomb", "seed_bomb", "mycelium_dash"], "protect": [], "requires": {}},
	"protect_outside": {"name": "x", "desc": "x", "kit": ["solar_lance", "seed_bomb", "mycelium_dash"], "protect": ["vine_whip"], "requires": {}},
	"protect_not_array": {"name": "x", "desc": "x", "kit": ["solar_lance", "seed_bomb", "mycelium_dash"], "protect": "seed_bomb", "requires": {}},
	"no_requires": {"name": "x", "desc": "x", "kit": ["solar_lance", "seed_bomb", "mycelium_dash"], "protect": []},
	"bad_package": {"name": "x", "desc": "x", "kit": ["solar_lance", "seed_bomb", "mycelium_dash"], "protect": [], "requires": {"packages": ["alchemy"]}},
	"bad_requires_key": {"name": "x", "desc": "x", "kit": ["solar_lance", "seed_bomb", "mycelium_dash"], "protect": [], "requires": {"wins": 1}},
	"extra_row_key": {"name": "x", "desc": "x", "kit": ["solar_lance", "seed_bomb", "mycelium_dash"], "protect": [], "requires": {}, "hooks": []},
}
const GOOD_LOADOUTS := {
	"starter": {"name": "x", "desc": "x", "kit": ["solar_lance", "seed_bomb", "mycelium_dash"], "protect": ["mycelium_dash", "seed_bomb"], "requires": {}},
	"gated": {"name": "x", "desc": "x", "kit": ["gust", "seed_bomb", "updraft"], "protect": ["updraft"], "requires": {"packages": ["aeolian"]}},
	"bare": {"name": "x", "desc": "x", "kit": ["burrow", "seed_bomb", "tide"], "protect": [], "requires": {"packages": ["mycology", "hydraulics"]}},
}


func _lint_loadout_selftest() -> Array:
	var out: Array = []
	var bad: Array = _lint_loadouts(BAD_LOADOUTS)
	for lid in BAD_LOADOUTS.keys():
		var hit := false
		for f in bad:
			if String(f).begins_with("loadout %s" % lid):
				hit = true
		if not hit:
			out.append("loadout lint self-test: bad fixture '%s' was accepted" % lid)
	var good: Array = _lint_loadouts(GOOD_LOADOUTS)
	for f in good:
		out.append("loadout lint self-test: good fixture rejected: %s" % f)
	print("loadout lint self-test: %d bad rows -> %d failures; %d good rows -> %d failures" % [
		BAD_LOADOUTS.size(), bad.size(), GOOD_LOADOUTS.size(), good.size()])
	return out


# --- 12) Block D3: enemies read terrain -----------------------------------------

## Every TERRAIN_BOOL_KEYS key present on a row must be a bool: Game reads them
## through bool(), where a stray 1 or "true" would pass silently.
func _lint_terrain_bools(kind: String, row: Dictionary) -> Array:
	var out: Array = []
	for key in TERRAIN_BOOL_KEYS:
		if row.has(key) and not (row[key] is bool):
			out.append("TERRAIN %s: '%s' must be a bool, got %s" % [kind, key, str(row[key])])
	return out


## An ENEMIES-shaped table: "avoid", when present, is an Array of TERRAIN kinds
## (closed vocabulary - Game._chase_step compares it with _terrain_kind), with
## no duplicates. Failure strings start with the enemy kind.
func _lint_enemy_avoid(enemies: Dictionary) -> Array:
	var out: Array = []
	for kind in enemies:
		var row: Dictionary = enemies[kind]
		if not row.has("avoid"):
			continue
		if not (row["avoid"] is Array):
			out.append("%s: avoid must be an Array of TERRAIN kinds, got %s" % [kind, str(row["avoid"])])
			continue
		var seen := {}
		for k in row["avoid"]:
			if not (k is String) or not Content.TERRAIN.has(k):
				out.append("%s: avoid kind '%s' not in TERRAIN" % [kind, str(k)])
			elif seen.has(k):
				out.append("%s: avoid lists '%s' twice" % [kind, str(k)])
			seen[k] = true
	return out


## ENEMY_AVOID_COST: an int >= 1 (0 would make the avoid lists dead data, a
## float would break the integer bucket queue).
func _lint_avoid_cost(cost) -> Array:
	if not (cost is int) or int(cost) < 1:
		return ["ENEMY_AVOID_COST: must be an int >= 1, got %s" % str(cost)]
	return []


## SCREENED_INTENTS: a non-empty Array whose entries are INTENT_TYPES, no
## duplicates (Game._screened reads it as a set of intent types).
func _lint_screened_intents(list) -> Array:
	var out: Array = []
	if not (list is Array) or list.is_empty():
		return ["SCREENED_INTENTS: must be a non-empty Array of intent types, got %s" % str(list)]
	var seen := {}
	for it in list:
		if not (it is String) or not INTENT_TYPES.has(it):
			out.append("SCREENED_INTENTS: '%s' is not an enemy intent type" % str(it))
		elif seen.has(it):
			out.append("SCREENED_INTENTS: '%s' listed twice" % str(it))
		seen[it] = true
	return out


## Enemy rows the avoid lint MUST reject, one violation each (the id prefixes
## the failure), plus one row it must accept.
const BAD_ENEMY_ROWS := {
	"za_avoid_not_array": {"name": "x", "hp": 1, "dmg": 1, "slow": false, "traits": [], "avoid": "fire"},
	"zb_avoid_unknown_kind": {"name": "x", "hp": 1, "dmg": 1, "slow": false, "traits": [], "avoid": ["lava"]},
	"zc_avoid_not_string": {"name": "x", "hp": 1, "dmg": 1, "slow": false, "traits": [], "avoid": [3]},
	"zd_avoid_duplicate": {"name": "x", "hp": 1, "dmg": 1, "slow": false, "traits": [], "avoid": ["fire", "fire"]},
}
const GOOD_ENEMY_ROWS := {
	"ya_avoid_two": {"name": "x", "hp": 1, "dmg": 1, "slow": false, "traits": [], "avoid": ["fire", "goo"]},
	"yb_avoid_absent": {"name": "x", "hp": 1, "dmg": 1, "slow": false, "traits": []},
	"yc_avoid_empty": {"name": "x", "hp": 1, "dmg": 1, "slow": false, "traits": [], "avoid": []},
}
## TERRAIN rows whose "screens" is the wrong shape (the row id prefixes the failure).
const BAD_TERRAIN_SCREENS := {
	"xa_screens_int": {"screens": 1},
	"xb_screens_string": {"screens": "true"},
}


## The D3 lint checking itself: every bad fixture named by a failure, every
## good one clean; the cost and the intent list rejected in each bad shape.
func _lint_d3_selftest() -> Array:
	var out: Array = []
	var bad: Array = _lint_enemy_avoid(BAD_ENEMY_ROWS)
	for kind in BAD_ENEMY_ROWS.keys():
		var caught := false
		for f in bad:
			if String(f).begins_with(String(kind)):
				caught = true
		if not caught:
			out.append("d3 lint self-test: bad enemy fixture '%s' was accepted" % kind)
	var good: Array = _lint_enemy_avoid(GOOD_ENEMY_ROWS)
	for f in good:
		out.append("d3 lint self-test: good enemy fixture rejected: %s" % f)
	var bad_screens := 0
	for kind in BAD_TERRAIN_SCREENS.keys():
		var fails: Array = _lint_terrain_bools(kind, BAD_TERRAIN_SCREENS[kind])
		if fails.is_empty():
			out.append("d3 lint self-test: bad terrain fixture '%s' was accepted" % kind)
		else:
			bad_screens += fails.size()
	if not _lint_terrain_bools("good", {"screens": true}).is_empty():
		out.append("d3 lint self-test: screens true rejected")
	var bad_costs: Array = [0, -1, 2.5, "4", null]
	var cost_fails := 0
	for c in bad_costs:
		if _lint_avoid_cost(c).is_empty():
			out.append("d3 lint self-test: avoid cost %s was accepted" % str(c))
		else:
			cost_fails += 1
	if not _lint_avoid_cost(1).is_empty() or not _lint_avoid_cost(4).is_empty():
		out.append("d3 lint self-test: a legal avoid cost was rejected")
	var bad_lists: Array = [[], ["gum", "melt"], ["gum", "gum"], "gum", [7]]
	var list_fails := 0
	for l in bad_lists:
		if _lint_screened_intents(l).is_empty():
			out.append("d3 lint self-test: screened intents %s were accepted" % str(l))
		else:
			list_fails += 1
	if not _lint_screened_intents(["drain", "gum", "drag"]).is_empty():
		out.append("d3 lint self-test: the shipped SCREENED_INTENTS shape was rejected")
	print("d3 lint self-test: %d bad enemy rows -> %d failures; %d good rows -> %d failures; %d bad screens -> %d; %d bad costs -> %d; %d bad intent lists -> %d" % [
		BAD_ENEMY_ROWS.size(), bad.size(), GOOD_ENEMY_ROWS.size(), good.size(),
		BAD_TERRAIN_SCREENS.size(), bad_screens, bad_costs.size(), cost_fails, bad_lists.size(), list_fails])
	return out


# --- 13) Block D4 draft slot lint ---------------------------------------------

## DRAFT_SLOTS: a non-empty Array whose entries are `roles` (the closed role
## set Game._draw_draft_offers dispatches on). Duplicates are legal - two
## affinity slots is the named lever.
func _lint_draft_slots(slots, roles) -> Array:
	if not (slots is Array) or slots.is_empty():
		return ["DRAFT_SLOTS: must be a non-empty Array of slot roles, got %s" % str(slots)]
	var out: Array = []
	for i in slots.size():
		var r = slots[i]
		if not (r is String) or not (roles is Array) or not roles.has(r):
			out.append("DRAFT_SLOTS: slot %d role '%s' not in DRAFT_SLOT_ROLES" % [i, str(r)])
	return out


## A closed name list (DRAFT_SLOT_ROLES, DRAFT_SLOT_REPORTS): non-empty
## Array of non-empty Strings, no duplicates.
func _lint_name_list(label: String, list) -> Array:
	if not (list is Array) or list.is_empty():
		return ["%s: must be a non-empty Array of names, got %s" % [label, str(list)]]
	var out: Array = []
	var seen := {}
	for n in list:
		if not (n is String) or String(n).is_empty():
			out.append("%s: entry '%s' is not a non-empty String" % [label, str(n)])
		elif seen.has(n):
			out.append("%s: '%s' listed twice" % [label, str(n)])
		seen[n] = true
	return out


## AFFINITY_IGNORED_TAGS: an Array (empty is legal: nothing ignored) of
## distinct `tags` entries, and never all of them - the list says which tags
## do NOT define a build, so a list covering the whole vocabulary means no
## ability defines one, which empties the affinity set and the upgrade list
## on every run and degrades both build-steering slots to wild without any
## other symptom.
func _lint_ignored_tags(list, tags) -> Array:
	if not (list is Array):
		return ["AFFINITY_IGNORED_TAGS: must be an Array of TAGS entries, got %s" % str(list)]
	var out: Array = []
	var seen := {}
	for t in list:
		if not (t is String) or not (tags is Array) or not tags.has(t):
			out.append("AFFINITY_IGNORED_TAGS: '%s' not in TAGS" % str(t))
		elif seen.has(t):
			out.append("AFFINITY_IGNORED_TAGS: '%s' listed twice" % str(t))
		seen[t] = true
	if tags is Array and not tags.is_empty() and seen.size() == tags.size():
		out.append("AFFINITY_IGNORED_TAGS: ignores every TAGS entry, so nothing defines a build")
	return out


## Does `aid` define a build? The reference reading of AFFINITY_IGNORED_TAGS,
## kept here in the lint rather than called out of the sim: any tag outside
## the ignored list. Game._build_defining must agree with it (the D4 checks in
## tests/test_grammar.gd pin the sim side).
func _defines_build(aid: String) -> bool:
	for t in Content.ABILITIES.get(Content.base_id(aid), {}).get("tags", []):
		if not Content.AFFINITY_IGNORED_TAGS.has(t):
			return true
	return false


## Every LOADOUTS kit holds at least one build-defining ability. A kit that
## did not would start with an empty affinity set AND an all-ignored upgrade
## list, so both build-steering slots would roll wild for the whole run - the
## degenerate case AFFINITY_IGNORED_TAGS can cause by growing.
func _lint_loadout_affinity() -> Array:
	var out: Array = []
	var defining := 0
	for lid in Content.LOADOUTS:
		var any := false
		for aid in Content.LOADOUTS[lid].get("kit", []):
			if _defines_build(String(aid)):
				any = true
				break
		if any:
			defining += 1
		else:
			out.append("LOADOUTS '%s': no kit ability defines a build (every tag is in AFFINITY_IGNORED_TAGS)" % str(lid))
	print("loadout affinity: %d / %d kits hold a build-defining ability" % [defining, Content.LOADOUTS.size()])
	return out


## Fixtures the D4 lint MUST reject, one shape each, and the ones it must accept.
const BAD_DRAFT_SLOTS := {
	"empty": [],
	"not_array": "affinity",
	"unknown_role": ["affinity", "upgrade", "wild"],
	"not_string": ["affinity", 2],
	"report_as_role": ["focus"],
}
const GOOD_DRAFT_SLOTS := {
	"shipped": ["affinity", "upgrade_or_affinity", "wild"],
	"one_wild": ["wild"],
	"two_affinity": ["affinity", "affinity", "wild"],
}
const BAD_NAME_LISTS := {
	"empty": [],
	"not_array": "wild",
	"empty_string": ["wild", ""],
	"not_string": ["wild", 1],
	"duplicate": ["wild", "wild"],
}
const BAD_IGNORED_TAGS := {
	"not_array": "mobility",
	"unknown_tag": ["lava"],
	"not_string": [3],
	"duplicate": ["mobility", "mobility"],
}
const GOOD_IGNORED_TAGS := {
	"shipped": ["mobility"],
	"none": [],
	"two": ["mobility", "economy"],
}


## The D4 lint checking itself: every bad fixture rejected, every good one clean.
func _lint_d4_selftest() -> Array:
	var out: Array = []
	var bad_slots := 0
	for k in BAD_DRAFT_SLOTS:
		var fails: Array = _lint_draft_slots(BAD_DRAFT_SLOTS[k], Content.DRAFT_SLOT_ROLES)
		if fails.is_empty():
			out.append("d4 lint self-test: bad DRAFT_SLOTS fixture '%s' was accepted" % k)
		else:
			bad_slots += 1
	for k in GOOD_DRAFT_SLOTS:
		for f in _lint_draft_slots(GOOD_DRAFT_SLOTS[k], Content.DRAFT_SLOT_ROLES):
			out.append("d4 lint self-test: good DRAFT_SLOTS fixture '%s' rejected: %s" % [k, f])
	var bad_lists := 0
	for k in BAD_NAME_LISTS:
		if _lint_name_list("fixture", BAD_NAME_LISTS[k]).is_empty():
			out.append("d4 lint self-test: bad name list fixture '%s' was accepted" % k)
		else:
			bad_lists += 1
	if not _lint_name_list("fixture", ["affinity", "wild"]).is_empty():
		out.append("d4 lint self-test: a legal name list was rejected")
	var bad_tags := 0
	var bad_ignored: Dictionary = BAD_IGNORED_TAGS.duplicate()
	# built here rather than as a const: it is TAGS itself
	bad_ignored["ignores_everything"] = Content.TAGS.duplicate()
	for k in bad_ignored:
		if _lint_ignored_tags(bad_ignored[k], Content.TAGS).is_empty():
			out.append("d4 lint self-test: bad AFFINITY_IGNORED_TAGS fixture '%s' was accepted" % k)
		else:
			bad_tags += 1
	for k in GOOD_IGNORED_TAGS:
		for f in _lint_ignored_tags(GOOD_IGNORED_TAGS[k], Content.TAGS):
			out.append("d4 lint self-test: good AFFINITY_IGNORED_TAGS fixture '%s' rejected: %s" % [k, f])
	print("d4 lint self-test: %d bad slot lists -> %d rejected; %d good -> clean; %d bad name lists -> %d; %d bad ignored-tag lists -> %d; %d good -> clean" % [
		BAD_DRAFT_SLOTS.size(), bad_slots, GOOD_DRAFT_SLOTS.size(), BAD_NAME_LISTS.size(), bad_lists,
		bad_ignored.size(), bad_tags, GOOD_IGNORED_TAGS.size()])
	return out
