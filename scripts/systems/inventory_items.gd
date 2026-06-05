class_name InventoryItems
extends RefCounted

# Catálogo de itens equipáveis do Inventário (buffs PRÉ-JOGO). O jogador equipa
# itens e começa a run já com os efeitos aplicados. v1:
#   - midnight_dagger (Adaga da Meia-Noite): começa com +1 de Dano.
#   - golden_bow (Arco Dourado): começa com +1 de Velocidade de Ataque.
#
# Posse: por enquanto TODO item do catálogo é "possuído" (a loja meta que vai
# gatear a posse de verdade vem depois). Equipados salvos em settings.cfg
# [inventory] equipped (CSV de ids). Máx MAX_SLOTS equipados.

const _SETTINGS_PATH: String = "user://settings.cfg"
const _SECTION: String = "inventory"
const _KEY_EQUIPPED: String = "equipped"
const MAX_SLOTS: int = 3

# effect.type "start_status": aplica `amount` níveis de apply_upgrade(`status`)
# no início da run.
const ITEMS: Dictionary = {
	"midnight_dagger": {
		"name": "ITEM_MIDNIGHT_DAGGER_NAME",
		"desc": "ITEM_MIDNIGHT_DAGGER_DESC",
		"icon": "res://assets/Hud/itens/midnight_dagger.png",
		"effect": {"type": "start_status", "status": "damage", "amount": 1},
	},
	"golden_bow": {
		"name": "ITEM_GOLDEN_BOW_NAME",
		"desc": "ITEM_GOLDEN_BOW_DESC",
		"icon": "res://assets/Hud/itens/golden_bow.png",
		"effect": {"type": "start_status", "status": "attack_speed", "amount": 1},
	},
	# Mestre Elemental: NÃO é start_status. Faz o upgrade de boas-vindas (pós-wave-1)
	# virar uma escolha de 1 entre 3 elementais aleatórios (tratado no wave_manager
	# via has_welcome_elemental_choice()).
	"elemental_master": {
		"name": "ITEM_ELEMENTAL_MASTER_NAME",
		"desc": "ITEM_ELEMENTAL_MASTER_DESC",
		"icon": "res://assets/Hud/itens/elemental_master.png",
		"effect": {"type": "welcome_elemental_choice"},
	},
}


static func all_ids() -> Array:
	return ITEMS.keys()


static func is_owned(_id: String) -> bool:
	# v1: todo item definido é possuído (sem loja meta ainda).
	return ITEMS.has(_id)


# True se algum item equipado faz o upgrade de boas-vindas virar escolha de
# elemental (Mestre Elemental). Lido pelo wave_manager no free upgrade.
static func has_welcome_elemental_choice() -> bool:
	for id in get_equipped():
		var eff: Dictionary = ITEMS.get(id, {}).get("effect", {})
		if String(eff.get("type", "")) == "welcome_elemental_choice":
			return true
	return false


static func get_equipped() -> Array:
	var cfg := ConfigFile.new()
	if cfg.load(_SETTINGS_PATH) != OK:
		return []
	var raw: String = str(cfg.get_value(_SECTION, _KEY_EQUIPPED, ""))
	if raw.is_empty():
		return []
	var out: Array = []
	for s in raw.split(",", false):
		if ITEMS.has(s):  # ignora ids órfãos (item removido do catálogo)
			out.append(s)
	return out


static func is_equipped(id: String) -> bool:
	return id in get_equipped()


static func set_equipped(ids: Array) -> void:
	var cfg := ConfigFile.new()
	cfg.load(_SETTINGS_PATH)
	cfg.set_value(_SECTION, _KEY_EQUIPPED, ",".join(PackedStringArray(ids)))
	cfg.save(_SETTINGS_PATH)


# Alterna o estado de equipado. Retorna true se ficou EQUIPADO, false se
# desequipou OU se não coube (slots cheios).
static func toggle_equipped(id: String) -> bool:
	if not is_owned(id):
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


# Aplica os efeitos dos itens equipados no player no INÍCIO da run.
static func apply_to_player(player: Node) -> void:
	if player == null:
		return
	for id in get_equipped():
		var item: Dictionary = ITEMS.get(id, {})
		var eff: Dictionary = item.get("effect", {})
		if String(eff.get("type", "")) == "start_status" and player.has_method("apply_upgrade"):
			var status: String = String(eff.get("status", ""))
			for _i in int(eff.get("amount", 0)):
				player.apply_upgrade(status)


static func get_icon_path(id: String) -> String:
	return String(ITEMS.get(id, {}).get("icon", ""))
