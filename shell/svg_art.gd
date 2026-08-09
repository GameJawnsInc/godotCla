extends RefCounted
## Hand-drawn SVG sprite set for the shell, rasterized at runtime with
## Image.load_svg_from_string (CPU-side, works headless). One 32x32 viewBox
## per sprite; the shell scales them to the tile size it draws at.
## The sim never sees any of this (style guide §1/§4).

const W := "http://www.w3.org/2000/svg"


static func _svg(body: String) -> String:
	return '<svg xmlns="%s" viewBox="0 0 32 32">%s</svg>' % [W, body]


# --- terrain & map features ---------------------------------------------------
static var ART := {
	"oil": _svg('<ellipse cx="16" cy="19" rx="11" ry="7" fill="#14100e"/><ellipse cx="16" cy="17" rx="9" ry="5" fill="#241c18"/><ellipse cx="13" cy="15" rx="3" ry="1.4" fill="#4a3a56" opacity="0.8"/>'),
	"goo": _svg('<path d="M6 22q-2-8 5-9 1-5 6-4 6-1 7 4 5 2 2 9-2 4-10 4t-10-4z" fill="#3c6b1f"/><circle cx="12" cy="17" r="2" fill="#5b9431"/><circle cx="20" cy="19" r="1.5" fill="#5b9431"/>'),
	"rich_goo": _svg('<path d="M6 22q-2-8 5-9 1-5 6-4 6-1 7 4 5 2 2 9-2 4-10 4t-10-4z" fill="#3c6b1f"/><circle cx="12" cy="17" r="2" fill="#5b9431"/><path d="M20 13l1.2 2.6 2.8 0.4-2 2 0.5 2.8-2.5-1.3-2.5 1.3 0.5-2.8-2-2 2.8-0.4z" fill="#e8c840"/>'),
	"growth": _svg('<path d="M16 26V14" stroke="#3f8f3a" stroke-width="2"/><path d="M16 18q-6 0-7-7 7 1 7 7z" fill="#57b34a"/><path d="M16 16q6 0 7-9-7 2-7 9z" fill="#6cc95c"/><path d="M10 27q6-3 12 0z" fill="#2f6b2c"/>'),
	"fire": _svg('<path d="M16 4q6 7 4 12 3-1 4-4 3 9-2 13-4 3-9 1-6-3-4-11 1-4 4-6 0 3 1 4 1-5 2-9z" fill="#e8722a"/><path d="M15 14q4 5 1 9-3 2-5-1-1-5 4-8z" fill="#f7c948"/>'),
	"smoke": _svg('<circle cx="11" cy="19" r="6" fill="#6b6f72" opacity="0.85"/><circle cx="19" cy="16" r="7" fill="#7d8184" opacity="0.85"/><circle cx="24" cy="21" r="5" fill="#6b6f72" opacity="0.85"/>'),
	"roots": _svg('<path d="M4 8q10 8 24 4M4 16q12 6 24 0M4 24q10-6 24 2M10 4q2 12-2 24M22 4q-2 14 2 24" stroke="#7a5a34" stroke-width="2.4" fill="none"/>'),
	"vent": _svg('<circle cx="16" cy="16" r="10" fill="#3a4148"/><circle cx="16" cy="16" r="10" fill="none" stroke="#565f66" stroke-width="2"/><path d="M9 16h14M16 9v14M11 11l10 10M21 11l-10 10" stroke="#20262b" stroke-width="2"/>'),
	"stairs": _svg('<path d="M6 8h8v6h6v6h6v6H6z" fill="#8a8f96"/><path d="M6 8h8v6h6v6h6v6" fill="none" stroke="#565b61" stroke-width="1.5"/><path d="M22 10l4 4-4 4" stroke="#2c3134" stroke-width="2" fill="none"/>'),
	"shrine": _svg('<rect x="12" y="14" width="8" height="12" rx="1.5" fill="#9aa08f"/><rect x="9" y="24" width="14" height="4" rx="1" fill="#7b8272"/><path d="M16 14q-5-1-5-8 5 1 5 8z" fill="#57b34a"/><path d="M16 14q5-1 5-8-5 1-5 8z" fill="#6cc95c"/><circle cx="16" cy="19" r="2" fill="#e8c840"/>'),

	# --- player -----------------------------------------------------------------
	"player": _svg('<circle cx="16" cy="12" r="6.5" fill="#8fdc6a"/><circle cx="14" cy="11" r="1.3" fill="#1c3315"/><circle cx="19" cy="11" r="1.3" fill="#1c3315"/><path d="M16 5q1-4 5-4-1 4-5 4z" fill="#4a9a3d"/><path d="M9 28q0-9 7-9t7 9z" fill="#579a48"/><path d="M12 22h8" stroke="#8fdc6a" stroke-width="1.5"/>'),

	# --- enemies: the combine ---------------------------------------------------
	"drill_bot": _svg('<rect x="9" y="8" width="14" height="12" rx="2" fill="#8a8f96"/><circle cx="13" cy="13" r="1.8" fill="#e04b3a"/><circle cx="19" cy="13" r="1.8" fill="#e04b3a"/><path d="M16 20l-5 9h10z" fill="#565b61"/><path d="M16 29l-2-4h4z" fill="#31363a"/><rect x="7" y="11" width="2" height="6" fill="#565b61"/><rect x="23" y="11" width="2" height="6" fill="#565b61"/>'),
	"oil_sludge": _svg('<path d="M5 24q-2-10 6-11 1-6 7-5 7-1 8 5 6 2 3 11-2 5-12 5T5 24z" fill="#181310"/><circle cx="12" cy="18" r="2.2" fill="#d8c92e"/><circle cx="20" cy="18" r="2.2" fill="#d8c92e"/><circle cx="12" cy="18" r="1" fill="#181310"/><circle cx="20" cy="18" r="1" fill="#181310"/>'),
	"sludgeling": _svg('<path d="M10 24q-2-6 3-7 1-4 5-3 4 0 4 4 3 2 1 6-1 3-7 3t-6-3z" fill="#181310"/><circle cx="14" cy="20" r="1.4" fill="#d8c92e"/><circle cx="19" cy="20" r="1.4" fill="#d8c92e"/>'),
	"leech_drone": _svg('<ellipse cx="16" cy="14" rx="6" ry="5" fill="#5d6a72"/><path d="M10 12Q3 8 4 15q4 2 6 0zM22 12q7-4 6 3-4 2-6 0z" fill="#8fa0aa" opacity="0.9"/><path d="M16 19v7" stroke="#b8443a" stroke-width="2.5"/><circle cx="16" cy="13" r="2" fill="#e04b3a"/>'),
	"tar_spitter": _svg('<path d="M7 22q0-9 9-9t9 9q0 5-9 5t-9-5z" fill="#2b2320"/><circle cx="12" cy="19" r="1.6" fill="#d8c92e"/><circle cx="20" cy="19" r="1.6" fill="#d8c92e"/><ellipse cx="16" cy="24" rx="4" ry="2.2" fill="#181310"/><path d="M14 10q2-4 4 0l-2 4z" fill="#181310"/>'),
	"coal_golem": _svg('<path d="M9 28V15l4-6h6l4 6v13h-4v-6h-6v6z" fill="#26292c"/><path d="M12 9l3 3M20 9l-3 3M9 18l4 2M23 18l-4 2" stroke="#41464a" stroke-width="1.5"/><circle cx="14" cy="14" r="1.5" fill="#e8722a"/><circle cx="18" cy="14" r="1.5" fill="#e8722a"/>'),
	"extractor_engine": _svg('<rect x="6" y="12" width="20" height="14" rx="1.5" fill="#4a3f33"/><rect x="9" y="6" width="4" height="8" fill="#6b5c48"/><circle cx="11" cy="5" r="2.5" fill="#7d8184" opacity="0.8"/><circle cx="18" cy="19" r="4" fill="#2b241d"/><path d="M18 15v8M14 19h8" stroke="#8a7a5e" stroke-width="1.5"/><rect x="21" y="14" width="3" height="3" fill="#e04b3a"/>'),
	"rust_hound": _svg('<path d="M6 20q1-6 8-6h8l4-4v7l-3 3q0 6-6 6h-5q-6 0-6-6z" fill="#8a5a30"/><circle cx="23" cy="13" r="1.4" fill="#e04b3a"/><path d="M9 26v3M14 26v3M19 26v3" stroke="#6b4523" stroke-width="2"/><path d="M8 15l-3-3" stroke="#8a5a30" stroke-width="2"/>'),
	"cinder_mite": _svg('<circle cx="16" cy="18" r="5" fill="#3a2a24"/><circle cx="16" cy="18" r="2.5" fill="#e8722a"/><path d="M11 14l-3-3M21 14l3-3M10 20l-4 1M22 20l4 1M12 23l-2 3M20 23l2 3" stroke="#3a2a24" stroke-width="1.8"/>'),
	"pump_jack": _svg('<path d="M8 27l6-16 4 16" fill="none" stroke="#6b5c48" stroke-width="2.5"/><path d="M6 12h17l4 4" stroke="#8a7a5e" stroke-width="3" fill="none"/><circle cx="14" cy="11" r="2" fill="#4a3f33"/><path d="M25 16v6" stroke="#8a7a5e" stroke-width="2.5"/><ellipse cx="25" cy="25" rx="4" ry="2" fill="#181310"/><rect x="5" y="26" width="22" height="3" fill="#4a3f33"/>'),
	"smokestack": _svg('<path d="M11 28V8h10v20z" fill="#5d5348"/><rect x="9" y="5" width="14" height="4" rx="1" fill="#736555"/><rect x="11" y="12" width="10" height="2" fill="#4a4138"/><rect x="11" y="18" width="10" height="2" fill="#4a4138"/><circle cx="16" cy="3" r="3" fill="#7d8184" opacity="0.85"/><circle cx="21" cy="1.5" r="2.2" fill="#6b6f72" opacity="0.7"/><rect x="8" y="27" width="16" height="3" fill="#3a342c"/>'),
	"magnet_crane": _svg('<rect x="6" y="26" width="20" height="3" fill="#4a4138"/><rect x="13" y="12" width="4" height="15" fill="#8a6a2a"/><path d="M13 13L27 8" stroke="#8a6a2a" stroke-width="3"/><path d="M26 8v6" stroke="#5d5348" stroke-width="1.5"/><path d="M22 16h8v4h-3v-2h-2v2h-3z" fill="#c23b30"/><path d="M23 21l3 3 3-3" stroke="#7ec8e0" stroke-width="1.5" fill="none"/>'),

	# --- bosses -----------------------------------------------------------------
	"furnace_core": _svg('<rect x="4" y="8" width="24" height="20" rx="2" fill="#33291f"/><path d="M8 8V5h4v3M20 8V5h4v3" fill="#33291f"/><circle cx="16" cy="18" r="7" fill="#e8722a"/><circle cx="16" cy="18" r="4" fill="#f7c948"/><path d="M4 14h24M4 24h24" stroke="#211a12" stroke-width="1.5"/>'),
	"overseer": _svg('<circle cx="16" cy="15" r="10" fill="#3a4148"/><circle cx="16" cy="15" r="6" fill="#c23b30"/><circle cx="16" cy="15" r="2.6" fill="#f7c948"/><path d="M6 15h-4M30 15h-4M16 5V1M16 29v-4M8 7L5 4M24 7l3-3" stroke="#3a4148" stroke-width="2.5"/><path d="M9 26q7 4 14 0" stroke="#565f66" stroke-width="2.5" fill="none"/>'),
	"the_dredge": _svg('<rect x="5" y="17" width="22" height="9" rx="2" fill="#4a4138"/><circle cx="10" cy="27" r="3" fill="#26292c"/><circle cx="21" cy="27" r="3" fill="#26292c"/><path d="M8 17L4 8l8 3z" fill="#8a6a2a"/><path d="M4 8q8-2 12 4" stroke="#8a6a2a" stroke-width="2.5" fill="none"/><path d="M16 12l5-2 1 4-5 2z" fill="#5d5348"/><rect x="18" y="19" width="6" height="4" fill="#3c6b1f"/><circle cx="14" cy="21" r="1.6" fill="#e04b3a"/>'),
}


static var _cache := {}


## Rasterize an SVG sprite at the given pixel size (cached).
static func tex(id: String, size: int) -> ImageTexture:
	var key := "%s@%d" % [id, size]
	if _cache.has(key):
		return _cache[key]
	if not ART.has(id):
		return null
	var img := Image.new()
	img.load_svg_from_string(ART[id], float(size) / 32.0)
	var t := ImageTexture.create_from_image(img)
	_cache[key] = t
	return t
