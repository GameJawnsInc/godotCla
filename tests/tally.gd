extends RefCounted
## Event tally for bot runs (review §7.1): fed every event game.step()
## returns inside Sweep.run_loop, plus begin_step/end_step hooks for
## before/after state (bloom deltas, shrine turns, unspent charge, clock
## stalls). Ability ids are normalised to their base id (trim "+"); plus-form
## casts are counted separately in plus_casts. Pure bookkeeping: it never
## touches the game, so feeding it cannot change a run.

# --- actions ------------------------------------------------------------------
var casts_by_base := {}
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

# --- shrine and items ---------------------------------------------------------
var buys_by_kind := {}
var grafts_by_id := {}
var ability_buys_by_id := {}
var upcycles := 0
var upcycle_abilities := 0
var item_uses_by_id := {}
var item_pickups := 0
var satchel_full := 0

# --- economy ------------------------------------------------------------------
var bloom_earned := 0
var bloom_spent := 0
var shrine_turns := 0  # end_turn taken while standing on the shrine
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

# --- damage by raw source string ---------------------------------------------
var enemy_dmg_by_src := {}
var player_dmg_by_src := {}
var kills_by_kind := {}  # enemy death events by kind

# --- errors and clock ---------------------------------------------------------
var illegal := 0  # {"t": "illegal"} plus {"t": "error"} events
var smog_at_descend: Array = []
var turns_per_floor: Array = []
var stall_floors := 0  # floors with turn > 60 or smog > choke + 30 at any point
var quota_unmet_at_death := false  # this run (or any merged run) died with greened < green_need
var quota_unmet_deaths := 0
var runs := 0  # runs finished into this tally (finish() increments, merge() sums)

# step-scoped state from begin_step
var _bloom0 := 0
var _pos0 := Vector2i.ZERO
var _charge0 := 0
var _floor0 := 0
var _stall_flagged := false
var _choke_floor := -1  # floor_def() deep-copies a table: cache choke per floor
var _choke := 0


static func base_id(aid: String) -> String:
	return aid.trim_suffix("+")


## Damage-source family: the part before ":" (sources carry no suffix today;
## the split is future-proofing for the bump-2 "src:detail" format).
static func src_family(src: String) -> String:
	var i := src.find(":")
	return src if i < 0 else src.substr(0, i)


static func _inc(d: Dictionary, k, amt: int = 1) -> void:
	d[k] = int(d.get(k, 0)) + amt


func begin_step(game) -> void:
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
			if aid.ends_with("+"):
				plus_casts += 1
		"strike":
			strikes += 1
		"cleanse":
			cleanses += 1
		"move":
			if String(ev.get("who", "player")) == "player":
				moves += 1
		"draft_offer":
			drafts += 1
			var any_plus := false
			for o in ev.get("offers", []):
				_inc(offers_by_id, String(o))
				if String(o).ends_with("+"):
					any_plus = true
			if any_plus:
				drafts_with_plus += 1
		"draft_pick":
			_inc(picks_by_id, String(ev.get("id", "")))
		"draft_upgrade":
			upgrades += 1
		"draft_skip":
			skips += 1
		"draft_drop":
			_inc(drops_by_id, String(ev.get("id", "")))
		"buy":
			var kind := String(ev.get("item", ""))
			_inc(buys_by_kind, kind)
			if kind == "graft":
				_inc(grafts_by_id, String(ev.get("id", "")))
			elif kind == "ability":
				_inc(ability_buys_by_id, String(ev.get("id", "")))
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
		"heal":
			growth_heal_hp += int(ev.get("amt", 0))
		"shield_absorb":
			shield_absorb_hp += int(ev.get("amt", 0))
		"damage":
			_add_damage(ev)
		"death":
			_inc(kills_by_kind, String(ev.get("who", "")))
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
		"thorns":
			thorns_hits += 1
		"fire":
			fire_hits_enemy += 1
		"spore":
			spore_ticks += 1


func end_step(game, action: Dictionary) -> void:
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
	_choke_floor = -1
	_stall_flagged = false
	if game.over and not game.won and game.greened < game.green_need:
		quota_unmet_at_death = true
		quota_unmet_deaths += 1


func merge(other) -> void:
	_merge_dict(casts_by_base, other.casts_by_base)
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
	bloom_earned += other.bloom_earned
	bloom_spent += other.bloom_spent
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
	_merge_dict(enemy_dmg_by_src, other.enemy_dmg_by_src)
	_merge_dict(player_dmg_by_src, other.player_dmg_by_src)
	_merge_dict(kills_by_kind, other.kills_by_kind)
	illegal += other.illegal
	smog_at_descend.append_array(other.smog_at_descend)
	turns_per_floor.append_array(other.turns_per_floor)
	stall_floors += other.stall_floors
	quota_unmet_at_death = quota_unmet_at_death or other.quota_unmet_at_death
	quota_unmet_deaths += other.quota_unmet_deaths
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


## Canonical kit string: sorted base ids joined by "+".
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
	var fire_unattr := float(t.enemy_dmg_by_src.get("fire", 0))
	var terrain := 0.0
	for src in t.enemy_dmg_by_src:
		var amt := float(t.enemy_dmg_by_src[src])
		var fam := src_family(String(src))
		match fam:
			"strike":
				strike += amt
			"solar_lance":
				lance += amt
			"fire", "collision", "thorns", "spore":
				terrain += amt
	var combos: int = t.ignite_ability + t.verdant + t.staggered + t.collision_hits + t.convert + t.thorns_hits
	var pick_rate := {}
	for aid in t.offers_by_id:
		pick_rate[aid] = _safe_div(float(t.picks_by_id.get(aid, 0)), float(t.offers_by_id[aid]))
	return {
		"strike_share": _safe_div(strike, total),
		"signature_share": 0.0 if total == 0.0 else 1.0 - (strike + lance + fire_unattr) / total,
		"terrain_share": _safe_div(terrain, total),
		"combo_rate": _safe_div(float(combos), float(n_runs)),
		"bloom_conversion": _safe_div(float(t.bloom_spent), float(t.bloom_earned)),
		"kit_entropy_bits": kit_entropy_bits(kits),
		"pick_rate_by_id": pick_rate,
		"enemy_dmg_total": int(total),
		"combos": combos,
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
	print("           actions/run: strike %.1f  cleanse %.1f  move %.1f  end_turn %.1f  item_use %.1f" % [
		strikes / n, cleanses / n, moves / n, end_turns / n, float(_sum(item_uses_by_id)) / n])
	var pr: Dictionary = k["pick_rate_by_id"]
	var prs: Array = []
	for aid in sorted_desc(offers_by_id):
		prs.append("%s %d/%d" % [aid, picks_by_id.get(aid, 0), offers_by_id[aid]])
	print("           pick rate (picks/offers): %s" % (", ".join(prs) if not prs.is_empty() else "no drafts"))
	print("           drafts %d  upgrades %d  skips %d  drops %s  P(plus offered|draft) %.2f" % [
		drafts, upgrades, skips, str(drops_by_id), _safe_div(float(drafts_with_plus), float(drafts))])
	print("           enemy dmg %d: strike share %.2f  signature share %.2f  terrain share %.2f  by src %s" % [
		k["enemy_dmg_total"], k["strike_share"], k["signature_share"], k["terrain_share"], str(enemy_dmg_by_src)])
	print("           player dmg %d by src %s  (fire %d, shield absorbed %d, growth heal %d)" % [
		dmg_taken(), str(player_dmg_by_src), fire_dmg_player, shield_absorb_hp, growth_heal_hp])
	print("           combos/run %.2f: ignite(ability) %.2f ignite(env) %.2f verdant %.2f staggered %.2f collision %.2f thorns %.2f fire-hits %.2f spore %.2f convert %.2f wash %.2f room_bloom %.2f restored %.2f seal_burst %.2f" % [
		k["combo_rate"], ignite_ability / n, ignite_env / n, verdant / n, staggered / n, collision_hits / n,
		thorns_hits / n, fire_hits_enemy / n, spore_ticks / n, convert / n, wash / n, room_bloom / n,
		floor_restored / n, seal_burst / n])
	print("           bloom earned %.1f/run  spent %.1f/run  conversion %.2f  buys %s  grafts %s  ability buys %s  upcycles %d/%d  pickups %d  satchel_full %d" % [
		bloom_earned / n, bloom_spent / n, k["bloom_conversion"], str(buys_by_kind), str(grafts_by_id),
		str(ability_buys_by_id), upcycles, upcycle_abilities, item_pickups, satchel_full])
	print("           shrine turns/run %.2f  unspent charge/end_turn %.2f  kit entropy %.2f bits" % [
		shrine_turns / n, _safe_div(float(unspent_charge_total), float(end_turns)), k["kit_entropy_bits"]])
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
