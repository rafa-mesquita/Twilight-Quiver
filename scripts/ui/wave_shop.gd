extends CanvasLayer

# Loja pós-wave: 4 categorias, cada uma com reroll próprio.
# - Estruturas (2 cards paisagem, esq. topo): Torre + slots futuros, placement.
# - Status (2 cards paisagem, esq. base): HP, Dano, Atk Speed, Move Speed.
# - Aliados (3 cards retrato, dir. topo): Claudio Druida + slots futuros, placement.
# - Upgrades (3 cards retrato, dir. base): perfuração, multi, chain, life steal,
#   gold magnet, dash + subs, fire, curse.
# Player seleciona max 1 por categoria (upgrades pode ser 1-2 com bonus em waves
# pares). Placements (estrut + aliado) entram numa fila ao apertar "Próxima Wave".

signal closed

const PRICE_TABLE: Array[int] = [4, 8, 20, 35]
const TOWER_PRICE: int = 7
# Aliados/pets têm tabela própria (mais cara que upgrades comuns) — boost de
# +1/+4/+4/+6 por estrela em cima dos valores antigos pra controlar pace de
# compra de pet vs upgrade.
const CLAUDIO_DRUIDA_PRICE_TABLE: Array[int] = [8, 14, 19, 41]
const LENO_PRICE_TABLE: Array[int] = [8, 14, 19, 41]
const CAPIVARA_PRICE_TABLE: Array[int] = [8, 14, 19, 41]
const TING_PRICE_TABLE: Array[int] = [8, 14, 19, 41]
# Mini Mago: preço placeholder igual aos outros pets — user vai re-balancear
# quando finalizar o design dos níveis.
const MINI_MAGO_PRICE_TABLE: Array[int] = [8, 14, 19, 41]
# Arbusto Carrara: preço placeholder padrão de pet — L2-L4 ainda em design.
const ARBUSTO_PRICE_TABLE: Array[int] = [8, 14, 19, 41]
const TILISKO_PRICE_TABLE: Array[int] = [8, 14, 19, 41]
# Pool de aliados pra rolagem na shop. 3 cards exibidos por wave; sorteia 3
# dos N possíveis (priorizando pets já owned pro player poder upgradar).
const _ALL_ALLY_IDS: Array[String] = ["claudio_druida", "leno", "capivara_joe", "ting", "mini_mago", "arbusto", "tilisko"]
const STRUCTURE_SURCHARGE_PER_OWNED: int = 3
# Aliado: primeira loja (wave 3) o pet é DADO de graça aleatório (não vai pra
# loja). Depois aparece pra venda nas waves 5, 7, 9, 11...
# Estrutura: a cada 4 waves (4, 8, 12...).
# Quando locked, a categoria mostra "Desbloqueia em X turnos" e nenhum slot é
# selecionável.
const ALIADO_FREE_PET_WAVE: int = 3
const ALIADO_SHOP_FIRST_WAVE: int = 5
const ALIADO_SHOP_INTERVAL: int = 2
# Cap de tipos distintos de aliados que o player pode ter ao mesmo tempo.
# Pra ter o 3o, precisa vender um (StatsCard.PetsBox: right-click no chip).
const MAX_DISTINCT_PETS: int = 2
# Slots de pet EXIBIDOS no card (cap de compra continua MAX_DISTINCT_PETS).
# O slot extra fica reservado vazio pro futuro item que abre vaga de pet.
const PETS_DISPLAY_SLOTS: int = 3
const ESTRUT_UNLOCK_INTERVAL: int = 4

# Pool dos cards de status (passive stats — escalonáveis ilimitadamente).
# `name` é o título do card (descrição breve, já que a card paisagem não tem
# DescLabel). Ex: "+15 HP" em vez de "Mais HP". Valores são translation keys —
# resolvidos via tr() onde o name é exibido (Label.text).
const STATUS_POOL: Array = [
	{"id": "hp", "name": "SHOP_HP_PLUS_18"},
	{"id": "damage", "name": "SHOP_DAMAGE"},
	{"id": "attack_speed", "name": "SHOP_ATTACK_SPEED"},
	{"id": "move_speed", "name": "SHOP_MOVE_SPEED"},
	{"id": "armor", "name": "SHOP_ARMOR_12"},
]

# Pool dos cards de upgrade (gameplay-changing items, com requirements).
const UPGRADE_POOL: Array = [
	{"id": "perfuracao", "name": "SHOP_UPG_PERFURACAO", "max_level": 4},
	{"id": "spectral_arrow", "name": "SHOP_UPG_SPECTRAL", "max_level": 4},
	{"id": "multi_arrow", "name": "SHOP_UPG_MULTI_ARROW", "max_level": 4},
	{"id": "double_arrows", "name": "SHOP_UPG_DOUBLE_ARROWS", "max_level": 4},
	{"id": "chain_lightning", "name": "SHOP_UPG_CHAIN_LIGHTNING", "max_level": 4},
	{"id": "life_steal", "name": "SHOP_UPG_LIFE_STEAL", "max_level": 4},
	{"id": "gold_magnet", "name": "SHOP_UPG_GOLD_MAGNET", "max_level": 4},
	{"id": "dash", "name": "SHOP_UPG_DASH", "max_level": 4},
	{"id": "esquivando", "name": "SHOP_UPG_ESQUIVANDO", "max_level": 4},
	{"id": "fenda", "name": "SHOP_UPG_FENDA", "max_level": 4},
	{"id": "adrenalina", "name": "SHOP_UPG_ADRENALINA", "max_level": 4},
	{"id": "ricochet_arrow", "name": "SHOP_UPG_RICOCHET", "max_level": 4},
	{"id": "graviton", "name": "SHOP_UPG_GRAVITON", "max_level": 4},
	{"id": "fire_arrow", "name": "SHOP_UPG_FIRE_ARROW", "max_level": 4},
	{"id": "curse_arrow", "name": "SHOP_UPG_CURSE_ARROW", "max_level": 4},
	{"id": "ice_arrow", "name": "SHOP_UPG_ICE_ARROW", "max_level": 4},
	{"id": "stone_arrow", "name": "SHOP_UPG_STONE_ARROW", "max_level": 4},
	{"id": "tide_arrow", "name": "SHOP_UPG_TIDE_ARROW", "max_level": 4},
	{"id": "boomerang", "name": "SHOP_UPG_BOOMERANG", "max_level": 4},
	{"id": "critical_chance", "name": "SHOP_UPG_CRITICAL_CHANCE", "max_level": 4},
	{"id": "tiger_claws", "name": "SHOP_UPG_TIGER_CLAWS", "max_level": 4},
]

const UPGRADE_PRICE_OVERRIDES: Dictionary = {}

# Pares de upgrades mutuamente exclusivos no mesmo run. Se o player tem um, o
# outro nem aparece no shop e fica bloqueado se ambos saírem na mesma rolada.
# - Fogo ↔ Maldição (mesmo design dos elementais)
# - Perfuração ↔ Flecha Ricochete (mesmo "slot" no design — flecha modifica o
#   comportamento ao bater, escolha uma)
const EXCLUSIVE_PAIRS: Array = [
	# Elementais: só 1 por run (fogo / maldição / cadeia de raios / sangue frio / pedra).
	["fire_arrow", "curse_arrow", "chain_lightning", "ice_arrow", "stone_arrow", "tide_arrow"],
	# Tipo de flecha (modifier on-hit): perfuração, ricochete OU espectral.
	["perfuracao", "ricochet_arrow", "spectral_arrow"],
	# Salva de flechas: multi (leque 30°) ou duplas (chance + apertado).
	["multi_arrow", "double_arrows"],
	# Categoria movimentação: dash (espaço), esquivando (espaço + stacks + dodge),
	# fenda (teleporte + corte) ou adrenalina (passivo + skill). Todos ocupam o
	# slot do espaço / a mesma carta → escolhe um.
	["dash", "esquivando", "fenda", "adrenalina"],
]

# Descrições por upgrade. Cada entry é uma translation key — resolvida via
# tr() no momento de exibição. Mantém o array por nível pra compat com o resto
# do código (clamp por target_level).
const HP_DESCS: Array[String] = ["SHOP_HP_DESC_1", "SHOP_HP_DESC_2", "SHOP_HP_DESC_3", "SHOP_HP_DESC_4"]
const ARMOR_DESCS: Array[String] = [
	"SHOP_ARMOR_DESC_1",
	"SHOP_ARMOR_DESC_2",
	"SHOP_ARMOR_DESC_3",
	"SHOP_ARMOR_DESC_4",
	"SHOP_ARMOR_DESC_5",
]
const DAMAGE_DESCS: Array[String] = ["SHOP_DAMAGE_DESC", "SHOP_DAMAGE_DESC", "SHOP_DAMAGE_DESC", "SHOP_DAMAGE_DESC"]
const PERFURACAO_DESCS: Array[String] = [
	"SHOP_PERFURACAO_DESC_1",
	"SHOP_PERFURACAO_DESC_2",
	"SHOP_PERFURACAO_DESC_3",
	"SHOP_PERFURACAO_DESC_4",
]
const SPECTRAL_DESCS: Array[String] = [
	"SHOP_SPECTRAL_DESC_1",
	"SHOP_SPECTRAL_DESC_2",
	"SHOP_SPECTRAL_DESC_3",
	"SHOP_SPECTRAL_DESC_4",
]
const ATTACK_SPEED_DESCS: Array[String] = [
	"SHOP_ATTACK_SPEED_DESC",
	"SHOP_ATTACK_SPEED_DESC",
	"SHOP_ATTACK_SPEED_DESC",
	"SHOP_ATTACK_SPEED_DESC",
]
const MULTI_ARROW_DESCS: Array[String] = [
	"SHOP_MULTI_ARROW_DESC_1",
	"SHOP_MULTI_ARROW_DESC_2",
	"SHOP_MULTI_ARROW_DESC_3",
	"SHOP_MULTI_ARROW_DESC_4",
]
const DOUBLE_ARROWS_DESCS: Array[String] = [
	"SHOP_DOUBLE_ARROWS_DESC_1",
	"SHOP_DOUBLE_ARROWS_DESC_2",
	"SHOP_DOUBLE_ARROWS_DESC_3",
	"SHOP_DOUBLE_ARROWS_DESC_4",
]
const CHAIN_LIGHTNING_DESCS: Array[String] = [
	"SHOP_CHAIN_LIGHTNING_DESC_1",
	"SHOP_CHAIN_LIGHTNING_DESC_2",
	"SHOP_CHAIN_LIGHTNING_DESC_3",
	"SHOP_CHAIN_LIGHTNING_DESC_4",
]
const MOVE_SPEED_DESCS: Array[String] = [
	"SHOP_MOVE_SPEED_DESC",
	"SHOP_MOVE_SPEED_DESC",
	"SHOP_MOVE_SPEED_DESC",
	"SHOP_MOVE_SPEED_DESC",
]
const GOLD_MAGNET_DESCS: Array[String] = [
	"SHOP_GOLD_MAGNET_DESC_1",
	"SHOP_GOLD_MAGNET_DESC_2",
	"SHOP_GOLD_MAGNET_DESC_3",
	"SHOP_GOLD_MAGNET_DESC_4",
]
const DASH_DESCS: Array[String] = [
	"SHOP_DASH_DESC_1",
	"SHOP_DASH_DESC_2",
	"SHOP_DASH_DESC_3",
	"SHOP_DASH_DESC_4",
]
const ESQUIVANDO_DESCS: Array[String] = [
	"SHOP_ESQUIVANDO_DESC_1",
	"SHOP_ESQUIVANDO_DESC_2",
	"SHOP_ESQUIVANDO_DESC_3",
	"SHOP_ESQUIVANDO_DESC_4",
]
const FENDA_DESCS: Array[String] = [
	"SHOP_FENDA_DESC_1",
	"SHOP_FENDA_DESC_2",
	"SHOP_FENDA_DESC_3",
	"SHOP_FENDA_DESC_4",
]
const ADRENALINA_DESCS: Array[String] = [
	"SHOP_ADRENALINA_DESC_1",
	"SHOP_ADRENALINA_DESC_2",
	"SHOP_ADRENALINA_DESC_3",
	"SHOP_ADRENALINA_DESC_4",
]
const LIFE_STEAL_DESCS: Array[String] = [
	"SHOP_LIFE_STEAL_DESC_1",
	"SHOP_LIFE_STEAL_DESC_2",
	"SHOP_LIFE_STEAL_DESC_3",
	"SHOP_LIFE_STEAL_DESC_4",
]
const RICOCHET_ARROW_DESCS: Array[String] = [
	"SHOP_RICOCHET_DESC_1",
	"SHOP_RICOCHET_DESC_2",
	"SHOP_RICOCHET_DESC_3",
	"SHOP_RICOCHET_DESC_4",
]
const GRAVITON_DESCS: Array[String] = [
	"SHOP_GRAVITON_DESC_1",
	"SHOP_GRAVITON_DESC_2",
	"SHOP_GRAVITON_DESC_3",
	"SHOP_GRAVITON_DESC_4",
]
const CLAUDIO_DRUIDA_DESCS: Array[String] = [
	"SHOP_CD_DESC_1",
	"SHOP_CD_DESC_2",
	"SHOP_CD_DESC_3",
	"SHOP_CD_DESC_4",
]
const LENO_DESCS: Array[String] = [
	"SHOP_LENO_DESC_1",
	"SHOP_LENO_DESC_2",
	"SHOP_LENO_DESC_3",
	"SHOP_LENO_DESC_4",
]
const TILISKO_DESCS: Array[String] = [
	"SHOP_ALLY_TILISKO_DESC_1",
	"SHOP_ALLY_TILISKO_DESC_2",
	"SHOP_ALLY_TILISKO_DESC_3",
	"SHOP_ALLY_TILISKO_DESC_4",
]
const CAPIVARA_JOE_DESCS: Array[String] = [
	"SHOP_CAPIVARA_DESC_1",
	"SHOP_CAPIVARA_DESC_2",
	"SHOP_CAPIVARA_DESC_3",
	"SHOP_CAPIVARA_DESC_4",
]
const TING_DESCS: Array[String] = [
	"SHOP_TING_DESC_1",
	"SHOP_TING_DESC_2",
	"SHOP_TING_DESC_3",
	"SHOP_TING_DESC_4",
]
# Placeholder até o user finalizar o design — texto genérico em todos os níveis.
const MINI_MAGO_DESCS: Array[String] = [
	"SHOP_MINI_MAGO_DESC_1",
	"SHOP_MINI_MAGO_DESC_2",
	"SHOP_MINI_MAGO_DESC_3",
	"SHOP_MINI_MAGO_DESC_4",
]
const ARBUSTO_DESCS: Array[String] = [
	"SHOP_ARBUSTO_DESC_1",
	"SHOP_ARBUSTO_DESC_2",
	"SHOP_ARBUSTO_DESC_3",
	"SHOP_ARBUSTO_DESC_4",
]
const FIRE_ARROW_DESCS: Array[String] = [
	"SHOP_FIRE_ARROW_DESC_1",
	"SHOP_FIRE_ARROW_DESC_2",
	"SHOP_FIRE_ARROW_DESC_3",
	"SHOP_FIRE_ARROW_DESC_4",
]
const CURSE_ARROW_DESCS: Array[String] = [
	"SHOP_CURSE_ARROW_DESC_1",
	"SHOP_CURSE_ARROW_DESC_2",
	"SHOP_CURSE_ARROW_DESC_3",
	"SHOP_CURSE_ARROW_DESC_4",
]
const ICE_ARROW_DESCS: Array[String] = [
	"SHOP_ICE_ARROW_DESC_1",
	"SHOP_ICE_ARROW_DESC_2",
	"SHOP_ICE_ARROW_DESC_3",
	"SHOP_ICE_ARROW_DESC_4",
]
const STONE_ARROW_DESCS: Array[String] = [
	"SHOP_STONE_ARROW_DESC_1",
	"SHOP_STONE_ARROW_DESC_2",
	"SHOP_STONE_ARROW_DESC_3",
	"SHOP_STONE_ARROW_DESC_4",
]
const TIDE_ARROW_DESCS: Array[String] = [
	"SHOP_TIDE_ARROW_DESC_1",
	"SHOP_TIDE_ARROW_DESC_2",
	"SHOP_TIDE_ARROW_DESC_3",
	"SHOP_TIDE_ARROW_DESC_4",
]
const BOOMERANG_DESCS: Array[String] = [
	"SHOP_BOOMERANG_DESC_1",
	"SHOP_BOOMERANG_DESC_2",
	"SHOP_BOOMERANG_DESC_3",
	"SHOP_BOOMERANG_DESC_4",
]
const CRITICAL_CHANCE_DESCS: Array[String] = [
	"SHOP_CRITICAL_CHANCE_DESC_1",
	"SHOP_CRITICAL_CHANCE_DESC_2",
	"SHOP_CRITICAL_CHANCE_DESC_3",
	"SHOP_CRITICAL_CHANCE_DESC_4",
]
const TIGER_CLAWS_DESCS: Array[String] = [
	"SHOP_TIGER_CLAWS_DESC_1",
	"SHOP_TIGER_CLAWS_DESC_2",
	"SHOP_TIGER_CLAWS_DESC_3",
	"SHOP_TIGER_CLAWS_DESC_4",
]

# Carta "Último Desejo" (joker do shop): uso único por run. Substitui 1 dos 3
# slots de upgrade com baixa probabilidade quando o player tem itens pra upar
# (a partir da wave 5). Quando comprada, abre modal pós-"Next Wave" pra player
# escolher 1 status/pet/upgrade já owned pra subir +1 nível.
const JOKER_ID: String = "joker"
const JOKER_PRICE: int = 10
const JOKER_SECOND_PRICE: int = 20  # 2ª aparição na run (só com Chamado do Palhaço)
const JOKER_FIRST_WAVE: int = 5
const JOKER_WEIGHT: float = 0.20  # ~20% da chance de uma carta normal por slot
# Carta "Roleta Elemental": troca o elemental atual (precisa estar no L3) por OUTRO
# elemental aleatório no L4. Custa 25G (10 a menos que comprar o L4 = 35G) e é mais
# rara que uma carta normal (peso 0.5). Surpresa: o L4 sorteado só é revelado ao comprar.
const ROULETTE_ID: String = "elemental_roulette"
const ROULETTE_PRICE: int = 25
const ROULETTE_WEIGHT: float = 0.5  # metade da chance de uma carta normal
const _ELEMENTAL_IDS: Array[String] = ["fire_arrow", "curse_arrow", "chain_lightning", "ice_arrow", "stone_arrow", "tide_arrow"]
# IDs que contam como "status" pro modal de seleção do joker (escala infinita).
const _JOKER_STATUS_IDS: Array[String] = ["hp", "damage", "attack_speed", "move_speed", "armor"]
# IDs de pets/aliados pro modal (top 4 cap).
const _JOKER_PET_IDS: Array[String] = ["claudio_druida", "leno", "capivara_joe", "ting", "mini_mago", "arbusto", "tilisko"]

@onready var gold_label: Label = $Root/GoldLabel
@onready var cleared_info_label: Label = $Root/ClearedInfoLabel
@onready var continue_btn: Button = $Root/ContinueBtn
@onready var placement_hint: Label = $PlacementHint
@onready var bg_rect: ColorRect = $Bg
@onready var root_panel: Control = $Root

@onready var estrut_cards: Array[Control] = [
	$Root/EstrutCard1,
	$Root/EstrutCard2,
]
@onready var status_cards: Array[Control] = [
	$Root/StatusCard1,
	$Root/StatusCard2,
]
@onready var upg_cards: Array[Control] = [
	$Root/UpgRow/UpgCard1,
	$Root/UpgRow/UpgCard2,
	$Root/UpgRow/UpgCard3,
]
@onready var aliado_cards: Array[Control] = [
	$Root/AliadoRow/AliadoCard1,
	$Root/AliadoRow/AliadoCard2,
	$Root/AliadoRow/AliadoCard3,
]

# Bonus +1 upgrade: começa na wave 3 e depois nas pares (3, 4, 6, 8...).
var max_upgrades_this_round: int = 1

# Slots
var status_slots: Array = []
var estrutura_slots: Array = []
var upg_slots: Array = []
var aliado_slots: Array = []

# Selection state
var _selected_status_idx: int = -1
var _selected_estrut_idx: int = -1
var _selected_aliado_idx: int = -1
var _selected_upgrade_idxs: Array[int] = []

# Reroll global: 1 botão reroll TUDO (status + estrutura + aliado + upgrade) ao
# mesmo tempo. Custo escalonado e cap em N rerolls por shop.
const GLOBAL_REROLL_COSTS: Array[int] = [1, 3, 6]
const MAX_GLOBAL_REROLLS: int = 3
var _global_rerolls_used: int = 0
# Estou com Sorte (item): se true, o PRIMEIRO reroll deste shop custa 0.
var _lucky_first_roll_free: bool = false
@onready var global_reroll_btn: TextureButton = $Root/GlobalReroll/Btn
@onready var global_reroll_cost: Label = $Root/GlobalReroll/CostLabel

# Augments column (right side): mostra os upgrades já comprados como slots.
# Hover de cada slot abre tooltip com efeito atual + próximo nível.
const _AUGMENT_MAX_SLOTS: int = 6
const _AUGMENT_SLOT_SIZE: Vector2 = Vector2(60, 60)
@onready var augments_box: GridContainer = $Root/StatsCard/SlotsBox
@onready var stats_box: VBoxContainer = $Root/StatsCard/StatsBox
@onready var pets_box: HBoxContainer = $Root/StatsCard/PetsBox
@onready var items_box: HBoxContainer = $Root/StatsCard/ItemsBox

# Aliados (pets) que aparecem no card do player. Ordem fixa.
const _PETS_ROW_IDS: Array[String] = ["claudio_druida", "leno", "capivara_joe", "ting", "mini_mago", "arbusto", "tilisko"]
# Estruturas conhecidas. Mapeia o scene_path em owned_structures pra um id
# usado no chip. Por enquanto só arrow_tower.
const _STRUCTURES_ROW: Array[Dictionary] = [
	{"id": "arrow_tower", "scene_path": "res://scenes/world/structures/arrow_tower.tscn"},
]
const _MINI_CHIP_SIZE: Vector2 = Vector2(60, 60)
# Tooltip lazy-created no primeiro hover.
var _augment_tooltip: PanelContainer = null
var _augment_tooltip_label: RichTextLabel = null
# Modal de confirmação de venda de pet (right-click no chip do StatsCard).
var _sell_confirm_dialog: Panel = null
var _all_augments_dialog: Panel = null

# Status que aparecem no StatsCard (em ordem de exibição).
const _STATS_CARD_ROWS: Array[Dictionary] = [
	{"id": "hp", "label": "SHOP_STAT_HP"},
	{"id": "damage", "label": "SHOP_STAT_DAMAGE"},
	{"id": "move_speed", "label": "SHOP_STAT_MOVE_SPEED"},
	{"id": "attack_speed", "label": "SHOP_STAT_ATTACK_SPEED"},
	{"id": "armor", "label": "SHOP_STAT_ARMOR"},
]

const BUY_SOUND: AudioStream = preload("res://audios/effects/buy_1.mp3")
const NEXT_WAVE_SOUND: AudioStream = preload("res://audios/effects/Next wave.mp3")

# Placement mode
const PLACEMENT_BOUNDS: Rect2 = Rect2(-80, -40, 680, 380)
const PLACEMENT_MIN_DIST: float = 80.0
const PLACEMENT_CLICK_RADIUS: float = 60.0
const PLACEMENT_SPOT_COUNT: int = 5

var _placement_active: bool = false
var _placement_ghosts: Array[Node2D] = []
# Fila de placements pendentes (estrutura primeiro, aliado depois).
var _placement_queue: Array[Dictionary] = []
var _placement_current: Dictionary = {}

# Setado pelo wave_manager antes do add_child quando o player ganha uma torre
# grátis na entrada da wave 8. Não-vazio dispara placement antes do shop abrir.
var pending_free_tower_scene: String = ""
# True enquanto processamos o placement da free tower — impede que o fim do
# placement comite upgrades/feche o shop (queremos voltar ao shop normal).
var _free_tower_in_progress: bool = false

const SELECTED_TINT: Color = Color(1.4, 1.25, 0.5, 1.0)
# Box roxa translúcida sobreposta a um card selecionado pra deixar claro.
const SELECTION_OVERLAY_COLOR: Color = Color(0.55, 0.25, 0.85, 0.4)


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var wm := get_tree().get_first_node_in_group("wave_manager")
	var next_wn: int = 1
	if wm != null and "wave_number" in wm:
		var wn: int = int(wm.wave_number)
		next_wn = wn + 1
		if wn == 3 or (wn >= 4 and wn % 2 == 0):
			max_upgrades_this_round = 2
		# Info da wave recém-limpa + tempo efetivo acumulado (timer já parado no
		# _finish_wave). wn aqui é a wave que acabou de ser limpa (ainda não
		# incrementada pra próxima).
		_set_cleared_info(wn)
		# Wave 3: pet grátis aleatório é entregue ANTES do shop abrir pelo
		# wave_manager._grant_free_random_pet (que mostra popup com card art).
		# Chamada antiga aqui removida pra não duplicar o grant.
	continue_btn.text = tr("SHOP_NEXT_WAVE_FMT") % next_wn
	continue_btn.pressed.connect(_on_continue_pressed)
	global_reroll_btn.pressed.connect(_on_global_reroll)
	# Estou com Sorte: rola a chance do primeiro reroll deste shop ser grátis.
	_lucky_first_roll_free = randf() < InventoryItems.equipped_free_first_roll_chance()
	_setup_bonus_label()
	_refresh_gold_label()
	_build_petal_label()
	_roll_all_slots()
	_build_all_cards()
	_connect_card_buttons()
	_refresh_button_states()
	_refresh_augments_column()
	_refresh_stats_card()
	_refresh_pets_box()
	_refresh_items_box()
	# Free tower grant: wave_manager seta pending_free_tower_scene quando o
	# player entra na wave 8. Dispara placement ANTES de liberar o shop.
	if pending_free_tower_scene != "":
		call_deferred("_start_free_tower_placement")
	# Birthday event: fireworks entre waves — gated em nick + janela (ou dev toggle).
	_maybe_spawn_fireworks()


func _notification(what: int) -> void:
	# Locale trocado em runtime (ex: player muda idioma no meio da run pelo menu).
	# Controls com auto_translate re-resolvem sozinhos, mas os textos de card são
	# bakeados via tr() na hora do _build_card, então precisam de re-render manual.
	if what == NOTIFICATION_TRANSLATION_CHANGED:
		_relocalize()


func _relocalize() -> void:
	# Só re-renderiza se a loja já montou os slots (evita rodar antes do _ready).
	if status_slots.is_empty():
		return
	_build_all_cards()
	_refresh_button_states()
	_refresh_augments_column()
	_refresh_stats_card()
	_refresh_pets_box()
	_refresh_items_box()
	var wm := get_tree().get_first_node_in_group("wave_manager")
	if wm != null and "wave_number" in wm:
		var wn: int = int(wm.wave_number)
		continue_btn.text = tr("SHOP_NEXT_WAVE_FMT") % (wn + 1)
		_set_cleared_info(wn)


func _set_cleared_info(cleared_wave: int) -> void:
	if cleared_info_label == null:
		return
	# Config: esconder tempos de round/run mostra só a confirmação da wave.
	if GameState.hide_time_info:
		cleared_info_label.text = tr("SHOP_CLEARED_NO_TIME") % cleared_wave
		return
	var wave_str: String = "0:00"
	var total_str: String = "0:00"
	var player := get_tree().get_first_node_in_group("player")
	if player != null and player.has_method("get_run_time_msec"):
		if player.has_method("get_wave_time_msec"):
			wave_str = _fmt_mmss(int(player.get_wave_time_msec()))
		total_str = _fmt_mmss(int(player.get_run_time_msec()))
	var line1: String = tr("SHOP_CLEARED_INFO_FMT") % [cleared_wave, wave_str]
	var line2: String = tr("SHOP_RUN_TOTAL_FMT") % total_str
	cleared_info_label.text = "%s  |  %s" % [line1, line2]


func _fmt_mmss(msec: int) -> String:
	var total_sec: int = msec / 1000
	return "%d:%02d" % [total_sec / 60, total_sec % 60]


func _maybe_spawn_fireworks() -> void:
	if not BirthdayEvent.is_party_active_for_current_user():
		return
	var fw_scene: PackedScene = load("res://scenes/effects/fireworks.tscn") as PackedScene
	if fw_scene == null:
		return
	var fw: Node2D = fw_scene.instantiate() as Node2D
	if fw == null:
		return
	var vp_size: Vector2 = get_viewport().get_visible_rect().size
	fw.position = Vector2(vp_size.x * 0.5, -16.0)
	# Adiciona como filho do CanvasLayer; coloca entre Bg e Root pra ficar
	# atrás da UI mas na frente do background.
	add_child(fw)
	var bg: Node = get_node_or_null("Bg")
	if bg != null:
		move_child(fw, bg.get_index() + 1)


func _start_free_tower_placement() -> void:
	var free_slot: Dictionary = {
		"id": "arrow_tower",
		"name": "SHOP_TOWER_NAME",
		"desc": "SHOP_TOWER_DESC",
		"price": 0,
		"available": true,
		"scene": pending_free_tower_scene,
		"free": true,
	}
	pending_free_tower_scene = ""
	_free_tower_in_progress = true
	_placement_queue.clear()
	_placement_queue.append({"type": "estrutura", "slot": free_slot, "free": true})
	_process_next_placement()


func _process(_delta: float) -> void:
	if _placement_active and not _placement_ghosts.is_empty():
		var mouse_world: Vector2 = _world_mouse_position()
		var nearest: Node2D = _nearest_ghost_to(mouse_world)
		for g in _placement_ghosts:
			if not is_instance_valid(g):
				continue
			if g == nearest:
				g.modulate = Color(1.3, 1.3, 1.3, 0.95)
			else:
				g.modulate = Color(1, 1, 1, 0.45)


func _input(event: InputEvent) -> void:
	if not _placement_active:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_Z:
			_cancel_placement()
			get_viewport().set_input_as_handled()
			return
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			var mouse_world: Vector2 = _world_mouse_position()
			var nearest: Node2D = _nearest_ghost_to(mouse_world)
			if nearest != null and nearest.global_position.distance_to(mouse_world) <= PLACEMENT_CLICK_RADIUS:
				_confirm_placement_at(nearest)
				get_viewport().set_input_as_handled()
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			_cancel_placement()
			get_viewport().set_input_as_handled()


func _world_mouse_position() -> Vector2:
	return get_viewport().get_canvas_transform().affine_inverse() * get_viewport().get_mouse_position()


func _nearest_ghost_to(pos: Vector2) -> Node2D:
	var best: Node2D = null
	var best_dist: float = INF
	for g in _placement_ghosts:
		if not is_instance_valid(g):
			continue
		var d: float = g.global_position.distance_to(pos)
		if d < best_dist:
			best = g
			best_dist = d
	return best


func _generate_random_positions(count: int) -> Array[Vector2]:
	var spawn_root := get_tree().get_first_node_in_group("tower_spawn_root")
	if spawn_root != null and spawn_root.get_child_count() > 0:
		var marker_positions: Array[Vector2] = []
		for c in spawn_root.get_children():
			if c is Node2D:
				marker_positions.append((c as Node2D).global_position)
		marker_positions.shuffle()
		var picked: Array[Vector2] = []
		for i in mini(count, marker_positions.size()):
			picked.append(marker_positions[i])
		return picked
	var result: Array[Vector2] = []
	var attempts: int = 0
	while result.size() < count and attempts < 200:
		attempts += 1
		var p := Vector2(
			randf_range(PLACEMENT_BOUNDS.position.x, PLACEMENT_BOUNDS.position.x + PLACEMENT_BOUNDS.size.x),
			randf_range(PLACEMENT_BOUNDS.position.y, PLACEMENT_BOUNDS.position.y + PLACEMENT_BOUNDS.size.y)
		)
		var ok: bool = true
		for existing in result:
			if existing.distance_to(p) < PLACEMENT_MIN_DIST:
				ok = false
				break
		if ok:
			result.append(p)
	return result


# ---------- Roll ----------

func _roll_all_slots() -> void:
	_roll_status_slots()
	_roll_estrutura_slots()
	_roll_upg_slots()
	_roll_aliado_slots()


func _roll_status_slots() -> void:
	# 2 rolls distintos do STATUS_POOL.
	status_slots.clear()
	var picks: Array = STATUS_POOL.duplicate()
	# No Limite (item): tira o status de HP da loja.
	if InventoryItems.disables_shop_hp():
		var filtered: Array = []
		for e in picks:
			if String(e.get("id", "")) != "hp":
				filtered.append(e)
		picks = filtered
	picks.shuffle()
	var player := _get_player()
	for i in 2:
		if i >= picks.size():
			status_slots.append({"id": "none", "name": "—", "desc": "—", "price": 0, "available": false})
			continue
		var picked: Dictionary = picks[i]
		var picked_id: String = picked["id"]
		var current_level: int = 0
		if player != null and player.has_method("get_upgrade_count"):
			current_level = player.get_upgrade_count(picked_id)
		var target_level: int = current_level + 1
		var price: int = _status_price_for(picked_id, current_level)
		status_slots.append({
			"id": picked_id,
			"name": _status_title_for(picked_id, target_level, picked["name"]),
			"desc": _get_upgrade_desc(picked_id, target_level),
			"price": price,
			"available": true,
			"target_level": target_level,
		})


# HP e armor têm progressão per-level (não constante), então o título do card
# tem que acompanhar o nível. Outros stats (dano/atk speed/move speed) ganham
# a mesma quantia por nível, então o nome estático do STATUS_POOL serve.
func _status_title_for(id: String, target_level: int, fallback_name: String) -> String:
	# Retorna translation key — resolvida via tr() onde o título é exibido.
	match id:
		"hp":
			match target_level:
				1: return "SHOP_HP_PLUS_18"
				2: return "SHOP_HP_PLUS_20"
				3: return "SHOP_HP_PLUS_22"
				_: return "SHOP_HP_PLUS_25"
		"armor":
			match target_level:
				1: return "SHOP_ARMOR_12"
				2: return "SHOP_ARMOR_18"
				3: return "SHOP_ARMOR_22"
				4: return "SHOP_ARMOR_25"
				_: return "SHOP_ARMOR_3"
	return fallback_name


const STATUS_BASE_PRICE: int = 4


func _status_price_for(_id: String, current_level: int) -> int:
	# Todos os status: 4G base, dobra a cada nível (4, 8, 16, 32, 64, ...).
	var lvl: int = maxi(current_level, 0)
	return STATUS_BASE_PRICE * int(pow(2, lvl))


func _roll_estrutura_slots() -> void:
	estrutura_slots.clear()
	# Gate: estruturas só aparecem a partir da wave 8.
	var wn_struct: int = _current_wave_number()
	# Wave 14 (Duskrose boss): shop pré-boss não vende estruturas.
	# Voltam normalmente no shop pós-boss (wn_struct == 14).
	if wn_struct == 13:
		for i in 2:
			estrutura_slots.append({"id": "locked", "name": "SHOP_BOSS_NO_STRUCTURES", "desc": "", "price": 0, "available": false})
		return
	if wn_struct < 8:
		var turns_to_8: int = max(8 - wn_struct, 1)
		var msg8: String = _build_lock_title(turns_to_8)
		for i in 2:
			estrutura_slots.append({"id": "locked", "name": msg8, "desc": "", "price": 0, "available": false})
		return
	var lock_remaining: int = _waves_until_unlock(ESTRUT_UNLOCK_INTERVAL)
	if lock_remaining > 0:
		var msg: String = _build_lock_title(lock_remaining)
		for i in 2:
			estrutura_slots.append({"id": "locked", "name": msg, "desc": "", "price": 0, "available": false})
		return
	var surcharge: int = STRUCTURE_SURCHARGE_PER_OWNED * _total_structures_bought()
	estrutura_slots.append({
		"id": "arrow_tower",
		"name": "SHOP_TOWER_NAME",
		"desc": "SHOP_TOWER_DESC",
		"price": TOWER_PRICE + surcharge,
		"available": true,
		"scene": "res://scenes/world/structures/arrow_tower.tscn",
	})
	estrutura_slots.append({"id": "soon", "name": "SHOP_COMING_SOON", "desc": "—", "price": 0, "available": false})


func _roll_aliado_slots() -> void:
	aliado_slots.clear()
	var wn: int = _current_wave_number()
	# Wave 3: pet grátis aleatório dado em _ready, sem cards de venda.
	if wn == ALIADO_FREE_PET_WAVE:
		for i in 3:
			aliado_slots.append({"id": "free_pet", "name": "SHOP_FREE_PET", "desc": "SHOP_FREE_PET_DESC", "price": 0, "available": false})
		return
	var lock_remaining: int = _aliado_lock_remaining(wn)
	if lock_remaining > 0:
		var lock_desc: String = _build_lock_desc(lock_remaining)
		for i in 3:
			aliado_slots.append({"id": "locked", "name": "SHOP_BLOCKED", "desc": lock_desc, "price": 0, "available": false})
		return
	var p := _get_player()
	# Pool dinâmico: 3 cards selecionados de _ALL_ALLY_IDS (= 4 pets disponíveis).
	# Owned pets (lvl > 0) sempre aparecem pro player poder upgradar; o resto
	# é preenchido com unowned random até bater 3 slots.
	var owned_ids: Array[String] = []
	var unowned_ids: Array[String] = []
	for ally_id in _ALL_ALLY_IDS:
		var lvl: int = 0
		if p != null and p.has_method("get_upgrade_count"):
			lvl = int(p.get_upgrade_count(ally_id))
		if lvl > 0:
			owned_ids.append(ally_id)
		else:
			unowned_ids.append(ally_id)
	var picked: Array[String] = owned_ids.duplicate()
	if picked.size() > 3:
		picked = picked.slice(0, 3)
	unowned_ids.shuffle()
	while picked.size() < 3 and not unowned_ids.is_empty():
		picked.append(unowned_ids.pop_back())
	var distinct_owned: int = _distinct_pets_owned(p)
	for ally_id in picked:
		var slot: Dictionary = _build_ally_slot(ally_id, p, distinct_owned)
		if not slot.is_empty():
			aliado_slots.append(slot)
	# Defensivo: se o pool foi menor que 3 (não deveria acontecer), padding.
	while aliado_slots.size() < 3:
		aliado_slots.append({"id": "none", "name": "—", "desc": "—", "price": 0, "available": false})


func _build_ally_slot(ally_id: String, p: Node, distinct_owned: int) -> Dictionary:
	var lvl: int = 0
	if p != null and p.has_method("get_upgrade_count"):
		lvl = int(p.get_upgrade_count(ally_id))
	var maxed: bool = lvl >= 4
	var pet_capped: bool = lvl == 0 and distinct_owned >= _effective_pet_cap()
	var price_table: Array = _pet_price_table_for(ally_id)
	var price: int = 0
	if not price_table.is_empty():
		price = int(price_table[mini(lvl, price_table.size() - 1)])
	var desc: String = ""
	if maxed:
		desc = "SHOP_MAX_REACHED"
	elif pet_capped:
		desc = "SHOP_PET_LIMIT_REACHED"
	elif ally_id == "claudio_druida":
		# Claudio Druida mantém as descs custom-WW_DESC_X (não passa por _get_upgrade_desc).
		match lvl:
			0: desc = "SHOP_CD_DESC_1"
			1: desc = "SHOP_CD_DESC_2"
			2: desc = "SHOP_CD_DESC_3"
			3: desc = "SHOP_CD_DESC_4"
			_: desc = ""
	else:
		desc = _get_upgrade_desc(ally_id, lvl + 1)
	var name_key: String = ""
	match ally_id:
		"claudio_druida": name_key = "SHOP_ALLY_CLAUDIO_DRUIDA"
		"leno": name_key = "SHOP_ALLY_LENO"
		"capivara_joe": name_key = "SHOP_ALLY_CAPIVARA"
		"ting": name_key = "SHOP_ALLY_TING"
		"mini_mago": name_key = "SHOP_ALLY_MINI_MAGO"
		"arbusto": name_key = "SHOP_ALLY_ARBUSTO"
		"tilisko": name_key = "SHOP_ALLY_TILISKO"
	return {
		"id": ally_id,
		"name": name_key,
		"desc": desc,
		"price": price,
		"available": not maxed and not pet_capped,
		"is_ally": true,
		"auto_spawn": true,
	}


# Quantos tipos distintos de pet o player tem (lvl > 0). Usado pelo cap
# MAX_DISTINCT_PETS no roll dos aliados.
func _distinct_pets_owned(p: Node) -> int:
	if p == null or not p.has_method("get_upgrade_count"):
		return 0
	var count: int = 0
	for id in _PETS_ROW_IDS:
		if int(p.get_upgrade_count(id)) > 0:
			count += 1
	return count


# Right-click no chip de pet → abre modal de confirmação de venda.
func _on_pet_chip_input(event: InputEvent, id: String) -> void:
	if not (event is InputEventMouseButton):
		return
	var mb: InputEventMouseButton = event
	if not (mb.pressed and mb.button_index == MOUSE_BUTTON_RIGHT):
		return
	_show_sell_confirm(id)
	get_viewport().set_input_as_handled()


# Tabela de preço por pet (mesma usada na compra). Sum dos níveis 1..lvl
# = total que o player pagou. Refund = metade (floor).
func _pet_price_table_for(id: String) -> Array:
	match id:
		"claudio_druida": return CLAUDIO_DRUIDA_PRICE_TABLE
		"leno": return LENO_PRICE_TABLE
		"capivara_joe": return CAPIVARA_PRICE_TABLE
		"ting": return TING_PRICE_TABLE
		"mini_mago": return MINI_MAGO_PRICE_TABLE
		"arbusto": return ARBUSTO_PRICE_TABLE
		"tilisko": return TILISKO_PRICE_TABLE
	return []


func _pet_total_paid(id: String, lvl: int) -> int:
	var price_table: Array = _pet_price_table_for(id)
	if price_table.is_empty() or lvl <= 0:
		return 0
	var total: int = 0
	for i in mini(lvl, price_table.size()):
		total += int(price_table[i])
	return total


# Modal de confirmação: mostra refund + total pago, botões Vender/Cancelar.
# Right-click no chip do pet abre. Cancelar dismissa, Vender executa.
func _show_sell_confirm(id: String) -> void:
	var p := _get_player()
	if p == null or not p.has_method("get_upgrade_count"):
		return
	var lvl: int = int(p.get_upgrade_count(id))
	if lvl <= 0:
		return
	var total_paid: int = _pet_total_paid(id, lvl)
	if total_paid <= 0:
		return
	var refund: int = total_paid / 2
	# Esconde tooltip do chip pra não sobrepor o modal.
	if _augment_tooltip != null:
		_augment_tooltip.visible = false
	_ensure_sell_confirm_dialog()
	# Atualiza textos. Path: dlg → Card (PanelContainer) → VBox → ...
	var title_label: Label = _sell_confirm_dialog.get_node("Card/VBox/Title") as Label
	var body_label: Label = _sell_confirm_dialog.get_node("Card/VBox/Body") as Label
	var pet_name: String = tr(_augment_title_for(id))
	title_label.text = tr("SHOP_SELL_PET_TITLE") % pet_name
	body_label.text = tr("SHOP_SELL_PET_BODY") % [refund, total_paid]
	# Reconnecta o botão de confirmar com o id atual.
	var confirm_btn: Button = _sell_confirm_dialog.get_node("Card/VBox/Buttons/Confirm") as Button
	for c in confirm_btn.pressed.get_connections():
		confirm_btn.pressed.disconnect(c["callable"])
	confirm_btn.pressed.connect(_on_sell_confirmed.bind(id))
	_sell_confirm_dialog.visible = true


func _on_sell_confirmed(id: String) -> void:
	if _sell_confirm_dialog != null:
		_sell_confirm_dialog.visible = false
	_sell_pet(id)


func _on_sell_cancelled() -> void:
	if _sell_confirm_dialog != null:
		_sell_confirm_dialog.visible = false


func _ensure_sell_confirm_dialog() -> void:
	if _sell_confirm_dialog != null:
		return
	# Backdrop semi-opaco que captura cliques fora — clicar dismissa.
	var dlg := Panel.new()
	dlg.name = "SellConfirmDialog"
	dlg.visible = false
	dlg.z_index = 200
	dlg.anchor_right = 1.0
	dlg.anchor_bottom = 1.0
	dlg.mouse_filter = Control.MOUSE_FILTER_STOP
	var backdrop_style := StyleBoxFlat.new()
	backdrop_style.bg_color = Color(0.0, 0.0, 0.0, 0.55)
	dlg.add_theme_stylebox_override("panel", backdrop_style)
	dlg.gui_input.connect(_on_sell_dialog_backdrop_input)
	root_panel.add_child(dlg)
	# Painel central com bordering (mesmo estilo do StatsCard).
	var card := PanelContainer.new()
	card.name = "Card"
	card.set_anchors_preset(Control.PRESET_CENTER)
	card.custom_minimum_size = Vector2(640, 280)
	card.position = Vector2(-320, -140)  # offset relative to center
	var card_style := StyleBoxFlat.new()
	card_style.bg_color = Color(0.10, 0.07, 0.14, 1.0)
	card_style.border_color = Color(0.55, 0.40, 0.70, 1.0)
	card_style.border_width_left = 3
	card_style.border_width_top = 3
	card_style.border_width_right = 3
	card_style.border_width_bottom = 3
	card_style.corner_radius_top_left = 6
	card_style.corner_radius_top_right = 6
	card_style.corner_radius_bottom_left = 6
	card_style.corner_radius_bottom_right = 6
	card_style.content_margin_left = 28
	card_style.content_margin_right = 28
	card_style.content_margin_top = 24
	card_style.content_margin_bottom = 20
	card.add_theme_stylebox_override("panel", card_style)
	dlg.add_child(card)
	var vbox := VBoxContainer.new()
	vbox.name = "VBox"
	vbox.add_theme_constant_override("separation", 16)
	card.add_child(vbox)
	# Title.
	var title := Label.new()
	title.name = "Title"
	title.add_theme_font_override("font", load("res://font/Silver.ttf"))
	title.add_theme_font_size_override("font_size", 42)
	title.add_theme_color_override("font_color", Color(0.95, 0.85, 1.0, 1.0))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)
	# Body.
	var body := Label.new()
	body.name = "Body"
	body.add_theme_font_override("font", load("res://font/Silver.ttf"))
	body.add_theme_font_size_override("font_size", 29)
	body.add_theme_color_override("font_color", Color(0.85, 0.82, 0.95, 1.0))
	body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.custom_minimum_size = Vector2(0, 90)
	vbox.add_child(body)
	# Buttons row.
	var buttons := HBoxContainer.new()
	buttons.name = "Buttons"
	buttons.add_theme_constant_override("separation", 24)
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_child(buttons)
	var cancel_btn := Button.new()
	cancel_btn.name = "Cancel"
	cancel_btn.text = "SHOP_SELL_PET_CANCEL"
	cancel_btn.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_INHERIT
	cancel_btn.custom_minimum_size = Vector2(180, 60)
	cancel_btn.add_theme_font_override("font", load("res://font/Silver.ttf"))
	cancel_btn.add_theme_font_size_override("font_size", 30)
	cancel_btn.pressed.connect(_on_sell_cancelled)
	buttons.add_child(cancel_btn)
	var confirm_btn := Button.new()
	confirm_btn.name = "Confirm"
	confirm_btn.text = "SHOP_SELL_PET_CONFIRM"
	confirm_btn.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_INHERIT
	confirm_btn.custom_minimum_size = Vector2(180, 60)
	confirm_btn.add_theme_font_override("font", load("res://font/Silver.ttf"))
	confirm_btn.add_theme_font_size_override("font_size", 30)
	confirm_btn.add_theme_color_override("font_color", Color(1.0, 0.84, 0.34, 1.0))
	buttons.add_child(confirm_btn)
	_sell_confirm_dialog = dlg


# Click no backdrop (fora do card) dismissa.
func _on_sell_dialog_backdrop_input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton):
		return
	var mb: InputEventMouseButton = event
	if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
		# Confirma só se clicou DENTRO do card filho — fora dismissa.
		# Como o card consome o evento via PanelContainer, esse handler
		# só dispara em clicks no backdrop (transparente).
		_on_sell_cancelled()


func _sell_pet(id: String) -> void:
	var p := _get_player()
	if p == null or not p.has_method("get_upgrade_count"):
		return
	var lvl: int = int(p.get_upgrade_count(id))
	if lvl <= 0:
		return
	var refund: int = _pet_total_paid(id, lvl) / 2
	if p.has_method("add_gold"):
		p.add_gold(refund)
	if p.has_method("reset_pet"):
		p.reset_pet(id)
	# Vender libera comprar outro pet: re-avalia os slots (preco/disponibilidade)
	# pro novo numero de pets, sem re-rolar a selecao exibida.
	_reeval_aliado_slots()
	if _augment_tooltip != null:
		_augment_tooltip.visible = false
	_play_buy_sound()
	# Rebuild de cards + UI do StatsCard. NÃO faz reroll dos slots — vender um
	# pet não troca os cards exibidos (player escolhe se quer um novo pet
	# usando o reroll manual).
	_build_all_cards()
	_connect_card_buttons()
	_refresh_button_states()
	_refresh_gold_label()
	_refresh_pets_box()
	_refresh_augments_column()
	_refresh_stats_card()


func _reeval_aliado_slots() -> void:
	# Recalcula availability/preco dos slots de aliado JA exibidos pro estado
	# atual de pets (ex: vender libera comprar outro). NAO re-rola a selecao.
	var p := _get_player()
	if p == null:
		return
	var distinct_owned: int = _distinct_pets_owned(p)
	for i in aliado_slots.size():
		var slot: Dictionary = aliado_slots[i]
		var sid: String = String(slot.get("id", ""))
		if sid in _ALL_ALLY_IDS:
			aliado_slots[i] = _build_ally_slot(sid, p, distinct_owned)


func _roll_upg_slots() -> void:
	upg_slots.clear()
	var player := _get_player()
	var already_picked_ids: Array[String] = []
	# Bias pra upgrades já comprados a partir da wave 5: +15% de chance relativa
	# (peso 1.15 vs 1.00). Facilita escalar builds existentes em vez de receber
	# sempre opções totalmente novas no mid/late-game.
	var _wn_for_bias: int = _current_wave_number()
	var owned_weight: float = 1.15 if _wn_for_bias >= 5 else 1.0
	# Joker ("Último Desejo"): wave 5+, não usado ainda, e player tem algo
	# upgradável (senão a carta é inútil). Dev flag força aparecer ignorando
	# TODOS os gates (wave, used, has_target) — útil pra testar o card antes
	# da wave 5 e independente do estado da run.
	var dev_force: bool = GameState.dev_force_joker_next_shop
	var joker_eligible: bool = dev_force or _joker_can_appear(player)
	var force_joker: bool = dev_force
	# Roleta Elemental: elegível quando o player tem um elemental no L3. Dev flag
	# força aparecer (slot 0) ignorando o weight.
	var force_roulette: bool = GameState.dev_force_roulette_next_shop
	var roulette_eligible: bool = force_roulette or _roulette_can_appear(player)
	if force_roulette:
		GameState.dev_force_roulette_next_shop = false
	if force_joker:
		GameState.dev_force_joker_next_shop = false
	for i in 3:
		var pool: Array = []
		var weights: Array[float] = []
		for u in UPGRADE_POOL:
			var id: String = u["id"]
			var max_level: int = u.get("max_level", 999)
			var current: int = 0
			if player != null and player.has_method("get_upgrade_count"):
				current = player.get_upgrade_count(id)
			if current >= max_level:
				continue
			if id in already_picked_ids:
				continue
			# Bloqueia counterpart de pares exclusivos quando o player já tem 1+
			# nível do outro lado (ex: tem Fogo → some Maldição; tem Perfuração
			# → some Ricochete).
			if _player_has_exclusive_counterpart(player, id):
				continue
			# Também bloqueia se OUTRO id do mesmo grupo exclusivo já foi pickeado
			# nesta mesma shop (ex: card 1 = chain → cards 2/3 não podem ter fogo
			# nem curse). Sem isso, dava pra comprar 2 elementais na mesma wave.
			var same_group_already_picked: bool = false
			for prev_id in already_picked_ids:
				var prev_group: Array = _get_exclusive_group(prev_id)
				if not prev_group.is_empty() and id in prev_group:
					same_group_already_picked = true
					break
			if same_group_already_picked:
				continue
			var requires: String = u.get("requires", "")
			if requires != "":
				var req_lvl: int = 0
				if player != null and player.has_method("get_upgrade_count"):
					req_lvl = player.get_upgrade_count(requires)
				if req_lvl <= 0:
					continue
			pool.append(u)
			# Owned (current >= 1) ganha peso extra a partir da wave 5.
			weights.append(owned_weight if current >= 1 else 1.0)
		# Joker entra no pool com weight baixo. Filtra após já ter sido pickeado
		# nesta shop (evita 2 jokers ao mesmo tempo nos 3 slots).
		if joker_eligible and not (JOKER_ID in already_picked_ids):
			pool.append(_make_joker_entry())
			# Chamado do Palhaço (item) multiplica o peso do coringa (×4).
			weights.append(JOKER_WEIGHT * InventoryItems.equipped_joker_weight_mult())
		# Roleta Elemental: entra com peso baixo, 1× por shop.
		if roulette_eligible and not (ROULETTE_ID in already_picked_ids):
			pool.append(_make_roulette_entry())
			weights.append(ROULETTE_WEIGHT)
		if pool.is_empty():
			upg_slots.append({"id": "none", "name": "—", "desc": "—", "price": 0, "available": false})
			continue
		# Force (dev): primeiro slot vira joker/roleta direto. Demais slots rolam normal.
		var picked: Dictionary
		if force_joker and i == 0:
			picked = _make_joker_entry()
		elif force_roulette and i == 0:
			picked = _make_roulette_entry()
		else:
			# Pick ponderado: roll uniforme em [0, total_weight) e caminha no acumulado.
			# Fallback no último entry cobre edge case de arredondamento float.
			var total_w: float = 0.0
			for w in weights:
				total_w += w
			var roll: float = randf() * total_w
			picked = pool[pool.size() - 1]
			var acc: float = 0.0
			for j in pool.size():
				acc += weights[j]
				if roll < acc:
					picked = pool[j]
					break
		already_picked_ids.append(picked["id"])
		var picked_id: String = picked["id"]
		var is_joker_pick: bool = bool(picked.get("is_joker", false))
		# Joker: target_level cosmético = 1 (não escala via current_level). Preço do
		# próximo uso (10g; 20g na 2ª vez com o Chamado do Palhaço), desc vazio.
		if is_joker_pick:
			upg_slots.append({
				"id": picked_id,
				"name": picked["name"],
				"desc": "",
				"price": _joker_price_now(player),
				"available": true,
				"target_level": 1,
				"is_joker": true,
			})
			continue
		# Roleta Elemental: carta especial (surpresa). Desc explica o efeito; o L4
		# sorteado só é revelado ao comprar (no _open_roulette_reveal).
		if bool(picked.get("is_roulette", false)):
			upg_slots.append({
				"id": ROULETTE_ID,
				"name": picked["name"],
				"desc": "SHOP_ELEMENTAL_ROULETTE_DESC",
				"price": ROULETTE_PRICE,
				"available": true,
				"target_level": 1,
				"is_roulette": true,
			})
			continue
		var current_level: int = 0
		if player != null and player.has_method("get_upgrade_count"):
			current_level = player.get_upgrade_count(picked_id)
		var target_level: int = current_level + 1
		var price: int = _get_upgrade_price(picked_id, current_level)
		upg_slots.append({
			"id": picked_id,
			"name": picked["name"],
			"desc": _get_upgrade_desc(picked_id, target_level),
			"price": price,
			"available": true,
			"target_level": target_level,
		})


func _get_upgrade_price(id: String, player_current_level: int) -> int:
	if id == JOKER_ID:
		return _joker_price_now(_get_player())
	if id == ROULETTE_ID:
		return ROULETTE_PRICE
	if id in UPGRADE_PRICE_OVERRIDES:
		return int(UPGRADE_PRICE_OVERRIDES[id])
	if player_current_level < 0:
		player_current_level = 0
	if player_current_level >= PRICE_TABLE.size():
		return PRICE_TABLE[PRICE_TABLE.size() - 1]
	return PRICE_TABLE[player_current_level]


# Entry "fake" do joker pra entrar no pool de _roll_upg_slots como um upgrade
# normal. is_joker=true sinaliza pro resto do pipeline tratar diferente.
func _make_joker_entry() -> Dictionary:
	return {
		"id": JOKER_ID,
		"name": "SHOP_JOKER_NAME",
		"max_level": 1,
		"is_joker": true,
	}


# Entry "fake" da Roleta Elemental pro pool de _roll_upg_slots.
func _make_roulette_entry() -> Dictionary:
	return {
		"id": ROULETTE_ID,
		"name": "SHOP_UPG_ELEMENTAL_ROULETTE",
		"max_level": 1,
		"is_roulette": true,
	}


# Roleta Elemental pode aparecer? Só quando o player tem um elemental EXATAMENTE no
# L3 (no L4 não há o que trocar; no L1/L2 ainda não investiu o suficiente).
func _roulette_can_appear(player: Node) -> bool:
	if player == null or not player.has_method("get_upgrade_count"):
		return false
	for id in _ELEMENTAL_IDS:
		if int(player.get_upgrade_count(id)) == 3:
			return true
	return false


# Joker pode aparecer? Precisa: wave 5+, não usado ainda, e player tem algum
# item upgradável (senão a carta é inútil — gasta 10g e o modal abre vazio).
func _joker_can_appear(player: Node) -> bool:
	var wn: int = _current_wave_number()
	if wn < JOKER_FIRST_WAVE:
		return false
	if player == null:
		return false
	# Uso único por run; com o Chamado do Palhaço equipado, até 2 usos.
	var used: int = int(player.joker_uses_this_run) if "joker_uses_this_run" in player else 0
	if used >= _joker_max_uses():
		return false
	return _joker_has_any_target(player)


# Máximo de jokers por run: 2 com o Chamado do Palhaço equipado, senão 1.
func _joker_max_uses() -> int:
	return 2 if InventoryItems.joker_allows_twice() else 1


# Preço do PRÓXIMO joker desta run: 1º = 10g, 2º (Chamado do Palhaço) = 20g.
func _joker_price_now(player: Node) -> int:
	var used: int = int(player.joker_uses_this_run) if (player != null and "joker_uses_this_run" in player) else 0
	return JOKER_SECOND_PRICE if used >= 1 else JOKER_PRICE


# Retorna true se o player tem ao menos 1 item que o joker pode upar:
# - Qualquer status com lvl >= 1 (sem cap)
# - Qualquer pet com lvl >= 1 e < 4
# - Qualquer upgrade gameplay com lvl >= 1 e < 4
func _joker_has_any_target(player: Node) -> bool:
	if player == null or not player.has_method("get_upgrade_count"):
		return false
	for sid in _JOKER_STATUS_IDS:
		if int(player.get_upgrade_count(sid)) >= 1:
			return true
	for pid in _JOKER_PET_IDS:
		var lvl: int = int(player.get_upgrade_count(pid))
		if lvl >= 1 and lvl < 4:
			return true
	for u in UPGRADE_POOL:
		var uid: String = String(u["id"])
		var max_lvl: int = int(u.get("max_level", 4))
		var ulvl: int = int(player.get_upgrade_count(uid))
		if ulvl >= 1 and ulvl < max_lvl:
			return true
	return false


func _get_upgrade_descs_array(id: String) -> Array:
	match id:
		"hp": return HP_DESCS
		"armor": return ARMOR_DESCS
		"damage": return DAMAGE_DESCS
		"perfuracao": return PERFURACAO_DESCS
		"spectral_arrow": return SPECTRAL_DESCS
		"attack_speed": return ATTACK_SPEED_DESCS
		"multi_arrow": return MULTI_ARROW_DESCS
		"double_arrows": return DOUBLE_ARROWS_DESCS
		"chain_lightning": return CHAIN_LIGHTNING_DESCS
		"move_speed": return MOVE_SPEED_DESCS
		"gold_magnet": return GOLD_MAGNET_DESCS
		"dash": return DASH_DESCS
		"esquivando": return ESQUIVANDO_DESCS
		"fenda": return FENDA_DESCS
		"adrenalina": return ADRENALINA_DESCS
		"life_steal": return LIFE_STEAL_DESCS
		"fire_arrow": return FIRE_ARROW_DESCS
		"curse_arrow": return CURSE_ARROW_DESCS
		"ice_arrow": return ICE_ARROW_DESCS
		"stone_arrow": return STONE_ARROW_DESCS
		"tide_arrow": return TIDE_ARROW_DESCS
		"boomerang": return BOOMERANG_DESCS
		"critical_chance": return CRITICAL_CHANCE_DESCS
		"tiger_claws": return TIGER_CLAWS_DESCS
		"ricochet_arrow": return RICOCHET_ARROW_DESCS
		"graviton": return GRAVITON_DESCS
		"claudio_druida": return CLAUDIO_DRUIDA_DESCS
		"leno": return LENO_DESCS
		"tilisko": return TILISKO_DESCS
		"capivara_joe": return CAPIVARA_JOE_DESCS
		"ting": return TING_DESCS
		"mini_mago": return MINI_MAGO_DESCS
		"arbusto": return ARBUSTO_DESCS
	return []


func _get_upgrade_desc(id: String, target_level: int) -> String:
	var arr: Array = _get_upgrade_descs_array(id)
	if arr.is_empty():
		return ""
	var idx: int = clampi(target_level - 1, 0, arr.size() - 1)
	return arr[idx]


# Altura da faixa do rodapé reservada pro indicador "ver mais" quando a desc
# estoura. O texto é encurtado nessa medida e o hint ocupa o espaço.
const _MORE_HINT_STRIP_H: float = 36.0
# Tamanho da fonte do "+ ver mais" (bem maior que o resto pra chamar atenção).
const _MORE_HINT_FONT_SIZE: int = 27
# Colado no fim do texto truncado pra indicar que tem continuação.
const _MORE_ELLIPSIS: String = " (...)"


func _refresh_more_hint(card: Control) -> void:
	# Mostra/esconde o indicador "+ ver mais" no rodapé do card quando a
	# descrição não cabe no DescLabel. Quando estoura, trunca o texto e cola
	# " (...)" no fim. Só vale pra cards com tooltip multi-nível (upgrades/
	# aliados) — estrutura/locked/placeholder não têm.
	if not is_instance_valid(card):
		return
	var desc_label: Label = card.get_node_or_null("DescLabel") as Label
	if desc_label == null:
		return
	# Captura o texto completo ANTES de qualquer await (o _build_card acabou de
	# setar o texto cheio; uma passada anterior pode tê-lo truncado).
	var full_text: String = desc_label.text
	await get_tree().process_frame
	if not is_instance_valid(card) or not is_instance_valid(desc_label):
		return
	var hint: Label = card.get_node_or_null("MoreHint") as Label
	# Guarda o offset_bottom original uma vez (estado "altura cheia").
	if not card.has_meta("desc_full_bottom"):
		card.set_meta("desc_full_bottom", desc_label.offset_bottom)
	var full_bottom: float = float(card.get_meta("desc_full_bottom"))
	# Reset pro estado base antes de medir (altura cheia + centralizado + texto cheio).
	desc_label.offset_bottom = full_bottom
	desc_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	desc_label.text = full_text
	if hint != null:
		hint.visible = false
	# Só cards com array de descs (upgrade/aliado real) ganham o indicador.
	var card_id: String = String(card.get_meta("aug_id", ""))
	if _get_upgrade_descs_array(card_id).is_empty():
		return
	if not desc_label.visible:
		return
	# Mede overflow com a altura cheia.
	await get_tree().process_frame
	if not is_instance_valid(card) or not is_instance_valid(desc_label):
		return
	var overflow: bool = desc_label.get_line_count() > desc_label.get_visible_line_count()
	if not overflow:
		return
	# Overflow: encurta a área de texto pra reservar a faixa do hint e alinha o
	# texto ao topo (a leitura começa do início, o corte fica embaixo).
	desc_label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	desc_label.offset_bottom = full_bottom - _MORE_HINT_STRIP_H
	await get_tree().process_frame
	if not is_instance_valid(card) or not is_instance_valid(desc_label):
		return
	# Trunca o texto pra caber na altura reduzida, deixando " (...)" no fim.
	var max_lines: int = desc_label.get_visible_line_count()
	_truncate_with_ellipsis(desc_label, full_text, max_lines)
	if hint == null:
		hint = _make_more_hint(card, desc_label, full_bottom)
	hint.add_theme_color_override("font_color", desc_label.get_theme_color("font_color"))
	hint.modulate = Color(1, 1, 1, 1)
	hint.visible = true


func _truncate_with_ellipsis(label: Label, full_text: String, max_lines: int) -> void:
	# Acha o maior prefixo de full_text que, com " (...)" no fim, ainda cabe em
	# max_lines linhas (busca binária por palavra). get_line_count() reflete o
	# texto atual após reshape, então mede sem esperar frame.
	if max_lines < 1:
		max_lines = 1
	label.text = full_text
	if label.get_line_count() <= max_lines:
		return
	var words: PackedStringArray = full_text.split(" ", false)
	if words.is_empty():
		label.text = _MORE_ELLIPSIS.strip_edges()
		return
	var best: String = ""
	var lo: int = 1
	var hi: int = words.size()
	while lo <= hi:
		var mid: int = (lo + hi) / 2
		var candidate: String = " ".join(words.slice(0, mid)) + _MORE_ELLIPSIS
		label.text = candidate
		if label.get_line_count() <= max_lines:
			best = candidate
			lo = mid + 1
		else:
			hi = mid - 1
	if best == "":
		best = _MORE_ELLIPSIS.strip_edges()  # nem 1 palavra coube
	label.text = best


func _make_more_hint(card: Control, desc_label: Label, full_bottom: float) -> Label:
	var hint := Label.new()
	hint.name = "MoreHint"
	hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hint.offset_left = desc_label.offset_left
	hint.offset_right = desc_label.offset_right
	hint.offset_top = full_bottom - _MORE_HINT_STRIP_H
	hint.offset_bottom = full_bottom
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hint.autowrap_mode = TextServer.AUTOWRAP_OFF
	var f: Font = desc_label.get_theme_font("font")
	if f != null:
		hint.add_theme_font_override("font", f)
	hint.add_theme_font_size_override("font_size", _MORE_HINT_FONT_SIZE)
	hint.text = tr("SHOP_VER_MAIS")
	card.add_child(hint)
	return hint


# Categorias de upgrade que afetam grupos exclusivos (EXCLUSIVE_PAIRS).
# Mostra no card de compra e no tooltip do equipado pra explicar pro jogador
# que aquela escolha bloqueia a outra do par.
const UPGRADE_CATEGORIES: Dictionary = {
	"fire_arrow": "SHOP_UPG_CAT_ELEMENTAL",
	"curse_arrow": "SHOP_UPG_CAT_ELEMENTAL",
	"chain_lightning": "SHOP_UPG_CAT_ELEMENTAL",
	"ice_arrow": "SHOP_UPG_CAT_ELEMENTAL",
	"stone_arrow": "SHOP_UPG_CAT_ELEMENTAL",
	"tide_arrow": "SHOP_UPG_CAT_ELEMENTAL",
	"perfuracao": "SHOP_UPG_CAT_ARROW_MOD",
	"ricochet_arrow": "SHOP_UPG_CAT_ARROW_MOD",
	"multi_arrow": "SHOP_UPG_CAT_ARROW_VOLLEY",
	"double_arrows": "SHOP_UPG_CAT_ARROW_VOLLEY",
	"dash": "SHOP_UPG_CAT_MOBILITY",
	"esquivando": "SHOP_UPG_CAT_MOBILITY",
	"fenda": "SHOP_UPG_CAT_MOBILITY",
	"adrenalina": "SHOP_UPG_CAT_MOBILITY",
}


# ---------- Build cards ----------

func _build_all_cards() -> void:
	for i in 2:
		_build_card(estrut_cards[i], estrutura_slots[i], 0, "estrutura")
	for i in 2:
		var tl: int = int(status_slots[i].get("target_level", 0))
		_build_card(status_cards[i], status_slots[i], tl, "status")
	for i in 3:
		var tl2: int = int(upg_slots[i].get("target_level", 0))
		_build_card(upg_cards[i], upg_slots[i], tl2, "upgrade")
	for i in 3:
		var tl3: int = _aliado_target_level(aliado_slots[i])
		_build_card(aliado_cards[i], aliado_slots[i], tl3, "aliado")


func _aliado_target_level(slot: Dictionary) -> int:
	# Aliado não usa target_level no slot; calcula a partir do nível atual do
	# player (claudio_druida = nível atual + 1; futuros aliados podem seguir o
	# mesmo padrão se forem stackable).
	var id: String = slot.get("id", "")
	if id == "" or id == "soon" or id == "none":
		return 0
	var player := _get_player()
	if player == null or not player.has_method("get_upgrade_count"):
		return 1
	return int(player.get_upgrade_count(id)) + 1


func _build_card(card: Control, slot: Dictionary, target_level: int, category: String) -> void:
	var available: bool = slot.get("available", false)
	# Metadata pra tooltip on hover (mostra todos os níveis do upgrade).
	card.set_meta("aug_id", String(slot.get("id", "")))
	card.set_meta("aug_target_level", target_level)
	card.set_meta("aug_category", category)
	# Arte por id: aplica primeiro pra saber se está em modo placeholder (sem arte
	# própria) — placeholders tingem texto em cinza pra diferenciar visualmente.
	_apply_card_art(card, category, slot.get("id", ""), target_level, available)
	_ensure_coin_icon(card, category)
	var is_placeholder: bool = bool(card.get_meta("using_placeholder", false))
	var slot_id_str: String = slot.get("id", "")
	var text_color: Color = _resolve_text_color(category, slot_id_str, is_placeholder)
	var title_label: Label = card.get_node_or_null("TitleLabel") as Label
	if title_label != null:
		title_label.text = slot.get("name", "—")
		title_label.add_theme_color_override("font_color", text_color)
		title_label.modulate = Color.WHITE
	# Cor do desc/price: por padrão = cor do título. Mas alguns ids têm
	# UPGRADE_DESC_COLORS que sobrescreve só pra desc/price (título mantém o seu).
	# Funciona tanto pra category "upgrade" quanto "aliado" (Leno usa esse override).
	var desc_color: Color = text_color
	if not is_placeholder and (category == "upgrade" or category == "aliado") and UPGRADE_DESC_COLORS.has(slot_id_str):
		desc_color = UPGRADE_DESC_COLORS[slot_id_str]
	var desc_label: Label = card.get_node_or_null("DescLabel") as Label
	if desc_label != null:
		var desc_text: String = tr(slot.get("desc", "—"))
		# Prefixa com categoria (Elemental / Tipo de flecha) pros upgrades de
		# par exclusivo, pra explicar pro jogador que escolher um bloqueia o outro.
		if not is_placeholder and category == "upgrade" and UPGRADE_CATEGORIES.has(slot_id_str):
			desc_text = "[%s]\n%s" % [tr(UPGRADE_CATEGORIES[slot_id_str]), desc_text]
		desc_label.text = desc_text
		desc_label.add_theme_color_override("font_color", desc_color)
		desc_label.modulate = Color.WHITE
	var price_label: Label = card.get_node_or_null("PriceLabel") as Label
	if price_label != null:
		price_label.text = ("%d" % int(slot.get("price", 0))) if available else "—"
		# Em placeholder, modulate pega a cor de placeholder da categoria
		# (default = cinza). Em arte real, modulate fica branco e a cor vem
		# do font_color override mais abaixo.
		price_label.modulate = text_color if is_placeholder else Color.WHITE
		# Preço usa a cor de desc (que default é a cor do título, mas pode ser
		# override pelo UPGRADE_DESC_COLORS).
		if not is_placeholder:
			if category == "status" and STATUS_TITLE_COLORS.has(slot_id_str):
				price_label.add_theme_color_override("font_color", STATUS_TITLE_COLORS[slot_id_str])
			elif (category == "upgrade" or category == "aliado") and UPGRADE_DESC_COLORS.has(slot_id_str):
				price_label.add_theme_color_override("font_color", UPGRADE_DESC_COLORS[slot_id_str])
			elif category == "upgrade" and UPGRADE_TITLE_COLORS.has(slot_id_str):
				price_label.add_theme_color_override("font_color", UPGRADE_TITLE_COLORS[slot_id_str])
			elif category == "aliado" and slot_id_str != "" and slot_id_str != "soon" and slot_id_str != "none" and slot_id_str != "locked" and slot_id_str != "free_pet":
				# Aliado com cor de título dedicada (ex: Tilisko → branco) usa ela; senão o padrão.
				price_label.add_theme_color_override("font_color", UPGRADE_TITLE_COLORS.get(slot_id_str, ALIADO_TEXT_COLOR))
			else:
				price_label.remove_theme_color_override("font_color")
		else:
			price_label.remove_theme_color_override("font_color")
	var stars_label: Label = card.get_node_or_null("StarsLabel") as Label
	if stars_label != null:
		stars_label.text = ""
	# Cards específicos pedem título + desc centralizados (em vez do layout
	# default que tem título offset à direita pra dar espaço pra arte à
	# esquerda). Coin master tem arte central então texto centralizado fica
	# melhor visualmente.
	if CENTERED_TEXT_IDS.has(slot_id_str):
		if title_label != null:
			title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			title_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			title_label.offset_left = 12.0
			title_label.offset_right = 292.0
		if desc_label != null:
			desc_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			desc_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	# Joker e Roleta Elemental: sem texto visual na carta (só price + tooltip on hover).
	# Restaurado pra visible=true pelos próximos rebuilds do card via os labels
	# acima recebendo .text — visible só fica false enquanto este slot é joker/roleta.
	var hide_text_card: bool = bool(slot.get("is_joker", false)) or bool(slot.get("is_roulette", false))
	if title_label != null:
		title_label.visible = not hide_text_card
	if desc_label != null:
		desc_label.visible = not hide_text_card
	# "Ver mais": descrições longas estouram o DescLabel (clip_text). Quando isso
	# acontece num card com tooltip multi-nível, mostra um indicador no rodapé
	# apontando pro hover (que já lista todos os níveis).
	_refresh_more_hint(card)


# IDs de upgrade cujo título + desc devem ser centralizados horizontal e
# verticalmente (em vez do layout default que deixa o título encostado à
# direita pra dar espaço pra arte à esquerda).
const CENTERED_TEXT_IDS: Array[String] = ["gold_magnet", "life_steal", "stone_arrow"]


# Tamanho do frame por categoria (paisagem vs retrato).
const _CARD_FRAME_SIZES: Dictionary = {
	"status": Vector2i(65, 17),
	"estrutura": Vector2i(65, 17),
	"aliado": Vector2i(38, 47),
	"upgrade": Vector2i(38, 47),
}

# Sheets combinados por categoria: 1 arquivo PNG com várias linhas, cada linha
# = um id da categoria, cada coluna = um nível (1, 2, 3, 4, 4+). Tem
# prioridade sobre os arquivos individuais `<category>/<id>.png` quando o id
# está na tabela `rows`.
const _CATEGORY_SHEETS: Dictionary = {
	"status": {
		"path": "res://assets/Hud/shop/status/HP - atck speed - Move speed - Atck Dmg.png",
		"rows": {"hp": 0, "attack_speed": 1, "move_speed": 2, "damage": 3},
	},
}

# Cor do texto quando o card mostra a arte placeholder (sem desenho próprio
# ainda) — cinza pra avisar visualmente "card temporário".
const PLACEHOLDER_TEXT_COLOR: Color = Color(0x6e / 255.0, 0x6e / 255.0, 0x6e / 255.0)  # #6e6e6e
# Override de cor do texto placeholder por categoria. Quando a arte do
# placeholder é desenhada (não a default cinza), o texto pode pedir uma cor
# que combine com a arte — ex: estrutura placeholder marrom-escuro = #392c0e.
const PLACEHOLDER_TEXT_COLORS_BY_CATEGORY: Dictionary = {
	"estrutura": Color(0x39 / 255.0, 0x2c / 255.0, 0x0e / 255.0),  # #392c0e
}
# Override de filename do placeholder por categoria. Usado quando o asset não
# está nomeado simplesmente "placeholder.png" (ex: "estrutura card placeholder.png").
const PLACEHOLDER_FILE_OVERRIDES: Dictionary = {
	"estrutura": "estrutura card placeholder",
}
# Cor do título por status — combina com a arte de cada card.
const STATUS_TITLE_COLORS: Dictionary = {
	"hp": Color(0x29 / 255.0, 0x7b / 255.0, 0x59 / 255.0),  # #297b59
	"attack_speed": Color(0xb4 / 255.0, 0x7f / 255.0, 0x0a / 255.0),  # #b47f0a
	"damage": Color(0x34 / 255.0, 0x10 / 255.0, 0x42 / 255.0),  # #341042
	"move_speed": Color(0x58 / 255.0, 0x58 / 255.0, 0x58 / 255.0),  # #585858
	"armor": Color(0x1f / 255.0, 0x54 / 255.0, 0x54 / 255.0),  # #1f5454
}
# Override de nome de arquivo por slot_id (status). Útil quando o asset não
# segue exatamente o padrão `<id>.png` (ex: id="armor" mas o arquivo é
# "Armadura.png" porque o user nomeou em PT).
const STATUS_FILE_OVERRIDES: Dictionary = {
	"armor": "Armadura",
}
# Cor do título/desc por upgrade — combina com a arte de cada card. Upgrades
# que não estão aqui (e não têm sheet próprio) caem em placeholder gray.
const UPGRADE_TITLE_COLORS: Dictionary = {
	"tilisko": Color.WHITE,  # arte do card escura → texto branco
	"chain_lightning": Color(0xfb / 255.0, 0xdd / 255.0, 0x82 / 255.0),  # #fbdd82
	"multi_arrow": Color(0x3d / 255.0, 0x15 / 255.0, 0x00 / 255.0),  # #3d1500 (marrom escuro)
	"double_arrows": Color(0x3d / 255.0, 0x15 / 255.0, 0x00 / 255.0),  # #3d1500 (marrom escuro — mesma família do multi_arrow)
	"fire_arrow": Color(0x77 / 255.0, 0x20 / 255.0, 0x00 / 255.0),  # #772000
	"curse_arrow": Color.WHITE,  # texto branco no card do Disparo Profano
	"ice_arrow": Color(0x1b / 255.0, 0x31 / 255.0, 0x6c / 255.0),  # #1b316c (azul escuro — combina com a arte do card)
	"stone_arrow": Color.WHITE,  # texto branco no card da Pedra
	"leno": Color(0xfc / 255.0, 0xb4 / 255.0, 0xcc / 255.0),  # #fcb4cc
	"claudio_druida": Color(0x5d / 255.0, 0x80 / 255.0, 0x5a / 255.0),  # #5d805a
	"ting": Color.WHITE,  # branco — alto contraste no fundo laranja
	"capivara_joe": Color.WHITE,  # branco — alto contraste no fundo vermelho
	"mini_mago": Color.WHITE,  # branco — pedido pelo design da carta
	"arbusto": Color(0x2d / 255.0, 0x55 / 255.0, 0x2d / 255.0),  # verde escuro
	"graviton": Color.WHITE,
	"perfuracao": Color.WHITE,
	"ricochet_arrow": Color.WHITE,
	"gold_magnet": Color(0x6a / 255.0, 0x53 / 255.0, 0x0b / 255.0),  # #6a530b
	"life_steal": Color(0x58 / 255.0, 0x14 / 255.0, 0x1f / 255.0),  # #58141f
	"dash": Color(0x3d / 255.0, 0x28 / 255.0, 0x18 / 255.0),  # #3d2818 (marrom escuro contrasta com cream)
	"esquivando": Color(0x3d / 255.0, 0x28 / 255.0, 0x18 / 255.0),  # mesmo do dash — compartilham arte
	"fenda": Color(0x3d / 255.0, 0x28 / 255.0, 0x18 / 255.0),  # mesmo do dash — compartilha arte
	"adrenalina": Color(0x3d / 255.0, 0x28 / 255.0, 0x18 / 255.0),  # mesmo do dash — compartilha arte
	"boomerang": Color(0xfb / 255.0, 0xe3 / 255.0, 0xc6 / 255.0),  # creme claro (fundo marrom da carta)
	"critical_chance": Color(0xcb / 255.0, 0x49 / 255.0, 0x0d / 255.0),  # #cb490d (laranja-vermelho)
}
# Cor secundária (DescLabel + PriceLabel) por upgrade. Quando definido,
# sobrescreve a cor do título nesses dois labels — útil pra cards onde título
# e descrição têm contraste de cor (ex: Leno: rosa-claro título, rosa-escuro desc).
const UPGRADE_DESC_COLORS: Dictionary = {
	"leno": Color(0xab / 255.0, 0x54 / 255.0, 0x82 / 255.0),  # #ab5482
	"claudio_druida": Color(0x2d / 255.0, 0x3e / 255.0, 0x2b / 255.0),  # #2d3e2b
	"ting": Color.WHITE,  # mesmo do título — branco em todo o texto
	"capivara_joe": Color.WHITE,  # mesmo do título — branco em todo o texto
	"mini_mago": Color.WHITE,  # mesmo do título — branco em todo o texto
	"arbusto": Color(0x55 / 255.0, 0x7a / 255.0, 0x52 / 255.0),  # verde médio
	"graviton": Color(0x61 / 255.0, 0x61 / 255.0, 0x61 / 255.0),  # #616161
	"chain_lightning": Color(0xa7 / 255.0, 0x8f / 255.0, 0x24 / 255.0),  # #a78f24
}
# Path absoluto pra arte do card por slot_id. Usado quando o asset não segue
# o padrão `<category>/<id>.png` (ex: Leno tem subfolder e nome com espaço).
const CARD_PATH_OVERRIDES: Dictionary = {
	"leno": "res://assets/Hud/shop/aliado/Leno/Leno Card.png",
	"claudio_druida": "res://assets/Hud/shop/aliado/claudio_druida/claudio_druida card.png",
	"ting": "res://assets/Hud/shop/aliado/ting/ting card.png",
	"capivara_joe": "res://assets/Hud/shop/aliado/capivara joe/capivara joe card.png",
	"mini_mago": "res://assets/Hud/shop/aliado/mini mago/mini mago card.png",
	"arbusto": "res://assets/Hud/shop/aliado/abursto carrara/arbusto.png",
	"graviton": "res://assets/Hud/shop/upgrade/graviton/graviton card-Sheet.png",
	# id é "ricochet_arrow" mas o arquivo é "ricochete.png" (PT). Override pra
	# o loader achar a arte certa.
	"ricochet_arrow": "res://assets/Hud/shop/upgrade/ricochete.png",
	# Placeholder: reusa a arte do ricochete até a Espectral ter arte própria.
	"spectral_arrow": "res://assets/Hud/shop/upgrade/ricochete.png",
	"tilisko": "res://assets/Hud/shop/aliado/tilisko/tilosko card.png",
	# id é "gold_magnet" mas o arquivo é "coin master.png" (com espaço).
	"gold_magnet": "res://assets/Hud/shop/upgrade/coin master.png",
	# id "life_steal" mas arquivo é "life steal.png" (com espaço).
	"life_steal": "res://assets/Hud/shop/upgrade/life steal.png",
	# fire_arrow2.png é a arte nova; fire_arrow.png antigo foi removido.
	"fire_arrow": "res://assets/Hud/shop/upgrade/fire_arrow2.png",
	# Sangue Frio: sheet 4 frames (1 por nível), na subpasta "ice arrow".
	"ice_arrow": "res://assets/Hud/shop/upgrade/ice arrow/sangue frio card design-Sheet.png",
	# Disparo de Pedra: sheet 4 frames (1 por nível), mesma dim do card de gelo.
	"stone_arrow": "res://assets/Hud/shop/upgrade/disparo do pedra/disparo de pedra card-Sheet.png",
	# Fúria da Maré: sheet 4 frames (só o L1 usado por enquanto).
	"tide_arrow": "res://assets/Hud/shop/upgrade/furia da maré/furia da maré.png",
	"boomerang": "res://assets/Hud/shop/upgrade/boomerang/boomerang card design.png",
	"critical_chance": "res://assets/Hud/shop/upgrade/flechas criticas/felchas criticas card design.png",
	"tiger_claws": "res://assets/Hud/shop/upgrade/garras de tigre/garras de tigre hud-Sheet.png",
	# id "dash" mas arquivo é "deslizando.png" (nome PT do upgrade).
	"dash": "res://assets/Hud/shop/upgrade/deslizando.png",
	# Esquivando compartilha a arte do dash (mesma categoria movimentação,
	# mutuamente exclusivos — o player só compra um dos dois por run).
	"esquivando": "res://assets/Hud/shop/upgrade/deslizando.png",
	"fenda": "res://assets/Hud/shop/upgrade/deslizando.png",
	"adrenalina": "res://assets/Hud/shop/upgrade/deslizando.png",
	# double_arrows compartilha a arte do multi_arrow (mesma família — marrom).
	# Quando tiver arte própria, trocar pra "res://assets/Hud/shop/upgrade/double_arrows.png".
	"double_arrows": "res://assets/Hud/shop/upgrade/multi_arrow.png",
	# Carta "Último Desejo" (joker): subpasta dedicada, sem desc na arte.
	"joker": "res://assets/Hud/shop/upgrade/carta coringa/carta coringa.png",
	# Carta "Roleta Elemental": arte única 38×47 (PNG exportado do .aseprite).
	"elemental_roulette": "res://assets/Hud/shop/upgrade/up elemental/up elemental.png",
}
# Cor única pros aliados (todos compartilham por enquanto).
const ALIADO_TEXT_COLOR: Color = Color(0x2c / 255.0, 0x1f / 255.0, 0x1f / 255.0)  # #2c1f1f
# Posição default do CoinIcon por categoria (relativo ao card). User pode
# ajustar via layout editor. Tamanho reduzido pra não competir visualmente
# com o número do preço.
const _COIN_ICON_DEFAULTS: Dictionary = {
	"status": Rect2(360.0, 51.0, 24.0, 24.0),
	"estrutura": Rect2(360.0, 51.0, 24.0, 24.0),
	"aliado": Rect2(120.0, 305.0, 20.0, 20.0),
	"upgrade": Rect2(120.0, 305.0, 20.0, 20.0),
}


func _apply_card_art(card: Control, category: String, slot_id: String, target_level: int, available: bool) -> void:
	var bg: TextureRect = card.get_node_or_null("Bg") as TextureRect
	if bg == null:
		return
	# Cacheia textura default da .tscn (fallback final) na primeira passada.
	if not card.has_meta("base_texture"):
		card.set_meta("base_texture", bg.texture)
	card.set_meta("using_placeholder", false)
	# Slots vazios / indisponíveis usam o placeholder da categoria (se houver)
	# em vez do template genérico. Mantém o visual consistente entre cards.
	if slot_id == "" or slot_id == "soon" or slot_id == "none" or not available:
		var placeholder_tex: Texture2D = _load_card_texture(category, "placeholder")
		if placeholder_tex != null:
			bg.texture = _make_card_atlas(placeholder_tex, category, target_level)
			card.set_meta("using_placeholder", true)
		else:
			bg.texture = card.get_meta("base_texture")
		return
	# 1) Sheet combinado da categoria (várias rows = vários ids num PNG só).
	var combined_atlas: AtlasTexture = _try_combined_sheet_atlas(category, slot_id, target_level)
	if combined_atlas != null:
		bg.texture = combined_atlas
		return
	# 2) Arquivo individual `<category>/<id>.png` (1 row, várias colunas).
	var tex: Texture2D = _load_card_texture(category, slot_id)
	if tex == null:
		# 3) Placeholder da categoria.
		tex = _load_card_texture(category, "placeholder")
		if tex != null:
			card.set_meta("using_placeholder", true)
	if tex == null:
		bg.texture = card.get_meta("base_texture")
		return
	bg.texture = _make_card_atlas(tex, category, target_level)


func _try_combined_sheet_atlas(category: String, slot_id: String, target_level: int) -> AtlasTexture:
	if not _CATEGORY_SHEETS.has(category):
		return null
	var sheet: Dictionary = _CATEGORY_SHEETS[category]
	var rows: Dictionary = sheet.get("rows", {})
	if not rows.has(slot_id):
		return null
	var path: String = sheet.get("path", "")
	if path == "" or not ResourceLoader.exists(path):
		return null
	var tex: Texture2D = load(path) as Texture2D
	if tex == null:
		return null
	var fsize: Vector2i = _CARD_FRAME_SIZES.get(category, Vector2i(38, 47))
	var col_count: int = maxi(1, int(tex.get_width() / fsize.x))
	var col: int = clampi(target_level - 1, 0, col_count - 1)
	var row: int = int(rows[slot_id])
	var atlas := AtlasTexture.new()
	atlas.atlas = tex
	atlas.region = Rect2(col * fsize.x, row * fsize.y, fsize.x, fsize.y)
	return atlas


func _load_card_texture(category: String, name_id: String) -> Texture2D:
	# Path absoluto override vence todo o resto (ex: Leno tem subfolder + nome
	# com espaço — não cabe no template padrão `<category>/<id>.png`).
	if CARD_PATH_OVERRIDES.has(name_id):
		var override_path: String = CARD_PATH_OVERRIDES[name_id]
		if ResourceLoader.exists(override_path):
			return load(override_path) as Texture2D
	var filename: String = name_id
	if name_id == "placeholder" and PLACEHOLDER_FILE_OVERRIDES.has(category):
		filename = PLACEHOLDER_FILE_OVERRIDES[category]
	elif category == "status" and STATUS_FILE_OVERRIDES.has(name_id):
		filename = STATUS_FILE_OVERRIDES[name_id]
	var path := "res://assets/Hud/shop/%s/%s.png" % [category, filename]
	if not ResourceLoader.exists(path):
		return null
	return load(path) as Texture2D


func _resolve_text_color(category: String, slot_id: String, is_placeholder: bool) -> Color:
	# Placeholder sempre vence (card sem arte real). Por padrão cinza, mas
	# categorias com arte placeholder dedicada podem ter cor própria.
	if is_placeholder:
		if PLACEHOLDER_TEXT_COLORS_BY_CATEGORY.has(category):
			return PLACEHOLDER_TEXT_COLORS_BY_CATEGORY[category]
		return PLACEHOLDER_TEXT_COLOR
	if category == "status" and STATUS_TITLE_COLORS.has(slot_id):
		return STATUS_TITLE_COLORS[slot_id]
	if category == "upgrade" and UPGRADE_TITLE_COLORS.has(slot_id):
		return UPGRADE_TITLE_COLORS[slot_id]
	if category == "aliado" and slot_id != "" and slot_id != "soon" and slot_id != "none":
		# Aliados podem ter cor de título dedicada (Leno → pink-light).
		# Senão caem no ALIADO_TEXT_COLOR padrão.
		if UPGRADE_TITLE_COLORS.has(slot_id):
			return UPGRADE_TITLE_COLORS[slot_id]
		return ALIADO_TEXT_COLOR
	return Color.WHITE


func _ensure_coin_icon(card: Control, category: String) -> void:
	# Adiciona um CoinIcon (TextureRect com a moeda dourada) como filho do card,
	# se ainda não existir. Posição default por categoria — user pode arrastar
	# via layout editor.
	var icon: TextureRect = card.get_node_or_null("CoinIcon") as TextureRect
	if icon != null:
		return
	icon = TextureRect.new()
	icon.name = "CoinIcon"
	icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Frame 0 do spritesheet de moedas (4 frames de 8×8).
	var coin_sheet: Texture2D = load("res://assets/obecjts map/coins.png")
	if coin_sheet != null:
		var atlas := AtlasTexture.new()
		atlas.atlas = coin_sheet
		atlas.region = Rect2(0, 0, 8, 8)
		icon.texture = atlas
	var rect: Rect2 = _COIN_ICON_DEFAULTS.get(category, Rect2(0, 0, 32, 32))
	icon.offset_left = rect.position.x
	icon.offset_top = rect.position.y
	icon.offset_right = rect.position.x + rect.size.x
	icon.offset_bottom = rect.position.y + rect.size.y
	card.add_child(icon)


func _make_card_atlas(tex: Texture2D, category: String, target_level: int) -> AtlasTexture:
	var fsize: Vector2i = _CARD_FRAME_SIZES.get(category, Vector2i(38, 47))
	var fw: int = fsize.x
	var fh: int = fsize.y
	var img_w: int = tex.get_width()
	var frame_count: int = maxi(1, int(img_w / fw))
	var frame_idx: int = clampi(target_level - 1, 0, frame_count - 1)
	var atlas := AtlasTexture.new()
	atlas.atlas = tex
	atlas.region = Rect2(frame_idx * fw, 0, fw, fh)
	return atlas


func _connect_card_buttons() -> void:
	for i in 2:
		_connect_button(estrut_cards[i].get_node("BuyBtn"), Callable(self, "_buy_estrutura").bind(i))
		_setup_card_hover(estrut_cards[i])
	for i in 2:
		_connect_button(status_cards[i].get_node("BuyBtn"), Callable(self, "_buy_status").bind(i))
		_setup_card_hover(status_cards[i])
	for i in 3:
		_connect_button(upg_cards[i].get_node("BuyBtn"), Callable(self, "_buy_upgrade").bind(i))
		_setup_card_hover(upg_cards[i])
	for i in 3:
		_connect_button(aliado_cards[i].get_node("BuyBtn"), Callable(self, "_buy_aliado").bind(i))
		_setup_card_hover(aliado_cards[i])


func _connect_button(btn_node: Node, target: Callable) -> void:
	var btn := btn_node as Button
	if btn == null:
		return
	for c in btn.pressed.get_connections():
		btn.pressed.disconnect(c["callable"])
	btn.pressed.connect(target)


# ---------- Hover animation ----------

const HOVER_SCALE: Vector2 = Vector2(1.04, 1.04)
const HOVER_TWEEN_DURATION: float = 0.12


func _setup_card_hover(card: Control) -> void:
	var btn := card.get_node_or_null("BuyBtn") as Button
	if btn == null:
		return
	# Pivot no centro pra escalar de dentro pra fora.
	var sz := Vector2(card.offset_right - card.offset_left, card.offset_bottom - card.offset_top)
	card.pivot_offset = sz * 0.5
	# Conexões só uma vez (evita duplicação se _connect_card_buttons rerodar).
	if not btn.mouse_entered.is_connected(_on_card_mouse_entered):
		btn.mouse_entered.connect(_on_card_mouse_entered.bind(card))
	if not btn.mouse_exited.is_connected(_on_card_mouse_exited):
		btn.mouse_exited.connect(_on_card_mouse_exited.bind(card))


func _on_card_mouse_entered(card: Control) -> void:
	if _placement_active:
		return
	var btn := card.get_node_or_null("BuyBtn") as Button
	var disabled: bool = btn != null and btn.disabled
	if not disabled:
		var tw := create_tween()
		tw.tween_property(card, "scale", HOVER_SCALE, HOVER_TWEEN_DURATION).set_trans(Tween.TRANS_SINE)
	# Tooltip mostra mesmo em cards desabilitados (max/locked) — útil pra ver todos os níveis.
	_show_card_tooltip(card)


func _on_card_mouse_exited(card: Control) -> void:
	var tw := create_tween()
	tw.tween_property(card, "scale", Vector2.ONE, HOVER_TWEEN_DURATION).set_trans(Tween.TRANS_SINE)
	if _augment_tooltip != null:
		_augment_tooltip.visible = false


# ---------- Compra (toggle) ----------

func _buy_status(idx: int) -> void:
	if _placement_active:
		return
	var slot: Dictionary = status_slots[idx]
	if not slot.get("available", false):
		return
	if _selected_status_idx == idx:
		_selected_status_idx = -1
		_refresh_button_states()
		return
	var player := _get_player()
	if player == null:
		return
	var price: int = int(slot["price"])
	# Swap permitido (devolve preço do status já selecionado).
	if player.gold < _selected_total_cost() - _status_price() + price:
		return
	_selected_status_idx = idx
	_play_buy_sound()
	_refresh_button_states()


func _buy_estrutura(idx: int) -> void:
	if _placement_active:
		return
	var slot: Dictionary = estrutura_slots[idx]
	if not slot.get("available", false):
		return
	if _selected_estrut_idx == idx:
		_selected_estrut_idx = -1
		_refresh_button_states()
		return
	var player := _get_player()
	if player == null:
		return
	var price: int = int(slot["price"])
	if player.gold < _selected_total_cost() - _estrut_price() + price:
		return
	_selected_estrut_idx = idx
	_play_buy_sound()
	_refresh_button_states()


func _buy_aliado(idx: int) -> void:
	if _placement_active:
		return
	var slot: Dictionary = aliado_slots[idx]
	if not slot.get("available", false):
		return
	if _selected_aliado_idx == idx:
		_selected_aliado_idx = -1
		_refresh_button_states()
		return
	var player := _get_player()
	if player == null:
		return
	var price: int = int(slot["price"])
	if player.gold < _selected_total_cost() - _aliado_price() + price:
		return
	_selected_aliado_idx = idx
	_play_buy_sound()
	_refresh_button_states()


func _buy_upgrade(idx: int) -> void:
	if _placement_active:
		return
	var slot: Dictionary = upg_slots[idx]
	if not slot.get("available", false):
		return
	if idx in _selected_upgrade_idxs:
		_selected_upgrade_idxs.erase(idx)
		_refresh_button_states()
		return
	if _selected_upgrade_idxs.size() >= max_upgrades_this_round:
		return
	if _is_elemental_blocked_by_selection(slot.get("id", "")):
		return
	if _roulette_conflicts_with_selection(slot.get("id", "")):
		return
	var player := _get_player()
	if player == null:
		return
	var price: int = int(slot["price"])
	if player.gold < _selected_total_cost() + price:
		return
	_selected_upgrade_idxs.append(idx)
	_play_buy_sound()
	_refresh_button_states()


func _is_elemental_blocked_by_selection(id: String) -> bool:
	# Cobre TODOS os grupos exclusivos (elementais, tipo de flecha, salva).
	# Bloqueia se OUTRO item do mesmo grupo já está selecionado nesta shop.
	var group: Array = _get_exclusive_group(id)
	if group.is_empty():
		return false
	for sel_idx in _selected_upgrade_idxs:
		var sel_id: String = upg_slots[sel_idx].get("id", "")
		if sel_id == id:
			continue
		if sel_id in group:
			return true
	return false


func _roulette_conflicts_with_selection(id: String) -> bool:
	# A Roleta troca o elemental atual — não faz sentido comprar junto com o upgrade
	# de um elemental no mesmo round. Também bloqueia junto com o Joker (cada um abre
	# seu próprio modal/efeito no commit — evita os dois de uma vez). Bidirecional.
	var selecting_roulette: bool = (id == ROULETTE_ID)
	var selecting_blocking_other: bool = (id in _ELEMENTAL_IDS) or (id == JOKER_ID)
	if not selecting_roulette and not selecting_blocking_other:
		return false
	for sel_idx in _selected_upgrade_idxs:
		var sel_id: String = upg_slots[sel_idx].get("id", "")
		if selecting_roulette and ((sel_id in _ELEMENTAL_IDS) or sel_id == JOKER_ID):
			return true
		if selecting_blocking_other and sel_id == ROULETTE_ID:
			return true
	return false


func _get_exclusive_group(id: String) -> Array:
	# Retorna o grupo inteiro (incluindo o próprio id) ao qual o upgrade pertence.
	# Vazio se não tem grupo (upgrades sem restrição).
	for group in EXCLUSIVE_PAIRS:
		if id in group:
			return group
	return []


func _player_has_exclusive_counterpart(player: Node, id: String) -> bool:
	if player == null or not player.has_method("get_upgrade_count"):
		return false
	var group: Array = _get_exclusive_group(id)
	if group.is_empty():
		return false
	for other_id in group:
		if other_id == id:
			continue
		if int(player.get_upgrade_count(other_id)) > 0:
			return true
	return false


# ---------- Selection accounting ----------

func _selected_upgrades_total_cost() -> int:
	var total: int = 0
	for i in _selected_upgrade_idxs:
		total += int(upg_slots[i].get("price", 0))
	return total


func _selected_total_cost() -> int:
	var total: int = _selected_upgrades_total_cost()
	if _selected_status_idx >= 0:
		total += int(status_slots[_selected_status_idx].get("price", 0))
	if _selected_estrut_idx >= 0:
		total += int(estrutura_slots[_selected_estrut_idx].get("price", 0))
	if _selected_aliado_idx >= 0:
		total += int(aliado_slots[_selected_aliado_idx].get("price", 0))
	return total


func _status_price() -> int:
	return int(status_slots[_selected_status_idx].get("price", 0)) if _selected_status_idx >= 0 else 0


func _estrut_price() -> int:
	return int(estrutura_slots[_selected_estrut_idx].get("price", 0)) if _selected_estrut_idx >= 0 else 0


func _aliado_price() -> int:
	return int(aliado_slots[_selected_aliado_idx].get("price", 0)) if _selected_aliado_idx >= 0 else 0


# ---------- Refresh ----------

func _refresh_button_states() -> void:
	var player := _get_player()
	var current_gold: int = player.gold if player != null else 0
	var pending_cost: int = _selected_total_cost()
	var available_gold: int = current_gold - pending_cost
	_refresh_global_reroll()
	_refresh_gold_label()
	# Status (single-select com swap).
	for i in 2:
		var slot: Dictionary = status_slots[i]
		var price: int = int(slot.get("price", 0))
		var is_selected: bool = _selected_status_idx == i
		var afford_swap: bool = current_gold >= pending_cost - _status_price() + price
		_apply_card_state(status_cards[i], slot, is_selected, afford_swap)
	# Estrutura (single-select com swap).
	for i in 2:
		var slot: Dictionary = estrutura_slots[i]
		var price: int = int(slot.get("price", 0))
		var is_selected: bool = _selected_estrut_idx == i
		var afford_swap: bool = current_gold >= pending_cost - _estrut_price() + price
		_apply_card_state(estrut_cards[i], slot, is_selected, afford_swap)
	# Aliado (single-select com swap).
	for i in 3:
		var slot: Dictionary = aliado_slots[i]
		var price: int = int(slot.get("price", 0))
		var is_selected: bool = _selected_aliado_idx == i
		var afford_swap: bool = current_gold >= pending_cost - _aliado_price() + price
		_apply_card_state(aliado_cards[i], slot, is_selected, afford_swap)
	# Upgrades (multi-select limitado).
	var limit_reached: bool = _selected_upgrade_idxs.size() >= max_upgrades_this_round
	for i in 3:
		var slot: Dictionary = upg_slots[i]
		var price: int = int(slot.get("price", 0))
		var is_selected: bool = i in _selected_upgrade_idxs
		var blocked: bool = _is_elemental_blocked_by_selection(slot.get("id", ""))
		var can_select: bool = not limit_reached and available_gold >= price and not blocked
		_apply_card_state(upg_cards[i], slot, is_selected, can_select or is_selected)


func _apply_card_state(card: Control, slot: Dictionary, is_selected: bool, can_buy: bool) -> void:
	var available: bool = slot.get("available", false)
	var bg: TextureRect = card.get_node_or_null("Bg") as TextureRect
	if bg != null:
		# Mantém o tint base configurado na .tscn (ex: laranja do upgrade card).
		# Selection agora é mostrado por um overlay roxo, não por tint.
		if not card.has_meta("base_tint"):
			card.set_meta("base_tint", bg.modulate)
		var base_tint: Color = card.get_meta("base_tint")
		bg.modulate = base_tint * Color(0.5, 0.5, 0.5, 0.7) if not available else base_tint
	# Box roxa por cima quando selecionado.
	_ensure_selection_overlay(card)
	var overlay: ColorRect = card.get_node_or_null("SelectionOverlay") as ColorRect
	if overlay != null:
		overlay.visible = is_selected
	var btn: Button = card.get_node_or_null("BuyBtn") as Button
	if btn != null:
		btn.disabled = not available or (not is_selected and not can_buy)


func _ensure_selection_overlay(card: Control) -> void:
	var existing: ColorRect = card.get_node_or_null("SelectionOverlay") as ColorRect
	if existing != null:
		return
	var overlay := ColorRect.new()
	overlay.name = "SelectionOverlay"
	overlay.color = SELECTION_OVERLAY_COLOR
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.visible = false
	card.add_child(overlay)
	# Fica logo após o Bg pra Labels e BuyBtn aparecerem por cima do overlay.
	var bg_node: Node = card.get_node_or_null("Bg")
	if bg_node != null:
		card.move_child(overlay, bg_node.get_index() + 1)


# ---------- Continue & placement queue ----------

func _on_continue_pressed() -> void:
	if _placement_active:
		_cancel_placement()
		return
	_play_next_wave_sound()
	_placement_queue.clear()
	if _selected_estrut_idx >= 0:
		var sel_e: Dictionary = estrutura_slots[_selected_estrut_idx]
		if sel_e.get("available", false) and "scene" in sel_e:
			_placement_queue.append({"type": "estrutura", "slot": sel_e})
	if _selected_aliado_idx >= 0:
		var sel_a: Dictionary = aliado_slots[_selected_aliado_idx]
		if sel_a.get("available", false):
			# Auto-spawn (Leno): pula placement, commitado em _commit_aliado_no_placement.
			if sel_a.get("auto_spawn", false):
				pass
			elif "scene" in sel_a:
				_placement_queue.append({"type": "aliado", "slot": sel_a})
	if _placement_queue.is_empty():
		_commit_status_only()
		_commit_aliado_no_placement()
		_commit_upgrades_and_close()
		return
	_process_next_placement()


func _process_next_placement() -> void:
	if _placement_queue.is_empty():
		if _free_tower_in_progress:
			# Fim do placement da torre grátis — devolve controle pro shop
			# normal sem comitar nada.
			_free_tower_in_progress = false
			return
		_commit_status_only()
		_commit_aliado_no_placement()
		_commit_upgrades_and_close()
		return
	_placement_current = _placement_queue.pop_front()
	_enter_placement_mode(_placement_current["slot"])


func _commit_status_only() -> void:
	var player := _get_player()
	if player == null:
		return
	if _selected_status_idx >= 0:
		var slot: Dictionary = status_slots[_selected_status_idx]
		if slot.get("available", false):
			if player.spend_gold(int(slot.get("price", 0))):
				# Capacete Veloz: COMPRAR Armadura antes da wave 4 marca metade do
				# unlock (a outra metade é matar o 1º boss na mesma run).
				if String(slot.get("id", "")) == "armor" and _current_wave_number() < 4 and "stats_armor_before_w4" in player:
					player.stats_armor_before_w4 = true
				if player.has_method("apply_upgrade"):
					player.apply_upgrade(slot["id"])
		_selected_status_idx = -1


func _commit_aliado_no_placement() -> void:
	# Aliados com flag `auto_spawn` (Leno + Claudio Druida hoje) não passam por
	# placement — `apply_upgrade` no player faz o spawn automaticamente.
	# Aliados com "scene" usam placement (não há mais nenhum hoje).
	var player := _get_player()
	if player == null:
		return
	if _selected_aliado_idx < 0:
		return
	var slot: Dictionary = aliado_slots[_selected_aliado_idx]
	if not slot.get("auto_spawn", false):
		return
	if not slot.get("available", false):
		return
	if player.spend_gold(int(slot.get("price", 0))):
		if player.has_method("apply_upgrade"):
			player.apply_upgrade(slot["id"])
	_selected_aliado_idx = -1


func _commit_upgrades_and_close() -> void:
	var player := _get_player()
	var joker_bought: bool = false
	var roulette_new_id: String = ""
	# Nível do Fogo antes da compra — pra detectar a transição pra L2 e disparar
	# o modal de escolha de rastro (player primeiro vs flecha primeiro).
	var fire_before: int = player.get_upgrade_count("fire_arrow") if player != null else 0
	if player != null:
		for idx in _selected_upgrade_idxs:
			var slot: Dictionary = upg_slots[idx]
			if bool(slot.get("is_joker", false)):
				# Joker: paga gold + marca usada, mas APLICAÇÃO é adiada pro modal
				# de seleção. Se spend_gold falhar (não deveria — _buy_upgrade já
				# garantiu), skip.
				if player.spend_gold(int(slot.get("price", 0))):
					if "joker_used" in player:
						player.joker_used = true
					if "joker_uses_this_run" in player:
						player.joker_uses_this_run += 1
					if "stats_joker_used" in player:
						player.stats_joker_used += 1  # progresso do unlock do Chamado do Palhaço
					joker_bought = true
				continue
			if bool(slot.get("is_roulette", false)):
				# Roleta Elemental: paga + troca o elemental atual por outro no L4.
				# O L4 sorteado é revelado no modal pós-compra.
				if player.spend_gold(int(slot.get("price", 0))):
					if "stats_roulette_buys" in player:
						player.stats_roulette_buys += 1
					if player.has_method("swap_current_elemental_for_random_l4"):
						roulette_new_id = String(player.swap_current_elemental_for_random_l4())
				continue
			if not player.spend_gold(int(slot.get("price", 0))):
				continue
			if player.has_method("apply_upgrade"):
				player.apply_upgrade(slot["id"])
	# Escolha de rastro do Fogo: pendente quando a compra levou o Fogo a exatamente
	# L2. Mostrada como ÚLTIMO modal (depois de Joker/Roleta, se houver), via
	# _maybe_finish_or_fire_choice nos fechamentos.
	var fire_after: int = player.get_upgrade_count("fire_arrow") if player != null else 0
	_pending_fire_choice = fire_before < 2 and fire_after == 2
	if roulette_new_id != "":
		_open_roulette_reveal(roulette_new_id)
		return
	if joker_bought:
		_open_joker_modal()
		return
	_maybe_finish_or_fire_choice()


# ---------- Placement mode ----------

func _enter_placement_mode(slot: Dictionary) -> void:
	var scene: PackedScene = load(slot["scene"])
	if scene == null:
		return
	var world := get_tree().get_first_node_in_group("world")
	if world == null:
		return
	var positions: Array[Vector2] = _generate_random_positions(PLACEMENT_SPOT_COUNT)
	_placement_ghosts.clear()
	for pos in positions:
		var ghost: Node2D = scene.instantiate()
		world.add_child(ghost)
		ghost.global_position = pos
		ghost.modulate = Color(1, 1, 1, 0.5)
		ghost.process_mode = Node.PROCESS_MODE_DISABLED
		_placement_ghosts.append(ghost)
	_placement_active = true
	bg_rect.visible = false
	root_panel.visible = false
	placement_hint.visible = true
	_set_camera_overview(true)


func _confirm_placement_at(chosen: Node2D) -> void:
	var slot: Dictionary = _placement_current["slot"]
	var player := _get_player()
	if player == null:
		_cancel_placement()
		return
	# Free tower (grant da wave 8) não debita gold.
	var is_free: bool = bool(slot.get("free", false))
	if not is_free and not player.spend_gold(int(slot["price"])):
		_cancel_placement()
		return
	for g in _placement_ghosts:
		if not is_instance_valid(g):
			continue
		if g == chosen:
			g.modulate = Color(1, 1, 1, 1)
			g.process_mode = Node.PROCESS_MODE_INHERIT
		else:
			g.queue_free()
	_placement_ghosts.clear()
	if slot.get("id", "") == "claudio_druida" and player.has_method("apply_upgrade"):
		player.apply_upgrade("claudio_druida")
		var wm0 := get_tree().get_first_node_in_group("wave_manager")
		if wm0 != null and wm0.has_method("_apply_claudio_druida_scaling_if_applicable"):
			wm0._apply_claudio_druida_scaling_if_applicable(chosen, slot["scene"])
			if "max_hp" in chosen and "hp" in chosen:
				chosen.hp = chosen.max_hp
				if chosen.has_node("HpBar"):
					chosen.get_node("HpBar").set_ratio(1.0)
	var wm := get_tree().get_first_node_in_group("wave_manager")
	if wm != null and wm.has_method("register_structure"):
		wm.register_structure(slot["scene"], chosen.global_position, chosen)
	if _placement_current.get("type", "") == "estrutura":
		_selected_estrut_idx = -1
	elif _placement_current.get("type", "") == "aliado":
		_selected_aliado_idx = -1
	_placement_current = {}
	_exit_placement_mode()
	_process_next_placement()


func _cancel_placement() -> void:
	for g in _placement_ghosts:
		if is_instance_valid(g):
			g.queue_free()
	_placement_ghosts.clear()
	_placement_queue.clear()
	_placement_current = {}
	# Se o player cancelou durante a free tower, libera a flag pra não bloquear
	# fluxos futuros — a torre grátis é perdida (já foi marcada como entregue
	# no wave_manager).
	_free_tower_in_progress = false
	_exit_placement_mode()
	_refresh_button_states()


func _exit_placement_mode() -> void:
	_placement_active = false
	bg_rect.visible = true
	root_panel.visible = true
	placement_hint.visible = false
	_set_camera_overview(false)


func _set_camera_overview(active: bool) -> void:
	var camera := get_viewport().get_camera_2d()
	if camera != null and camera.has_method("set_overview_mode"):
		camera.set_overview_mode(active)


# ---------- Tier visuals ----------

func _level_tint_for_label(level: int) -> Color:
	match level:
		1: return Color(1.0, 1.0, 1.0, 1.0)
		2: return Color(0.55, 0.85, 1.0, 1.0)
		3: return Color(0.95, 0.6, 1.0, 1.0)
		_: return Color(1.0, 0.85, 0.3, 1.0)


# ---------- Gold label ----------

func _refresh_gold_label() -> void:
	var player := _get_player()
	var g: int = player.gold if player != null else 0
	var available: int = g - _selected_total_cost()
	gold_label.text = tr("SHOP_GOLD_LABEL") % available


func _build_petal_label() -> void:
	# Display de pétalas no shop, à DIREITA do header "ESTRUTURAS" — essa seção
	# vira a loja de pétalas no P2. Só informativo no P1 (sem gasto ainda).
	if gold_label == null:
		return
	var parent := gold_label.get_parent()
	if parent == null or parent.has_node("PetalLabel"):
		return
	# Base = à direita do texto do header de Estruturas (fallback fixo).
	var hx: float = 360.0
	var hy: float = 460.0
	var header := parent.get_node_or_null("EstrutHeader") as Control
	if header != null:
		hx = header.offset_left + 290.0
		hy = header.offset_top
	var icon := Sprite2D.new()
	icon.name = "PetalShopIcon"
	icon.texture = load("res://assets/Hud/petals.png") as Texture2D
	icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	icon.scale = Vector2(1.8, 1.8)
	icon.position = Vector2(hx, hy + 22.0)
	parent.add_child(icon)
	var lbl := Label.new()
	lbl.name = "PetalLabel"
	lbl.offset_left = hx + 24.0
	lbl.offset_top = hy - 2.0
	lbl.offset_right = hx + 170.0
	lbl.offset_bottom = hy + 42.0
	lbl.add_theme_color_override("font_color", Color(1.0, 0.62, 0.82, 1.0))
	lbl.add_theme_font_size_override("font_size", 39)
	var gf := gold_label.get_theme_font("font")
	if gf != null:
		lbl.add_theme_font_override("font", gf)
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	var pl := _get_player()
	lbl.text = str(pl.petals) if pl != null and "petals" in pl else "0"
	parent.add_child(lbl)
func _get_player() -> Node:
	return get_tree().get_first_node_in_group("player")


func _waves_until_unlock(interval: int) -> int:
	# Retorna 0 se a categoria está desbloqueada NESTE shop, senão o número de
	# turnos restantes até o próximo unlock.
	var wm := get_tree().get_first_node_in_group("wave_manager")
	if wm == null or not "wave_number" in wm:
		return interval
	var w: int = int(wm.wave_number)
	if w <= 0:
		return interval
	if w % interval == 0:
		return 0
	return interval - (w % interval)


func _current_wave_number() -> int:
	var wm := get_tree().get_first_node_in_group("wave_manager")
	if wm == null or not "wave_number" in wm:
		return 0
	return int(wm.wave_number)


func _aliado_lock_remaining(w: int) -> int:
	# Wave 5 abre pra venda; depois a cada ALIADO_SHOP_INTERVAL waves (5, 7, 9...).
	# Wave 3 é tratada à parte (pet grátis em _ready), aqui retornamos 2 turnos
	# (pra apontar pra wave 5) caso o caller chame com w==3.
	if w >= ALIADO_SHOP_FIRST_WAVE:
		var off: int = (w - ALIADO_SHOP_FIRST_WAVE) % ALIADO_SHOP_INTERVAL
		if off == 0:
			return 0
		return ALIADO_SHOP_INTERVAL - off
	return ALIADO_SHOP_FIRST_WAVE - w


func _build_lock_title(turns_left: int) -> String:
	# Versão curta pra paisagem cards (status/estrutura — sem DescLabel).
	var key: String = "SHOP_LOCK_TITLE_SINGULAR" if turns_left == 1 else "SHOP_LOCK_TITLE_PLURAL"
	return tr(key) % turns_left


func _build_lock_desc(turns_left: int) -> String:
	# Versão pro DescLabel dos retrato cards (aliado).
	var key: String = "SHOP_LOCK_TITLE_SINGULAR" if turns_left == 1 else "SHOP_LOCK_TITLE_PLURAL"
	return tr(key) % turns_left


func _total_structures_bought() -> int:
	var wm := get_tree().get_first_node_in_group("wave_manager")
	if wm == null or not "owned_structures" in wm:
		return 0
	return (wm.owned_structures as Array).size()


func _play_buy_sound() -> void:
	if BUY_SOUND == null:
		return
	var p := AudioStreamPlayer.new()
	p.bus = &"SFX"
	p.stream = BUY_SOUND
	p.volume_db = -16.0
	add_child(p)
	p.play()
	p.finished.connect(p.queue_free)


func _play_next_wave_sound() -> void:
	# Som tocado quando o player confirma "Próxima Wave" e o shop fecha pra
	# próxima horda. Pula os 0.2s iniciais (silêncio do mp3) usando play(from).
	# Reparenteia pra raiz da scene pra continuar tocando mesmo após o
	# WaveShop ser queue_free'd.
	if NEXT_WAVE_SOUND == null:
		return
	var p := AudioStreamPlayer.new()
	p.bus = &"SFX"
	p.stream = NEXT_WAVE_SOUND
	p.volume_db = -10.0
	get_tree().current_scene.add_child(p)
	p.play(0.2)
	p.finished.connect(p.queue_free)


# ---------- Bonus +1 upgrade label ----------

func _setup_bonus_label() -> void:
	if max_upgrades_this_round <= 1:
		return
	var upg_header: Label = $Root/UpgHeader
	if upg_header == null:
		return
	var bonus := Label.new()
	bonus.name = "BonusUpgradeLabel"
	bonus.text = "SHOP_BONUS_PLUS_ONE"
	var at01_font: Font = load("res://font/Silver.ttf")
	if at01_font != null:
		bonus.add_theme_font_override("font", at01_font)
	bonus.add_theme_font_size_override("font_size", 25)
	bonus.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3, 1.0))
	bonus.position = Vector2(720, 4)
	bonus.size = Vector2(200, 40)
	upg_header.add_child(bonus)
	var tw := bonus.create_tween().set_loops()
	tw.tween_property(bonus, "modulate:a", 0.55, 0.6)
	tw.tween_property(bonus, "modulate:a", 1.0, 0.6)


# ---------- Global Reroll ----------
# 1 botão único faz reroll de TUDO (status, estrutura, aliado, upgrade) ao
# mesmo tempo. Mais simples e mais limpo visualmente.

func _next_global_reroll_cost() -> int:
	if _global_rerolls_used == 0 and _lucky_first_roll_free:
		return 0
	var idx: int = clampi(_global_rerolls_used, 0, GLOBAL_REROLL_COSTS.size() - 1)
	return GLOBAL_REROLL_COSTS[idx]


func _on_global_reroll() -> void:
	if _global_rerolls_used >= MAX_GLOBAL_REROLLS:
		return
	var cost: int = _next_global_reroll_cost()
	var player := _get_player()
	if player == null:
		return
	if cost > 0 and not player.spend_gold(cost):
		return
	_global_rerolls_used += 1
	# Telemetria: registra reroll com wave atual + custo + qual uso é esse.
	if has_node("/root/Telemetry"):
		var wm := get_tree().get_first_node_in_group("wave_manager")
		var wave_num: int = int(wm.wave_number) if wm != null and "wave_number" in wm else 0
		get_node("/root/Telemetry").track("shop_reroll", {
			"wave": wave_num,
			"cost": cost,
			"reroll_index": _global_rerolls_used,
		})
	# Limpa todas as seleções pendentes (vão sair do roll).
	_selected_status_idx = -1
	_selected_estrut_idx = -1
	_selected_aliado_idx = -1
	_selected_upgrade_idxs.clear()
	_play_buy_sound()
	_roll_all_slots()
	_build_all_cards()
	_refresh_button_states()


func _refresh_global_reroll() -> void:
	if global_reroll_btn == null:
		return
	var maxed: bool = _global_rerolls_used >= MAX_GLOBAL_REROLLS
	var cost: int = _next_global_reroll_cost()
	var player := _get_player()
	var current_gold: int = player.gold if player != null else 0
	var available_gold: int = current_gold - _selected_total_cost()
	var disabled: bool = maxed or available_gold < cost
	global_reroll_btn.disabled = disabled
	global_reroll_btn.modulate = Color(0.55, 0.55, 0.55, 0.65) if disabled else Color.WHITE
	if global_reroll_cost != null:
		global_reroll_cost.text = "—" if maxed else "%d" % cost
		global_reroll_cost.modulate = Color(0.55, 0.55, 0.55, 0.65) if disabled else Color.WHITE


# ---------- Augments column (right side) ----------
# Mostra os upgrades já comprados como slots. Hover de cada slot abre tooltip
# com efeito do nível atual + efeito do próximo nível (ou MAX se já capped).
# Reusa o icon atlas do HUD pra não duplicar arte/path mapping.

func _refresh_augments_column() -> void:
	if augments_box == null:
		return
	for c in augments_box.get_children():
		c.queue_free()
	var p := _get_player()
	if p == null or not p.has_method("get_upgrade_count"):
		return
	var hud := get_tree().get_first_node_in_group("hud")
	if hud == null:
		return
	# Itera na ordem de display do HUD; pega só os comprados, cap em MAX_SLOTS.
	# Status vão pro StatsCard. Allies (pets) vão pro PetsBox abaixo. Aqui só
	# entram upgrades de gameplay (perfuração, fire arrow, dash, etc).
	var ids: Array = hud.UPGRADE_DISPLAY_ORDER
	var owned: Array = []
	for id_v in ids:
		var id: String = String(id_v)
		if _is_status_id(id) or id in _PETS_ROW_IDS:
			continue
		var lvl: int = int(p.get_upgrade_count(id))
		if lvl <= 0:
			continue
		owned.append({"id": id, "lvl": lvl})
	# Cabe tudo: mostra todos. Estoura: mostra (MAX-1) chips + botao +N (ver todos).
	if owned.size() <= _AUGMENT_MAX_SLOTS:
		for o in owned:
			augments_box.add_child(_build_augment_chip(String(o["id"]), int(o["lvl"]), hud))
	else:
		var shown: int = _AUGMENT_MAX_SLOTS - 1
		for i in shown:
			augments_box.add_child(_build_augment_chip(String(owned[i]["id"]), int(owned[i]["lvl"]), hud))
		augments_box.add_child(_build_see_all_chip(owned.size() - shown, owned, hud))


# IDs de "status" (HP/armor/damage/attack_speed/move_speed) — escala infinita,
# vão pro StatsCard, não pro grid de upgrades.
func _is_status_id(id: String) -> bool:
	return id == "hp" or id == "armor" or id == "damage" or id == "attack_speed" or id == "move_speed"


# Renderiza o StatsCard (canto inferior direito): 5 stat lines com label +
# ganho do stat sobre o base + level. Stats não comprados em cinza, comprados
# em amarelo.
func _refresh_stats_card() -> void:
	if stats_box == null:
		return
	for c in stats_box.get_children():
		c.queue_free()
	var p := _get_player()
	for row in _STATS_CARD_ROWS:
		var id: String = String(row["id"])
		var lbl_key: String = String(row["label"])
		var lvl: int = 0
		if p != null and p.has_method("get_upgrade_count"):
			lvl = int(p.get_upgrade_count(id))
		var gain_text: String = _get_stat_gain_text(id, lvl, p)
		stats_box.add_child(_build_stat_line(lbl_key, lvl, gain_text))


# Calcula o ganho do stat sobre o base atual do player. HP/dmg/move/atk-speed
# mostram "+X%" relativo ao base 1.0 (ou 100 pra HP). Armor mostra absoluto
# (% de damage reduction direto). Sem upgrades: string vazia.
func _get_stat_gain_text(id: String, lvl: int, p: Node) -> String:
	if lvl <= 0 or p == null:
		return ""
	match id:
		"hp":
			# Base = 100 max_hp. Ganho = (max_hp - 100) / 100.
			var max_hp: float = float(p.get("max_hp")) if "max_hp" in p else 100.0
			return "+%d%%" % int(round(max(0.0, max_hp - 100.0)))
		"damage":
			# arrow_damage_multiplier base 1.0, +0.24 por stack.
			var m: float = float(p.get("arrow_damage_multiplier")) if "arrow_damage_multiplier" in p else 1.0
			return "+%d%%" % int(round((m - 1.0) * 100.0))
		"move_speed":
			# move_speed_multiplier base 1.0, +0.10 por stack.
			var m2: float = float(p.get("move_speed_multiplier")) if "move_speed_multiplier" in p else 1.0
			return "+%d%%" % int(round((m2 - 1.0) * 100.0))
		"attack_speed":
			# attack_speed_multiplier base 1.0, +0.24 por stack.
			var m3: float = float(p.get("attack_speed_multiplier")) if "attack_speed_multiplier" in p else 1.0
			return "+%d%%" % int(round((m3 - 1.0) * 100.0))
		"armor":
			# Mostra dano reduzido / lentidão reduzida (slow res = metade do dr).
			var dr: float = float(p.get("damage_reduction_pct")) if "damage_reduction_pct" in p else 0.0
			var sr: float = float(p.get("slow_resistance_pct")) if "slow_resistance_pct" in p else dr * 0.5
			return "%d%% / %d%%" % [int(round(dr * 100.0)), int(round(sr * 100.0))]
	return ""


# Pets (aliados): MAX_DISTINCT_PETS slots fixos (= 2). Mostra os pets
# COMPRADOS (lvl > 0) na ordem canônica de _PETS_ROW_IDS, completando com
# slots vazios até preencher MAX_DISTINCT_PETS. Adicionar novos tipos de
# pet em _PETS_ROW_IDS não aumenta a quantidade de slots — o cap continua.
func _refresh_pets_box() -> void:
	if pets_box == null:
		return
	for c in pets_box.get_children():
		c.queue_free()
	var p := _get_player()
	var hud := get_tree().get_first_node_in_group("hud")
	if hud == null:
		return
	# Coleta os tipos comprados na ordem canônica.
	var owned: Array[Dictionary] = []
	if p != null and p.has_method("get_upgrade_count"):
		for id in _PETS_ROW_IDS:
			var lvl: int = int(p.get_upgrade_count(id))
			if lvl > 0:
				owned.append({"id": id, "lvl": lvl})
	# Renderiza até MAX_DISTINCT_PETS slots: comprados primeiro, depois padding
	# vazio.
	for i in PETS_DISPLAY_SLOTS:
		if i < owned.size():
			var entry: Dictionary = owned[i]
			pets_box.add_child(_build_mini_owned_chip(String(entry["id"]), int(entry["lvl"]), hud, true))
		else:
			pets_box.add_child(_build_mini_owned_chip("", 0, hud, false))


# Mini chip versão menor do augment chip (60x60). Usado pra Pets/Structures.
# Slot vazio (lvl=0): bg cinza com "—". Slot cheio: icon + ★N badge + hover
# tooltip (reusa o augment tooltip). Se `sellable=true` (pets), right-click
# refunda metade do total pago e zera o pet.
func _build_mini_owned_chip(id: String, lvl: int, hud: Node, sellable: bool = false) -> Control:
	var chip := Control.new()
	chip.custom_minimum_size = _MINI_CHIP_SIZE
	chip.mouse_filter = Control.MOUSE_FILTER_STOP
	var bg := ColorRect.new()
	bg.color = Color(0.10, 0.07, 0.13, 0.85) if lvl > 0 else Color(0.06, 0.05, 0.08, 0.6)
	bg.anchor_right = 1.0
	bg.anchor_bottom = 1.0
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chip.add_child(bg)
	if lvl > 0:
		var icon := TextureRect.new()
		icon.texture = hud._get_upgrade_icon_atlas(id, lvl)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		icon.anchor_right = 1.0
		icon.anchor_bottom = 1.0
		icon.offset_left = 2.0
		icon.offset_top = 2.0
		icon.offset_right = -2.0
		icon.offset_bottom = -2.0
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		chip.add_child(icon)
		var badge := Label.new()
		var max_lvl: int = _max_level_for(id)
		var is_max: bool = max_lvl > 0 and lvl >= max_lvl
		badge.text = "MAX" if is_max else "%d" % lvl
		badge.add_theme_font_size_override("font_size", 15)
		badge.add_theme_color_override("font_color", Color(1.0, 0.84, 0.34, 1.0))
		badge.add_theme_color_override("font_outline_color", Color.BLACK)
		badge.add_theme_constant_override("outline_size", 3)
		badge.anchor_left = 1.0
		badge.anchor_top = 1.0
		badge.anchor_right = 1.0
		badge.anchor_bottom = 1.0
		badge.offset_left = -32.0
		badge.offset_top = -16.0
		badge.offset_right = -2.0
		badge.offset_bottom = -1.0
		badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		badge.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
		badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
		chip.add_child(badge)
		# Hover: tooltip do augment (mesma fonte).
		chip.mouse_entered.connect(_on_augment_hovered.bind(id, lvl, chip))
		chip.mouse_exited.connect(_on_augment_unhovered)
		# Right-click pra vender (só pets). Refunda metade do total pago.
		if sellable:
			chip.gui_input.connect(_on_pet_chip_input.bind(id))
	else:
		# Slot vazio: traço cinza no centro.
		var dash := Label.new()
		dash.text = "—"
		dash.add_theme_font_size_override("font_size", 28)
		dash.add_theme_color_override("font_color", Color(0.35, 0.30, 0.42, 1.0))
		dash.anchor_right = 1.0
		dash.anchor_bottom = 1.0
		dash.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		dash.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		dash.mouse_filter = Control.MOUSE_FILTER_IGNORE
		chip.add_child(dash)
	return chip


func _build_stat_line(label_key: String, lvl: int, gain_text: String) -> Control:
	var row := HBoxContainer.new()
	row.custom_minimum_size = Vector2(0, 24)
	var has_lvl: bool = lvl > 0
	var label_color: Color = Color(0.85, 0.82, 0.95, 1.0) if has_lvl else Color(0.5, 0.45, 0.6, 1.0)
	var accent_color: Color = Color(1.0, 0.84, 0.34, 1.0) if has_lvl else Color(0.45, 0.4, 0.55, 1.0)
	var label := Label.new()
	label.text = label_key
	label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_INHERIT
	label.add_theme_font_override("font", load("res://font/Silver.ttf"))
	label.add_theme_font_size_override("font_size", 25)
	label.add_theme_color_override("font_color", label_color)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)
	# Coluna do meio: ganho percentual sobre o base. Vazia se sem upgrades.
	var gain := Label.new()
	gain.text = gain_text
	gain.custom_minimum_size = Vector2(110, 0)
	gain.add_theme_font_override("font", load("res://font/Silver.ttf"))
	gain.add_theme_font_size_override("font_size", 25)
	gain.add_theme_color_override("font_color", Color(0.62, 0.95, 0.62, 1.0) if has_lvl else label_color)
	gain.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(gain)
	# Coluna direita: nível ★ N (ou —).
	var value := Label.new()
	value.text = ("★ %d" % lvl) if has_lvl else "—"
	value.custom_minimum_size = Vector2(70, 0)
	value.add_theme_font_override("font", load("res://font/Silver.ttf"))
	value.add_theme_font_size_override("font_size", 25)
	value.add_theme_color_override("font_color", accent_color)
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(value)
	return row


func _build_see_all_chip(extra: int, owned: Array, hud: Node) -> Control:
	var chip := Button.new()
	chip.custom_minimum_size = _AUGMENT_SLOT_SIZE
	chip.focus_mode = Control.FOCUS_NONE
	chip.text = "+%d" % extra
	chip.add_theme_font_override("font", load("res://font/Silver.ttf"))
	chip.add_theme_font_size_override("font_size", 28)
	chip.add_theme_color_override("font_color", Color(1.0, 0.84, 0.34, 1.0))
	chip.add_theme_color_override("font_hover_color", Color(1.0, 0.92, 0.6, 1.0))
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.16, 0.10, 0.20, 0.95)
	sb.border_color = Color(0.65, 0.45, 0.85, 1.0)
	sb.border_width_left = 2
	sb.border_width_top = 2
	sb.border_width_right = 2
	sb.border_width_bottom = 2
	chip.add_theme_stylebox_override("normal", sb)
	chip.add_theme_stylebox_override("hover", sb)
	chip.add_theme_stylebox_override("pressed", sb)
	chip.tooltip_text = tr("SHOP_SEE_ALL_UPGRADES")
	chip.pressed.connect(_show_all_augments_dialog.bind(owned, hud))
	return chip


func _ensure_all_augments_dialog() -> void:
	if _all_augments_dialog != null:
		return
	var dlg := Panel.new()
	dlg.name = "AllAugmentsDialog"
	dlg.visible = false
	dlg.z_index = 200
	dlg.anchor_right = 1.0
	dlg.anchor_bottom = 1.0
	dlg.mouse_filter = Control.MOUSE_FILTER_STOP
	var bstyle := StyleBoxFlat.new()
	bstyle.bg_color = Color(0.0, 0.0, 0.0, 0.55)
	dlg.add_theme_stylebox_override("panel", bstyle)
	dlg.gui_input.connect(_on_all_augments_backdrop_input)
	root_panel.add_child(dlg)
	var center := CenterContainer.new()
	center.name = "Center"
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dlg.add_child(center)
	var card := PanelContainer.new()
	card.name = "Card"
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	var cs := StyleBoxFlat.new()
	cs.bg_color = Color(0.10, 0.07, 0.14, 1.0)
	cs.border_color = Color(0.55, 0.40, 0.70, 1.0)
	cs.border_width_left = 3
	cs.border_width_top = 3
	cs.border_width_right = 3
	cs.border_width_bottom = 3
	cs.corner_radius_top_left = 6
	cs.corner_radius_top_right = 6
	cs.corner_radius_bottom_left = 6
	cs.corner_radius_bottom_right = 6
	cs.content_margin_left = 24
	cs.content_margin_right = 24
	cs.content_margin_top = 20
	cs.content_margin_bottom = 20
	card.add_theme_stylebox_override("panel", cs)
	center.add_child(card)
	var vbox := VBoxContainer.new()
	vbox.name = "VBox"
	vbox.add_theme_constant_override("separation", 16)
	card.add_child(vbox)
	var title := Label.new()
	title.name = "Title"
	title.text = "SHOP_OWNED_UPGRADES_TITLE"
	title.add_theme_font_override("font", load("res://font/Silver.ttf"))
	title.add_theme_font_size_override("font_size", 38)
	title.add_theme_color_override("font_color", Color(0.95, 0.85, 1.0, 1.0))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)
	var grid := GridContainer.new()
	grid.name = "Grid"
	grid.columns = 8
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	vbox.add_child(grid)
	_all_augments_dialog = dlg


func _show_all_augments_dialog(owned: Array, hud: Node) -> void:
	_ensure_all_augments_dialog()
	var grid: GridContainer = _all_augments_dialog.get_node("Center/Card/VBox/Grid") as GridContainer
	if grid == null:
		return
	for c in grid.get_children():
		c.queue_free()
	for o in owned:
		grid.add_child(_build_augment_chip(String(o["id"]), int(o["lvl"]), hud))
	_all_augments_dialog.visible = true


func _on_all_augments_backdrop_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if _all_augments_dialog != null:
			_all_augments_dialog.visible = false


func _build_augment_chip(id: String, lvl: int, hud: Node) -> Control:
	var chip := Control.new()
	chip.custom_minimum_size = _AUGMENT_SLOT_SIZE
	chip.mouse_filter = Control.MOUSE_FILTER_STOP
	# Bg sutil pro slot — frame escuro com border roxo.
	var bg := ColorRect.new()
	bg.color = Color(0.10, 0.07, 0.13, 0.85)
	bg.anchor_right = 1.0
	bg.anchor_bottom = 1.0
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chip.add_child(bg)
	var icon := TextureRect.new()
	icon.texture = hud._get_upgrade_icon_atlas(id, lvl)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	icon.anchor_right = 1.0
	icon.anchor_bottom = 1.0
	icon.offset_left = 2.0
	icon.offset_top = 2.0
	icon.offset_right = -2.0
	icon.offset_bottom = -2.0
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chip.add_child(icon)
	# Badge ★ N (ou MAX) no canto inferior direito — chip pequeno, badge compacto.
	var badge := Label.new()
	var max_lvl: int = _max_level_for(id)
	var is_max: bool = max_lvl > 0 and lvl >= max_lvl
	badge.text = "MAX" if is_max else "%d" % lvl
	badge.add_theme_font_size_override("font_size", 15)
	badge.add_theme_color_override("font_color", Color(1.0, 0.84, 0.34, 1.0))
	badge.add_theme_color_override("font_outline_color", Color.BLACK)
	badge.add_theme_constant_override("outline_size", 3)
	badge.anchor_left = 1.0
	badge.anchor_top = 1.0
	badge.anchor_right = 1.0
	badge.anchor_bottom = 1.0
	badge.offset_left = -32.0
	badge.offset_top = -16.0
	badge.offset_right = -2.0
	badge.offset_bottom = -1.0
	badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	badge.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chip.add_child(badge)
	# Hover: tooltip com efeito atual + próximo nível.
	chip.mouse_entered.connect(_on_augment_hovered.bind(id, lvl, chip))
	chip.mouse_exited.connect(_on_augment_unhovered)
	return chip


func _on_augment_hovered(id: String, lvl: int, chip: Control) -> void:
	_ensure_augment_tooltip()
	var title: String = tr(_augment_title_for(id))
	var max_lvl: int = _max_level_for(id)
	var is_max: bool = max_lvl > 0 and lvl >= max_lvl
	# Header: título + nível atual (★ N ou ★ MAX).
	var header: String = "[b]%s[/b]  [color=#ffd757]★ %s[/color]" % [
		title, "MAX" if is_max else str(lvl)
	]
	# Linha de categoria pros upgrades de par exclusivo.
	var cat_line: String = ""
	if UPGRADE_CATEGORIES.has(id):
		cat_line = "[color=#a890c8][i]%s[/i][/color]\n" % tr(UPGRADE_CATEGORIES[id])
	# Lista TODOS os níveis. Marca o atual em amarelo, futuros em verde claro,
	# já passados em cinza apagado.
	var descs: Array = _get_upgrade_descs_array(id)
	var lines: Array[String] = []
	for i in descs.size():
		var n: int = i + 1
		var desc_text: String = tr(descs[i])
		if n == lvl:
			lines.append("[color=#ffd757]LV %d ▸ %s[/color]" % [n, desc_text])
		elif n < lvl:
			lines.append("[color=#6a5870]LV %d · %s[/color]" % [n, desc_text])
		else:
			lines.append("[color=#bfd4e8]LV %d · %s[/color]" % [n, desc_text])
	var body: String = header + "\n" + cat_line + "\n" + "\n".join(lines)
	_augment_tooltip_label.text = body
	_augment_tooltip.visible = true
	# Posiciona à esquerda do chip (a coluna fica colada na borda direita).
	var chip_global: Vector2 = chip.get_global_rect().position
	var tip_size: Vector2 = await _await_tooltip_size()
	_apply_tooltip_pos(Vector2(chip_global.x - tip_size.x - 16.0, chip_global.y), tip_size)


func _on_augment_unhovered() -> void:
	if _augment_tooltip != null:
		_augment_tooltip.visible = false


# Tooltip pros cards de COMPRA. Reusa o mesmo painel do tooltip de augment.
# Highlight no nível-alvo (verde, ▸); níveis já comprados em cinza (passados);
# níveis acima do alvo em azul claro (futuros).
func _show_card_tooltip(card: Control) -> void:
	var card_id: String = String(card.get_meta("aug_id", ""))
	# Cards placeholder/locked/free não têm desc multi-nível — tooltip pulado.
	if card_id == "" or card_id == "none" or card_id == "soon" or card_id == "locked" or card_id == "free_pet":
		return
	# Joker: tooltip dedicado (a carta não tem descs por nível — é one-shot).
	if card_id == JOKER_ID:
		_show_joker_tooltip(card)
		return
	# Roleta Elemental: idem joker — carta sem texto, explicação só no tooltip.
	if card_id == ROULETTE_ID:
		_show_roulette_tooltip(card)
		return
	var descs: Array = _get_upgrade_descs_array(card_id)
	if descs.is_empty():
		return  # Estrutura/Tower sem array de descs — tooltip não aplicável.
	var target_level: int = int(card.get_meta("aug_target_level", 1))
	var p := _get_player()
	var current_lvl: int = 0
	if p != null and p.has_method("get_upgrade_count"):
		current_lvl = int(p.get_upgrade_count(card_id))
	_ensure_augment_tooltip()
	# Header: título + indicador de nível-alvo.
	var title: String = tr(_augment_title_for(card_id))
	var max_lvl: int = descs.size()
	var is_max: bool = target_level > max_lvl
	var header: String = ""
	if is_max:
		header = "[b]%s[/b]  [color=#ffd757]★ MAX[/color]" % title
	else:
		header = "[b]%s[/b]  [color=#9fffa9]→ ★ %d[/color]" % [title, target_level]
	# Categoria (Elemental / Tipo de flecha) quando aplica.
	var cat_line: String = ""
	if UPGRADE_CATEGORIES.has(card_id):
		# Hover explica que só dá pra escolher 1 upgrade da mesma categoria por run.
		var hint: String = tr("SHOP_UPG_CAT_HINT") % tr(UPGRADE_CATEGORIES[card_id])
		cat_line = "[color=#a890c8][i]%s[/i][/color]\n" % hint
	# Lista todos os níveis: passado (já comprado) cinza, alvo verde, futuros azul.
	var lines: Array[String] = []
	for i in descs.size():
		var n: int = i + 1
		var dt: String = tr(descs[i])
		if n == target_level:
			lines.append("[color=#9fffa9]LV %d ▸ %s[/color]" % [n, dt])
		elif n <= current_lvl:
			lines.append("[color=#6a5870]LV %d · %s[/color]" % [n, dt])
		else:
			lines.append("[color=#bfd4e8]LV %d · %s[/color]" % [n, dt])
	var body: String = header + "\n" + cat_line + "\n" + "\n".join(lines)
	_augment_tooltip_label.text = body
	_augment_tooltip.visible = true
	_position_card_tooltip(card)


# ---------- Joker modal ----------

var _joker_modal: Panel = null
# Modal de revelação da Roleta Elemental (mostra o L4 sorteado e fecha o shop).
var _roulette_modal: Panel = null
# Escolha de rastro do Fogo (player vs flecha) ao chegar no L2. Pendente entre o
# commit e o último modal; mostrado por _maybe_finish_or_fire_choice.
var _fire_choice_modal: Panel = null
var _pending_fire_choice: bool = false
# Estado da seleção (mesmo padrão do shop principal: clica, fica roxo, pode
# trocar, só commita no botão Confirmar).
var _joker_selected_id: String = ""
# Lista dos chips renderizados pra poder atualizar overlay quando seleção muda.
# Cada entry: {"id": String, "btn": Button, "overlay": ColorRect}
var _joker_chips: Array = []
var _joker_confirm_btn: Button = null


func _open_joker_modal() -> void:
	# Fade visual do shop pra dar foco no modal (sem fechá-lo — vamos voltar
	# pra closed.emit() depois do confirm).
	if root_panel != null:
		root_panel.modulate = Color(1, 1, 1, 0.35)
	_joker_selected_id = ""
	_joker_chips.clear()
	_joker_modal = Panel.new()
	_joker_modal.anchor_left = 0.5
	_joker_modal.anchor_top = 0.5
	_joker_modal.anchor_right = 0.5
	_joker_modal.anchor_bottom = 0.5
	_joker_modal.offset_left = -560
	_joker_modal.offset_top = -340
	_joker_modal.offset_right = 560
	_joker_modal.offset_bottom = 340
	_joker_modal.z_index = 50
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.09, 0.06, 0.13, 0.97)
	sb.border_color = Color(0.85, 0.65, 0.20, 1.0)  # dourado: destaque do joker
	sb.border_width_left = 3
	sb.border_width_top = 3
	sb.border_width_right = 3
	sb.border_width_bottom = 3
	sb.corner_radius_top_left = 6
	sb.corner_radius_top_right = 6
	sb.corner_radius_bottom_left = 6
	sb.corner_radius_bottom_right = 6
	_joker_modal.add_theme_stylebox_override("panel", sb)
	add_child(_joker_modal)
	var vbox := VBoxContainer.new()
	vbox.anchor_right = 1.0
	vbox.anchor_bottom = 1.0
	vbox.offset_left = 24.0
	vbox.offset_top = 18.0
	vbox.offset_right = -24.0
	vbox.offset_bottom = -18.0
	vbox.add_theme_constant_override("separation", 14)
	_joker_modal.add_child(vbox)
	var title := Label.new()
	title.text = tr("SHOP_JOKER_MODAL_TITLE")
	var byte_font: Font = load("res://font/Silver.ttf")
	if byte_font != null:
		title.add_theme_font_override("font", byte_font)
	title.add_theme_font_size_override("font_size", 39)
	title.add_theme_color_override("font_color", Color(1.0, 0.85, 0.30, 1.0))
	title.add_theme_color_override("font_outline_color", Color.BLACK)
	title.add_theme_constant_override("outline_size", 3)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)
	# Aviso de uso único (reusa a key do tooltip da carta) — reforça na hora de usar.
	var subtitle := Label.new()
	subtitle.text = tr("SHOP_JOKER_TOOLTIP_RARE")
	subtitle.add_theme_font_size_override("font_size", 20)
	subtitle.add_theme_color_override("font_color", Color(0.72, 0.62, 0.85, 1.0))
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(subtitle)
	var player := _get_player()
	var hud := get_tree().get_first_node_in_group("hud")
	var status_targets: Array[String] = _collect_joker_status_targets(player)
	var pet_targets: Array[String] = _collect_joker_pet_targets(player)
	var upgrade_targets: Array[String] = _collect_joker_upgrade_targets(player)
	_add_joker_section(vbox, "SHOP_JOKER_MODAL_SECTION_STATUS", status_targets, player, hud)
	_add_joker_section(vbox, "SHOP_JOKER_MODAL_SECTION_PETS", pet_targets, player, hud)
	_add_joker_section(vbox, "SHOP_JOKER_MODAL_SECTION_UPGRADES", upgrade_targets, player, hud)
	# Edge case: player não tem nada upgradável. Mostra mensagem e auto-fecha
	# (não há o que selecionar nem confirmar).
	if status_targets.is_empty() and pet_targets.is_empty() and upgrade_targets.is_empty():
		var empty_lbl := Label.new()
		empty_lbl.text = tr("SHOP_JOKER_MODAL_EMPTY")
		empty_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty_lbl.add_theme_font_size_override("font_size", 28)
		empty_lbl.add_theme_color_override("font_color", Color(0.85, 0.85, 0.90, 1.0))
		vbox.add_child(empty_lbl)
		get_tree().create_timer(1.2).timeout.connect(_close_joker_modal_and_emit)
		return
	# Botão Confirmar — habilitado só quando _joker_selected_id != "".
	var confirm_row := HBoxContainer.new()
	confirm_row.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_child(confirm_row)
	_joker_confirm_btn = Button.new()
	_joker_confirm_btn.text = tr("SHOP_NEXT_WAVE")
	_joker_confirm_btn.custom_minimum_size = Vector2(240, 56)
	_joker_confirm_btn.focus_mode = Control.FOCUS_NONE
	if byte_font != null:
		_joker_confirm_btn.add_theme_font_override("font", byte_font)
	_joker_confirm_btn.add_theme_font_size_override("font_size", 30)
	_joker_confirm_btn.add_theme_color_override("font_color", Color(1.0, 0.92, 0.55, 1.0))
	_joker_confirm_btn.add_theme_color_override("font_color_disabled", Color(0.55, 0.50, 0.55, 1.0))
	var btn_sb := StyleBoxFlat.new()
	btn_sb.bg_color = Color(0.32, 0.22, 0.10, 1.0)
	btn_sb.border_color = Color(0.85, 0.65, 0.20, 1.0)
	btn_sb.border_width_left = 2
	btn_sb.border_width_top = 2
	btn_sb.border_width_right = 2
	btn_sb.border_width_bottom = 2
	btn_sb.corner_radius_top_left = 4
	btn_sb.corner_radius_top_right = 4
	btn_sb.corner_radius_bottom_left = 4
	btn_sb.corner_radius_bottom_right = 4
	var btn_hover_sb: StyleBoxFlat = btn_sb.duplicate()
	btn_hover_sb.bg_color = Color(0.46, 0.32, 0.14, 1.0)
	var btn_disabled_sb: StyleBoxFlat = btn_sb.duplicate()
	btn_disabled_sb.bg_color = Color(0.15, 0.12, 0.14, 1.0)
	btn_disabled_sb.border_color = Color(0.35, 0.30, 0.35, 1.0)
	_joker_confirm_btn.add_theme_stylebox_override("normal", btn_sb)
	_joker_confirm_btn.add_theme_stylebox_override("hover", btn_hover_sb)
	_joker_confirm_btn.add_theme_stylebox_override("pressed", btn_hover_sb)
	_joker_confirm_btn.add_theme_stylebox_override("disabled", btn_disabled_sb)
	_joker_confirm_btn.disabled = true
	_joker_confirm_btn.pressed.connect(_on_joker_confirm)
	confirm_row.add_child(_joker_confirm_btn)


func _collect_joker_status_targets(player: Node) -> Array[String]:
	var out: Array[String] = []
	if player == null or not player.has_method("get_upgrade_count"):
		return out
	for sid in _JOKER_STATUS_IDS:
		if int(player.get_upgrade_count(sid)) >= 1:
			out.append(sid)
	return out


func _collect_joker_pet_targets(player: Node) -> Array[String]:
	var out: Array[String] = []
	if player == null or not player.has_method("get_upgrade_count"):
		return out
	for pid in _JOKER_PET_IDS:
		var lvl: int = int(player.get_upgrade_count(pid))
		if lvl >= 1 and lvl < 4:
			out.append(pid)
	return out


func _collect_joker_upgrade_targets(player: Node) -> Array[String]:
	var out: Array[String] = []
	if player == null or not player.has_method("get_upgrade_count"):
		return out
	for u in UPGRADE_POOL:
		var uid: String = String(u["id"])
		var max_lvl: int = int(u.get("max_level", 4))
		var ulvl: int = int(player.get_upgrade_count(uid))
		if ulvl >= 1 and ulvl < max_lvl:
			out.append(uid)
	return out


func _add_joker_section(parent: VBoxContainer, title_key: String, ids: Array[String], player: Node, hud: Node) -> void:
	if ids.is_empty():
		return
	var section_label := Label.new()
	section_label.text = tr(title_key)
	var byte_font: Font = load("res://font/Silver.ttf")
	if byte_font != null:
		section_label.add_theme_font_override("font", byte_font)
	section_label.add_theme_font_size_override("font_size", 25)
	section_label.add_theme_color_override("font_color", Color(0.78, 0.68, 0.95, 1.0))
	parent.add_child(section_label)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	parent.add_child(row)
	for id in ids:
		row.add_child(_build_joker_chip(id, player, hud))


const _JOKER_CHIP_SIZE: Vector2 = Vector2(96, 110)


func _build_joker_chip(id: String, player: Node, hud: Node) -> Control:
	var btn := Button.new()
	btn.custom_minimum_size = _JOKER_CHIP_SIZE
	btn.flat = true
	btn.focus_mode = Control.FOCUS_NONE
	var chip_bg := StyleBoxFlat.new()
	chip_bg.bg_color = Color(0.14, 0.10, 0.18, 1.0)
	chip_bg.border_color = Color(0.45, 0.35, 0.60, 1.0)
	chip_bg.border_width_left = 2
	chip_bg.border_width_top = 2
	chip_bg.border_width_right = 2
	chip_bg.border_width_bottom = 2
	chip_bg.corner_radius_top_left = 4
	chip_bg.corner_radius_top_right = 4
	chip_bg.corner_radius_bottom_left = 4
	chip_bg.corner_radius_bottom_right = 4
	btn.add_theme_stylebox_override("normal", chip_bg)
	var hover_bg: StyleBoxFlat = chip_bg.duplicate()
	hover_bg.bg_color = Color(0.20, 0.14, 0.26, 1.0)
	hover_bg.border_color = Color(0.95, 0.75, 0.25, 1.0)
	btn.add_theme_stylebox_override("hover", hover_bg)
	btn.add_theme_stylebox_override("pressed", hover_bg)
	# Icon (atlas do HUD).
	var lvl: int = int(player.get_upgrade_count(id)) if player != null and player.has_method("get_upgrade_count") else 0
	var icon := TextureRect.new()
	if hud != null and hud.has_method("_get_upgrade_icon_atlas"):
		icon.texture = hud._get_upgrade_icon_atlas(id, lvl)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	icon.anchor_right = 1.0
	icon.offset_left = 6.0
	icon.offset_top = 6.0
	icon.offset_right = -6.0
	icon.offset_bottom = 70.0
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	btn.add_child(icon)
	# Level transition label.
	var lvl_label := Label.new()
	lvl_label.text = "%d → %d" % [lvl, lvl + 1]
	var byte_font: Font = load("res://font/Silver.ttf")
	if byte_font != null:
		lvl_label.add_theme_font_override("font", byte_font)
	lvl_label.add_theme_font_size_override("font_size", 20)
	lvl_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.30, 1.0))
	lvl_label.add_theme_color_override("font_outline_color", Color.BLACK)
	lvl_label.add_theme_constant_override("outline_size", 2)
	lvl_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lvl_label.anchor_top = 1.0
	lvl_label.anchor_right = 1.0
	lvl_label.anchor_bottom = 1.0
	lvl_label.offset_top = -36.0
	lvl_label.offset_left = 0.0
	lvl_label.offset_right = 0.0
	lvl_label.offset_bottom = -2.0
	lvl_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	btn.add_child(lvl_label)
	# Overlay roxo de seleção — mesma cor do shop principal (SELECTION_OVERLAY_COLOR).
	# Começa invisível; vira visível quando esse chip é o selecionado.
	var overlay := ColorRect.new()
	overlay.color = SELECTION_OVERLAY_COLOR
	overlay.anchor_right = 1.0
	overlay.anchor_bottom = 1.0
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.visible = false
	btn.add_child(overlay)
	btn.pressed.connect(_on_joker_chip_clicked.bind(id))
	_joker_chips.append({"id": id, "btn": btn, "overlay": overlay})
	return btn


func _on_joker_chip_clicked(id: String) -> void:
	# Toggle behavior: clique no chip selecionado desfaz a seleção. Clicar em
	# outro chip troca. Confirm fica disabled enquanto nada selecionado.
	if _joker_selected_id == id:
		_joker_selected_id = ""
	else:
		_joker_selected_id = id
	_play_buy_sound()
	_refresh_joker_chip_overlays()
	if _joker_confirm_btn != null:
		_joker_confirm_btn.disabled = _joker_selected_id == ""


func _refresh_joker_chip_overlays() -> void:
	for entry in _joker_chips:
		var overlay: ColorRect = entry["overlay"]
		if overlay == null or not is_instance_valid(overlay):
			continue
		overlay.visible = String(entry["id"]) == _joker_selected_id


func _on_joker_confirm() -> void:
	if _joker_selected_id == "":
		return
	var picked_id: String = _joker_selected_id
	var player := _get_player()
	if player != null and player.has_method("apply_upgrade"):
		player.apply_upgrade(picked_id)
	if has_node("/root/Telemetry"):
		var wm := get_tree().get_first_node_in_group("wave_manager")
		var wave_num: int = int(wm.wave_number) if wm != null and "wave_number" in wm else 0
		get_node("/root/Telemetry").track("joker_used", {
			"wave": wave_num,
			"picked_id": picked_id,
		})
	_play_next_wave_sound()
	_close_joker_modal_and_emit()


func _close_joker_modal_and_emit() -> void:
	if _joker_modal != null and is_instance_valid(_joker_modal):
		_joker_modal.queue_free()
		_joker_modal = null
	_joker_chips.clear()
	_joker_confirm_btn = null
	_joker_selected_id = ""
	if root_panel != null:
		root_panel.modulate = Color.WHITE
	_maybe_finish_or_fire_choice()


# Revelação da Roleta Elemental: mostra qual elemental L4 saiu e, no OK, fecha o
# shop. A troca já foi aplicada no player antes de abrir isto.
func _open_roulette_reveal(elemental_id: String) -> void:
	if root_panel != null:
		root_panel.modulate = Color(1, 1, 1, 0.35)
	_roulette_modal = Panel.new()
	_roulette_modal.anchor_left = 0.5
	_roulette_modal.anchor_top = 0.5
	_roulette_modal.anchor_right = 0.5
	_roulette_modal.anchor_bottom = 0.5
	_roulette_modal.offset_left = -380
	_roulette_modal.offset_top = -270
	_roulette_modal.offset_right = 380
	_roulette_modal.offset_bottom = 270
	_roulette_modal.z_index = 50
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.09, 0.06, 0.13, 0.97)
	sb.border_color = Color(0.65, 0.45, 0.85, 1.0)
	sb.set_border_width_all(3)
	sb.set_corner_radius_all(6)
	_roulette_modal.add_theme_stylebox_override("panel", sb)
	add_child(_roulette_modal)
	var byte_font: Font = load("res://font/Silver.ttf")
	var vbox := VBoxContainer.new()
	vbox.anchor_right = 1.0
	vbox.anchor_bottom = 1.0
	vbox.offset_left = 28.0
	vbox.offset_top = 24.0
	vbox.offset_right = -28.0
	vbox.offset_bottom = -24.0
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 18)
	_roulette_modal.add_child(vbox)
	var title := Label.new()
	title.text = tr("SHOP_ROULETTE_REVEAL_TITLE")
	if byte_font != null:
		title.add_theme_font_override("font", byte_font)
	title.add_theme_font_size_override("font_size", 36)
	title.add_theme_color_override("font_color", Color(0.85, 0.65, 1.0, 1.0))
	title.add_theme_color_override("font_outline_color", Color.BLACK)
	title.add_theme_constant_override("outline_size", 3)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)
	# Arte do card L4 do elemental ganho (frame 4 da sheet 152×47 do elemental).
	var art_tex: Texture2D = _load_card_texture("upgrade", elemental_id)
	if art_tex != null:
		var art := TextureRect.new()
		art.texture = _make_card_atlas(art_tex, "upgrade", 4)
		art.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		art.custom_minimum_size = Vector2(38 * 4, 47 * 4)  # 152×188 (4× o frame)
		art.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		art.mouse_filter = Control.MOUSE_FILTER_IGNORE
		vbox.add_child(art)
	var result := Label.new()
	result.text = tr("SHOP_ROULETTE_REVEAL_RESULT") % tr(_augment_title_for(elemental_id))
	if byte_font != null:
		result.add_theme_font_override("font", byte_font)
	result.add_theme_font_size_override("font_size", 44)
	result.add_theme_color_override("font_color", Color(1.0, 0.92, 0.45, 1.0))
	result.add_theme_color_override("font_outline_color", Color.BLACK)
	result.add_theme_constant_override("outline_size", 3)
	result.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(result)
	var ok_btn := Button.new()
	ok_btn.text = tr("SHOP_ROULETTE_REVEAL_OK")
	ok_btn.focus_mode = Control.FOCUS_NONE
	ok_btn.custom_minimum_size = Vector2(0, 56)
	if byte_font != null:
		ok_btn.add_theme_font_override("font", byte_font)
	ok_btn.add_theme_font_size_override("font_size", 30)
	ok_btn.pressed.connect(_close_roulette_reveal_and_emit)
	vbox.add_child(ok_btn)


func _close_roulette_reveal_and_emit() -> void:
	if _roulette_modal != null and is_instance_valid(_roulette_modal):
		_roulette_modal.queue_free()
		_roulette_modal = null
	if root_panel != null:
		root_panel.modulate = Color.WHITE
	_maybe_finish_or_fire_choice()


# ---------- Escolha de rastro do Fogo (L2) ----------

func _maybe_finish_or_fire_choice() -> void:
	# Se a compra levou o Fogo ao L2, mostra a escolha de rastro como último passo
	# antes de fechar o shop. Senão, fecha direto.
	if _pending_fire_choice:
		_pending_fire_choice = false
		_open_fire_trail_choice()
		return
	closed.emit()


func _open_fire_trail_choice() -> void:
	# Modal pós-compra no mesmo molde do reveal da Roleta: dimma o shop, painel
	# central, título + subtítulo e DUAS opções (player primeiro / flecha primeiro).
	# Obrigatório escolher — não há botão de fechar.
	if root_panel != null:
		root_panel.modulate = Color(1, 1, 1, 0.35)
	_fire_choice_modal = Panel.new()
	_fire_choice_modal.anchor_left = 0.5
	_fire_choice_modal.anchor_top = 0.5
	_fire_choice_modal.anchor_right = 0.5
	_fire_choice_modal.anchor_bottom = 0.5
	_fire_choice_modal.offset_left = -440
	_fire_choice_modal.offset_top = -240
	_fire_choice_modal.offset_right = 440
	_fire_choice_modal.offset_bottom = 240
	_fire_choice_modal.z_index = 50
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.12, 0.06, 0.05, 0.97)
	sb.border_color = Color(1.0, 0.55, 0.2, 1.0)  # laranja: tema do Fogo
	sb.set_border_width_all(3)
	sb.set_corner_radius_all(6)
	_fire_choice_modal.add_theme_stylebox_override("panel", sb)
	add_child(_fire_choice_modal)
	var byte_font: Font = load("res://font/Silver.ttf")
	var vbox := VBoxContainer.new()
	vbox.anchor_right = 1.0
	vbox.anchor_bottom = 1.0
	vbox.offset_left = 28.0
	vbox.offset_top = 24.0
	vbox.offset_right = -28.0
	vbox.offset_bottom = -24.0
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 14)
	_fire_choice_modal.add_child(vbox)
	var title := Label.new()
	title.text = tr("SHOP_FIRE_TRAIL_TITLE")
	if byte_font != null:
		title.add_theme_font_override("font", byte_font)
	title.add_theme_font_size_override("font_size", 36)
	title.add_theme_color_override("font_color", Color(1.0, 0.72, 0.4, 1.0))
	title.add_theme_color_override("font_outline_color", Color.BLACK)
	title.add_theme_constant_override("outline_size", 3)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)
	var subtitle := Label.new()
	# Mostra o DoT real do rastro (já escalado pelo Dano atual). Os dois rastros têm
	# o mesmo DoT — a escolha é só ONDE o fogo cai.
	var _fp := get_tree().get_first_node_in_group("player")
	var _trail_dps: int = 3
	if _fp != null and _fp.has_method("_fire_trail_dps"):
		_trail_dps = int(round(float(_fp._fire_trail_dps())))
	subtitle.text = tr("SHOP_FIRE_TRAIL_SUBTITLE") % _trail_dps
	if byte_font != null:
		subtitle.add_theme_font_override("font", byte_font)
	subtitle.add_theme_font_size_override("font_size", 24)
	subtitle.add_theme_color_override("font_color", Color(0.85, 0.8, 0.75, 1.0))
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(subtitle)
	var hbox := HBoxContainer.new()
	hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	hbox.add_theme_constant_override("separation", 28)
	hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(hbox)
	hbox.add_child(_make_fire_choice_option(
		"player_first", "SHOP_FIRE_TRAIL_OPT_PLAYER", "SHOP_FIRE_TRAIL_DESC_PLAYER", byte_font))
	hbox.add_child(_make_fire_choice_option(
		"arrow_first", "SHOP_FIRE_TRAIL_OPT_ARROW", "SHOP_FIRE_TRAIL_DESC_ARROW", byte_font))


func _make_fire_choice_option(variant: String, name_key: String, desc_key: String, byte_font: Font) -> Control:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.custom_minimum_size = Vector2(360, 0)
	var btn := Button.new()
	btn.text = tr(name_key)
	btn.focus_mode = Control.FOCUS_NONE
	btn.custom_minimum_size = Vector2(0, 64)
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if byte_font != null:
		btn.add_theme_font_override("font", byte_font)
	btn.add_theme_font_size_override("font_size", 30)
	btn.add_theme_color_override("font_color", Color(1.0, 0.84, 0.34, 1.0))
	btn.pressed.connect(_close_fire_choice_and_emit.bind(variant))
	col.add_child(btn)
	var desc := Label.new()
	desc.text = tr(desc_key)
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if byte_font != null:
		desc.add_theme_font_override("font", byte_font)
	desc.add_theme_font_size_override("font_size", 22)
	desc.add_theme_color_override("font_color", Color(0.8, 0.78, 0.82, 1.0))
	desc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_child(desc)
	return col


func _close_fire_choice_and_emit(variant: String) -> void:
	var player := _get_player()
	if player != null and "fire_trail_variant" in player:
		player.fire_trail_variant = variant
	if _fire_choice_modal != null and is_instance_valid(_fire_choice_modal):
		_fire_choice_modal.queue_free()
		_fire_choice_modal = null
	if root_panel != null:
		root_panel.modulate = Color.WHITE
	closed.emit()


func _show_joker_tooltip(card: Control) -> void:
	_ensure_augment_tooltip()
	var header: String = "[b]%s[/b]  [color=#ffd757]★[/color]" % tr("SHOP_JOKER_TOOLTIP_HEADER")
	var body_line: String = "[color=#bfd4e8]%s[/color]" % tr("SHOP_JOKER_TOOLTIP_BODY")
	var rare_line: String = "[color=#a890c8][i]%s[/i][/color]" % tr("SHOP_JOKER_TOOLTIP_RARE")
	_augment_tooltip_label.text = header + "\n\n" + body_line + "\n\n" + rare_line
	_augment_tooltip.visible = true
	_position_card_tooltip(card)


# Tooltip da Roleta Elemental (mesmo molde do joker: carta sem texto, explicação
# só aqui no hover). Header = nome, corpo = descrição do efeito.
func _show_roulette_tooltip(card: Control) -> void:
	_ensure_augment_tooltip()
	var header: String = "[b]%s[/b]  [color=#c79bff]🎲[/color]" % tr("SHOP_UPG_ELEMENTAL_ROULETTE")
	var body_line: String = "[color=#bfd4e8]%s[/color]" % tr("SHOP_ELEMENTAL_ROULETTE_DESC")
	_augment_tooltip_label.text = header + "\n\n" + body_line
	_augment_tooltip.visible = true
	_position_card_tooltip(card)


# Posiciona o tooltip ao lado do card (esquerda/direita conforme metade da tela).
# Extraído do _show_joker_tooltip pra reuso (joker + roleta).
func _position_card_tooltip(card: Control) -> void:
	# Posicionamento mesmo padrão do tooltip normal.
	var tip_size: Vector2 = await _await_tooltip_size()
	var screen: Vector2 = get_viewport().get_visible_rect().size
	var card_rect: Rect2 = card.get_global_rect()
	var card_center_x: float = card_rect.position.x + card_rect.size.x / 2.0
	var pos: Vector2
	if card_center_x < screen.x / 2.0:
		pos = Vector2(card_rect.position.x + card_rect.size.x + 16.0, card_rect.position.y)
	else:
		pos = Vector2(card_rect.position.x - tip_size.x - 16.0, card_rect.position.y)
	_apply_tooltip_pos(pos, tip_size)


func _ensure_augment_tooltip() -> void:
	if _augment_tooltip != null:
		return
	_augment_tooltip = PanelContainer.new()
	_augment_tooltip.visible = false
	_augment_tooltip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# z acima do modal "Seus Upgrades" (z=200) pra o tooltip nao ficar atras dele.
	_augment_tooltip.z_index = 300
	_augment_tooltip.custom_minimum_size = Vector2(380, 0)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.10, 0.07, 0.14, 0.96)
	sb.border_color = Color(0.55, 0.40, 0.70, 1.0)
	sb.border_width_left = 2
	sb.border_width_top = 2
	sb.border_width_right = 2
	sb.border_width_bottom = 2
	sb.content_margin_left = 16
	sb.content_margin_right = 16
	sb.content_margin_top = 12
	sb.content_margin_bottom = 12
	_augment_tooltip.add_theme_stylebox_override("panel", sb)
	_augment_tooltip_label = RichTextLabel.new()
	_augment_tooltip_label.bbcode_enabled = true
	_augment_tooltip_label.fit_content = true
	_augment_tooltip_label.scroll_active = false
	_augment_tooltip_label.add_theme_font_override("normal_font", load("res://font/Silver.ttf"))
	_augment_tooltip_label.add_theme_font_override("bold_font", load("res://font/Silver.ttf"))
	_augment_tooltip_label.add_theme_font_size_override("normal_font_size", 25)
	_augment_tooltip_label.add_theme_font_size_override("bold_font_size", 28)
	_augment_tooltip_label.add_theme_color_override("default_color", Color(0.92, 0.86, 1.0, 1.0))
	_augment_tooltip_label.custom_minimum_size = Vector2(348, 0)
	_augment_tooltip.add_child(_augment_tooltip_label)
	root_panel.add_child(_augment_tooltip)


# Título (translation key) por upgrade id. Reusa as mesmas keys que os cards
# da loja usam pra TitleLabel.
func _augment_title_for(id: String) -> String:
	match id:
		"hp": return "SHOP_HP_TITLE"
		"armor": return "SHOP_UPG_ARMOR"
		"damage": return "SHOP_UPG_DAMAGE"
		"attack_speed": return "SHOP_UPG_ATTACK_SPEED"
		"move_speed": return "SHOP_UPG_MOVE_SPEED"
		"perfuracao": return "SHOP_UPG_PERFURACAO"
		"ricochet_arrow": return "SHOP_UPG_RICOCHET"
		"multi_arrow": return "SHOP_UPG_MULTI_ARROW"
		"double_arrows": return "SHOP_UPG_DOUBLE_ARROWS"
		"chain_lightning": return "SHOP_UPG_CHAIN_LIGHTNING"
		"fire_arrow": return "SHOP_UPG_FIRE_ARROW"
		"curse_arrow": return "SHOP_UPG_CURSE_ARROW"
		"ice_arrow": return "SHOP_UPG_ICE_ARROW"
		"stone_arrow": return "SHOP_UPG_STONE_ARROW"
		"tide_arrow": return "SHOP_UPG_TIDE_ARROW"
		"boomerang": return "SHOP_UPG_BOOMERANG"
		"critical_chance": return "SHOP_UPG_CRITICAL_CHANCE"
		"tiger_claws": return "SHOP_UPG_TIGER_CLAWS"
		"graviton": return "SHOP_UPG_GRAVITON"
		"life_steal": return "SHOP_UPG_LIFE_STEAL"
		"dash": return "SHOP_UPG_DASH"
		"esquivando": return "SHOP_UPG_ESQUIVANDO"
		"fenda": return "SHOP_UPG_FENDA"
		"adrenalina": return "SHOP_UPG_ADRENALINA"
		"gold_magnet": return "SHOP_UPG_GOLD_MAGNET"
		"claudio_druida": return "SHOP_ALLY_CLAUDIO_DRUIDA"
		"leno": return "SHOP_ALLY_LENO"
		"capivara_joe": return "SHOP_ALLY_CAPIVARA"
		"ting": return "SHOP_ALLY_TING"
		"mini_mago": return "SHOP_ALLY_MINI_MAGO"
		"arbusto": return "SHOP_ALLY_ARBUSTO"
		"tilisko": return "SHOP_ALLY_TILISKO"
		"spectral_arrow": return "SHOP_UPG_SPECTRAL"
	return id


# Cap de nível por upgrade. Status (hp/armor/damage/atk_speed/move_speed) escala
# infinito — retorna 0 (sem cap). Demais usam o cap de _UPG_CAPS do HUD se
# disponível, fallback 4.
func _max_level_for(id: String) -> int:
	if id == "hp" or id == "armor" or id == "damage" or id == "attack_speed" or id == "move_speed":
		return 0  # sem cap
	return 4


func _refresh_items_box() -> void:
	# Linha "ITENS" do StatsCard: 3 slots de itens equipados (read-only). Vazio =
	# slot padrão (igual pets/estruturas); equipado = ícone do item + tooltip.
	if items_box == null:
		return
	for c in items_box.get_children():
		c.queue_free()
	var hud := get_tree().get_first_node_in_group("hud")
	var equipped: Array = InventoryItems.get_equipped()
	for i in InventoryItems.MAX_SLOTS:
		var id: String = String(equipped[i]) if i < equipped.size() else ""
		items_box.add_child(_build_item_chip(id, hud))


func _build_item_chip(id: String, hud: Node) -> Control:
	# Slot vazio reusa o mini chip (traço "—"). Slot cheio = ícone do item (sprite
	# próprio em assets/Hud/itens, NÃO o atlas de upgrades) + tooltip no hover.
	if id == "":
		return _build_mini_owned_chip("", 0, hud)
	var chip := Control.new()
	chip.custom_minimum_size = _MINI_CHIP_SIZE
	chip.mouse_filter = Control.MOUSE_FILTER_STOP
	var bg := ColorRect.new()
	bg.color = Color(0.10, 0.07, 0.13, 0.85)
	bg.anchor_right = 1.0
	bg.anchor_bottom = 1.0
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chip.add_child(bg)
	var tex := load(InventoryItems.get_icon_path(id)) as Texture2D
	if tex != null:
		var icon := TextureRect.new()
		icon.texture = tex
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		icon.anchor_right = 1.0
		icon.anchor_bottom = 1.0
		icon.offset_left = 2.0
		icon.offset_top = 2.0
		icon.offset_right = -2.0
		icon.offset_bottom = -2.0
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		chip.add_child(icon)
	chip.mouse_entered.connect(_on_item_hovered.bind(id, chip))
	chip.mouse_exited.connect(_on_augment_unhovered)
	return chip


func _on_item_hovered(id: String, chip: Control) -> void:
	_ensure_augment_tooltip()
	var item: Dictionary = InventoryItems.ITEMS.get(id, {})
	var title: String = tr(String(item.get("name", "")))
	var desc: String = tr(String(item.get("desc", "")))
	_augment_tooltip_label.text = "[b]%s[/b]\n\n%s" % [title, desc]
	_augment_tooltip.visible = true
	var chip_global: Vector2 = chip.get_global_rect().position
	var tip_size: Vector2 = await _await_tooltip_size()
	_apply_tooltip_pos(Vector2(chip_global.x - tip_size.x - 16.0, chip_global.y), tip_size)


# Cap de pets distintos compráveis = base + bônus de item (Adote Mais Um).
func _effective_pet_cap() -> int:
	return MAX_DISTINCT_PETS + InventoryItems.equipped_pet_slot_bonus()


# Espera o layout do tooltip assentar (fit_content precisa de 1-2 frames) e
# devolve o tamanho REAL (max entre .size e o minimo combinado). Evita medir
# uma altura menor que o conteudo (causava overflow pra baixo da tela).
func _await_tooltip_size() -> Vector2:
	await get_tree().process_frame
	await get_tree().process_frame
	var sz: Vector2 = _augment_tooltip.size
	var mn: Vector2 = _augment_tooltip.get_combined_minimum_size()
	return Vector2(maxf(sz.x, mn.x), maxf(sz.y, mn.y))


# Clampa o tooltip pra caber 100% na tela (usa o tamanho REAL do viewport — antes
# era 1920x1080 fixo, que cortava o tooltip quando a janela era menor). Se for maior
# que a tela, ancora no topo/esquerda. maxf garante max >= min (sem degenerar).
func _apply_tooltip_pos(pos: Vector2, tip_size: Vector2) -> void:
	var screen: Vector2 = get_viewport().get_visible_rect().size
	pos.x = clampf(pos.x, 16.0, maxf(16.0, screen.x - tip_size.x - 16.0))
	pos.y = clampf(pos.y, 16.0, maxf(16.0, screen.y - tip_size.y - 16.0))
	_augment_tooltip.position = pos
