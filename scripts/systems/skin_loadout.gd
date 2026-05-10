class_name SkinLoadout
extends RefCounted

# Helper estático pra ler/salvar a skin equipada do user://settings.cfg.
# Loadout é Dictionary[StringName -> SkinPart]. Slot ausente = sem peça.
#
# Auto-discovery: escaneia assets/player/<slot_dir>/*.png em runtime.
# Pra adicionar variantes: drop o PNG na pasta certa, aparece automático na UI.
#
# Sistema de unlock baseado em quests (ver SKIN_QUESTS abaixo). Cada quest
# tem um tipo + valor + label + flag hidden. Stats persistentes em [progress]
# guardam o progresso entre runs.

const _SETTINGS_PATH: String = "user://settings.cfg"
const _SECTION: String = "skin"
const _PROGRESS_SECTION: String = "progress"

# Slots existentes. Ordem importa só na UI (de cima pra baixo).
const SLOTS: Array[StringName] = [
	&"body", &"legs", &"shirt", &"alfaja", &"cape", &"quiver", &"hair", &"bow"
]
# Slots que aceitam "Nenhum" (jogador pode remover).
const REMOVABLE_SLOTS: Array[StringName] = [&"hair", &"cape", &"shirt", &"alfaja", &"legs"]

# Mapeia slot interno → pasta em assets/player/.
const SLOT_TO_DIR: Dictionary = {
	&"body":   "skin",
	&"legs":   "legs",
	&"shirt":  "shirt",
	&"alfaja": "alfaja",
	&"cape":   "cape",
	&"quiver": "quiver",
	&"hair":   "hair",
	&"bow":    "bow",
}

const DEFAULT_PREFERENCES: Dictionary = {
	&"body":   "Default",
	&"legs":   "Default",
	&"shirt":  "Default",
	&"alfaja": "",
	&"cape":   "Default",
	&"quiver": "Default",
	&"hair":   "Default",
	&"bow":    "Default",
}

# ---------- Quest config ----------
# Cada chave é o display_name da skin (PNG filename sem extensão).
# Skins não listadas aqui NÃO têm quest = sempre desbloqueadas.
#
# Tipos de quest suportados:
#   wave_reached    — alcançar raid X (max_wave_reached >= value)
#   enemies_killed  — matar X inimigos no total (enemies_killed_total >= value)
#   dmg_dealt       — causar X dano no total (dmg_dealt_total >= value)
#   runs_completed  — completar X runs (morrer X vezes; runs_completed >= value)
#   no_damage_run   — completar X runs sem tomar dano (runs_no_damage >= value)
#   boss_killed     — matar boss específico (value=boss_id, ex: "mage_monkey")
#
# Pra adicionar novo type: adicione um case em _is_quest_satisfied(),
# adicione tracking em record_run() se for stat novo.
#
# `hidden`: se true, skin só aparece na UI depois de desbloqueada (surpresa).
# Se false (default), aparece com label da quest enquanto não desbloqueada.
const SKIN_QUESTS: Dictionary = {
	"Red_Velvet": {
		"type": "wave_reached",
		"value": 10,
		# `label` é uma translation key — exibida via tr() em skin_select.gd e hud.gd.
		"label": "PLAYER_QUEST_RED_VELVET",
		"hidden": false,
	},
	"Gingerale": {
		"type": "enemies_killed",
		"value": 3000,
		"label": "PLAYER_QUEST_GINGERALE",
		"hidden": false,
	},
	"Bluey": {
		"type": "boss_killed",
		"value": "mage_monkey",
		"label": "PLAYER_QUEST_BLUEY",
		"hidden": false,
	},
}

# Stats persistentes em [progress]. Chaves usadas pelo sistema.
const STAT_MAX_WAVE: StringName = &"max_wave_reached"
const STAT_KILLS: StringName = &"enemies_killed_total"
const STAT_DMG_DEALT: StringName = &"dmg_dealt_total"
const STAT_RUNS_COMPLETED: StringName = &"runs_completed"
const STAT_RUNS_NO_DAMAGE: StringName = &"runs_no_damage"
const STAT_BOSSES_KILLED_TOTAL: StringName = &"bosses_killed_total"
# Set de boss IDs já abatidos (persistente entre runs). Armazenado como string
# CSV no settings.cfg porque ConfigFile só aceita primitivos.
const _KEY_BOSSES_KILLED_SET: String = "bosses_killed_set"


# ---------- Loadout (load/save) ----------

static func load_loadout() -> Dictionary:
	var cfg := ConfigFile.new()
	var has_settings: bool = cfg.load(_SETTINGS_PATH) == OK
	if not has_settings or not cfg.has_section(_SECTION):
		return _build_default_loadout()
	var result: Dictionary = {}
	var by_slot: Dictionary = scan_available_parts()
	for slot in SLOTS:
		var saved_path: String = str(cfg.get_value(_SECTION, String(slot), ""))
		if saved_path.is_empty():
			continue
		var parts: Array = by_slot.get(slot, [])
		for p in parts:
			var part: SkinPart = p
			if part.texture != null and part.texture.resource_path == saved_path and is_unlocked(part):
				result[slot] = part
				break
	return result


static func save_loadout(loadout: Dictionary) -> void:
	var cfg := ConfigFile.new()
	cfg.load(_SETTINGS_PATH)
	for slot in SLOTS:
		var part: SkinPart = loadout.get(slot)
		var path: String = part.texture.resource_path if part != null and part.texture != null else ""
		cfg.set_value(_SECTION, String(slot), path)
	cfg.save(_SETTINGS_PATH)


static func apply_to(target: Node) -> void:
	var skin: Node = target.get_node_or_null("Skin")
	if skin == null or not skin.has_method("set_part"):
		return
	var loadout: Dictionary = load_loadout()
	for slot in SLOTS:
		var part: SkinPart = loadout.get(slot)
		skin.set_part(slot, part)


static func _build_default_loadout() -> Dictionary:
	var by_slot: Dictionary = scan_available_parts()
	var loadout: Dictionary = {}
	for slot in SLOTS:
		var preferred: String = String(DEFAULT_PREFERENCES.get(slot, ""))
		if preferred.is_empty():
			continue
		var parts: Array = by_slot.get(slot, [])
		var match_part: SkinPart = null
		var fallback_part: SkinPart = null
		for p in parts:
			var part: SkinPart = p
			if not is_unlocked(part):
				continue
			if part.display_name == preferred:
				match_part = part
				break
			if part.display_name == "Default" and fallback_part == null:
				fallback_part = part
		if match_part != null:
			loadout[slot] = match_part
		elif fallback_part != null:
			loadout[slot] = fallback_part
	return loadout


# ---------- Scan available parts ----------

static func scan_available_parts() -> Dictionary:
	var by_slot: Dictionary = {}
	for slot in SLOTS:
		var dir_name: String = SLOT_TO_DIR.get(slot, String(slot))
		var dir_path: String = "res://assets/player/%s" % dir_name
		var dir := DirAccess.open(dir_path)
		if dir == null:
			continue
		var parts: Array = []
		# Em build exportado, os .png originais NÃO ficam no .pck — só os
		# .png.import (metadata) + .ctex (textura binária). No editor, ambos
		# existem. Aceita os dois formatos e dedupe pelo nome final do PNG.
		var seen_png: Dictionary = {}
		dir.list_dir_begin()
		var file: String = dir.get_next()
		while file != "":
			if not dir.current_is_dir():
				var lower: String = file.to_lower()
				var png_name: String = ""
				if lower.ends_with(".png"):
					png_name = file
				elif lower.ends_with(".png.import"):
					png_name = file.substr(0, file.length() - 7)  # tira ".import"
				if not png_name.is_empty() and not seen_png.has(png_name):
					seen_png[png_name] = true
					if not (slot == &"bow" and png_name.to_lower().ends_with("_back.png")):
						var part: SkinPart = _build_part(slot, dir_path, png_name)
						if part != null:
							parts.append(part)
			file = dir.get_next()
		dir.list_dir_end()
		parts.sort_custom(func(a: SkinPart, b: SkinPart) -> bool:
			return a.display_name.to_lower() < b.display_name.to_lower())
		by_slot[slot] = parts
	return by_slot


static func _build_part(slot: StringName, dir_path: String, file: String) -> SkinPart:
	var primary_path: String = "%s/%s" % [dir_path, file]
	var tex: Texture2D = load(primary_path) as Texture2D
	if tex == null:
		return null
	var part := SkinPart.new()
	part.slot = slot
	var stem: String = file.get_basename()
	if slot == &"bow":
		stem = stem.trim_suffix("_front").trim_suffix("_Front").trim_suffix("_FRONT")
	part.display_name = stem
	part.texture = tex
	part.thumbnail = tex
	if slot == &"bow":
		for suffix in ["_back.png", "_Back.png", "_BACK.png"]:
			var back_path: String = "%s/%s%s" % [dir_path, stem, suffix]
			if ResourceLoader.exists(back_path):
				part.texture_back = load(back_path) as Texture2D
				break
	return part


# ---------- Persistent stats ----------

static func get_stat(key: StringName) -> int:
	var cfg := ConfigFile.new()
	if cfg.load(_SETTINGS_PATH) != OK:
		return 0
	return int(cfg.get_value(_PROGRESS_SECTION, String(key), 0))


static func set_stat(key: StringName, value: int) -> void:
	var cfg := ConfigFile.new()
	cfg.load(_SETTINGS_PATH)
	cfg.set_value(_PROGRESS_SECTION, String(key), value)
	cfg.save(_SETTINGS_PATH)


# ---------- Quest evaluation ----------

static func _is_quest_satisfied(quest: Dictionary) -> bool:
	var qtype: String = String(quest.get("type", ""))
	var raw_value: Variant = quest.get("value", 0)
	match qtype:
		"wave_reached":
			return get_stat(STAT_MAX_WAVE) >= int(raw_value)
		"enemies_killed":
			return get_stat(STAT_KILLS) >= int(raw_value)
		"dmg_dealt":
			return get_stat(STAT_DMG_DEALT) >= int(raw_value)
		"runs_completed":
			return get_stat(STAT_RUNS_COMPLETED) >= int(raw_value)
		"no_damage_run":
			return get_stat(STAT_RUNS_NO_DAMAGE) >= int(raw_value)
		"boss_killed":
			return has_killed_boss(String(raw_value))
	return true  # type desconhecido: assume desbloqueada (não bloqueia o jogo).


# Set persistente de IDs de bosses já abatidos (qualquer run).
static func get_bosses_killed_set() -> PackedStringArray:
	var cfg := ConfigFile.new()
	if cfg.load(_SETTINGS_PATH) != OK:
		return PackedStringArray()
	var raw: String = str(cfg.get_value(_PROGRESS_SECTION, _KEY_BOSSES_KILLED_SET, ""))
	if raw.is_empty():
		return PackedStringArray()
	return PackedStringArray(raw.split(",", false))


static func _save_bosses_killed_set(arr: PackedStringArray) -> void:
	var cfg := ConfigFile.new()
	cfg.load(_SETTINGS_PATH)
	cfg.set_value(_PROGRESS_SECTION, _KEY_BOSSES_KILLED_SET, ",".join(arr))
	cfg.save(_SETTINGS_PATH)


static func has_killed_boss(boss_id: String) -> bool:
	if boss_id.is_empty():
		return false
	return boss_id in get_bosses_killed_set()


static func is_unlocked(part: SkinPart) -> bool:
	if part == null:
		return true
	# Debug build (editor + debug export) libera tudo — facilita testar skins
	# sem precisar grindar quests. Release build mantém unlock real.
	if OS.is_debug_build():
		return true
	var quest: Dictionary = SKIN_QUESTS.get(part.display_name, {})
	if quest.is_empty():
		return true
	return _is_quest_satisfied(quest)


static func get_quest_for(display_name: String) -> Dictionary:
	return SKIN_QUESTS.get(display_name, {})


# Skin "hidden lock" = quest tem `hidden=true` E ainda está locked.
# UI usa pra esconder o card completamente (vs mostrar como "?" / lockada).
static func is_hidden_locked(part: SkinPart) -> bool:
	if part == null:
		return false
	if is_unlocked(part):
		return false
	var quest: Dictionary = SKIN_QUESTS.get(part.display_name, {})
	return bool(quest.get("hidden", false))


# Atualiza stats persistentes baseado nos resultados da run e retorna lista
# de display_names que acabaram de desbloquear (eram lockados antes, agora satisfeitos).
# Chamado de hud.gd no death.
#
# run_stats: { wave, kills, dmg_dealt, dmg_taken } — todos opcionais (default 0).
static func record_run(run_stats: Dictionary) -> Array:
	# 1. Snapshot do estado de unlock antes de atualizar stats.
	var was_locked: Dictionary = {}
	for skin_name in SKIN_QUESTS.keys():
		was_locked[skin_name] = not _is_quest_satisfied(SKIN_QUESTS[skin_name])

	# 2. Atualiza stats persistentes com os resultados da run.
	var run_wave: int = int(run_stats.get("wave", 0))
	var run_kills: int = int(run_stats.get("kills", 0))
	var run_dmg_dealt: int = int(run_stats.get("dmg_dealt", 0))
	var run_dmg_taken: int = int(run_stats.get("dmg_taken", 0))

	if run_wave > get_stat(STAT_MAX_WAVE):
		set_stat(STAT_MAX_WAVE, run_wave)
	if run_kills > 0:
		set_stat(STAT_KILLS, get_stat(STAT_KILLS) + run_kills)
	if run_dmg_dealt > 0:
		set_stat(STAT_DMG_DEALT, get_stat(STAT_DMG_DEALT) + run_dmg_dealt)
	set_stat(STAT_RUNS_COMPLETED, get_stat(STAT_RUNS_COMPLETED) + 1)
	if run_dmg_taken == 0 and run_wave >= 1:
		set_stat(STAT_RUNS_NO_DAMAGE, get_stat(STAT_RUNS_NO_DAMAGE) + 1)
	# Bosses mortos nesta run: incrementa total e adiciona IDs novos ao set.
	# Total conta cada kill (mesmo boss em runs diferentes); set é único.
	var run_bosses: Array = run_stats.get("bosses_killed", [])
	if not run_bosses.is_empty():
		var existing: PackedStringArray = get_bosses_killed_set()
		var changed: bool = false
		for boss_id_v in run_bosses:
			var boss_id: String = String(boss_id_v)
			if boss_id.is_empty():
				continue
			set_stat(STAT_BOSSES_KILLED_TOTAL, get_stat(STAT_BOSSES_KILLED_TOTAL) + 1)
			if not boss_id in existing:
				existing.append(boss_id)
				changed = true
		if changed:
			_save_bosses_killed_set(existing)

	# 3. Detecta quem mudou de locked → unlocked.
	var newly_unlocked: Array = []
	for skin_name in SKIN_QUESTS.keys():
		if was_locked[skin_name] and _is_quest_satisfied(SKIN_QUESTS[skin_name]):
			newly_unlocked.append(String(skin_name))
	return newly_unlocked


# Retorna { slot -> SkinPart } pra todas as peças com o display_name dado.
static func get_parts_by_skin_name(skin_name: String) -> Dictionary:
	var by_slot: Dictionary = scan_available_parts()
	var result: Dictionary = {}
	for slot in by_slot.keys():
		for p in by_slot[slot]:
			var part: SkinPart = p
			if part.display_name == skin_name:
				result[slot] = part
				break
	return result
