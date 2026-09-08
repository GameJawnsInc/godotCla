extends RefCounted
const Content := preload("res://sim/content.gd")
## Event tally for bot runs (review §7.1): fed every event game.step()
## returns inside Sweep.run_loop, plus begin_step/end_step hooks for
## before/after state (bloom deltas, shrine turns, unspent charge, clock
## stalls). Ability ids are normalised to their base id (Content.base_id);
## plus-form casts are counted separately in plus_casts. Pure bookkeeping: it
## never touches the game, so feeding it cannot change a run.
## Since Block C1a it also counts effect-grammar rider events (per / bonus /
## then), which feed the combo rate alongside ignite / verdant / stagger, and
## since Block D1 the stat surges ({"t": "surge"}) and the tiles a plant_origin
## op leaves behind. Neither moves the combo rate: every surge is already one
## `verdant`, so counting it again would double it.
## Block D2 adds the shrine reroll columns - spins taken, the bloom they cost,
## buys made off an already-spun counter - and the bloom a run ends still
## holding, which is the number a repeatable sink is supposed to shrink.
## Block D3 adds the two terrain-denial columns: the enemy intents a smoke
## screen swallowed ({"t": "screened"}) by intent type, and the fire damage
## enemies walked into, which is what the rows' avoid lists are meant to shrink.
## Block D6 adds the two per-VARIANT columns - casts_by_id and
## effective_casts_by_id, keyed by the full "<base>+<variant>" id - because
## every other per-ability table here folds a fork's two siblings onto one base
## key, and "no strictly dominated sibling" cannot be read off a folded column.
## Block D4 adds the draft-slot columns: every offer and every pick counted by
## the slot role that produced it (the draft_offer event's "slots" array), plus
## the drafts a skipped draft focused. That is the affinity draft's own metric -
## how often a build-matching slot is what the player actually takes.

# --- actions ------------------------------------------------------------------
var casts_by_base := {}
## Block D6 per-VARIANT counters, keyed by the FULL cast id
## ("grow_spike+impale", not "grow_spike"). casts_by_base folds the two
## siblings of a fork onto one key, which would make them indistinguishable in
## the very instrument the "no strictly dominated sibling" gate reads; these
## two are the split. effective_casts_by_id is the sim's OWN effectiveness
## rule, not a re-derivation: end_step diffs game.effective_uses (base-keyed)
## across the step and attributes the increment to the id the "ability" event
## named, so a cast counts here exactly when the sim counted it.
var casts_by_id := {}
var effective_casts_by_id := {}
var plus_casts := 0
var strikes := 0
var cleanses := 0
var moves := 0
var end_turns := 0
var end_turn_count := 0  # same count as end_turns; the denominator of unspent_charge_total

# --- drafts -------------------------------------------------------------------
var drafts := 0  # draft_offer events
var drafts_with_plus := 0  # drafts with at least one "+" offer
var offers_by_id := {}
var picks_by_id := {}
var upgrades := 0
var skips := 0
var drops_by_id := {}
## Block D4 draft slots: which role rolled each offer ("affinity" / "upgrade" /
## "wild" / "focus", a Content.DRAFT_SLOT_REPORTS entry) and which role the
## taken offer came from. picks_by_slot is read against offers_by_slot as a
## per-role pick rate - the number the affinity draft is measured by. An offer
## whose draft carried no "slots" key (a pre-D4 event) counts as "unknown", so
## a wiring break shows up as a column instead of as silence.
var offers_by_slot := {}
var picks_by_slot := {}
## Drafts rolled with focus armed (the draft_offer event's "focus" flag): the
## drafts a previous skip paid for. Read against `skips`, which is what arms it.
var focus_drafts := 0

# --- shrine and items ---------------------------------------------------------
var buys_by_kind := {}
var grafts_by_id := {}
var ability_buys_by_id := {}
var upcycles := 0
var upcycle_abilities := 0
var item_uses_by_id := {}
var item_pickups := 0
var satchel_full := 0
var graft_discards := 0  # graft buys that threw the second offer away
## Bloom paid for grafts, at each offer's own price (Content.GRAFTS "price"
## plus the per-graft-owned step and the tier markup) - the graft half of
## bloom_spent, so a pass that reprices grafts can be read off directly.
var bloom_spent_on_grafts := 0
## Shrine rerolls (Block D2): spins taken, the bloom they cost (the event
## carries its own price, which escalates per spin), and the buys made on a
## counter that had already been spun at least once - the sink's payoff half,
## read off the live game.shop at the buy event.
var rerolls := 0
var bloom_spent_on_rerolls := 0
var buys_after_reroll := 0

# --- economy ------------------------------------------------------------------
var bloom_earned := 0
var bloom_spent := 0
var shrine_turns := 0  # end_turn taken while standing on the shrine
## Bloom still in the purse when the run ended (summed over runs): the bloom
## the run never converted into anything, which is what a repeatable sink is
## meant to shrink. Per run it is the same number the persona line prints as
## "avg bloom" (Sweep's bloom_end); it lives here so kpis()/merge() carry it
## beside the reroll columns it is read against.
var bloom_unspent := 0
var unspent_charge_total := 0  # sum of player charge at each end_turn

# --- combo counters -----------------------------------------------------------
var ignite_ability := 0  # ignite events inside an "ability" step
var ignite_env := 0  # ignite events in any other step (environment spread, enemies)
var verdant := 0
var staggered := 0
var collision_hits := 0
var thorns_hits := 0
var fire_hits_enemy := 0
var fire_dmg_player := 0
var spore_ticks := 0
var convert := 0
var wash := 0
var room_bloom := 0
var floor_restored := 0
var seal_burst := 0
var growth_heal_hp := 0
var shield_absorb_hp := 0
## Rider events ({"t": "rider", id, kind, amt}) by kind (per / bonus / then)
## and by casting ability id. Unlike casts_by_base these keep the raw id, so a
## rider only the "+" form carries stays visible (as collision_by_aid does).
var riders_by_kind := {}
var riders_by_aid := {}
## Verdant surges that carried a stat delta ({"t": "surge", id, keys}), by
## casting ability id (Block D1). Like riders_by_aid these keep the raw id, so
## a surge only the "+" form carries stays visible. The cost half of a surge
## emits no event of its own: the tile consumption is the `verdant` count
## above, which counts every surge, stat or discount.
var surges_by_aid := {}
## Tiles planted by a plant_origin op (Spore Trail), by casting ability id:
## terrain written on the tile the cast departed from. Counted by watching the
## terrain events of a cast whose row carries the op, so no ability id is named
## here either.
var origin_plants_by_aid := {}

# --- terrain / status bookkeeping (Block C1b) ---------------------------------
## Fires that burnt out into ash ({"t": "ash", tile}); every one leaves a
## corruption tile behind, so ash_events is also "quota the fire handed back".
var ash_events := 0
## Which corruption kind each cleanse removed, from the cleanse event's "kind".
var cleanses_by_kind := {}
## Status applications refused by a Content.STATUSES cooldown ({"t": "resisted"}).
var resisted_events := 0
## Status applications that landed, by status name. Stacking is invisible in
## the event itself (the sim reports the applied turns, not the total), so a
## second spore on the same enemy shows up here as a second "spore".
var status_by_kind := {}

# --- terrain denial (Block D3) -------------------------------------------------
## Enemy intents a smoke screen swallowed ({"t": "screened", id, intent}), by
## intent type (a Content.SCREENED_INTENTS entry). One count per fizzled
## action: the intent was still computed and telegraphed, so this is the number
## of enemy turns the player bought with terrain instead of with damage.
var screened_by_intent := {}

# --- graft hooks (Block C3) ---------------------------------------------------
## Hook rows that ran ({"t": "hook", id, on, tile}), by source id (the graft or
## ability row that owns the hook) and by hook kind (the event that fired it).
## One count per row that ran, so a row carrying three effects still counts once.
var hooks_by_graft := {}
var hooks_by_kind := {}
## Hooks skipped by Content.HOOK_DEPTH_MAX / HOOK_STEP_CAP ({"t": "hook_capped"});
## the sim emits that at most once per step, so this counts steps that hit a cap.
var hook_capped := 0
## Oil Tithe discounts that actually applied ({"t": "tithe", id}) - at most one
## per turn while the graft is held.
var tithes := 0

# --- damage by raw source string ---------------------------------------------
var enemy_dmg_by_src := {}
var player_dmg_by_src := {}
var kills_by_kind := {}  # enemy death events by kind
## Bump-2 attribution: enemy fire damage by igniter ("fire:x" -> x, "env" when
## unattributed) and enemy collision damage by the casting ability id.
var fire_dmg_by_by := {}
var collision_by_aid := {}

# --- errors and clock ---------------------------------------------------------
var illegal := 0  # {"t": "illegal"} plus {"t": "error"} events
var smog_at_descend: Array = []
var turns_per_floor: Array = []
var stall_floors := 0  # floors with turn > 60 or smog > choke + 30 at any point
var quota_unmet_at_death := false  # this run (or any merged run) died with greened < green_need
var quota_unmet_deaths := 0
var quota_reclamps := 0  # green gates that shrank because corruption vanished uncleansed
var runs := 0  # runs finished into this tally (finish() increments, merge() sums)

# step-scoped state from begin_step
var _bloom0 := 0
var _pos0 := Vector2i.ZERO
var _charge0 := 0
var _floor0 := 0
var _stall_flagged := false
var _choke_floor := -1  # floor_def() deep-copies a table: cache choke per floor
var _choke := 0
## The cast currently being watched for a plant_origin terrain event, and the
## kinds its plant_origin ops write: set on the "ability" event, cleared as
## soon as one matching terrain event on the departure tile is counted (a cast
## plants its origin at most once) and on the next cast / step.
var _origin_aid := ""
var _origin_kinds: Array = []
## The full id of the ability cast in the step being tallied ("" for a step
## that cast none), and game.effective_uses as it stood before the step: the
## pair that attributes an effective cast to a variant.
var _cast_aid := ""
var _eff0 := {}
## The open draft's offer id -> slot role, rebuilt at every draft_offer: the
## pick events name an ability, not an index, and a draft never offers the same
## id twice (Block D4), so the id is enough to attribute the pick to its slot.
var _slot_by_offer := {}


## Ability/source id folded onto its base. Content.base_id, NEVER
## trim_suffix("+"): since Block D6 an upgrade id is "<base>+<variant>"
## ("grow_spike+impale"), which trim_suffix returns UNCHANGED - every
## per-ability table here routes through this call, so the old form would have
## split each base into three silent columns.
static func base_id(aid: String) -> String:
	return Content.base_id(aid)


## Damage-source family: the part before ":". Since bump 2 the enemy-side
## sources carry attribution as "family:detail" - "fire:<igniter>" (the
## casting ability id, the enemy kind, or "env") and "collision:<ability id>".
static func src_family(src: String) -> String:
	var i := src.find(":")
	return src if i < 0 else src.substr(0, i)


## The attribution half of a bump-2 source string; "env" when it carries none
## (a fire tile with no igniter, or a pre-bump source string).
static func src_detail(src: String) -> String:
	var i := src.find(":")
	return "env" if i < 0 else src.substr(i + 1)


## Terrain kinds a cast of `aid` can write on the tile it departs from: the
## "kind" of every plant_origin op on the row (Block D1, Spore Trail). Empty
## for every other row, which is what keeps the origin-plant counter from
## catching ordinary planting.
static func _origin_plant_kinds(aid: String) -> Array:
	var adef: Dictionary = Content.ABILITIES.get(aid, {})
	var kinds: Array = []
	for eff in adef.get("effects", []):
		if String(eff.get("op", "")) == "plant_origin":
			kinds.append(String(eff.get("kind", "")))
		for sub in eff.get("then", []):
			if String(sub.get("op", "")) == "plant_origin":
				kinds.append(String(sub.get("kind", "")))
	return kinds


static func _inc(d: Dictionary, k, amt: int = 1) -> void:
	d[k] = int(d.get(k, 0)) + amt


func begin_step(game) -> void:
	_origin_aid = ""
	_origin_kinds = []
	_cast_aid = ""
	_eff0 = game.effective_uses.duplicate()
	_bloom0 = game.bloom
	_pos0 = game.player["pos"]
	_charge0 = game.player["charge"]
	_floor0 = game.floor_num


## Called on every event returned by game.step(action).
func add(ev: Dictionary, action: Dictionary, game) -> void:
	var t := String(ev.get("t", ""))
	match t:
		"ability":
			var aid := String(ev.get("id", ""))
			_inc(casts_by_base, base_id(aid))
			_inc(casts_by_id, aid)
			_cast_aid = aid
			if Content.is_upgrade(aid):
				plus_casts += 1
			_origin_aid = aid
			_origin_kinds = _origin_plant_kinds(aid)
		"strike":
			strikes += 1
		"cleanse":
			cleanses += 1
			_inc(cleanses_by_kind, String(ev.get("kind", "")))
		"move":
			if String(ev.get("who", "player")) == "player":
				moves += 1
		"draft_offer":
			drafts += 1
			if bool(ev.get("focus", false)):
				focus_drafts += 1
			var slots: Array = ev.get("slots", [])
			var offers: Array = ev.get("offers", [])
			_slot_by_offer = {}
			var any_plus := false
			for i in offers.size():
				var oid := String(offers[i])
				_inc(offers_by_id, oid)
				var role := String(slots[i]) if i < slots.size() else "unknown"
				_inc(offers_by_slot, role)
				_slot_by_offer[oid] = role
				if Content.is_upgrade(oid):
					any_plus = true
			if any_plus:
				drafts_with_plus += 1
		"draft_pick":
			var pid := String(ev.get("id", ""))
			_inc(picks_by_id, pid)
			_inc(picks_by_slot, String(_slot_by_offer.get(pid, "unknown")))
		"draft_upgrade":
			upgrades += 1
		"draft_skip":
			skips += 1
		"draft_drop":
			_inc(drops_by_id, String(ev.get("id", "")))
		"buy":
			var kind := String(ev.get("item", ""))
			_inc(buys_by_kind, kind)
			# the stock this buy came off: a spun counter still carries its
			# reroll count (a buy erases only its own slot), so the live shop
			# says whether the sink paid for itself
			if int(game.shop.get("rerolls", 0)) > 0:
				buys_after_reroll += 1
			if kind == "graft":
				var gid := String(ev.get("id", ""))
				_inc(grafts_by_id, gid)
				# what it cost: the sim prices a graft from its own row plus a
				# step per graft owned, and this buy has already added itself
				# to the pile, so ask the live game and take that step back off
				bloom_spent_on_grafts += maxi(
					int(game.shop_cost("graft", gid)) - Content.GRAFT_PRICE_STEP, 0)
				if String(ev.get("discarded", "")) != "":
					graft_discards += 1
			elif kind == "ability":
				_inc(ability_buys_by_id, String(ev.get("id", "")))
		"reroll":
			rerolls += 1
			bloom_spent_on_rerolls += int(ev.get("cost", 0))
		"upcycle":
			upcycles += 1
		"upcycle_ability":
			upcycle_abilities += 1
		"item_use":
			_inc(item_uses_by_id, String(ev.get("id", "")))
		"item_pickup":
			item_pickups += 1
		"satchel_full":
			satchel_full += 1
		"ignite":
			if String(action.get("type", "")) == "ability":
				ignite_ability += 1
			else:
				ignite_env += 1
		"verdant":
			verdant += 1
		"surge":
			_inc(surges_by_aid, String(ev.get("id", "")))
		"terrain":
			# Spore Trail: a plant_origin op writes its kind on the tile the
			# cast departed from - which is where the player stood when this
			# step began (_pos0), so a hook planting elsewhere never counts
			if _origin_aid != "" and ev.get("tile", null) == _pos0 \
					and _origin_kinds.has(String(ev.get("kind", ""))):
				_inc(origin_plants_by_aid, _origin_aid)
				_origin_aid = ""
				_origin_kinds = []
		"staggered":
			staggered += 1
		"convert":
			convert += 1
		"wash":
			wash += 1
		"room_bloom":
			room_bloom += 1
		"floor_restored":
			floor_restored += 1
		"seal_burst":
			seal_burst += 1
		"ash":
			ash_events += 1
		"resisted":
			resisted_events += 1
		"status":
			_inc(status_by_kind, String(ev.get("status", "")))
		"screened":
			_inc(screened_by_intent, String(ev.get("intent", "")))
		"hook":
			_inc(hooks_by_graft, String(ev.get("id", "")))
			_inc(hooks_by_kind, String(ev.get("on", "")))
		"hook_capped":
			hook_capped += 1
		"tithe":
			tithes += 1
		"heal":
			growth_heal_hp += int(ev.get("amt", 0))
		"shield_absorb":
			shield_absorb_hp += int(ev.get("amt", 0))
		"rider":
			_inc(riders_by_kind, String(ev.get("kind", "")))
			_inc(riders_by_aid, String(ev.get("id", "")))
		"damage":
			_add_damage(ev)
		"death":
			_inc(kills_by_kind, String(ev.get("who", "")))
		"quota_reclamp":
			quota_reclamps += 1
		"illegal", "error":
			illegal += 1
		"descend":
			smog_at_descend.append(game.smog)
			turns_per_floor.append(game.turn)


func _add_damage(ev: Dictionary) -> void:
	var src := String(ev.get("src", ""))
	var amt := int(ev.get("amt", 0))
	var fam := src_family(src)
	if String(ev.get("who", "")) == "player":
		_inc(player_dmg_by_src, src, amt)
		if fam == "fire":
			fire_dmg_player += amt
		return
	_inc(enemy_dmg_by_src, src, amt)
	match fam:
		"collision":
			collision_hits += 1
			_inc(collision_by_aid, src_detail(src), amt)
		"thorns":
			thorns_hits += 1
		"fire":
			fire_hits_enemy += 1
			_inc(fire_dmg_by_by, src_detail(src), amt)
		"spore":
			spore_ticks += 1


func end_step(game, action: Dictionary) -> void:
	# effective casts, per variant: the sim increments effective_uses[base] when
	# a cast actually did something (an outcome fired or a rider ran). One step
	# is at most one cast, so the base's delta belongs to the id just cast.
	if _cast_aid != "":
		var b := base_id(_cast_aid)
		var d: int = int(game.effective_uses.get(b, 0)) - int(_eff0.get(b, 0))
		if d > 0:
			_inc(effective_casts_by_id, _cast_aid, d)
	var delta: int = game.bloom - _bloom0
	if delta > 0:
		bloom_earned += delta
	elif delta < 0:
		bloom_spent -= delta
	if String(action.get("type", "")) == "end_turn":
		end_turns += 1
		end_turn_count += 1
		unspent_charge_total += _charge0
		if _pos0 == game.map.get("shrine", Vector2i(-99, -99)):
			shrine_turns += 1
	if game.floor_num != _floor0:
		_stall_flagged = false
	if not _stall_flagged and not game.over:
		if _choke_floor != game.floor_num:
			_choke_floor = game.floor_num
			_choke = int(game.floor_def(game.floor_num).get("smog_choke", 0))
		if game.turn > 60 or (_choke > 0 and game.smog > _choke + 30):
			_stall_flagged = true
			stall_floors += 1


## Called once when the run loop exits (win, death, or cap).
func finish(game) -> void:
	turns_per_floor.append(game.turn)
	runs += 1
	bloom_unspent += game.bloom
	_choke_floor = -1
	_stall_flagged = false
	if game.over and not game.won and game.greened < game.green_need:
		quota_unmet_at_death = true
		quota_unmet_deaths += 1


func merge(other) -> void:
	_merge_dict(casts_by_base, other.casts_by_base)
	_merge_dict(casts_by_id, other.casts_by_id)
	_merge_dict(effective_casts_by_id, other.effective_casts_by_id)
	plus_casts += other.plus_casts
	strikes += other.strikes
	cleanses += other.cleanses
	moves += other.moves
	end_turns += other.end_turns
	end_turn_count += other.end_turn_count
	drafts += other.drafts
	drafts_with_plus += other.drafts_with_plus
	_merge_dict(offers_by_id, other.offers_by_id)
	_merge_dict(picks_by_id, other.picks_by_id)
	_merge_dict(offers_by_slot, other.offers_by_slot)
	_merge_dict(picks_by_slot, other.picks_by_slot)
	focus_drafts += other.focus_drafts
	upgrades += other.upgrades
	skips += other.skips
	_merge_dict(drops_by_id, other.drops_by_id)
	_merge_dict(buys_by_kind, other.buys_by_kind)
	_merge_dict(grafts_by_id, other.grafts_by_id)
	_merge_dict(ability_buys_by_id, other.ability_buys_by_id)
	upcycles += other.upcycles
	upcycle_abilities += other.upcycle_abilities
	_merge_dict(item_uses_by_id, other.item_uses_by_id)
	item_pickups += other.item_pickups
	satchel_full += other.satchel_full
	graft_discards += other.graft_discards
	bloom_spent_on_grafts += other.bloom_spent_on_grafts
	rerolls += other.rerolls
	bloom_spent_on_rerolls += other.bloom_spent_on_rerolls
	buys_after_reroll += other.buys_after_reroll
	bloom_earned += other.bloom_earned
	bloom_spent += other.bloom_spent
	bloom_unspent += other.bloom_unspent
	shrine_turns += other.shrine_turns
	unspent_charge_total += other.unspent_charge_total
	ignite_ability += other.ignite_ability
	ignite_env += other.ignite_env
	verdant += other.verdant
	staggered += other.staggered
	collision_hits += other.collision_hits
	thorns_hits += other.thorns_hits
	fire_hits_enemy += other.fire_hits_enemy
	fire_dmg_player += other.fire_dmg_player
	spore_ticks += other.spore_ticks
	convert += other.convert
	wash += other.wash
	room_bloom += other.room_bloom
	floor_restored += other.floor_restored
	seal_burst += other.seal_burst
	growth_heal_hp += other.growth_heal_hp
	shield_absorb_hp += other.shield_absorb_hp
	_merge_dict(riders_by_kind, other.riders_by_kind)
	_merge_dict(riders_by_aid, other.riders_by_aid)
	_merge_dict(surges_by_aid, other.surges_by_aid)
	_merge_dict(origin_plants_by_aid, other.origin_plants_by_aid)
	ash_events += other.ash_events
	_merge_dict(cleanses_by_kind, other.cleanses_by_kind)
	resisted_events += other.resisted_events
	_merge_dict(status_by_kind, other.status_by_kind)
	_merge_dict(screened_by_intent, other.screened_by_intent)
	_merge_dict(hooks_by_graft, other.hooks_by_graft)
	_merge_dict(hooks_by_kind, other.hooks_by_kind)
	hook_capped += other.hook_capped
	tithes += other.tithes
	_merge_dict(enemy_dmg_by_src, other.enemy_dmg_by_src)
	_merge_dict(player_dmg_by_src, other.player_dmg_by_src)
	_merge_dict(kills_by_kind, other.kills_by_kind)
	_merge_dict(fire_dmg_by_by, other.fire_dmg_by_by)
	_merge_dict(collision_by_aid, other.collision_by_aid)
	illegal += other.illegal
	smog_at_descend.append_array(other.smog_at_descend)
	turns_per_floor.append_array(other.turns_per_floor)
	stall_floors += other.stall_floors
	quota_unmet_at_death = quota_unmet_at_death or other.quota_unmet_at_death
	quota_unmet_deaths += other.quota_unmet_deaths
	quota_reclamps += other.quota_reclamps
	runs += other.runs


static func _merge_dict(into: Dictionary, from: Dictionary) -> void:
	for k in from:
		into[k] = int(into.get(k, 0)) + int(from[k])


static func _sum(d: Dictionary) -> int:
	var s := 0
	for k in d:
		s += int(d[k])
	return s


func dmg_taken() -> int:
	return _sum(player_dmg_by_src)


static func _safe_div(a: float, b: float) -> float:
	return 0.0 if b == 0.0 else a / b


## Keys sorted by value descending, ties broken by key ascending (stable
## and deterministic regardless of dictionary insertion order).
static func sorted_desc(d: Dictionary) -> Array:
	var keys: Array = d.keys()
	keys.sort_custom(func(a, b):
		var va: int = int(d[a])
		var vb: int = int(d[b])
		if va != vb:
			return va > vb
		return String(a) < String(b))
	return keys


## Draft-slot roles in report order: the Content.DRAFT_SLOT_REPORTS entries
## that occur, then anything else sorted - so a role the sim added (or an
## "unknown" from a draft with no "slots" key) still prints, at the end.
static func slot_order(d: Dictionary) -> Array:
	var out: Array = []
	for role in Content.DRAFT_SLOT_REPORTS:
		if d.has(role):
			out.append(role)
	var extra: Array = []
	for role in d:
		if not out.has(role):
			extra.append(role)
	extra.sort()
	out.append_array(extra)
	return out


## Canonical kit string: sorted BASE ids joined by "+". The join separator is
## not an id suffix - every entry is folded through base_id first, so a Block
## D6 variant ("solar_lance+noon") contributes "solar_lance" and the key stays
## unambiguous and comparable with every pre-D6 entropy number.
static func kit_key(kit: Array) -> String:
	var ids: Array = []
	for aid in kit:
		ids.append(base_id(String(aid)))
	ids.sort()
	return "+".join(ids)


## Shannon entropy (bits) over the multiset of kit_key strings.
static func kit_entropy_bits(kits: Array) -> float:
	if kits.is_empty():
		return 0.0
	var counts := {}
	for kit in kits:
		_inc(counts, kit_key(kit))
	var n := float(kits.size())
	var h := 0.0
	for k in counts:
		var p: float = float(counts[k]) / n
		if p > 0.0:
			h -= p * (log(p) / log(2.0))
	return h


## Headline KPIs (review §7.1). Every division is guarded; shares are 0 when
## no enemy damage was dealt.
static func kpis(t, n_runs: int, kits: Array) -> Dictionary:
	var total := float(_sum(t.enemy_dmg_by_src))
	var strike := 0.0
	var lance := 0.0
	# Families are read through base_id and never through the raw source key:
	# bump 2 renamed the enemy-side sources ("fire" -> "fire:<igniter>",
	# "solar_lance" -> the casting id, so "solar_lance+" for the upgrade), and
	# every share below keeps the meaning it had before that rename.
	var fire_dmg := 0.0
	var terrain := 0.0
	var by_family := {}
	for src in t.enemy_dmg_by_src:
		var amt := float(t.enemy_dmg_by_src[src])
		var fam := base_id(src_family(String(src)))
		_inc(by_family, fam, int(t.enemy_dmg_by_src[src]))
		match fam:
			"strike":
				strike += amt
			"solar_lance":
				lance += amt
			"fire":
				terrain += amt
				fire_dmg += amt
			"collision", "thorns", "spore":
				terrain += amt
	# Riders are combos too: a per / bonus / then that actually changed
	# something is exactly the "the pieces talked to each other" event the
	# combo rate counts (review 7.1; zero until a content row carries one).
	var riders := _sum(t.riders_by_kind)
	var combos: int = t.ignite_ability + t.verdant + t.staggered + t.collision_hits + t.convert + t.thorns_hits + riders
	var pick_rate := {}
	for aid in t.offers_by_id:
		pick_rate[aid] = _safe_div(float(t.picks_by_id.get(aid, 0)), float(t.offers_by_id[aid]))
	# Block D4: the same pick rate cut by the slot role that rolled the
	# offer - "how often is a build-matching offer what gets taken".
	var slot_rate := {}
	for role in t.offers_by_slot:
		slot_rate[role] = _safe_div(float(t.picks_by_slot.get(role, 0)), float(t.offers_by_slot[role]))
	return {
		"strike_share": _safe_div(strike, total),
		"signature_share": 0.0 if total == 0.0 else 1.0 - (strike + lance + fire_dmg) / total,
		"terrain_share": _safe_div(terrain, total),
		"combo_rate": _safe_div(float(combos), float(n_runs)),
		"bloom_conversion": _safe_div(float(t.bloom_spent), float(t.bloom_earned)),
		"kit_entropy_bits": kit_entropy_bits(kits),
		"pick_rate_by_id": pick_rate,
		# Block D6 fork instrument: casts and effective casts by FULL variant
		# id, the only columns that tell two siblings of a fork apart
		"casts_by_id": t.casts_by_id.duplicate(),
		"effective_casts_by_id": t.effective_casts_by_id.duplicate(),
		# draft slots (Block D4)
		"offers_by_slot": t.offers_by_slot.duplicate(),
		"picks_by_slot": t.picks_by_slot.duplicate(),
		"pick_rate_by_slot": slot_rate,
		"focus_drafts": t.focus_drafts,
		"enemy_dmg_total": int(total),
		"combos": combos,
		"enemy_dmg_by_family": by_family,  # keys are base-id families
		# bump-2 attribution: which igniter/ability the terrain damage came from
		"fire_dmg_by_by": t.fire_dmg_by_by.duplicate(),
		"collision_by_aid": t.collision_by_aid.duplicate(),
		"quota_reclamps": t.quota_reclamps,
		"graft_discards": t.graft_discards,
		"bloom_spent_on_grafts": t.bloom_spent_on_grafts,
		# shrine rerolls (Block D2): the sink's cost half and its payoff half
		"rerolls": t.rerolls,
		"bloom_spent_on_rerolls": t.bloom_spent_on_rerolls,
		"buys_after_reroll": t.buys_after_reroll,
		"bloom_unspent": t.bloom_unspent,
		# effect-grammar riders (Block C1a)
		"riders": riders,
		"riders_by_kind": t.riders_by_kind.duplicate(),
		"riders_by_aid": t.riders_by_aid.duplicate(),
		# per-ability stat surges and Spore Trail (Block D1)
		"surges": _sum(t.surges_by_aid),
		"surges_by_aid": t.surges_by_aid.duplicate(),
		"origin_plants": _sum(t.origin_plants_by_aid),
		"origin_plants_by_aid": t.origin_plants_by_aid.duplicate(),
		# terrain / status bookkeeping (Block C1b)
		"ash_events": t.ash_events,
		"cleanses_by_kind": t.cleanses_by_kind.duplicate(),
		"resisted_events": t.resisted_events,
		"status_by_kind": t.status_by_kind.duplicate(),
		# terrain denial (Block D3): the intents smoke swallowed, and the fire
		# damage enemies walked into anyway - the avoid lists' own metric, read
		# off the same "fire" family that feeds the terrain share above
		"screened": _sum(t.screened_by_intent),
		"screened_by_intent": t.screened_by_intent.duplicate(),
		"enemy_fire_dmg": int(fire_dmg),
		# graft hooks (Block C3): rows run by source id and by firing kind
		"hooks": _sum(t.hooks_by_kind),
		"hooks_by_graft": t.hooks_by_graft.duplicate(),
		"hooks_by_kind": t.hooks_by_kind.duplicate(),
		"hook_capped": t.hook_capped,
		"tithes": t.tithes,
	}


## Compact report block; every line is indented so it nests under a runner's
## own summary lines.
func print_block(n_runs: int, kits: Array) -> void:
	var n := maxf(1.0, float(n_runs))
	var k := kpis(self, n_runs, kits)
	var parts: Array = []
	for aid in sorted_desc(casts_by_base):
		parts.append("%s %.1f" % [aid, float(casts_by_base[aid]) / n])
	print("           casts/run: %s  (plus-form casts %d)" % [", ".join(parts) if not parts.is_empty() else "none", plus_casts])
	# the fork line (Block D6): only variant ids, and only when one was cast -
	# a run holding no upgrade prints nothing extra
	var vparts: Array = []
	for aid in sorted_desc(casts_by_id):
		if not Content.is_upgrade(String(aid)):
			continue
		vparts.append("%s %.1f (eff %.1f)" % [aid, float(casts_by_id[aid]) / n,
			float(effective_casts_by_id.get(aid, 0)) / n])
	if not vparts.is_empty():
		print("           variant casts/run: %s" % ", ".join(vparts))
	print("           actions/run: strike %.1f  cleanse %.1f  move %.1f  end_turn %.1f  item_use %.1f" % [
		strikes / n, cleanses / n, moves / n, end_turns / n, float(_sum(item_uses_by_id)) / n])
	var pr: Dictionary = k["pick_rate_by_id"]
	var prs: Array = []
	for aid in sorted_desc(offers_by_id):
		prs.append("%s %d/%d" % [aid, picks_by_id.get(aid, 0), offers_by_id[aid]])
	print("           pick rate (picks/offers): %s" % (", ".join(prs) if not prs.is_empty() else "no drafts"))
	print("           drafts %d  upgrades %d  skips %d  drops %s  P(plus offered|draft) %.2f" % [
		drafts, upgrades, skips, str(drops_by_id), _safe_div(float(drafts_with_plus), float(drafts))])
	var slot_parts: Array = []
	for role in slot_order(offers_by_slot):
		var off: int = int(offers_by_slot[role])
		var took: int = int(picks_by_slot.get(role, 0))
		slot_parts.append("%s %d/%d (%.2f)" % [role, took, off, _safe_div(float(took), float(off))])
	print("           draft: picks/offers by slot %s  focus drafts %d of %d (skips %d)" % [
		", ".join(slot_parts) if not slot_parts.is_empty() else "no drafts", focus_drafts, drafts, skips])
	print("           enemy dmg %d: strike share %.2f  signature share %.2f  terrain share %.2f  by family %s" % [
		k["enemy_dmg_total"], k["strike_share"], k["signature_share"], k["terrain_share"], str(k["enemy_dmg_by_family"])])
	print("             by src %s" % str(enemy_dmg_by_src))
	print("             fire dmg by igniter %s  collision dmg by ability %s" % [
		str(fire_dmg_by_by), str(collision_by_aid)])
	print("           player dmg %d by src %s  (fire %d, shield absorbed %d, growth heal %d)" % [
		dmg_taken(), str(player_dmg_by_src), fire_dmg_player, shield_absorb_hp, growth_heal_hp])
	print("           combos/run %.2f: ignite(ability) %.2f ignite(env) %.2f verdant %.2f staggered %.2f collision %.2f thorns %.2f fire-hits %.2f spore %.2f convert %.2f wash %.2f room_bloom %.2f restored %.2f seal_burst %.2f" % [
		k["combo_rate"], ignite_ability / n, ignite_env / n, verdant / n, staggered / n, collision_hits / n,
		thorns_hits / n, fire_hits_enemy / n, spore_ticks / n, convert / n, wash / n, room_bloom / n,
		floor_restored / n, seal_burst / n])
	print("           riders: %.2f/run  by kind %s  by ability %s" % [
		float(_sum(riders_by_kind)) / n, str(riders_by_kind), str(riders_by_aid)])
	print("           surges: %.2f/run stat-surged casts %s  (of %.2f verdant/run)  origin plants %.2f/run %s" % [
		float(_sum(surges_by_aid)) / n, str(surges_by_aid), verdant / n,
		float(_sum(origin_plants_by_aid)) / n, str(origin_plants_by_aid)])
	print("           terrain: ash %d  cleanses by kind %s  resisted %d  statuses %s" % [
		ash_events, str(cleanses_by_kind), resisted_events, str(status_by_kind)])
	print("           denial: screened %.2f/run (%d total) %s  enemy fire dmg %.2f/run (%d total)" % [
		float(_sum(screened_by_intent)) / n, _sum(screened_by_intent), str(screened_by_intent),
		float(int(k["enemy_fire_dmg"])) / n, int(k["enemy_fire_dmg"])])
	print("           hooks: by graft %s  by kind %s  capped %d  tithe %d" % [
		str(hooks_by_graft), str(hooks_by_kind), hook_capped, tithes])
	print("           bloom earned %.1f/run  spent %.1f/run  conversion %.2f  buys %s  grafts %s  ability buys %s  upcycles %d/%d  pickups %d  satchel_full %d" % [
		bloom_earned / n, bloom_spent / n, k["bloom_conversion"], str(buys_by_kind), str(grafts_by_id),
		str(ability_buys_by_id), upcycles, upcycle_abilities, item_pickups, satchel_full])
	print("           shrine turns/run %.2f  unspent charge/end_turn %.2f  kit entropy %.2f bits" % [
		shrine_turns / n, _safe_div(float(unspent_charge_total), float(end_turns)), k["kit_entropy_bits"]])
	print("           choice sinks: graft offers discarded %d  bloom spent on grafts %d (%.1f/run)  quota reclamps %d" % [
		graft_discards, bloom_spent_on_grafts, bloom_spent_on_grafts / n, quota_reclamps])
	print("           rerolls: %.2f/run (%d total)  bloom spent %d (%.1f/run)  buys after a reroll %d  bloom unspent at end %.1f/run" % [
		rerolls / n, rerolls, bloom_spent_on_rerolls, bloom_spent_on_rerolls / n, buys_after_reroll, bloom_unspent / n])
	var smog_avg := 0.0
	for s in smog_at_descend:
		smog_avg += float(s)
	smog_avg = _safe_div(smog_avg, float(smog_at_descend.size()))
	var tpf := 0.0
	for x in turns_per_floor:
		tpf += float(x)
	tpf = _safe_div(tpf, float(turns_per_floor.size()))
	print("           clock: smog at descend avg %.1f  turns/floor avg %.1f  stall floors %d  quota-unmet deaths %d  illegal %d" % [
		smog_avg, tpf, stall_floors, quota_unmet_deaths, illegal])
