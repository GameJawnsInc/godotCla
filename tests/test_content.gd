extends SceneTree
## Structural checks on the sim-ignored ability metadata in sim/content.gd:
## 1) every ABILITIES entry has tags from TAGS and a role from ROLES
## 2) every "+" form carries its base's tags/role
## 3) ARCHETYPES cores and package requirements reference real ids
## 4) every draftable ability is in some archetype core, or is mobility/utility
## 5) base_id() round-trips; archetypes_for(DRAFT_POOL) = the package-free set
## Run: godot --headless --path . --script tests/test_content.gd

const Content := preload("res://sim/content.gd")


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
		if not aid.begins_with(base) or (aid != base and aid != base + "+"):
			failures.append("base_id(%s) = '%s' does not round-trip" % [aid, base])

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

	if failures.is_empty():
		print("content: OK")
		quit(0)
	else:
		for f in failures:
			print("FAIL: %s" % f)
		print("content: %d failure(s)" % failures.size())
		quit(1)
