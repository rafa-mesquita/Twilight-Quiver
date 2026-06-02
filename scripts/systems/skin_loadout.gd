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

# Override de peça por kit + slot. Permite kits partilharem peças idênticas sem
# duplicar PNGs. Formato: { kit_display_name: { slot: part_display_name } }.
#  - body de "Linked"/"Rosa_Onyx" resolve pra "Linked_Pink" (mesmo tom de pele).
#  - arco+aljava de "Hawk"/"Skeleton" resolvem pra "Hawk_Skeleton" — peça única,
#    aparece como UM card nas abas Arco/Aljava em vez de dois iguais.
#  - body de "Hawk"/"Destiny" resolve pra "Hawk_Destiny" (corpo idêntico). As
#    PERNAS são próprias de cada um (diferentes). Destiny NÃO tem bow/quiver
#    próprios → caem no Default (preenchimento do kit).
const KIT_PART_OVERRIDE: Dictionary = {
	"Linked":    {&"body": "Linked_Pink"},
	"Rosa_Onyx": {&"body": "Linked_Pink"},
	"Hawk":      {&"bow": "Hawk_Skeleton", &"quiver": "Hawk_Skeleton", &"body": "Hawk_Destiny"},
	"Skeleton":  {&"bow": "Hawk_Skeleton", &"quiver": "Hawk_Skeleton"},
	"Destiny":   {&"body": "Hawk_Destiny"},
	# Warrior e Patriota compartilham o MESMO corpo/rosto (a cor de pele "Green_Eyes").
	# Patriota tem o resto próprio; Warrior compartilha arco/aljava/capa+máscara
	# com a Sputnik (peça única "Sputnik_Warrior").
	"Warrior":   {&"body": "Green_Eyes", &"bow": "Sputnik_Warrior", &"quiver": "Sputnik_Warrior", &"cape": "Sputnik_Warrior"},
	"Patriota":  {&"body": "Green_Eyes"},
	# Sputnik: body/legs/shirt/hair próprios; arco/aljava/capa+máscara vêm da peça
	# partilhada "Sputnik_Warrior" (idêntica à do Warrior).
	"Sputnik":   {&"bow": "Sputnik_Warrior", &"quiver": "Sputnik_Warrior", &"cape": "Sputnik_Warrior"},
}

# Peças PARTILHADAS entre kits (resolvidas via KIT_PART_OVERRIDE), NÃO kits
# próprios. Mesmo ocupando >= _KIT_MIN_SLOTS slots, não listam como card de kit.
const SHARED_PART_NAMES: Array[String] = ["Hawk_Skeleton", "Hawk_Destiny", "Sputnik_Warrior"]

# Migração de display_names salvos (saves antigos) → nome atual, por slot.
#  - body "Linked" virou "Linked_Pink".
#  - arco/aljava "Hawk" e "Skeleton" viraram a peça partilhada "Hawk_Skeleton".
#  - "Terracota" foi renomeada pra "Earthy" (todas as peças do kit).
const PART_NAME_MIGRATIONS: Dictionary = {
	&"body":   {"Linked": "Linked_Pink", "Terracota": "Earthy", "Hawk": "Hawk_Destiny", "Destiny": "Hawk_Destiny", "Warrior": "Green_Eyes"},
	&"legs":   {"Terracota": "Earthy"},
	&"shirt":  {"Terracota": "Earthy"},
	&"cape":   {"Terracota": "Earthy", "Warrior": "Sputnik_Warrior"},
	&"quiver": {"Hawk": "Hawk_Skeleton", "Skeleton": "Hawk_Skeleton", "Terracota": "Earthy", "Warrior": "Sputnik_Warrior"},
	&"hair":   {"Terracota": "Earthy"},
	&"bow":    {"Hawk": "Hawk_Skeleton", "Skeleton": "Hawk_Skeleton", "Terracota": "Earthy", "Warrior": "Sputnik_Warrior"},
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
#   armor_lv5       — comprar Armadura até o Lv5 em alguma run (flag persistente)
#   long_mage_kill  — matar um mago longe (>= 350px) com flecha perfurante (flag)
#   no_arrow_round  — passar de um round sem disparo manual de flecha (flag)
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
	"Linked": {
		"type": "monkeys_cursed",
		"value": 200,
		"label": "PLAYER_QUEST_LINKED",
		"hidden": false,
	},
	"Hawk": {
		# Passar das waves 1, 2 e 3 sem tomar NENHUM dano (flag setada no fim da
		# wave 3 se o dano acumulado da run for 0).
		"type": "flawless_w3",
		"value": 1,
		"label": "PLAYER_QUEST_HAWK",
		"hidden": false,
	},
	"Rosa_Onyx": {
		"type": "boss_killed",
		"value": "duskrose",
		"label": "PLAYER_QUEST_ROSA_ONYX",
		"hidden": false,
	},
	"Earthy": {
		"type": "stun_seconds",
		"value": 1000,
		"label": "PLAYER_QUEST_EARTHY",
		"hidden": false,
	},
	"Skeleton": {
		"type": "elemental_l4",
		"value": 1,
		"label": "PLAYER_QUEST_SKELETON",
		"hidden": false,
	},
	"Urban": {
		# Usar skills ativáveis (Q elemental OU espaço: dash/esquivando) 500 vezes.
		"type": "active_skills_used",
		"value": 500,
		"label": "PLAYER_QUEST_URBAN",
		"hidden": false,
	},
	"Destiny": {
		# Derrotar os DOIS bosses da Raid 21 (confronto duplo). A raid 21 só
		# termina com os dois mortos → o wave_manager reporta "raid21" via
		# notify_boss_killed ao concluir a wave (mesma engrenagem do boss_killed).
		"type": "boss_killed",
		"value": "raid21",
		"label": "PLAYER_QUEST_DESTINY",
		"hidden": false,
	},
	"Warrior": {
		# Comprar o status de Armadura até o Lv5 em alguma run (flag persistente,
		# setada no record_run quando armor_level >= 5 no death).
		"type": "armor_lv5",
		"value": 1,
		"label": "PLAYER_QUEST_WARRIOR",
		"hidden": false,
	},
	"Patriota": {
		# Tema futebol americano ("lançamento longo"): matar um mago a longa
		# distância (>= 350px, além do alcance da flecha normal) com flecha
		# PERFURANTE do player. Flag persistente setada no arrow.gd via
		# notify_long_mage_kill → record_run.
		"type": "long_mage_kill",
		"value": 1,
		"label": "PLAYER_QUEST_PATRIOTA",
		"hidden": false,
	},
	"Sputnik": {
		# Passar de um round (qualquer wave >= 1) sem disparar NENHUMA flecha pelo
		# botão do mouse. Skills (garra/boomerang/dash) são livres — o auto-ataque
		# do dash NÃO conta como disparo manual. Flag persistente setada no
		# wave_manager._finish_wave via stats_no_arrow_round → record_run.
		"type": "no_arrow_round",
		"value": 1,
		"label": "PLAYER_QUEST_SPUTNIK",
		"hidden": false,
	},
}

# DEV: skins que ficam BLOQUEADAS mesmo em debug build, pra testar a UI de skin
# bloqueada (nome vermelho, "!", tooltip de unlock no hover, preview com filtro
# vermelho leve, botão Salvar travado). Esvaziar ([]) pra desbloquear tudo em
# debug como antes. IGNORADO em release — lá vale a quest real de cada skin.
const DEV_FORCE_LOCKED: Array[String] = []
# DEV: quando true, debug build libera TODAS as skins (atalho pra testar visuais
# sem grindar). Setado FALSE pra testar os UNLOCKS reais no dev — as skins ficam
# bloqueadas até cumprir a quest, igual ao release. Flipar pra true pra voltar ao
# atalho. (Em release sempre vale a quest real, independente disso.)
const DEV_UNLOCK_ALL: bool = true
# DEV: skins que respeitam a quest REAL mesmo com DEV_UNLOCK_ALL=true (o resto
# continua livre no dev). Use pra testar a liberação de skins específicas sem
# relockar tudo. Esvaziar ([]) quando terminar de testar.
const DEV_QUEST_LOCKED: Array[String] = ["Patriota", "Sputnik"]

# Stats persistentes em [progress]. Chaves usadas pelo sistema.
const STAT_MAX_WAVE: StringName = &"max_wave_reached"
const STAT_KILLS: StringName = &"enemies_killed_total"
const STAT_DMG_DEALT: StringName = &"dmg_dealt_total"
const STAT_RUNS_COMPLETED: StringName = &"runs_completed"
const STAT_RUNS_NO_DAMAGE: StringName = &"runs_no_damage"
const STAT_BOSSES_KILLED_TOTAL: StringName = &"bosses_killed_total"
# Macaquinhos (grupo "monkey") convertidos pelo disparo profano. Acumula
# entre runs — unlock da skin Linked aos 200.
const STAT_MONKEYS_CURSED: StringName = &"monkeys_cursed_total"
# Segundos de stun que o player causa em inimigos, acumulados entre runs
# (qualquer fonte: claudio druida, pedra, terremoto, gelo). Unlock da Earthy.
const STAT_STUN_SECONDS: StringName = &"stun_seconds_total"
# Flag (0/1): jogador já chegou ao Lv4 de QUALQUER elemental (fogo/maldição/
# gelo/pedra) em alguma run. Unlock da skin Skeleton.
const STAT_ELEMENTAL_L4: StringName = &"elemental_l4_reached"
# Quantas skills ativáveis (Q elemental ou espaço: dash/esquivando) o player
# usou no total entre runs. Unlock da skin Urban.
const STAT_ACTIVE_SKILLS: StringName = &"active_skills_used_total"
# Flag (0/1): jogador já passou das waves 1, 2 e 3 sem tomar dano em alguma run.
# Unlock da skin Hawk.
const STAT_FLAWLESS_W3: StringName = &"flawless_through_w3"
# Flag (0/1): jogador já comprou Armadura até o Lv5 em alguma run. Unlock da skin Warrior.
const STAT_ARMOR_LV5: StringName = &"armor_lv5_reached"
# Flag (0/1): matou um mago longe (>= 350px) com flecha perfurante. Unlock da skin Patriota.
const STAT_LONG_MAGE_KILL: StringName = &"long_mage_kill_done"
# Flag (0/1): jogador já passou de um round sem disparo manual de flecha. Unlock Sputnik.
const STAT_NO_ARROW_ROUND: StringName = &"no_arrow_round_done"
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
		var saved: String = str(cfg.get_value(_SECTION, String(slot), ""))
		if saved.is_empty():
			continue
		# Migração de saves antigos: nomes renomeados → atuais (por slot).
		var slot_migrations: Dictionary = PART_NAME_MIGRATIONS.get(slot, {})
		if slot_migrations.has(saved):
			saved = String(slot_migrations[saved])
		var parts: Array = by_slot.get(slot, [])
		# Match em 2 etapas pra compat: 1º tenta display_name (formato novo,
		# estável entre builds); 2º tenta resource_path (formato legado pré-fix).
		# Resource_path quebrava em build exportado porque texturas viram .ctex
		# com hash que difere entre builds.
		var matched: SkinPart = null
		for p in parts:
			var part: SkinPart = p
			if not is_unlocked(part):
				continue
			if part.display_name == saved:
				matched = part
				break
		if matched == null:
			for p in parts:
				var part2: SkinPart = p
				if part2.texture != null and part2.texture.resource_path == saved and is_unlocked(part2):
					matched = part2
					break
		if matched != null:
			result[slot] = matched
	# Fill-in: pra qualquer slot ainda vazio que tenha Default disponível,
	# usa Default (resiliente a settings corrompido / migração de versão).
	for slot in SLOTS:
		if result.has(slot):
			continue
		for p in (by_slot.get(slot, []) as Array):
			var part: SkinPart = p
			if part.display_name == "Default" and is_unlocked(part):
				result[slot] = part
				break
	return result


static func save_loadout(loadout: Dictionary) -> void:
	var cfg := ConfigFile.new()
	cfg.load(_SETTINGS_PATH)
	for slot in SLOTS:
		var part: SkinPart = loadout.get(slot)
		# Salva display_name (basename do PNG) — estável entre builds. O
		# resource_path do imported .ctex pode mudar e quebrava o load.
		var saved: String = part.display_name if part != null else ""
		cfg.set_value(_SECTION, String(slot), saved)
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
		"monkeys_cursed":
			return get_stat(STAT_MONKEYS_CURSED) >= int(raw_value)
		"stun_seconds":
			return get_stat(STAT_STUN_SECONDS) >= int(raw_value)
		"elemental_l4":
			return get_stat(STAT_ELEMENTAL_L4) >= int(raw_value)
		"active_skills_used":
			return get_stat(STAT_ACTIVE_SKILLS) >= int(raw_value)
		"flawless_w3":
			return get_stat(STAT_FLAWLESS_W3) >= int(raw_value)
		"armor_lv5":
			return get_stat(STAT_ARMOR_LV5) >= int(raw_value)
		"long_mage_kill":
			return get_stat(STAT_LONG_MAGE_KILL) >= int(raw_value)
		"no_arrow_round":
			return get_stat(STAT_NO_ARROW_ROUND) >= int(raw_value)
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


static func quest_progress_suffix(quest: Dictionary) -> String:
	# Sufixo " | X / Y" pra quests de CONTAGEM. Binarias (boss_killed/elemental_l4/
	# flawless_w3) ou value<=1: retorna vazio (sem progresso a mostrar).
	var target: int = int(quest.get("value", 0))
	if target <= 1:
		return ""
	var stat_by_type := {
		"wave_reached": STAT_MAX_WAVE,
		"enemies_killed": STAT_KILLS,
		"dmg_dealt": STAT_DMG_DEALT,
		"runs_completed": STAT_RUNS_COMPLETED,
		"no_damage_run": STAT_RUNS_NO_DAMAGE,
		"monkeys_cursed": STAT_MONKEYS_CURSED,
		"stun_seconds": STAT_STUN_SECONDS,
		"active_skills_used": STAT_ACTIVE_SKILLS,
	}
	var qtype: String = String(quest.get("type", ""))
	if not stat_by_type.has(qtype):
		return ""
	var current: int = mini(get_stat(stat_by_type[qtype]), target)
	return "  |  %d / %d" % [current, target]


static func progress_suffix_for_label(label_key: String) -> String:
	# Acha a quest pelo label (translation key) e devolve o sufixo de progresso.
	if label_key == "":
		return ""
	for skin_name in SKIN_QUESTS:
		if String(SKIN_QUESTS[skin_name].get("label", "")) == label_key:
			return quest_progress_suffix(SKIN_QUESTS[skin_name])
	return ""


static func is_unlocked(part: SkinPart) -> bool:
	if part == null:
		return true
	# Debug build libera tudo SÓ se DEV_UNLOCK_ALL (atalho de teste de visuais).
	# Com DEV_UNLOCK_ALL=false, debug respeita a quest real (skins relockadas pra
	# testar os unlocks). DEV_FORCE_LOCKED força locked mesmo com DEV_UNLOCK_ALL.
	if OS.is_debug_build() and DEV_UNLOCK_ALL:
		# DEV_QUEST_LOCKED: estas respeitam a quest real (pra testar a liberação);
		# o resto fica livre no dev.
		if DEV_QUEST_LOCKED.has(part.display_name):
			var q: Dictionary = SKIN_QUESTS.get(part.display_name, {})
			return q.is_empty() or _is_quest_satisfied(q)
		return not DEV_FORCE_LOCKED.has(part.display_name)
	var quest: Dictionary = SKIN_QUESTS.get(part.display_name, {})
	if quest.is_empty():
		return true
	return _is_quest_satisfied(quest)


static func get_quest_for(display_name: String) -> Dictionary:
	return SKIN_QUESTS.get(display_name, {})


static func is_kit_unlocked(kit_name: String) -> bool:
	# Unlock de um KIT inteiro pela quest do NOME do kit. Necessário porque o
	# body de alguns kits é sobrescrito (KIT_PART_OVERRIDE → "Linked_Pink"), e
	# checar o unlock pela peça body resolveria a quest errada: a peça partilhada
	# "Linked_Pink" não tem quest, então Linked/Rosa_Onyx desbloqueavam sem o
	# desafio. Aqui a quest é buscada pelo nome do kit (que casa com SKIN_QUESTS).
	if OS.is_debug_build() and DEV_UNLOCK_ALL:
		if DEV_QUEST_LOCKED.has(kit_name):
			var q: Dictionary = SKIN_QUESTS.get(kit_name, {})
			return q.is_empty() or _is_quest_satisfied(q)
		return not DEV_FORCE_LOCKED.has(kit_name)
	var quest: Dictionary = SKIN_QUESTS.get(kit_name, {})
	if quest.is_empty():
		return true
	return _is_quest_satisfied(quest)


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
	var run_monkeys_cursed: int = int(run_stats.get("monkeys_cursed", 0))
	var run_stun_seconds: int = int(run_stats.get("stun_seconds", 0))
	var run_active_skills: int = int(run_stats.get("active_skills_used", 0))

	if run_wave > get_stat(STAT_MAX_WAVE):
		set_stat(STAT_MAX_WAVE, run_wave)
	if run_kills > 0:
		set_stat(STAT_KILLS, get_stat(STAT_KILLS) + run_kills)
	if run_dmg_dealt > 0:
		set_stat(STAT_DMG_DEALT, get_stat(STAT_DMG_DEALT) + run_dmg_dealt)
	if run_monkeys_cursed > 0:
		set_stat(STAT_MONKEYS_CURSED, get_stat(STAT_MONKEYS_CURSED) + run_monkeys_cursed)
	if run_stun_seconds > 0:
		set_stat(STAT_STUN_SECONDS, get_stat(STAT_STUN_SECONDS) + run_stun_seconds)
	if run_active_skills > 0:
		set_stat(STAT_ACTIVE_SKILLS, get_stat(STAT_ACTIVE_SKILLS) + run_active_skills)
	# Flag persistente: chegou ao Lv4 de algum elemental nesta run (unlock Skeleton).
	if bool(run_stats.get("elemental_l4_reached", false)) and get_stat(STAT_ELEMENTAL_L4) < 1:
		set_stat(STAT_ELEMENTAL_L4, 1)
	# Flag persistente: passou das waves 1-3 sem dano nesta run (unlock Hawk).
	if bool(run_stats.get("flawless_through_w3", false)) and get_stat(STAT_FLAWLESS_W3) < 1:
		set_stat(STAT_FLAWLESS_W3, 1)
	# Flag persistente: comprou Armadura até o Lv5 nesta run (unlock Warrior).
	if bool(run_stats.get("armor_lv5_reached", false)) and get_stat(STAT_ARMOR_LV5) < 1:
		set_stat(STAT_ARMOR_LV5, 1)
	# Flag persistente: matou um mago longe (>= 350px) com flecha perfurante (unlock Patriota).
	if bool(run_stats.get("long_mage_kill", false)) and get_stat(STAT_LONG_MAGE_KILL) < 1:
		set_stat(STAT_LONG_MAGE_KILL, 1)
	# Flag persistente: passou de um round sem disparo manual de flecha (unlock Sputnik).
	if bool(run_stats.get("no_arrow_round", false)) and get_stat(STAT_NO_ARROW_ROUND) < 1:
		set_stat(STAT_NO_ARROW_ROUND, 1)
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
# Slots com override em KIT_PART_OVERRIDE resolvem pra outra peça (kits podem
# partilhar tom de pele e arco/aljava sem duplicar PNG).
static func get_parts_by_skin_name(skin_name: String) -> Dictionary:
	var by_slot: Dictionary = scan_available_parts()
	var result: Dictionary = {}
	var overrides: Dictionary = KIT_PART_OVERRIDE.get(skin_name, {})
	for slot in by_slot.keys():
		var target_name: String = String(overrides.get(slot, skin_name))
		for p in by_slot[slot]:
			var part: SkinPart = p
			if part.display_name == target_name:
				result[slot] = part
				break
	return result
