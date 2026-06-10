# Diamante de Primeira Classe — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Item equipável que, no início da run, sorteia 1 dos 21 upgrades pra ficar ~30% mais forte a run inteira (marcado com 💎 na carta + descrição do buff), em troca de desligar os rerolls da loja.

**Architecture:** Um único estado no player — `_diamond_upgrade_id: String` — setado no run-start sorteando da lista dos 21 (menos os já dados de graça por item). Cada "versão diamante" é lida no ponto onde aquele upgrade calcula seu efeito, via o helper `is_diamond(id)`. A loja lê o flag pra cravar o 💎 + desc e desligar o reroll. Sem o item, `_diamond_upgrade_id == ""` → comportamento idêntico ao atual.

**Tech Stack:** Godot 4 / GDScript. **Sem framework de testes** — verificação é MANUAL via dev panel (F5 → painel dev). Spec de referência: [docs/superpowers/specs/2026-06-10-diamante-primeira-classe-buffs.md](../specs/2026-06-10-diamante-primeira-classe-buffs.md).

**Convenção de verificação:** cada task de buff é verificada equipando o Diamante e forçando o upgrade-alvo pelo dev panel (botões criados na Task 4), comprando o upgrade, e observando o efeito turbinado vs o normal. "PASS" = efeito turbinado visível; comparar tirando o Diamante.

---

## Arquivos tocados

| Arquivo | Responsabilidade |
|---------|------------------|
| `scripts/systems/inventory_items.gd` | Define o item `diamante_primeira_classe` (effect `diamond_pick` + unlock quest); seta `_has_diamante` no player em `apply_to_player`. |
| `scripts/player/player.gd` | Estado `_diamond_upgrade_id` + `reroll_used_this_run`; const `DIAMOND_ELIGIBLE`; `_roll_diamond_upgrade()`; helper `is_diamond()`; getter `get_diamond_upgrade_id()`; os hooks das 21 versões diamante nas funções de efeito. |
| `scripts/skills/arrow.gd` | Versões diamante que vivem na flecha (multi 360°, ricochete, etc.). |
| `scripts/ui/wave_shop.gd` | 💎 overlay + linha de desc na carta; flag de reroll; desligar reroll com o item. |
| `scripts/systems/wave_manager.gd` | Excluir `_diamond_upgrade_id` do grant grátis (FREE_UPGRADE_POOL). |
| `scripts/systems/skin_loadout.gd` | Stat de unlock (`diamante_unlock_done`) gravado em `record_run`. |
| `scripts/ui/run_build_modal.gd` | Mostrar qual upgrade teve o diamante na build da run. |
| `scripts/ui/dev_panel.gd` (+ `.tscn`) | Botões dev: equipar Diamante + ciclar o upgrade diamante forçado. |
| `assets/i18n/translations.csv` | Keys `ITEM_DIAMANTE_*`, `ITEM_REQ_DIAMANTE`, `SHOP_DIAMANTE_DESC_*` (21). |
| `project.godot` | Bump de versão (só no deploy — NÃO nesta feature). |

---

# FASE 1 — Mecânica do item

## Task 1: Estado no player + helper `is_diamond`

**Files:**
- Modify: `scripts/player/player.gd` (perto dos outros `var` de estado, ex: ~linha 540–560 onde ficam flags de item como `_capacete_veloz_equipped`)

- [ ] **Step 1: Adicionar as variáveis de estado**

Em `player.gd`, junto das flags de item equipado:

```gdscript
# Diamante de Primeira Classe (item): no início da run sorteia 1 upgrade pra ficar
# turbinado a run inteira. Vazio = sem o item. Setado em _roll_diamond_upgrade().
var _diamond_upgrade_id: String = ""
var _has_diamante: bool = false  # setado por InventoryItems.apply_to_player
# Flag por-run pro unlock do Diamante: vira true em qualquer reroll global.
var reroll_used_this_run: bool = false
```

- [ ] **Step 2: Adicionar helper + getter** (perto de `get_upgrade_count`, ~linha 4030)

```gdscript
# True se `id` é o upgrade sorteado pelo Diamante de Primeira Classe.
func is_diamond(id: String) -> bool:
	return _diamond_upgrade_id != "" and _diamond_upgrade_id == id


func get_diamond_upgrade_id() -> String:
	return _diamond_upgrade_id
```

- [ ] **Step 3: Verificar que compila** — Run: abrir o projeto no editor (F5). Expected: sem erro de parse no player.gd.

- [ ] **Step 4: Commit**

```bash
git add scripts/player/player.gd
git commit -m "feat(diamante): estado _diamond_upgrade_id + helper is_diamond"
```

---

## Task 2: Item no inventário + i18n + flag em apply_to_player

**Files:**
- Modify: `scripts/systems/inventory_items.gd` (ITEMS dict ~linha 35–197; `apply_to_player` ~505–557; comentário de effect types ~31)
- Modify: `assets/i18n/translations.csv`

- [ ] **Step 1: Documentar o novo effect type** (no comentário ~linha 31)

```gdscript
#   "diamond_pick"           — sorteia 1 upgrade pra ficar turbinado a run inteira (sem rerolls).
```

- [ ] **Step 2: Adicionar o item ao ITEMS dict**

```gdscript
	"diamante_primeira_classe": {
		"name": "ITEM_DIAMANTE_NAME",
		"desc": "ITEM_DIAMANTE_DESC",
		"icon": "res://assets/Hud/itens/diamante_primeira_classe.png",
		"effect": {"type": "diamond_pick"},
		"unlock": {"type": "quest", "reqs": [
			{"stat": &"diamante_unlock_done", "value": 1, "label": "ITEM_REQ_DIAMANTE"},
		]},
	},
```

> ✅ Arte pronta: `assets/Hud/itens/diamante_primeira_classe.png` (32×32, gerado de `Diamante de primeira classe.aseprite` via `tools/diamante_export.py`).

- [ ] **Step 3: Setar a flag no player em `apply_to_player`** (no `match t:` ~linha 511)

```gdscript
			"diamond_pick":
				if "_has_diamante" in player:
					player._has_diamante = true
```

- [ ] **Step 4: Adicionar as keys no CSV** (`assets/i18n/translations.csv`)

```
ITEM_DIAMANTE_NAME,Diamante de Primeira Classe,First-Class Diamond,Diamante de Primera Clase,Diamant de Première Classe
ITEM_DIAMANTE_DESC,"No início da run, um upgrade aleatório fica turbinado a run inteira (marcado com 💎 na loja). Em troca, você não tem mais rerolls.","At run start, a random upgrade is supercharged for the whole run (marked 💎 in the shop). In exchange, you lose all rerolls.","Al inicio de la run, un upgrade aleatorio queda potenciado toda la run (marcado 💎 en la tienda). A cambio, pierdes los rerolls.","Au début de la run, une amélioration aléatoire est surchargée pour toute la run (marquée 💎 en boutique). En échange, vous perdez les rerolls."
ITEM_REQ_DIAMANTE,Passe da wave 14 sem usar nenhum reroll,Reach past wave 14 without using any reroll,Supera la oleada 14 sin usar ningún reroll,Dépassez la vague 14 sans utiliser de reroll
```

- [ ] **Step 5: Verificar** — F5 → menu Player/Inventário. Expected: o item "Diamante de Primeira Classe" aparece (bloqueado, com o requisito). Em debug com `DEV_UNLOCK_ALL_ITEMS`, aparece desbloqueado.

- [ ] **Step 6: Commit**

```bash
git add scripts/systems/inventory_items.gd assets/i18n/translations.csv
git commit -m "feat(diamante): item no inventario + i18n + flag _has_diamante"
```

---

## Task 3: Sorteio no run-start (com exclusões)

**Files:**
- Modify: `scripts/player/player.gd` (run-start: `_ready()` ~linha 735, logo após `InventoryItems.apply_to_player(self)`)

- [ ] **Step 1: Const com os 21 upgrades elegíveis** (perto dos outros const de pool)

```gdscript
# Os 21 upgrades de build que o Diamante pode sortear (espelha UPGRADE_POOL do shop).
const DIAMOND_ELIGIBLE: Array[String] = [
	"perfuracao", "spectral_arrow", "multi_arrow", "double_arrows", "chain_lightning",
	"life_steal", "gold_magnet", "dash", "esquivando", "fenda", "adrenalina",
	"ricochet_arrow", "graviton", "fire_arrow", "curse_arrow", "ice_arrow",
	"stone_arrow", "tide_arrow", "boomerang", "critical_chance", "tiger_claws",
]
```

- [ ] **Step 2: Função de sorteio** (com exclusão de upgrades dados de graça por item)

```gdscript
# Sorteia o upgrade do Diamante: dos 21, exclui os que algum item equipado já dá de
# graça no início (start_status). Se sobrar vazio (improvável), fica sem diamante.
func _roll_diamond_upgrade() -> void:
	if not _has_diamante:
		return
	var pool: Array[String] = []
	for id in DIAMOND_ELIGIBLE:
		if InventoryItems.start_granted_amount(id) > 0:
			continue
		pool.append(id)
	if pool.is_empty():
		return
	_diamond_upgrade_id = pool[randi() % pool.size()]
	print("[diamante] upgrade sorteado: ", _diamond_upgrade_id)
```

- [ ] **Step 3: Chamar no run-start** — em `_ready()`, logo DEPOIS de `InventoryItems.apply_to_player(self)` (~linha 735):

```gdscript
	InventoryItems.apply_to_player(self)
	_roll_diamond_upgrade()  # sorteia o diamante (precisa dos itens já aplicados)
```

- [ ] **Step 4: Verificar** — F5, equipar o Diamante (via dev panel após Task 4, ou `DEV_UNLOCK_ALL_ITEMS` + equipar no menu), começar run. Expected: o print `[diamante] upgrade sorteado: <id>` no Output.

- [ ] **Step 5: Commit**

```bash
git add scripts/player/player.gd
git commit -m "feat(diamante): sorteio do upgrade no run-start com exclusao de itens"
```

---

## Task 4: Dev tooling (equipar + forçar upgrade do diamante)

**Files:**
- Modify: `scripts/ui/dev_panel.gd` (padrão de botão ~linha 17–101)
- Modify: `scenes/ui/dev_panel.tscn` (adicionar os 2 botões)
- Modify: `scripts/player/player.gd` (setter dev)

- [ ] **Step 1: Setter dev no player** (pra forçar o upgrade do diamante)

```gdscript
# DEV: força qual upgrade é o do diamante (e liga o flag). Usado pelo dev panel.
func dev_set_diamond_upgrade(id: String) -> void:
	_has_diamante = true
	_diamond_upgrade_id = id
	print("[dev][diamante] forcado: ", id)
```

- [ ] **Step 2: Adicionar 2 botões no `dev_panel.tscn`** — dois `Button` no container de botões do painel: `EquipDiamanteBtn` (texto "Equipar Diamante") e `CycleDiamondBtn` (texto "Diamante: <id>"). Seguir o mesmo layout/estilo dos botões existentes ("Abrir Shop" etc.).

- [ ] **Step 3: Conectar no `dev_panel.gd` `_ready()`**

```gdscript
	var eq := get_node_or_null("%EquipDiamanteBtn")
	if eq != null:
		eq.pressed.connect(_dev_equip_diamante)
	var cyc := get_node_or_null("%CycleDiamondBtn")
	if cyc != null:
		cyc.pressed.connect(_dev_cycle_diamond)
```

- [ ] **Step 4: Callbacks no `dev_panel.gd`**

```gdscript
var _dev_diamond_idx: int = -1

func _dev_equip_diamante() -> void:
	InventoryItems.set_equipped(InventoryItems.get_equipped() + ["diamante_primeira_classe"])
	var p := get_tree().get_first_node_in_group("player")
	if p != null and "_has_diamante" in p:
		p._has_diamante = true
	print("[dev] Diamante equipado")

func _dev_cycle_diamond() -> void:
	var p := get_tree().get_first_node_in_group("player")
	if p == null or not p.has_method("dev_set_diamond_upgrade"):
		return
	_dev_diamond_idx = (_dev_diamond_idx + 1) % p.DIAMOND_ELIGIBLE.size()
	var id: String = p.DIAMOND_ELIGIBLE[_dev_diamond_idx]
	p.dev_set_diamond_upgrade(id)
	var btn := get_node_or_null("%CycleDiamondBtn")
	if btn != null:
		btn.text = "Diamante: " + id
```

> Nota: `InventoryItems.set_equipped` — se a API exata diferir, usar o método de equipar que já existe (ver `inventory_items.gd`); o objetivo é só forçar o item equipado em dev.

- [ ] **Step 5: Verificar** — F5 → dev panel → "Diamante: ..." cicla pelos 21 ids e o print confirma. Expected: o botão atualiza o texto e o player passa a ter aquele `_diamond_upgrade_id`.

- [ ] **Step 6: Commit**

```bash
git add scripts/ui/dev_panel.gd scenes/ui/dev_panel.tscn scripts/player/player.gd
git commit -m "feat(diamante): dev tooling (equipar + ciclar upgrade do diamante)"
```

---

## Task 5: Reroll — flag + desligar com o Diamante

**Files:**
- Modify: `scripts/ui/wave_shop.gd` (`_on_global_reroll` ~2649; estado/refresh do botão de reroll `_refresh_global_reroll` ~2679)

- [ ] **Step 1: Setar a flag no commit do reroll** — em `_on_global_reroll`, logo após o gold ser gasto e `_global_rerolls_used` incrementar:

```gdscript
	var p := _get_player()
	if p != null and "reroll_used_this_run" in p:
		p.reroll_used_this_run = true
```

- [ ] **Step 2: Desligar o reroll quando o Diamante está equipado** — em `_refresh_global_reroll` (ou onde o botão de reroll é habilitado/desenhado), no começo:

```gdscript
	var pl := _get_player()
	var diamante_on: bool = pl != null and "get_diamond_upgrade_id" in pl and pl.get_diamond_upgrade_id() != ""
	if diamante_on:
		# Diamante de Primeira Classe: sem rerolls. Esconde/desabilita o botão.
		if global_reroll_btn != null:
			global_reroll_btn.disabled = true
			global_reroll_btn.visible = false
		return
```

> Ajustar o nome do nó do botão (`global_reroll_btn`) ao que existe no wave_shop. Se for melhor só desabilitar (em vez de esconder), manter `visible = true` e `disabled = true` com um tooltip.

- [ ] **Step 3: Verificar** — dev panel: equipar Diamante + ciclar um upgrade → abrir shop. Expected: botão de reroll some/desabilita. Sem o Diamante: reroll normal. Usar um reroll sem Diamante e confirmar (via print temporário ou debugger) que `reroll_used_this_run` vira true.

- [ ] **Step 4: Commit**

```bash
git add scripts/ui/wave_shop.gd
git commit -m "feat(diamante): flag reroll_used_this_run + desliga reroll com o item"
```

---

## Task 6: Excluir o upgrade do diamante do grant grátis

**Files:**
- Modify: `scripts/systems/wave_manager.gd` (onde a `FREE_UPGRADE_POOL` é sorteada pro welcome/free grant)

- [ ] **Step 1: Filtrar o diamante na hora de sortear o free** — localizar a função que escolhe um item da `FREE_UPGRADE_POOL` (busca por `FREE_UPGRADE_POOL` em wave_manager.gd) e, ao montar os candidatos, pular o id do diamante:

```gdscript
	var player := get_tree().get_first_node_in_group("player")
	var diamond_id: String = ""
	if player != null and player.has_method("get_diamond_upgrade_id"):
		diamond_id = player.get_diamond_upgrade_id()
	# ... ao iterar/filtrar os candidatos do FREE_UPGRADE_POOL:
	if String(entry.get("id", "")) == diamond_id:
		continue  # o upgrade do diamante NUNCA vem de graça
```

- [ ] **Step 2: Verificar** — dev panel: forçar o diamante num upgrade que costuma cair no welcome (ex: `damage` não está nos 21, então usar ex `fire_arrow`). Reiniciar várias runs e confirmar (print) que o welcome nunca dá o upgrade do diamante. Expected: o welcome pula o id do diamante.

- [ ] **Step 3: Commit**

```bash
git add scripts/systems/wave_manager.gd
git commit -m "feat(diamante): upgrade do diamante nunca vem como grant gratis"
```

---

## Task 7: 💎 na carta + linha de descrição do buff

**Files:**
- Modify: `scripts/ui/wave_shop.gd` (`_build_card` ~1556; rendering da desc)
- Modify: `assets/i18n/translations.csv` (21 keys `SHOP_DIAMANTE_DESC_*`)

- [ ] **Step 1: Adicionar as 21 keys de descrição no CSV** (texto curto do buff por upgrade)

```
SHOP_DIAMANTE_DESC_PERFURACAO,💎 +30% dano perfurante e hitbox maior já no L1,💎 +30% pierce damage and bigger hitbox from L1,💎 +30% daño perforante y hitbox mayor desde L1,💎 +30% dégâts perçants et hitbox plus grande dès le N1
SHOP_DIAMANTE_DESC_MULTI_ARROW,💎 L3 vira 5 flechas; L4 dispara 10 em 360°,💎 L3 becomes 5 arrows; L4 fires 10 in 360°,💎 L3 pasa a 5 flechas; L4 dispara 10 en 360°,💎 N3 devient 5 flèches; N4 tire 10 en 360°
SHOP_DIAMANTE_DESC_DOUBLE_ARROWS,💎 +30% nas chances de flechas extras,💎 +30% extra-arrow proc chances,💎 +30% en las probabilidades de flechas extra,💎 +30% de chances de flèches bonus
SHOP_DIAMANTE_DESC_SPECTRAL_ARROW,💎 +1 espectral por nível e +10% dano,💎 +1 spectral per level and +10% damage,💎 +1 espectral por nivel y +10% daño,💎 +1 spectrale par niveau et +10% dégâts
SHOP_DIAMANTE_DESC_RICOCHET_ARROW,💎 +1 pulo por nível,💎 +1 bounce per level,💎 +1 rebote por nivel,💎 +1 rebond par niveau
SHOP_DIAMANTE_DESC_CRITICAL_CHANCE,💎 +20% de chance e +10% de dano crítico em todos os níveis,💎 +20% crit chance and +10% crit damage at all levels,💎 +20% prob. y +10% daño crítico en todos los niveles,💎 +20% chances et +10% dégâts critiques à tous les niveaux
SHOP_DIAMANTE_DESC_FIRE_ARROW,💎 +30% na queima e +40% nos rastros,💎 +30% burn and +40% trail damage,💎 +30% quemadura y +40% en los rastros,💎 +30% brûlure et +40% sur les traînées
SHOP_DIAMANTE_DESC_ICE_ARROW,💎 inimigos que morrem congelados explodem (dano+slow),💎 enemies dying frozen explode (damage+slow),💎 enemigos que mueren congelados explotan (daño+lentitud),💎 les ennemis morts gelés explosent (dégâts+ralentissement)
SHOP_DIAMANTE_DESC_CURSE_ARROW,💎 maldição com propagação infinita e decay de aliado 25s,💎 curse spreads infinitely; ally decay 25s,💎 maldición con propagación infinita; decay aliado 25s,💎 malédiction à propagation infinie; déclin allié 25s
SHOP_DIAMANTE_DESC_STONE_ARROW,💎 sem perda de alcance e +1s de stun,💎 no range penalty and +1s stun,💎 sin penalización de alcance y +1s de aturdimiento,💎 sans malus de portée et +1s d'étourdissement
SHOP_DIAMANTE_DESC_TIDE_ARROW,💎 sem o -15% de dano e +10% atk speed no L2,💎 no -15% damage penalty and +10% atk speed at L2,💎 sin el -15% de daño y +10% vel. ataque en L2,💎 sans le -15% de dégâts et +10% de cadence au N2
SHOP_DIAMANTE_DESC_CHAIN_LIGHTNING,💎 +1 alvo por nível na cadeia e no raio,💎 +1 target per level on chain and bolt,💎 +1 objetivo por nivel en cadena y rayo,💎 +1 cible par niveau sur la chaîne et l'éclair
SHOP_DIAMANTE_DESC_GRAVITON,💎 explosão já no L3 e +25% de dano no L4,💎 explosion from L3 and +25% damage at L4,💎 explosión desde L3 y +25% daño en L4,💎 explosion dès le N3 et +25% dégâts au N4
SHOP_DIAMANTE_DESC_BOOMERANG,💎 +50% dano, -30% cooldown e 6 bumerangues no L4,💎 +50% damage, -30% cooldown and 6 boomerangs at L4,💎 +50% daño, -30% enfriamiento y 6 bumeranes en L4,💎 +50% dégâts, -30% recharge et 6 boomerangs au N4
SHOP_DIAMANTE_DESC_TIGER_CLAWS,💎 +1 alvo por nível e +15% de dano,💎 +1 target per level and +15% damage,💎 +1 objetivo por nivel y +15% daño,💎 +1 cible par niveau et +15% dégâts
SHOP_DIAMANTE_DESC_DASH,💎 -30% cooldown e rastro de dano já no L1,💎 -30% cooldown and damage trail from L1,💎 -30% enfriamiento y rastro de daño desde L1,💎 -30% recharge et traînée de dégâts dès le N1
SHOP_DIAMANTE_DESC_ESQUIVANDO,💎 +30% por stack e +50% de esquiva,💎 +30% per stack and +50% dodge,💎 +30% por acumulación y +50% de evasión,💎 +30% par cumul et +50% d'esquive
SHOP_DIAMANTE_DESC_FENDA,💎 -20% cooldown e dano em área no destino,💎 -20% cooldown and AoE damage at the destination,💎 -20% enfriamiento y daño en área en el destino,💎 -20% recharge et dégâts de zone à la destination
SHOP_DIAMANTE_DESC_ADRENALINA,💎 +50% move por HP perdido e +30% atk speed na skill,💎 +50% move per missing HP and +30% atk speed on skill,💎 +50% mov. por vida perdida y +30% vel. ataque en la habilidad,💎 +50% de vitesse par PV perdu et +30% de cadence sur la compétence
SHOP_DIAMANTE_DESC_LIFE_STEAL,💎 +30% de cura, puxa corações no L3 e coração dá move speed,💎 +30% heal, pulls hearts from L3, hearts give move speed,💎 +30% curación, atrae corazones desde L3 y dan vel. mov.,💎 +30% de soin, attire les cœurs dès le N3 et donnent de la vitesse
SHOP_DIAMANTE_DESC_GOLD_MAGNET,💎 puxa moedas no L3 e +1% de drop por nível,💎 pulls coins from L3 and +1% drop per level,💎 atrae monedas desde L3 y +1% de drop por nivel,💎 attire les pièces dès le N3 et +1% de butin par niveau
```

- [ ] **Step 2: Helper de lookup da key** em `wave_shop.gd` (mapeia id → key, em UPPER):

```gdscript
func _diamond_desc_key(id: String) -> String:
	return "SHOP_DIAMANTE_DESC_" + id.to_upper()
```

- [ ] **Step 3: Injetar a linha na desc + overlay** — em `_build_card`, depois de `desc_label.text = desc_text` (~linha 1561), e usando o id da carta:

```gdscript
	var pl := _get_player()
	if pl != null and pl.has_method("get_diamond_upgrade_id") and slot_id_str == pl.get_diamond_upgrade_id() and slot_id_str != "":
		desc_label.text = desc_text + "\n[color=#9ad7ff]" + tr(_diamond_desc_key(slot_id_str)) + "[/color]"
		_add_diamond_overlay(card)
```

> Se o `DescLabel` não for BBCode (`RichTextLabel`), trocar o `[color]` por só o texto e dar destaque via `desc_label.add_theme_color_override` numa segunda label, ou simplesmente concatenar `"\n" + tr(...)`. Verificar o tipo do nó.

- [ ] **Step 4: Broche (TextureRect) no canto superior-direito, vazando a borda**

Usa a arte pronta `diamante_broche.png` (só a camada `item` + brilho branco, 39×42). Fica meio dentro / meio fora da carta no canto superior-direito.

```gdscript
func _add_diamond_overlay(card: Control) -> void:
	if card.get_node_or_null("DiamondBadge") != null:
		return
	card.clip_contents = false  # deixa o broche vazar pra fora da borda da carta
	var badge := TextureRect.new()
	badge.name = "DiamondBadge"
	badge.texture = load("res://assets/Hud/itens/diamante_broche.png")
	badge.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	badge.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	badge.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Canto superior-direito, no limite da carta: ~metade dentro, ~metade fora.
	badge.anchor_left = 1.0
	badge.anchor_right = 1.0
	badge.offset_left = -34.0   # puxa pra dentro (metade na carta)
	badge.offset_top = -22.0    # sobe pra vazar por cima da borda
	badge.offset_right = 24.0   # estende além da borda direita (metade pra fora)
	badge.offset_bottom = 36.0
	card.add_child(badge)
```

> Verificar na execução: se a carta (ou o container pai, ex: `UpgRow`) tiver `clip_contents = true`, o vazamento é cortado — nesse caso adicionar o broche num pai mais acima ou desligar o clip do pai. Ajustar os offsets pra o broche pegar ~metade da carta e ~metade fora, como pedido.

- [ ] **Step 5: Verificar** — dev panel: equipar + ciclar pro `fire_arrow` → abrir shop até a carta de Flecha de Fogo aparecer (sem reroll; pode precisar reabrir shop algumas vezes ou usar "Abrir Shop" repetido). Expected: a carta tem o 💎 no canto e a linha "💎 +30% na queima...".

- [ ] **Step 6: Commit**

```bash
git add scripts/ui/wave_shop.gd assets/i18n/translations.csv
git commit -m "feat(diamante): 💎 + linha de descricao do buff na carta"
```

---

## Task 8: Unlock (passar da wave 14 sem reroll)

**Files:**
- Modify: `scripts/systems/skin_loadout.gd` (const de stat + `record_run` ~824–912)
- Modify: `scripts/player/player.gd` ou onde `record_run` é chamado na morte (montar `run_stats`)

- [ ] **Step 1: Const do stat** em `skin_loadout.gd` (junto dos outros `STAT_*`)

```gdscript
# Flag (0/1): passou da wave 14 numa run sem usar reroll (unlock do Diamante).
const STAT_DIAMANTE_UNLOCK: StringName = &"diamante_unlock_done"
```

- [ ] **Step 2: Gravar no `record_run`** (no mesmo lugar dos outros flags por-run, ~linha 907)

```gdscript
	if int(run_stats.get("max_wave", 0)) > 14 and not bool(run_stats.get("reroll_used", false)) \
			and get_stat(STAT_DIAMANTE_UNLOCK) < 1:
		set_stat(STAT_DIAMANTE_UNLOCK, 1)
```

- [ ] **Step 3: Popular `run_stats`** — onde a run monta o dict `run_stats` passado pro `record_run` (na morte/fim de run), incluir:

```gdscript
	run_stats["reroll_used"] = player.reroll_used_this_run
	# "max_wave" provavelmente já está no run_stats; se não, adicionar a wave alcançada.
```

> Localizar a chamada de `SkinLoadout.record_run(...)` (grep) e o dict `run_stats` ali; garantir que `max_wave` e `reroll_used` estão preenchidos.

- [ ] **Step 4: Resetar a flag no começo da run** — garantir `player.reroll_used_this_run = false` no `_ready()` (já é o default da var, mas confirmar que não persiste entre runs se o player é reusado).

- [ ] **Step 5: Verificar** — jogar (ou via dev: pular pra wave 15) sem reroll e morrer → conferir em `user://settings.cfg [progress] diamante_unlock_done = 1`. Com reroll usado, NÃO grava. Expected: stat só sobe quando passou de 14 sem reroll.

- [ ] **Step 6: Commit**

```bash
git add scripts/systems/skin_loadout.gd scripts/player/player.gd
git commit -m "feat(diamante): unlock - passar da wave 14 sem reroll"
```

---

## Task 9: Mostrar o diamante na build da run (leaderboard modal)

**Files:**
- Modify: onde a build da run é montada (grep por `"upgrades"` + `"items"` na montagem do payload — provavelmente em player.gd/wave_manager ao enviar score) + `scripts/ui/run_build_modal.gd` (`open` ~167)

- [ ] **Step 1: Incluir o id no payload da build** — onde o dict `build` é montado (com `upgrades` e `items`), adicionar:

```gdscript
	build["diamond_upgrade"] = player.get_diamond_upgrade_id()  # "" se sem o item
```

- [ ] **Step 2: Renderizar no modal** — em `run_build_modal.gd open()`, após renderizar upgrades, se houver diamante:

```gdscript
	var diamond_id: String = String(build.get("diamond_upgrade", ""))
	if diamond_id != "":
		_add_subtitle("💎 " + tr("SHOP_UPG_" + diamond_id.to_upper()))
```

> Conferir a key de nome do upgrade (alguns usam `SHOP_UPG_<ID>`, outros `SHOP_<ID>_TITLE`). Usar a mesma que a loja usa pra aquele id.

- [ ] **Step 3: Verificar** — terminar uma run com o Diamante e abrir a build no leaderboard. Expected: linha "💎 <nome do upgrade>" aparece.

- [ ] **Step 4: Commit**

```bash
git add scripts/ui/run_build_modal.gd scripts/player/player.gd
git commit -m "feat(diamante): build da run mostra o upgrade do diamante"
```

---

# FASE 2 — Versões diamante "só número"

> Padrão: em cada função/const de efeito do upgrade, adicionar um ramo `if is_diamond("<id>")`. Verificação: dev panel equipa + cicla pro id, compra o upgrade, observa o valor turbinado (comparar tirando o Diamante).

## Task 10: Perfuração

**Files:** Modify `scripts/player/player.gd` (helpers de perfuração: `_is_piercing_shot`/contador ~1700; mult de dano do pierce; hitbox)

- [ ] **Step 1:** No mult de dano do tiro perfurante, multiplicar por 1.3 quando `is_diamond("perfuracao")`. No threshold do contador (L1/L2 a cada 3→2). Na aplicação da hitbox 1.8×, liberar já no L1 quando diamante.

```gdscript
	# exemplo no calculo do mult de dano do pierce:
	if is_diamond("perfuracao"):
		mult *= 1.3
```

- [ ] **Step 2: Verificar** — dev: diamante=perfuracao, comprar Perfuração, observar dano perfurante maior + hitbox grande já no L1. PASS = visivelmente mais forte que sem o item.
- [ ] **Step 3: Commit** — `git commit -am "feat(diamante): buff Perfuracao"`

## Task 11: Flechas Duplas

**Files:** Modify `scripts/player/player.gd` (chances do double_arrows ~apply/consts)

- [ ] **Step 1:** Multiplicar as chances de proc por ~1.3 quando `is_diamond("double_arrows")` (50→65 / 60→78 / 75+45→90+60 / 90+60+5→95+75+12). Clamp em 1.0.
- [ ] **Step 2: Verificar** — dev: diamante=double_arrows, comprar, observar mais flechas extras com frequência.
- [ ] **Step 3: Commit** — `git commit -am "feat(diamante): buff Flechas Duplas"`

## Task 12: Flecha Espectral

**Files:** Modify `scripts/player/player.gd` (count + dano da espectral)

- [ ] **Step 1:** +1 espectral do L2+ (1/2/3/4) e dano ×1.10 quando `is_diamond("spectral_arrow")`.
- [ ] **Step 2: Verificar** — dev: diamante=spectral_arrow, matar inimigo, contar espectrais.
- [ ] **Step 3: Commit** — `git commit -am "feat(diamante): buff Flecha Espectral"`

## Task 13: Flechas Críticas

**Files:** Modify `scripts/player/player.gd` (`CRIT_CHANCE_BY_LEVEL` ~477 + mult de dano crítico)

- [ ] **Step 1:** Quando `is_diamond("critical_chance")`: +0.20 na chance (clamp 1.0) e +0.10 no mult de dano crítico, em todos os níveis. Como `CRIT_CHANCE_BY_LEVEL` é const, ler via um wrapper:

```gdscript
func _crit_chance() -> float:
	var c: float = CRIT_CHANCE_BY_LEVEL[mini(critical_chance_level - 1, 3)]
	if is_diamond("critical_chance"):
		c = minf(c + 0.20, 1.0)
	return c
# (substituir os usos diretos de CRIT_CHANCE_BY_LEVEL[...] por _crit_chance())
```

- [ ] **Step 2: Verificar** — dev: diamante=critical_chance, comprar L1, observar muito mais crit + dano maior.
- [ ] **Step 3: Commit** — `git commit -am "feat(diamante): buff Flechas Criticas"`

## Task 14: Flecha de Fogo

**Files:** Modify `scripts/player/player.gd` (`_fire_burn_dps` ~1756; dano dos rastros de fogo/flecha)

- [ ] **Step 1:** Em `_fire_burn_dps`, `if is_diamond("fire_arrow"): dps *= 1.3`. Nos dois rastros (fogo + flecha), dano ×1.4.
- [ ] **Step 2: Verificar** — dev: diamante=fire_arrow, comprar, observar queima/rastros mais fortes.
- [ ] **Step 3: Commit** — `git commit -am "feat(diamante): buff Flecha de Fogo"`

## Task 15: Disparo de Pedra

**Files:** Modify `scripts/player/player.gd` (`_stone_direct_dmg_mult` ~2106; `_stone_speed`/range; `_stone_stun_duration`)

- [ ] **Step 1:** Quando `is_diamond("stone_arrow")`: remover o downgrade de alcance (usar lifetime/range normal da flecha em vez do reduzido da pedra) e `_stone_stun_duration` +1.0s em todos os níveis. (Manter o mult de dano direto atual; o foco aqui é range+stun.)
- [ ] **Step 2: Verificar** — dev: diamante=stone_arrow, comprar, observar flecha de pedra com alcance normal + stun mais longo.
- [ ] **Step 3: Commit** — `git commit -am "feat(diamante): buff Disparo de Pedra"`

## Task 16: Fúria da Maré

**Files:** Modify `scripts/player/player.gd` (`_mare_damage_factor`/−15%; `TIDE_ATK_SPEED_BY_LEVEL` ~141)

- [ ] **Step 1:** Quando `is_diamond("tide_arrow")`: zerar o −15% de dano de flecha (factor = 1.0) e o L2 dar +0.10 de atk speed a mais (20%→30% no L2).
- [ ] **Step 2: Verificar** — dev: diamante=tide_arrow, comprar L2, observar sem penalidade de dano e atk speed maior.
- [ ] **Step 3: Commit** — `git commit -am "feat(diamante): buff Furia da Mare"`

## Task 17: Cadeia de Raios

**Files:** Modify `scripts/player/player.gd` (count de alvos da cadeia + do raio automático L2+)

- [ ] **Step 1:** Quando `is_diamond("chain_lightning")`: +1 alvo por nível tanto no salto da cadeia quanto no auto-bolt (L2+).
- [ ] **Step 2: Verificar** — dev: diamante=chain_lightning, comprar, contar saltos.
- [ ] **Step 3: Commit** — `git commit -am "feat(diamante): buff Cadeia de Raios"`

## Task 18: Gráviton

**Files:** Modify `scripts/player/player.gd` (`_graviton_explosion_damage` ~1732)

- [ ] **Step 1:** Reescrever pra: explosão a partir do L3 e +25% no L4 quando diamante:

```gdscript
func _graviton_explosion_damage() -> float:
	var diamond: bool = is_diamond("graviton")
	var min_lvl: int = 3 if diamond else 4
	if graviton_level >= min_lvl:
		var base: float = 20.0
		if diamond and graviton_level >= 4:
			base *= 1.25
		return _apply_dmg_pct_to_dps(base)
	return 0.0
```

- [ ] **Step 2: Verificar** — dev: diamante=graviton, comprar L3, observar explosão de dano (hoje só no L4).
- [ ] **Step 3: Commit** — `git commit -am "feat(diamante): buff Graviton"`

## Task 19: Boomerang

**Files:** Modify `scripts/player/player.gd` (`BOOMERANG_DAMAGE_BY_LEVEL` ~466; cooldown; count L4)

- [ ] **Step 1:** Quando `is_diamond("boomerang")`: dano ×1.5, cooldown ×0.7, e L4 lança 6 em vez de 4. Ler dano/cd via wrappers que aplicam o fator.
- [ ] **Step 2: Verificar** — dev: diamante=boomerang, comprar L4, contar 6 bumerangues + dano maior.
- [ ] **Step 3: Commit** — `git commit -am "feat(diamante): buff Boomerang"`

## Task 20: Garras de Tigre

**Files:** Modify `scripts/player/player.gd` (`TIGER_CLAWS_TARGETS` ~461; `TIGER_CLAWS_DMG` ~462)

- [ ] **Step 1:** Quando `is_diamond("tiger_claws")`: +1 alvo por nível a partir do L2 (1/3/3/5) e +15% de dano por arranhão. Ler via wrappers.
- [ ] **Step 2: Verificar** — dev: diamante=tiger_claws, comprar L2, contar 3 alvos.
- [ ] **Step 3: Commit** — `git commit -am "feat(diamante): buff Garras de Tigre"`

## Task 21: Esquivando

**Files:** Modify `scripts/player/player.gd` (`_esquivando_stack_pct` ~3354; `_esquivando_dodge_chance` ~3366)

- [ ] **Step 1:** Quando `is_diamond("esquivando")`: stack pct ×1.3 e dodge ×1.5.

```gdscript
func _esquivando_dodge_chance() -> float:
	if esquivando_level <= 0:
		return 0.0
	var d: float = ESQUIVANDO_DODGE_BY_LEVEL[mini(esquivando_level - 1, ESQUIVANDO_LEVEL_MAX - 1)]
	if is_diamond("esquivando"):
		d *= 1.5
	return d
```

- [ ] **Step 2: Verificar** — dev: diamante=esquivando, comprar, abrir shop e ver o stat "Esquiva" maior (StatsCard).
- [ ] **Step 3: Commit** — `git commit -am "feat(diamante): buff Esquivando"`

## Task 22: Adrenalina

**Files:** Modify `scripts/player/player.gd` (`_adrenalina_move_buff` ~3515 / `ADRENALINA_MS_PER_HP_BY_LEVEL` ~426; `ADRENALINA_ATK_BY_LEVEL` ~430)

- [ ] **Step 1:** Quando `is_diamond("adrenalina")`: rate de move por HP ×1.5 e atk speed da skill ×1.3.
- [ ] **Step 2: Verificar** — dev: diamante=adrenalina, perder HP, observar move speed subindo mais rápido.
- [ ] **Step 3: Commit** — `git commit -am "feat(diamante): buff Adrenalina"`

## Task 23: Ímã de Ouro (Chuva de Coins)

**Files:** Modify `scripts/player/player.gd` (chance de drop de ouro por nível; início do ímã)

- [ ] **Step 1:** Quando `is_diamond("gold_magnet")`: +1% de chance de drop por nível a partir do L2 (acumulando) e puxar moedas já a partir do L3 (mantém comportamento atual se já é L3).
- [ ] **Step 2: Verificar** — dev: diamante=gold_magnet, comprar, observar mais drops/ímã.
- [ ] **Step 3: Commit** — `git commit -am "feat(diamante): buff Ima de Ouro"`

---

# FASE 3 — Versões diamante "mecânica nova" (🔧)

## Task 24: Ricochete — +1 pulo por nível

**Files:** Modify `scripts/player/player.gd` + `scripts/skills/arrow.gd` (onde o nº de pulos do ricochete é decidido)

- [ ] **Step 1:** Onde os hops do ricochete são definidos por nível (1/1/2/2), somar +1 quando `is_diamond("ricochet_arrow")` (2/2/3/3). Passar o flag pra flecha no spawn (ex: `arrow.ricochet_hops += 1`).
- [ ] **Step 2: Verificar** — dev: diamante=ricochet_arrow, comprar, contar pulos extras.
- [ ] **Step 3: Commit** — `git commit -am "feat(diamante): buff Ricochete (+1 pulo)"`

## Task 25: Múltiplas Flechas — L3=5, L4=10 em 360°

**Files:** Modify `scripts/player/player.gd` (montagem do volley do multi_arrow)

- [ ] **Step 1:** Quando `is_diamond("multi_arrow")`: no L3 usar o leque de 5 (igual L4 atual); no L4 montar 10 flechas distribuídas em 360° (ângulos a cada 36°) a partir da direção de mira. Reusar o `_spawn_arrow`/volley com os ângulos calculados.

```gdscript
	if is_diamond("multi_arrow") and multi_arrow_level >= 4:
		var n := 10
		for i in n:
			var ang := aim_dir.angle() + TAU * float(i) / float(n)
			# spawn arrow na direção Vector2.from_angle(ang) com dmg_mult do leque
```

- [ ] **Step 2: Verificar** — dev: diamante=multi_arrow, comprar L4, atirar e ver 10 flechas em círculo.
- [ ] **Step 3: Commit** — `git commit -am "feat(diamante): buff Multi Arrow (10 em 360)"`

## Task 26: Dash — rastro no L1 + dano no L2

**Files:** Modify `scripts/player/player.gd` (lógica do rastro do dash por nível; cd já coberto se feito como número — senão incluir aqui o ×0.7)

- [ ] **Step 1:** Quando `is_diamond("dash")`: cooldown ×0.7 (4.4/3.7/3.4/3.0), spawnar o rastro já a partir do L1 (hoje L2) e +50% de dano no rastro a partir do L2.
- [ ] **Step 2: Verificar** — dev: diamante=dash, comprar L1, dar dash e ver rastro causando dano.
- [ ] **Step 3: Commit** — `git commit -am "feat(diamante): buff Dash (rastro L1 + dano L2)"`

## Task 27: Fenda — dano em área no destino

**Files:** Modify `scripts/player/player.gd` (lógica da Fenda: cooldown, dano do corte, e novo AoE no destino)

- [ ] **Step 1:** Quando `is_diamond("fenda")`: cooldown ×0.8 (16/14.4/12.8/11.2), dano do corte ×1.2, o dano primário do corte já vale no L1 (hoje L2+), e ao teleportar aplicar um dano em ÁREA no ponto de destino (mesmo dano do corte). Reusar a hitbox/dano do corte existente, instanciando no destino.
- [ ] **Step 2: Verificar** — dev: diamante=fenda, comprar L1, teleportar pra cima de inimigos e ver o dano em área no destino.
- [ ] **Step 3: Commit** — `git commit -am "feat(diamante): buff Fenda (AoE no destino)"`

## Task 28: Fica Frio — inimigo congelado morto explode

**Files:** Modify `scripts/player/player.gd` (`_ice_*` consts/dps) + onde o inimigo morre / o estado de congelado é checado (enemy death handler ou no ice apply). Possivelmente `scripts/enemies/*` base de inimigo.

- [ ] **Step 1:** Quando `is_diamond("ice_arrow")`: ao morrer um inimigo que está congelado, disparar uma explosão (dano em área + slow em área) no ponto da morte; e Frostwisp +10% de dano. Implementar via um sinal/hook na morte do inimigo checando o estado de freeze + flag do player. Reusar a AoE de slow existente do gelo.
- [ ] **Step 2: Verificar** — dev: diamante=ice_arrow, congelar e matar inimigo, ver explosão de slow/dano.
- [ ] **Step 3: Commit** — `git commit -am "feat(diamante): buff Fica Frio (explosao ao morrer congelado)"`

## Task 29: Maldição — propagação infinita + decay 25s

**Files:** Modify `scripts/player/player.gd` ou onde a propagação da maldição (75px) e o decay do aliado (12s) são definidos (ver memory: curse propagation 75px, curse_ally 12s)

- [ ] **Step 1:** Quando `is_diamond("curse_arrow")`: range de propagação da maldição = infinito (ou um valor enorme tipo 99999) e o decay dos aliados convertidos = 25s (em vez de 12s).
- [ ] **Step 2: Verificar** — dev: diamante=curse_arrow, amaldiçoar, ver a maldição pulando entre inimigos distantes.
- [ ] **Step 3: Commit** — `git commit -am "feat(diamante): buff Maldicao (propagacao infinita)"`

## Task 30: Mestre da Cura — coração no L3 + move speed

**Files:** Modify `scripts/player/player.gd` (`_life_steal_*`: heal %, pull de coração, novo buff de move speed no pickup) + onde o coração é coletado

- [ ] **Step 1:** Quando `is_diamond("life_steal")`: cura por hit ×1.3, puxar corações já a partir do L3 (hoje L4), e cada coração coletado dá +7% de move speed por 1s (buff temporário, reusar o padrão de buff temporário tipo capivara/esquivando).
- [ ] **Step 2: Verificar** — dev: diamante=life_steal, pegar coração, ver o burst de move speed.
- [ ] **Step 3: Commit** — `git commit -am "feat(diamante): buff Mestre da Cura (coracao da move speed)"`

---

## Self-review (preencher na execução)

- [ ] Todas as 21 versões diamante batem com a Seção 2 do spec.
- [ ] `_diamond_upgrade_id == ""` → jogo idêntico ao atual (testar uma run sem o item).
- [ ] Item com checklist de integração de upgrade novo NÃO se aplica (é item, não upgrade) — mas conferir: aparece no inventário, no build da run, e a desc no card.
- [ ] Arte do ícone do item + 💎 trocados quando chegarem (placeholder até lá).
- [ ] Bump de versão em `project.godot` só no deploy.
