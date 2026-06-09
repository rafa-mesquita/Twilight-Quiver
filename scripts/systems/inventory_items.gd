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
const DEV_UNLOCK_ALL_ITEMS: bool = true

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
			{"stat": &"elemental_roulette_buys_total", "value": 5, "label": "ITEM_REQ_ELEMENTAL"},
		]},
	},
	"adopt_one_more": {
		"name": "ITEM_ADOPT_ONE_MORE_NAME",
		"desc": "ITEM_ADOPT_ONE_MORE_DESC",
		"icon": "res://assets/Hud/itens/adopt_one_more.png",
		"effect": {"type": "pet_slot", "amount": 1},
		"unlock": {"type": "quest", "reqs": [
			{"stat": &"ally_kills_total", "value": 300, "label": "ITEM_REQ_ADOPT_KILLS"},
		]},
	},
	"arcane_dividend": {
		"name": "ITEM_ARCANE_DIVIDEND_NAME",
		"desc": "ITEM_ARCANE_DIVIDEND_DESC",
		"icon": "res://assets/Hud/itens/arcane_dividend.png",
		"effect": {"type": "gold_per_round_chance"},
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
	"cajado_crepusculo": {
		"name": "ITEM_CAJADO_CREPUSCULO_NAME",
		"desc": "ITEM_CAJADO_CREPUSCULO_DESC",
		"icon": "res://assets/Hud/itens/cajado_crepusculo.png",
		"effects": [
			{"type": "arrow_damage_mult", "amount": 0.70},
			{"type": "skill_ally_damage_mult", "amount": 1.35},
			{"type": "clock_drop_chance", "amount": 0.04},
		],
		"unlock": {"type": "shop"},
	},
	"sanguinario": {
		"name": "ITEM_SANGUINARIO_NAME",
		"desc": "ITEM_SANGUINARIO_DESC",
		"icon": "res://assets/Hud/itens/sanguinario.png",
		"effect": {"type": "low_hp_damage", "threshold_pct": 40, "bonus": 0.30},
		"unlock": {"type": "shop"},
	},
	"chamado_palhaco": {
		"name": "ITEM_CHAMADO_PALHACO_NAME",
		"desc": "ITEM_CHAMADO_PALHACO_DESC",
		"icon": "res://assets/Hud/itens/chamado_palhaco.png",
		"effects": [
			{"type": "joker_weight_mult", "amount": 4.0},
			{"type": "joker_twice"},
		],
		"unlock": {"type": "quest", "reqs": [
			{"stat": &"joker_used_total", "value": 25, "label": "ITEM_REQ_JOKER"},
		]},
	},
	"capacete_veloz": {
		"name": "ITEM_CAPACETE_VELOZ_NAME",
		"desc": "ITEM_CAPACETE_VELOZ_DESC",
		"icon": "res://assets/Hud/itens/capacete_veloz.png",
		"effect": {"type": "armor_dodge", "pct_per_level": 0.03},
		"unlock": {"type": "quest", "reqs": [
			{"stat": &"capacete_veloz_unlock", "value": 1, "label": "ITEM_REQ_CAPACETE"},
		]},
	},
	"essencia_vital": {
		"name": "ITEM_ESSENCIA_VITAL_NAME",
		"desc": "ITEM_ESSENCIA_VITAL_DESC",
		"icon": "res://assets/Hud/itens/essencia_vital.png",
		"effect": {"type": "hp_status_bonus", "cdr_per_level": 0.10, "cdr_cap": 0.50, "hp_per_level": 5},
		"unlock": {"type": "quest", "reqs": [
			{"stat": &"essencia_vital_unlock", "value": 1, "label": "ITEM_REQ_ESSENCIA_VITAL"},
		]},
	},
	# Amuleto da Descoberta: a cada 5 rounds (5,10,15...) presenteia 1 upgrade/status
	# que o player ainda nao tem (nivel 1, gratis). Sem upgrade novo disponivel ->
	# da `gold_fallback` de gold. Efeito tipo "amulet_discovery" e GATILHO de
	# wave_manager (lido via is_equipped), nao tem apply_to_player.
	"amuleto_descoberta": {
		"name": "ITEM_AMULETO_DESCOBERTA_NAME",
		"desc": "ITEM_AMULETO_DESCOBERTA_DESC",
		"icon": "res://assets/Hud/itens/amuleto_descoberta.png",
		"effect": {"type": "amulet_discovery", "interval": 5, "gold_fallback": 4},
		"unlock": {"type": "quest", "reqs": [
			{"stat": &"distinct_status_bought_count", "value": 5, "label": "ITEM_REQ_AMULETO_STATUS"},
			{"stat": &"distinct_upgrade_bought_count", "value": 15, "label": "ITEM_REQ_AMULETO_UPGRADES"},
		]},
	},
	# Chamado da Matilha: pets a venda em TODA loja a partir da wave 5 (em vez de a
	# cada 2 waves). Efeito tipo "pets_every_shop" lido por wave_shop via is_equipped.
	# Unlock por compra na loja de petalas (200) — ver loja_petalas.CATALOG.
	"chamado_da_matilha": {
		"name": "ITEM_CHAMADO_MATILHA_NAME",
		"desc": "ITEM_CHAMADO_MATILHA_DESC",
		"icon": "res://assets/Hud/itens/chamado_da_matilha.png",
		"effect": {"type": "pets_every_shop"},
		"unlock": {"type": "shop"},
	},
	# Botas Ariscas: skills de mobilidade (dash/esquivando/fenda/adrenalina) já vêm
	# no L2 na 1ª aquisição e têm −20% de cooldown. Efeito tipo "mobility_cdr" liga
	# a flag _botas_ariscas_equipped no player (que faz as duas coisas).
	"botas_ariscas": {
		"name": "ITEM_BOTAS_ARISCAS_NAME",
		"desc": "ITEM_BOTAS_ARISCAS_DESC",
		"icon": "res://assets/Hud/itens/botas_ariscas.png",
		"effect": {"type": "mobility_cdr"},
		"unlock": {"type": "quest", "reqs": [
			{"stat": &"mobility_skill_uses_total", "value": 75, "label": "ITEM_REQ_BOTAS_ARISCAS"},
		]},
	},
	# Primavera Eterna: +1 pétala no fim de cada round (30% de chance de 2) e a
	# chance de drop de pétala por mob sobe pra 2%. Lido por wave_manager
	# (petal_per_round_roll) e PetalDrop (petal_drop_chance_override). Loja: 20 pétalas.
	"primavera_eterna": {
		"name": "ITEM_PRIMAVERA_NAME",
		"desc": "ITEM_PRIMAVERA_DESC",
		"icon": "res://assets/Hud/itens/primavera_eterna.png",
		"effects": [
			{"type": "petal_per_round", "base": 1, "double_chance": 0.30},
			{"type": "petal_drop_chance", "value": 0.02},
		],
		"unlock": {"type": "shop"},
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


# Linhas de "como liberar" pro tooltip. Cada entry: {label, met, current, target}.
# current/target alimentam o sufixo de progresso "X / Y" (igual às skins); current
# vem clampado no alvo. "default" -> vazio.
static func get_unlock_reqs(id: String) -> Array:
	var item: Dictionary = ITEMS.get(id, {})
	var unlock: Dictionary = item.get("unlock", {"type": "default"})
	var t: String = String(unlock.get("type", "default"))
	match t:
		"shop":
			return [{"label": "ITEM_UNLOCK_SHOP", "met": false, "current": 0, "target": 0}]
		"quest":
			var out: Array = []
			for req in unlock.get("reqs", []):
				var target: int = int(req.get("value", 0))
				var current: int = mini(SkinLoadout.get_stat(req.get("stat")), target)
				out.append({
					"label": String(req.get("label", "")),
					"met": current >= target,
					"current": current,
					"target": target,
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


# Amuleto da Descoberta: config do efeito se equipado (e liberado), senao {}.
# Retorna {"interval": int, "gold_fallback": int}. wave_manager usa pra decidir
# o gatilho a cada `interval` rounds e o gold do caso "tem tudo".
static func amulet_discovery_config() -> Dictionary:
	for id in get_equipped():
		for eff in _item_effects(id):
			if String(eff.get("type", "")) == "amulet_discovery":
				return {
					"interval": int(eff.get("interval", 5)),
					"gold_fallback": int(eff.get("gold_fallback", 4)),
				}
	return {}


# Chamado da Matilha: true se algum item equipado libera pets em toda loja.
static func pets_every_shop() -> bool:
	for id in get_equipped():
		for eff in _item_effects(id):
			if String(eff.get("type", "")) == "pets_every_shop":
				return true
	return false


# True se algum item equipado tira o status de HP da loja (No Limite).
static func disables_shop_hp() -> bool:
	for id in get_equipped():
		for eff in _item_effects(id):
			if String(eff.get("type", "")) == "disable_shop_hp":
				return true
	return false


# Quantos niveis de um status os itens equipados ja deram no inicio (start_status).
# Usado pra os presentes de boas-vindas NAO subirem um upgrade que so veio do item.
static func start_granted_amount(status_id: String) -> int:
	var total: int = 0
	for id in get_equipped():
		for eff in _item_effects(id):
			if String(eff.get("type", "")) == "start_status" and String(eff.get("status", "")) == status_id:
				total += int(eff.get("amount", 0))
	return total


# Bônus de slots de pet vindo de itens equipados (effect pet_slot).
static func equipped_pet_slot_bonus() -> int:
	var bonus: int = 0
	for id in get_equipped():
		for eff in _item_effects(id):
			if String(eff.get("type", "")) == "pet_slot":
				bonus += int(eff.get("amount", 0))
	return bonus


# Dividendo Arcano: sorteio EM CAMADAS do gold de fim de round (retorna 0/1/2; nunca soma).
# 2% -> +2, senão 50% -> +1, senão 0. Só conta com o item equipado E liberado.
static func arcane_dividend_roll() -> int:
	if not ("arcane_dividend" in get_equipped()):
		return 0
	if randf() < 0.02:
		return 2
	if randf() < 0.50:
		return 1
	return 0


# Primavera Eterna: pétalas extras no fim do round. Soma os efeitos petal_per_round
# dos itens equipados (cada um: `base` + chance `double_chance` de dobrar). 0 sem
# nenhum (e sem gastar randf à toa).
static func petal_per_round_roll() -> int:
	var total: int = 0
	for id in get_equipped():
		for eff in _item_effects(id):
			if String(eff.get("type", "")) == "petal_per_round":
				var amt: int = int(eff.get("base", 1))
				if randf() < float(eff.get("double_chance", 0.0)):
					amt *= 2
				total += amt
	return total


# Primavera Eterna: maior override da chance de drop de pétala por mob entre os
# itens equipados. Retorna -1.0 se nenhum item altera (PetalDrop usa a base).
static func petal_drop_chance_override() -> float:
	var best: float = -1.0
	for id in get_equipped():
		for eff in _item_effects(id):
			if String(eff.get("type", "")) == "petal_drop_chance":
				best = maxf(best, float(eff.get("value", 0.0)))
	return best


# Maior chance de "primeiro roll grátis" entre os itens equipados (Estou com Sorte).
static func equipped_free_first_roll_chance() -> float:
	var c: float = 0.0
	for id in get_equipped():
		for eff in _item_effects(id):
			if String(eff.get("type", "")) == "free_first_roll":
				c = maxf(c, float(eff.get("chance", 0.0)))
	return c


# Chamado do Palhaço: multiplicador do PESO do coringa (Último Desejo) no wave shop.
# Produto dos itens equipados; 1.0 sem nenhum (×4 com o Chamado equipado).
static func equipped_joker_weight_mult() -> float:
	var m: float = 1.0
	for id in get_equipped():
		for eff in _item_effects(id):
			if String(eff.get("type", "")) == "joker_weight_mult":
				m *= float(eff.get("amount", 1.0))
	return m


# Chamado do Palhaço: true se algum item equipado libera 2 usos do coringa por run.
static func joker_allows_twice() -> bool:
	for id in get_equipped():
		for eff in _item_effects(id):
			if String(eff.get("type", "")) == "joker_twice":
				return true
	return false


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


# Equipa `id` num slot específico, SUBSTITUINDO o ocupante (se houver). Usado pelo
# drag-and-drop: arrastar um item pra um slot que já tem outro troca os dois. Slots
# ocupados são os índices 0..size-1 (lista compacta); idx >= size = slot vazio →
# adiciona no fim. Retorna true se equipou.
static func equip_in_slot(id: String, idx: int) -> bool:
	if not is_unlocked(id) or idx < 0 or idx >= MAX_SLOTS:
		return false
	var eq: Array = get_equipped()
	eq.erase(id)  # evita duplicar caso já estivesse equipado
	if idx < eq.size():
		eq[idx] = id   # substitui o item que estava nesse slot
	else:
		eq.append(id)  # slot vazio → adiciona
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
			elif t == "arrow_damage_mult":
				# Cajado do Crepúsculo: −30% no dano das flechas.
				if "_cajado_arrow_mult" in player:
					player._cajado_arrow_mult = float(eff.get("amount", 1.0))
			elif t == "skill_ally_damage_mult":
				# Cajado do Crepúsculo: +35% no dano de skills e aliados.
				if "_cajado_power_mult" in player:
					player._cajado_power_mult = float(eff.get("amount", 1.0))
			elif t == "clock_drop_chance":
				# Cajado do Crepúsculo: override da chance de drop do Relógio (4%).
				if "_cajado_clock_chance" in player:
					player._cajado_clock_chance = float(eff.get("amount", 0.0))
			elif t == "low_hp_damage":
				# Sanguinário: +bonus de dano enquanto HP < limiar. Liga a flag e
				# avalia o estado já no início (caso a run comece com HP baixo).
				if "_sanguinario_bonus" in player:
					player._sanguinario_bonus = float(eff.get("bonus", 0.30))
					if player.has_method("_update_sanguinario_state"):
						player._update_sanguinario_state()
			elif t == "armor_dodge":
				# Capacete Veloz: liga o dodge por nível de Armadura comprada.
				if "_capacete_veloz_equipped" in player:
					player._capacete_veloz_equipped = true
			elif t == "hp_status_bonus":
				# Essência Vital: liga o item e guarda os params (CDR por status de HP + HP extra).
				if "_essencia_vital_equipped" in player:
					player._essencia_vital_equipped = true
					player._essencia_cdr_per_level = float(eff.get("cdr_per_level", 0.10))
					player._essencia_cdr_cap = float(eff.get("cdr_cap", 0.50))
					player._essencia_hp_per_level = float(eff.get("hp_per_level", 5.0))
			elif t == "mobility_cdr":
				# Botas Ariscas: liga a flag (−20% CD de mobilidade + skill já vem L2).
				if "_botas_ariscas_equipped" in player:
					player._botas_ariscas_equipped = true
