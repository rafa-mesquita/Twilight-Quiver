class_name InventoryItems
extends RefCounted

# Catálogo de itens equipáveis (buffs PRÉ-JOGO) + sistema de DESBLOQUEIO análogo às
# skins. Cada item tem um efeito e um requisito de unlock:
#   - "default": sempre liberado (ex.: elemental_master — exemplo de item liberado).
#   - "shop":    libera comprando na loja meta (ainda NÃO existe -> travado por ora).
#   - "quest":   libera cumprindo requisitos (stats persistentes via SkinLoadout).
# Itens liberados equipam (máx MAX_SLOTS); travados aparecem no inventário com visual
# de bloqueio + requisito no hover (ver skin_select.gd) e NUNCA ficam ativos.
#
# Equipados salvos em settings.cfg [inventory] equipped (CSV de ids).

const _SETTINGS_PATH: String = "user://settings.cfg"
const _SECTION: String = "inventory"
const _KEY_EQUIPPED: String = "equipped"
const _KEY_PURCHASED: String = "purchased"
const MAX_SLOTS: int = 3

# DEV: em debug build, true libera TODO item (pra testar efeitos). Default FALSE pra
# enxergar o estado travado no editor. Ignorado em release (lá vale o unlock real).
const DEV_UNLOCK_ALL_ITEMS: bool = false

# Fontes de kill consideradas "de Aliado" (creditadas via player.notify_kill_by_source).
# Usado pra contar o stat ally_kills (quest do Adote Mais Um).
const ALLY_KILL_SOURCES: Array[String] = [
	"frostwisp", "ting_turret", "capivara_joe", "leno", "claudio_druida",
]

# effect.type:
#   "start_status"           — aplica `amount` níveis de apply_upgrade(`status`) no início.
#   "welcome_elemental_choice" — welcome upgrade vira escolha de elemental (wave_manager).
#   "pet_slot"               — +`amount` slot(s) de aliado (lido por wave_shop).
#   "gold_per_round"         — +`amount` gold no fim de cada round (lido por wave_manager).
const ITEMS: Dictionary = {
	"midnight_dagger": {
		"name": "ITEM_MIDNIGHT_DAGGER_NAME",
		"desc": "ITEM_MIDNIGHT_DAGGER_DESC",
		"icon": "res://assets/Hud/itens/midnight_dagger.png",
		"effect": {"type": "start_status", "status": "damage", "amount": 1},
		"unlock": {"type": "shop"},
	},
	"golden_bow": {
		"name": "ITEM_GOLDEN_BOW_NAME",
		"desc": "ITEM_GOLDEN_BOW_DESC",
		"icon": "res://assets/Hud/itens/golden_bow.png",
		"effect": {"type": "start_status", "status": "attack_speed", "amount": 1},
		"unlock": {"type": "shop"},
	},
	"elemental_master": {
		"name": "ITEM_ELEMENTAL_MASTER_NAME",
		"desc": "ITEM_ELEMENTAL_MASTER_DESC",
		"icon": "res://assets/Hud/itens/elemental_master.png",
		"effect": {"type": "welcome_elemental_choice"},
		"unlock": {"type": "quest", "reqs": [
			{"stat": &"elemental_roulette_buys_total", "value": 10, "label": "ITEM_REQ_ELEMENTAL"},
		]},
	},
	"adopt_one_more": {
		"name": "ITEM_ADOPT_ONE_MORE_NAME",
		"desc": "ITEM_ADOPT_ONE_MORE_DESC",
		"icon": "res://assets/Hud/itens/adopt_one_more.png",
		"effect": {"type": "pet_slot", "amount": 1},
		"unlock": {"type": "quest", "reqs": [
			{"stat": &"ally_heal_total", "value": 1500, "label": "ITEM_REQ_ADOPT_HEAL"},
			{"stat": &"ally_kills_total", "value": 1000, "label": "ITEM_REQ_ADOPT_KILLS"},
		]},
	},
	"arcane_dividend": {
		"name": "ITEM_ARCANE_DIVIDEND_NAME",
		"desc": "ITEM_ARCANE_DIVIDEND_DESC",
		"icon": "res://assets/Hud/itens/arcane_dividend.png",
		"effect": {"type": "gold_per_round", "amount": 1},
		"unlock": {"type": "quest", "reqs": [
			{"stat": &"gold_spent_total", "value": 2500, "label": "ITEM_REQ_ARCANE_GOLD"},
		]},
	},
	"feeling_lucky": {
		"name": "ITEM_LUCKY_NAME",
		"desc": "ITEM_LUCKY_DESC",
		"icon": "res://assets/Hud/itens/feeling_lucky.png",
		"effect": {"type": "free_first_roll", "chance": 0.40},
		"unlock": {"type": "quest", "reqs": [
			{"stat": &"waves_cleared_total", "value": 1, "label": "ITEM_REQ_LUCKY"},
		]},
	},
	"no_limite": {
		"name": "ITEM_NO_LIMITE_NAME",
		"desc": "ITEM_NO_LIMITE_DESC",
		"icon": "res://assets/Hud/itens/no_limite.png",
		"effects": [
			{"type": "max_hp_override", "value": 50},
			{"type": "disable_shop_hp"},
			{"type": "start_status", "status": "move_speed", "amount": 1},
			{"type": "start_status", "status": "gold_magnet", "amount": 2},
		],
		"unlock": {"type": "quest", "reqs": [
			{"stat": &"low_hp_kills_total", "value": 500, "label": "ITEM_REQ_NO_LIMITE"},
		]},
	},
}


static func all_ids() -> Array:
	return ITEMS.keys()


static func get_icon_path(id: String) -> String:
	return String(ITEMS.get(id, {}).get("icon", ""))


# True se o item está liberado (equipável). "default" sempre; "shop" travado até a
# loja meta existir; "quest" depende dos stats persistentes (SkinLoadout).
static func is_unlocked(id: String) -> bool:
	var item: Dictionary = ITEMS.get(id, {})
	if item.is_empty():
		return false
	var unlock: Dictionary = item.get("unlock", {"type": "default"})
	var t: String = String(unlock.get("type", "default"))
	if t == "default":
		return true
	if DEV_UNLOCK_ALL_ITEMS and OS.is_debug_build():
		return true
	match t:
		"shop":
			return is_purchased(id)
		"quest":
			for req in unlock.get("reqs", []):
				if SkinLoadout.get_stat(req.get("stat")) < int(req.get("value", 0)):
					return false
			return true
	return false


# Compat: "owned" agora é sinônimo de "unlocked".
static func is_owned(id: String) -> bool:
	return is_unlocked(id)


# Compra persistente na loja meta (itens tipo "shop"). settings.cfg [inventory] purchased.
static func is_purchased(id: String) -> bool:
	var cfg := ConfigFile.new()
	if cfg.load(_SETTINGS_PATH) != OK:
		return false
	return id in str(cfg.get_value(_SECTION, _KEY_PURCHASED, "")).split(",", false)


static func mark_purchased(id: String) -> void:
	var cfg := ConfigFile.new()
	cfg.load(_SETTINGS_PATH)
	var ids: Array = []
	for s in str(cfg.get_value(_SECTION, _KEY_PURCHASED, "")).split(",", false):
		ids.append(s)
	if not (id in ids):
		ids.append(id)
		cfg.set_value(_SECTION, _KEY_PURCHASED, ",".join(PackedStringArray(ids)))
		cfg.save(_SETTINGS_PATH)


# Linhas de "como liberar" pro tooltip. Cada entry: {label, met}. "default" -> vazio.
static func get_unlock_reqs(id: String) -> Array:
	var item: Dictionary = ITEMS.get(id, {})
	var unlock: Dictionary = item.get("unlock", {"type": "default"})
	var t: String = String(unlock.get("type", "default"))
	match t:
		"shop":
			return [{"label": "ITEM_UNLOCK_SHOP", "met": false}]
		"quest":
			var out: Array = []
			for req in unlock.get("reqs", []):
				out.append({
					"label": String(req.get("label", "")),
					"met": SkinLoadout.get_stat(req.get("stat")) >= int(req.get("value", 0)),
				})
			return out
	return []


# Itens (quest) cujos requisitos estão satisfeitos com stats PERSISTENTES + os
# deltas da run atual (run_stats: mesmo dict do hud._collect_run_stats). Cada
# stat persistente "<x>_total" lê o delta da run pela chave "<x>". Usado pelo
# HUD pra o toast de desbloqueio em tempo real.
static func evaluate_live_unlocks(run_stats: Dictionary) -> Array:
	var out: Array = []
	for id in ITEMS.keys():
		var unlock: Dictionary = ITEMS[id].get("unlock", {})
		if String(unlock.get("type", "")) != "quest":
			continue
		var all_met: bool = true
		for req in unlock.get("reqs", []):
			var stat: StringName = req.get("stat")
			var run_key: String = String(stat).trim_suffix("_total")
			var live_val: int = SkinLoadout.get_stat(stat) + int(run_stats.get(run_key, 0))
			if live_val < int(req.get("value", 0)):
				all_met = false
				break
		if all_met:
			out.append(String(id))
	return out


# Lista de efeitos de um item (suporta "effects": [..] novo OU "effect": {..} antigo).
static func _item_effects(id: Variant) -> Array:
	var item: Dictionary = ITEMS.get(id, {})
	if item.has("effects"):
		return item.get("effects", [])
	if item.has("effect"):
		return [item.get("effect")]
	return []


# True se algum item equipado faz o welcome upgrade virar escolha de elemental.
static func has_welcome_elemental_choice() -> bool:
	for id in get_equipped():
		for eff in _item_effects(id):
			if String(eff.get("type", "")) == "welcome_elemental_choice":
				return true
	return false


# True se algum item equipado tira o status de HP da loja (No Limite).
static func disables_shop_hp() -> bool:
	for id in get_equipped():
		for eff in _item_effects(id):
			if String(eff.get("type", "")) == "disable_shop_hp":
				return true
	return false


# Bônus de slots de pet vindo de itens equipados (effect pet_slot).
static func equipped_pet_slot_bonus() -> int:
	var bonus: int = 0
	for id in get_equipped():
		for eff in _item_effects(id):
			if String(eff.get("type", "")) == "pet_slot":
				bonus += int(eff.get("amount", 0))
	return bonus


# Gold extra no fim do round (soma dos itens equipados com gold_per_round).
static func equipped_gold_per_round() -> int:
	var g: int = 0
	for id in get_equipped():
		for eff in _item_effects(id):
			if String(eff.get("type", "")) == "gold_per_round":
				g += int(eff.get("amount", 0))
	return g


# Maior chance de "primeiro roll grátis" entre os itens equipados (Estou com Sorte).
static func equipped_free_first_roll_chance() -> float:
	var c: float = 0.0
	for id in get_equipped():
		for eff in _item_effects(id):
			if String(eff.get("type", "")) == "free_first_roll":
				c = maxf(c, float(eff.get("chance", 0.0)))
	return c


# Equipados liberados (filtra ids órfãos E itens travados — nunca ficam ativos).
static func get_equipped() -> Array:
	var cfg := ConfigFile.new()
	if cfg.load(_SETTINGS_PATH) != OK:
		return []
	var raw: String = str(cfg.get_value(_SECTION, _KEY_EQUIPPED, ""))
	if raw.is_empty():
		return []
	var out: Array = []
	for s in raw.split(",", false):
		if ITEMS.has(s) and is_unlocked(s):
			out.append(s)
	return out


static func is_equipped(id: String) -> bool:
	return id in get_equipped()


static func set_equipped(ids: Array) -> void:
	var cfg := ConfigFile.new()
	cfg.load(_SETTINGS_PATH)
	cfg.set_value(_SECTION, _KEY_EQUIPPED, ",".join(PackedStringArray(ids)))
	cfg.save(_SETTINGS_PATH)


# Alterna o estado de equipado. Só itens LIBERADOS. Retorna true se ficou EQUIPADO,
# false se desequipou OU não coube (slots cheios) OU está travado.
static func toggle_equipped(id: String) -> bool:
	if not is_unlocked(id):
		return false
	var eq: Array = get_equipped()
	if id in eq:
		eq.erase(id)
		set_equipped(eq)
		return false
	if eq.size() >= MAX_SLOTS:
		return false
	eq.append(id)
	set_equipped(eq)
	return true


# Aplica os efeitos start_status dos itens equipados no INÍCIO da run.
static func apply_to_player(player: Node) -> void:
	if player == null:
		return
	for id in get_equipped():
		for eff in _item_effects(id):
			var t: String = String(eff.get("type", ""))
			if t == "start_status" and player.has_method("apply_upgrade"):
				var status: String = String(eff.get("status", ""))
				for _i in int(eff.get("amount", 0)):
					player.apply_upgrade(status)
			elif t == "max_hp_override":
				var v: float = float(eff.get("value", 100))
				if "max_hp" in player:
					player.max_hp = v
				if player.has_method("reset_hp"):
					player.reset_hp()
				elif "hp" in player:
					player.hp = v
