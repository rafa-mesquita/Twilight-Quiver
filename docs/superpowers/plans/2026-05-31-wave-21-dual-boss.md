# Wave 21 — Confronto Duplo (Gorilla + Duskrose) — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Adicionar uma wave de boss (wave 21) onde o jogador enfrenta o Gorilla (Mage Monkey) e a Duskrose ao mesmo tempo na arena da Duskrose, com duas barras de HP, cinematic de 2 alvos e trilha própria em loop de 2 faixas.

**Architecture:** Estende o sistema de waves de boss já existente no `wave_manager.gd` (que hoje trata waves 7 e 14). A wave 21 (`boss_dual_wave`) reusa a arena/maquinaria da wave 14 (Duskrose) via um helper `_uses_duskrose_arena(num)`. Mudanças genuinamente novas (dois bosses, escopo do escudo do Gorilla, desligar dark balls da Duskrose, duas barras de HP, sequenciador de música, cinematic multi-alvo) ficam em helpers focados. A lógica das waves 7/14 NÃO é alterada.

**Tech Stack:** Godot 4 / GDScript. **Sem harness de testes automatizados** — verificação é manual via o botão dev "Boss W21" (criado na Tarefa 1) e observação em jogo no editor.

**Spec:** `docs/superpowers/specs/2026-05-31-wave-21-dual-boss-design.md`

---

## File Structure

| Arquivo | Responsabilidade | Ação |
|---|---|---|
| `scripts/systems/wave_manager.gd` | Trigger da wave, spawn dos bosses, HP, arena swap, drops, música, cinematic | Modificar |
| `scripts/enemies/mage_monkey.gd` | Escopar o escudo do Gorilla pra contar só os próprios magos | Modificar |
| `scripts/enemies/duskrose.gd` | Desligar o summon de dark ball na wave 21 | Modificar |
| `scripts/ui/hud.gd` | Suporte a 2 barras de HP de boss simultâneas | Modificar |
| `scenes/ui/hud.tscn` | Segunda instância de BossHpBar | Modificar (editor) |
| `scripts/ui/dev_panel.gd` | Conectar botão "Boss W21" | Modificar |
| `scenes/ui/dev_panel.tscn` | Botão "Boss W21" na WaveBar | Modificar (editor) |
| `scripts/ui/hud.gd` (`play_boss_intro`) | Path de overlay pra wave 21 | Modificar |

---

## Task 1: Wave 21 alcançável — dois bosses spawnam na arena da Duskrose

**Objetivo:** Slice vertical testável — pular pra wave 21 pelo dev panel e ver os dois bosses na arena da Duskrose, estruturas limpas, a luta acontecendo e a wave terminando quando ambos morrem.

**Files:**
- Modify: `scripts/systems/wave_manager.gd`
- Modify: `scripts/ui/dev_panel.gd:78-82`
- Modify (editor): `scenes/ui/dev_panel.tscn` (WaveBar/Row)

- [ ] **Step 1: Adicionar o export `boss_dual_wave` e os exports de música**

Em `scripts/systems/wave_manager.gd`, logo após a linha 72 (`@export var boss_redux_extra_mult: float = 1.75`), adicionar:

```gdscript
# Wave 21 (boss duplo): Gorilla (Mage Monkey) no centro + Duskrose no topo, na
# arena da Duskrose. Reusa a maquinaria de boss da wave 14 via _uses_duskrose_arena.
@export var boss_dual_wave: int = 21
# Trilha da wave 21: sequência de 2 faixas em loop (faixa 1 → faixa 2 → faixa 1…).
@export var boss_dual_music_1: AudioStream = preload("res://audios/musics/Boss 21 wave.mp3")
@export var boss_dual_music_2: AudioStream = preload("res://audios/musics/Boss Wve 21 - 2.mp3")
```

- [ ] **Step 2: Incluir a wave 21 em `_is_boss_wave` e criar `_uses_duskrose_arena`**

Substituir a função em `scripts/systems/wave_manager.gd:809-810`:

```gdscript
func _is_boss_wave(num: int) -> bool:
	return num == 7 or num == boss_redux_wave
```

por:

```gdscript
func _is_boss_wave(num: int) -> bool:
	return num == 7 or num == boss_redux_wave or num == boss_dual_wave


# Waves que rodam na arena temática da Duskrose (swap de mapa, sem estruturas).
func _uses_duskrose_arena(num: int) -> bool:
	return num == boss_redux_wave or num == boss_dual_wave
```

- [ ] **Step 3: Config de spawn da wave 21 (dois bosses + horda inicial de magos)**

Em `scripts/systems/wave_manager.gd`, dentro de `_build_wave_config`, logo após o bloco da wave 14 (que termina em `}` na linha ~472, fechando o `if num == boss_redux_wave:`), adicionar:

```gdscript
	# Wave 21: BOSS DUPLO — Gorilla (Mage Monkey) no centro + Duskrose no topo.
	# Gorilla mantém o escudo (invulnerável enquanto tiver mago vivo); horda
	# inicial pequena pra abrir ele ser viável sob pressão da Duskrose. Duskrose
	# invoca Rose Monsters dinamicamente (config só o boss inicial dela).
	if num == boss_dual_wave:
		return {
			"mage_monkey": {"alive_target": 1, "total": 1},
			"duskrose": {"alive_target": 1, "total": 1},
			"mage": {"alive_target": 3, "total": 4},
		}
```

- [ ] **Step 4: Reusar a arena da Duskrose no swap de mapa (prespawn)**

Em `scripts/systems/wave_manager.gd:1697`, trocar:

```gdscript
	if wave_number == boss_redux_wave:
		_set_main_map_hidden(true)
		_set_main_entities_props_hidden(true)
		_spawn_wave14_map(world)
		_set_wave14_props_hidden(true)
```

por:

```gdscript
	if _uses_duskrose_arena(wave_number):
		_set_main_map_hidden(true)
		_set_main_entities_props_hidden(true)
		_spawn_wave14_map(world)
		_set_wave14_props_hidden(true)
```

- [ ] **Step 5: Limpar estruturas na wave 21 + não respawnar estruturas na arena**

Em `scripts/systems/wave_manager.gd:389`, trocar:

```gdscript
	if wave_number == boss_redux_wave:
		_clear_alive_structures_for_boss_wave()
```

por:

```gdscript
	if _uses_duskrose_arena(wave_number):
		_clear_alive_structures_for_boss_wave()
```

E em `scripts/systems/wave_manager.gd:1208`, trocar:

```gdscript
	if wave_number == boss_redux_wave:
		return
```

por:

```gdscript
	if _uses_duskrose_arena(wave_number):
		return
```

(`_cleanup_duskrose_decoration` em 985-995 já restaura o mapa incondicionalmente no fim da wave — nenhuma mudança necessária ali.)

- [ ] **Step 6: Adicionar o botão "Boss W21" na cena do dev panel**

No editor do Godot, abrir `scenes/ui/dev_panel.tscn`. Selecionar o node `WaveBar/Row` (HBoxContainer). Duplicar o botão `Wave14Btn` (Ctrl+D), renomear a cópia para `Wave21Btn`, e ajustar no Inspector:
- `text` = `Boss W21`
- `theme_override_colors/font_color` = `Color(1, 0.45, 0.45, 1)` (vermelho, distinto do roxo do W14)
- (manter `custom_minimum_size = Vector2(0, 40)`, font e font_size = 25 iguais aos outros)

Garantir que `Wave21Btn` fica como último filho de `WaveBar/Row`. Salvar a cena.

- [ ] **Step 7: Conectar o botão Boss W21 no dev_panel.gd**

Em `scripts/ui/dev_panel.gd:82`, logo após:

```gdscript
	$WaveBar/Row/Wave14Btn.pressed.connect(_simulate_wave.bind(14))
```

adicionar:

```gdscript
	$WaveBar/Row/Wave21Btn.pressed.connect(_simulate_wave.bind(21))
```

- [ ] **Step 8: Verificação manual**

Rodar o jogo no editor. Clicar no botão **Boss W21** na WaveBar (canto inferior-esquerdo). Observar:
- O mapa troca pra arena da Duskrose (visual temático).
- O Gorilla aparece no centro e a Duskrose no topo (ela desliza pro topo).
- As estruturas compradas (se houver) somem.
- A luta roda; ao matar os dois bosses (e seus súditos serem limpos pela morte de cada um), a wave termina e abre a shop.

Esperado: dois bosses presentes e funcionais. (HP, escudo, dark balls, barras, cinematic e música ainda NÃO estão finais — próximas tarefas.)

- [ ] **Step 9: Commit**

```bash
git add scripts/systems/wave_manager.gd scripts/ui/dev_panel.gd scenes/ui/dev_panel.tscn
git commit -m "feat(wave21): wave de boss duplo alcançável na arena da Duskrose + botão dev

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 2: HP dos bosses (6000 / 8000) + drops

**Objetivo:** Gorilla com 6000 HP, Duskrose com 8000 HP na wave 21, e cada boss dropando ~60% do gold de um boss solo.

**Files:**
- Modify: `scripts/systems/wave_manager.gd`

- [ ] **Step 1: Const do multiplicador de gold da wave 21**

Em `scripts/systems/wave_manager.gd`, logo após a linha 84 (`const BOSS_REDUX_GOLD_MULT: float = 2.45`), adicionar:

```gdscript
# Wave 21 (boss duplo): cada boss dropa ~60% do boss solo da wave 14 (são dois,
# então a soma fica generosa sem dobrar). Tunável.
const BOSS_DUAL_GOLD_MULT: float = 1.5
```

- [ ] **Step 2: HP override no `_prespawn_boss_wave_entities`**

Em `scripts/systems/wave_manager.gd`, no bloco do prespawn (linhas 1676-1684), substituir:

```gdscript
			if wave_number != 7 or type_key == "mage_monkey":
				_apply_wave_scaling(enemy)
				# Override pro boss Duskrose (wave 14): HP fixo 8500.
				if wave_number == boss_redux_wave and type_key == "duskrose" and "max_hp" in enemy:
					enemy.max_hp = 8500.0
			if wave_number == boss_redux_wave and (type_key == "mage_monkey" or type_key == "duskrose") and BOSS_REDUX_GOLD_MULT > 1.0:
				if "gold_drop_min" in enemy:
					enemy.gold_drop_min = int(round(float(enemy.gold_drop_min) * BOSS_REDUX_GOLD_MULT))
				if "gold_drop_max" in enemy:
					enemy.gold_drop_max = int(round(float(enemy.gold_drop_max) * BOSS_REDUX_GOLD_MULT))
				if "gold_drop_pivot" in enemy:
					enemy.gold_drop_pivot = int(round(float(enemy.gold_drop_pivot) * BOSS_REDUX_GOLD_MULT))
```

por:

```gdscript
			if wave_number != 7 or type_key == "mage_monkey":
				_apply_wave_scaling(enemy)
				# Override pro boss Duskrose (wave 14): HP fixo 8500.
				if wave_number == boss_redux_wave and type_key == "duskrose" and "max_hp" in enemy:
					enemy.max_hp = 8500.0
				# Wave 21 (boss duplo): HP fixo Gorilla 6000 / Duskrose 8000.
				if wave_number == boss_dual_wave and "max_hp" in enemy:
					if type_key == "mage_monkey":
						enemy.max_hp = 6000.0
					elif type_key == "duskrose":
						enemy.max_hp = 8000.0
			var gold_mult: float = 0.0
			if wave_number == boss_redux_wave:
				gold_mult = BOSS_REDUX_GOLD_MULT
			elif wave_number == boss_dual_wave:
				gold_mult = BOSS_DUAL_GOLD_MULT
			if gold_mult > 1.0 and (type_key == "mage_monkey" or type_key == "duskrose"):
				if "gold_drop_min" in enemy:
					enemy.gold_drop_min = int(round(float(enemy.gold_drop_min) * gold_mult))
				if "gold_drop_max" in enemy:
					enemy.gold_drop_max = int(round(float(enemy.gold_drop_max) * gold_mult))
				if "gold_drop_pivot" in enemy:
					enemy.gold_drop_pivot = int(round(float(enemy.gold_drop_pivot) * gold_mult))
```

- [ ] **Step 3: HP override no `_apply_wave_scaling`**

Em `scripts/systems/wave_manager.gd:679-687`, logo após o bloco do override da Duskrose (`enemy.max_hp = 8500.0`), adicionar:

```gdscript
		# Override pros bosses da wave 21 (boss duplo): Gorilla 6000 / Duskrose 8000.
		if wave_number == boss_dual_wave and "max_hp" in enemy:
			if type_key == "mage_monkey":
				enemy.max_hp = 6000.0
			elif type_key == "duskrose":
				enemy.max_hp = 8000.0
```

(`type_key` está no escopo de `_apply_wave_scaling` — o override da Duskrose logo acima, linha 686, já o usa: `if wave_number == boss_redux_wave and type_key == "duskrose"`.)

- [ ] **Step 4: Verificação manual**

Rodar, clicar **Boss W21**. Com o dev mode de dano (ou batendo), confirmar que:
- Quando o Gorilla fica vulnerável (sem magos), a barra/HP dele reflete ~6000.
- A Duskrose começa com ~8000.

(As barras finais vêm na Tarefa 6; por ora dá pra inspecionar via o painel de dano/HP do dev ou o print de HP.)

- [ ] **Step 5: Commit**

```bash
git add scripts/systems/wave_manager.gd
git commit -m "feat(wave21): HP fixo 6000/8000 e drops ~60% por boss

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 3: Escopar o escudo do Gorilla (não contar a Duskrose nem Rose Monsters)

**Objetivo:** Na wave 21 o escudo do Gorilla só deve ser sustentado pelos magos DELE — não pela Duskrose nem pelos Rose Monsters dela (senão o escudo nunca abre enquanto a Duskrose viver).

**Files:**
- Modify: `scripts/enemies/mage_monkey.gd:273-287`

- [ ] **Step 1: Excluir o outro boss e seus súditos da adoção de minions**

Em `scripts/enemies/mage_monkey.gd`, na função `_collect_existing_minions`, substituir:

```gdscript
func _collect_existing_minions() -> void:
	# Adopta como minion qualquer enemy vivo que NÃO seja o próprio boss. Isso
	# inclui os magos pré-spawnados pelo wave_manager + os que o boss invoca,
	# e qualquer mago novo que o wave_manager adicione ao longo da wave.
	for e in get_tree().get_nodes_in_group("enemy"):
		if not is_instance_valid(e):
			continue
		if e == self or (e as Node).is_in_group("mage_monkey"):
			continue
		if e in _minions:
			continue
		_minions.append(e)
		# Marca no grupo boss_minion pra outros sistemas (ex: cleanup) reconhecerem.
		if not (e as Node).is_in_group("boss_minion"):
			(e as Node).add_to_group("boss_minion")
```

por:

```gdscript
func _collect_existing_minions() -> void:
	# Adopta como minion qualquer enemy vivo que NÃO seja o próprio boss. Isso
	# inclui os magos pré-spawnados pelo wave_manager + os que o boss invoca,
	# e qualquer mago novo que o wave_manager adicione ao longo da wave.
	# EXCEÇÃO (wave 21 boss duplo): NÃO adota a Duskrose nem os Rose Monsters
	# dela — senão o escudo do Gorilla ficaria preso pelos súditos do outro boss.
	for e in get_tree().get_nodes_in_group("enemy"):
		if not is_instance_valid(e):
			continue
		var en := e as Node
		if e == self or en.is_in_group("mage_monkey"):
			continue
		if en.is_in_group("boss") or en.is_in_group("duskrose") or en.is_in_group("rose_monster"):
			continue
		if e in _minions:
			continue
		_minions.append(e)
		# Marca no grupo boss_minion pra outros sistemas (ex: cleanup) reconhecerem.
		if not en.is_in_group("boss_minion"):
			en.add_to_group("boss_minion")
```

(O Gorilla NÃO está no grupo `boss`? Conferir: o Mage Monkey adiciona-se a `boss` no `_ready`. A checagem `e == self` já o exclui ANTES da checagem de grupo `boss`, então excluir `boss` aqui remove só a Duskrose. Confirmar que o Gorilla cai no `e == self` — sim, `self` é o próprio node.)

- [ ] **Step 2: Verificação manual**

Rodar **Boss W21**. Deixar a Duskrose e Rose Monsters vivos e matar TODOS os magos do Gorilla. Observar:
- Assim que o último MAGO do Gorilla morre, ele sai de defesa (anim "idle") e fica vulnerável — mesmo com a Duskrose e Rose Monsters vivos na tela.
- Bater no Gorilla nesse estado causa dano (HP cai).

Esperado: o escudo abre quando só os magos dele acabam, ignorando os súditos da Duskrose.

- [ ] **Step 3: Commit**

```bash
git add scripts/enemies/mage_monkey.gd
git commit -m "fix(wave21): escudo do Gorilla ignora Duskrose e Rose Monsters

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 4: Desligar o summon de Dark Ball da Duskrose na wave 21

**Objetivo:** Sem dark balls na wave 21 (requisito do design). A Duskrose invoca dark balls por conta própria — desligar isso só na wave 21.

**Files:**
- Modify: `scripts/enemies/duskrose.gd`

- [ ] **Step 1: Adicionar um flag pra desabilitar o dark ball**

Em `scripts/enemies/duskrose.gd`, junto aos exports de dark ball (após a linha 61, `@export var dark_ball_summon_y_max: float = 230.0`), adicionar:

```gdscript
# Wave 21 (boss duplo): dark balls são desligados (setado pelo wave_manager).
var dark_ball_summon_enabled: bool = true
```

- [ ] **Step 2: Gatear o summon no flag**

Em `scripts/enemies/duskrose.gd`, na função `_cast_dark_ball_summon()` (linha 814), adicionar o guard como PRIMEIRA linha do corpo:

```gdscript
func _cast_dark_ball_summon() -> void:
	if not dark_ball_summon_enabled:
		return
	# ... (resto do corpo existente inalterado: checa dark_ball_scene, loop de
	#      dark_ball_summon_count spawns, etc.)
```

(O tick do cooldown em `_dark_ball_cd` nas linhas 381-383 continua rodando, mas `_cast_dark_ball_summon` vira no-op quando o flag está off — nenhum dark ball spawna.)

- [ ] **Step 3: Setar o flag = false na wave 21 (lado do wave_manager)**

Em `scripts/systems/wave_manager.gd`, no `_prespawn_boss_wave_entities`, dentro do loop que instancia os enemies (após `var enemy: Node2D = info["scene"].instantiate()` e antes de `world.add_child(enemy)`), adicionar:

```gdscript
			# Wave 21: a Duskrose não invoca dark balls (requisito do design).
			if wave_number == boss_dual_wave and type_key == "duskrose" and "dark_ball_summon_enabled" in enemy:
				enemy.dark_ball_summon_enabled = false
```

- [ ] **Step 4: Verificação manual**

Rodar **Boss W21** e deixar a luta correr ~30-60s (tempo que normalmente a Duskrose já teria invocado dark balls na wave 14). Observar: **nenhum dark ball** aparece. Comparar com **Boss W14** (onde dark balls aparecem) pra confirmar a diferença.

- [ ] **Step 5: Commit**

```bash
git add scripts/enemies/duskrose.gd scripts/systems/wave_manager.gd
git commit -m "feat(wave21): Duskrose não invoca dark balls no confronto duplo

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 5: Player começa no canto inferior-esquerdo

**Objetivo:** Na wave 21, o player spawna no canto inferior-esquerdo da arena (e não no meio-inferior como na wave 14). Também garantir explicitamente que a regra de dark_ball wave não vale pra waves de boss.

**Files:**
- Modify: `scripts/systems/wave_manager.gd:854` (player spawn) e `:585` (dark_ball guard)

- [ ] **Step 1: Posição do player na wave 21 (inferior-esquerda)**

Em `scripts/systems/wave_manager.gd`, dentro de `_prepare_wave7_spawn_assignments`, no fim da função (após o bloco `if wave_number == boss_redux_wave:` que termina em ~865), adicionar:

```gdscript
	# Wave 21 (boss duplo): player no canto inferior-ESQUERDO da arena (Gorilla
	# no centro, Duskrose no topo). X = menor X entre os spawn points; Y = média
	# dos spawn points "south" (metade inferior do mapa).
	if wave_number == boss_dual_wave:
		var min_x: float = INF
		for p in spawn_points:
			if p.global_position.x < min_x:
				min_x = p.global_position.x
		var south_y2: float = 320.0
		var south_count2: int = 0
		var south_y_sum2: float = 0.0
		for p in spawn_points:
			if p.global_position.y > _wave7_boss_center.y:
				south_y_sum2 += p.global_position.y
				south_count2 += 1
		if south_count2 > 0:
			south_y2 = south_y_sum2 / float(south_count2)
		if min_x != INF:
			_wave7_player_spawn = Vector2(min_x, south_y2)
```

- [ ] **Step 2: dark_ball guard explícito (não em waves de boss)**

Em `scripts/systems/wave_manager.gd:585`, trocar:

```gdscript
	var dark_ball_wave: bool = num == 6 or (num >= 9 and num % 3 == 0)
```

por:

```gdscript
	var dark_ball_wave: bool = (num == 6 or (num >= 9 and num % 3 == 0)) and not _is_boss_wave(num)
```

- [ ] **Step 3: Verificação manual**

Rodar **Boss W21**. Após o cinematic/spawn, confirmar que o player aparece no **canto inferior-esquerdo** da arena (não no centro-baixo). Confirmar (já coberto pela Tarefa 4, reforço aqui) que nenhum dark_ball "normal" spawna.

- [ ] **Step 4: Commit**

```bash
git add scripts/systems/wave_manager.gd
git commit -m "feat(wave21): player spawna no canto inferior-esquerdo + guard dark_ball em boss waves

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 6: Duas barras de HP de boss lado a lado na base

**Objetivo:** Quando há 2 bosses (wave 21), mostrar duas barras menores lado a lado na base da tela (Gorilla + Duskrose). Quando há 1 boss (waves 7/14), comportamento atual intacto.

**Files:**
- Modify (editor): `scenes/ui/hud.tscn` (segunda instância de BossHpBar)
- Modify: `scripts/ui/hud.gd`

- [ ] **Step 1: Adicionar a segunda barra na cena do HUD**

No editor, abrir `scenes/ui/hud.tscn`. Selecionar o node `BossHpBar`. Duplicá-lo (Ctrl+D) e nomear a cópia `BossHpBar2`, irmão do `BossHpBar` (mesmo pai). Deixar `visible = false` no `BossHpBar2` (Inspector). Salvar a cena.

(A posição/scale das duas barras é controlada por código no Step 4, então os offsets do .tscn não importam aqui — só garantir que `BossHpBar2` existe com a mesma estrutura interna: `ArtScale/Fill`, `Label`, `NameLabel`.)

- [ ] **Step 2: @onready refs da segunda barra**

Em `scripts/ui/hud.gd`, logo após a linha 123 (`@onready var boss_name_label: Label = $BossHpBar/NameLabel`), adicionar:

```gdscript
@onready var boss_hp_bar2: Control = $BossHpBar2
@onready var boss_hp_fill2: ColorRect = $BossHpBar2/ArtScale/Fill
@onready var boss_hp_label2: Label = $BossHpBar2/Label
@onready var boss_name_label2: Label = $BossHpBar2/NameLabel
# Layout das barras duplas (wave 21) já aplicado nesta sessão? (aplica 1×).
var _dual_bars_laid_out: bool = false
```

- [ ] **Step 3: Roteamento — 2 bosses vs 1 boss em `_update_boss_hp_bar`**

Em `scripts/ui/hud.gd`, no INÍCIO da função `_update_boss_hp_bar` (linha 372), inserir o roteamento antes da lógica existente:

```gdscript
func _update_boss_hp_bar() -> void:
	# Conta bosses vivos. 2+ → modo barra dupla (wave 21). Senão, modo single
	# (comportamento atual das waves 7/14).
	var bosses: Array = []
	for b in get_tree().get_nodes_in_group("boss"):
		if is_instance_valid(b) and b is Node2D:
			bosses.append(b)
	if bosses.size() >= 2:
		_update_dual_boss_bars(bosses)
		return
	# Saindo do modo duplo (um boss morreu): esconde a 2ª barra e reseta layout.
	if boss_hp_bar2.visible:
		boss_hp_bar2.visible = false
	if _dual_bars_laid_out:
		_dual_bars_laid_out = false
		_current_boss = null  # força re-posicionar a barra 1 pelo path single
	# --- (lógica single existente continua a partir daqui, inalterada) ---
```

(O resto da função `_update_boss_hp_bar` permanece exatamente como está, das linhas 375 em diante.)

- [ ] **Step 4: Implementar `_update_dual_boss_bars` + layout**

Em `scripts/ui/hud.gd`, logo após a função `_position_boss_hp_bar_for` (após a linha 437), adicionar:

```gdscript
# Wave 21: duas barras menores lado a lado na BASE da tela. bosses[0]/[1] são
# atribuídos por grupo (Gorilla à esquerda, Duskrose à direita) pra ficar estável.
func _update_dual_boss_bars(bosses: Array) -> void:
	if not _dual_bars_laid_out:
		_apply_dual_bar_layout()
		_dual_bars_laid_out = true
	# Ordena: mage_monkey (Gorilla) primeiro (barra esquerda), duskrose depois.
	var gorilla: Node2D = null
	var dusk: Node2D = null
	for b in bosses:
		if (b as Node).is_in_group("mage_monkey"):
			gorilla = b
		elif (b as Node).is_in_group("duskrose"):
			dusk = b
	# Fallback: se algum grupo não casar, usa ordem da lista.
	if gorilla == null:
		gorilla = bosses[0]
	if dusk == null:
		dusk = bosses[1] if bosses.size() > 1 else bosses[0]
	_fill_boss_bar(boss_hp_bar, boss_hp_fill, boss_hp_label, boss_name_label, gorilla, "MAGE MONKEY")
	_fill_boss_bar(boss_hp_bar2, boss_hp_fill2, boss_hp_label2, boss_name_label2, dusk, "DUSKROSE")


# Posiciona as duas barras menores lado a lado na base (uma vez por entrada no
# modo duplo). Larguras/posições tunáveis.
func _apply_dual_bar_layout() -> void:
	for bar in [boss_hp_bar, boss_hp_bar2]:
		bar.scale = Vector2(0.62, 0.62)  # ~62% do tamanho cheio (720→~446)
		bar.anchor_top = 1.0
		bar.anchor_bottom = 1.0
		bar.modulate.a = 1.0
		bar.visible = true
	# Barra esquerda (Gorilla): metade esquerda da base.
	boss_hp_bar.anchor_left = 0.0
	boss_hp_bar.anchor_right = 0.0
	boss_hp_bar.offset_left = 120.0
	boss_hp_bar.offset_top = _BOSS_BAR_BOTTOM_OFFSET_TOP
	boss_hp_bar.offset_bottom = _BOSS_BAR_BOTTOM_OFFSET_BOTTOM
	# Barra direita (Duskrose): metade direita da base (ancorada à direita).
	boss_hp_bar2.anchor_left = 1.0
	boss_hp_bar2.anchor_right = 1.0
	boss_hp_bar2.offset_left = -120.0 - 446.0  # ~largura escalada da barra
	boss_hp_bar2.offset_top = _BOSS_BAR_BOTTOM_OFFSET_TOP
	boss_hp_bar2.offset_bottom = _BOSS_BAR_BOTTOM_OFFSET_BOTTOM


# Preenche uma barra de boss (fill ratio + nome + label). Extraído pra reuso
# entre as duas barras do modo duplo.
func _fill_boss_bar(bar: Control, fill: ColorRect, label: Label, name_label: Label, boss: Node2D, name_text: String) -> void:
	if boss == null or not is_instance_valid(boss):
		bar.visible = false
		return
	bar.visible = true
	name_label.text = name_text
	if not ("hp" in boss) or not ("max_hp" in boss):
		return
	var hp: float = float(boss.hp)
	var maxhp: float = float(boss.max_hp)
	var ratio: float = 0.0 if maxhp <= 0.0 else clampf(hp / maxhp, 0.0, 1.0)
	var mat: ShaderMaterial = fill.material as ShaderMaterial
	if mat != null:
		mat.set_shader_parameter("fill_ratio", ratio)
	label.text = "%d/%d" % [int(round(hp)), int(round(maxhp))]
```

- [ ] **Step 5: Verificação manual**

Rodar **Boss W21**. Observar:
- Duas barras menores lado a lado na base: esquerda "MAGE MONKEY", direita "DUSKROSE", cada uma com HP/HP_max e fill correto.
- Ao bater nos bosses, o fill de cada barra deplete certo.
- Quando um boss morre, a barra dele some e a do outro permanece. Ao terminar a luta, ambas somem.
- Rodar **Boss W7** e **Boss W14** pra confirmar que a barra ÚNICA continua igual (W7 no topo, W14 na base) — sem regressão.

- [ ] **Step 6: Commit**

```bash
git add scripts/ui/hud.gd scenes/ui/hud.tscn
git commit -m "feat(wave21): duas barras de HP de boss lado a lado na base

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 7: Sequenciador de música (2 faixas em loop)

**Objetivo:** Na wave 21, tocar faixa 1 inteira → faixa 2 inteira → faixa 1 → … em loop. Restaurar a música default ao sair da wave.

**Files:**
- Modify: `scripts/systems/wave_manager.gd`

- [ ] **Step 1: Vars de estado do sequenciador**

Em `scripts/systems/wave_manager.gd`, junto às vars de estado (perto da linha 108, `var _default_music`), adicionar:

```gdscript
# Sequenciador de música da wave 21 (2 faixas em loop). _dual_music_active diz
# se o handler do sinal `finished` está conectado.
var _dual_music_active: bool = false
var _dual_music_index: int = 0
```

- [ ] **Step 2: Plugar o sequenciador no call site da música**

Em `scripts/systems/wave_manager.gd:396`, trocar:

```gdscript
	_swap_music_to(_music_for_wave(wave_number))
```

por:

```gdscript
	# Wave 21: sequência de 2 faixas em loop (faixa 1 → 2 → 1…). Demais waves:
	# troca simples de track. Sai do modo duplo ao trocar de wave.
	_stop_dual_music_sequence()
	if wave_number == boss_dual_wave:
		_start_dual_music_sequence()
	else:
		_swap_music_to(_music_for_wave(wave_number))
```

- [ ] **Step 3: Implementar o sequenciador**

Em `scripts/systems/wave_manager.gd`, logo após a função `_swap_music_to` (após a linha 1647), adicionar:

```gdscript
func _start_dual_music_sequence() -> void:
	var music_node := get_tree().get_first_node_in_group("music") as AudioStreamPlayer
	if music_node == null:
		return
	if boss_dual_music_1 == null or boss_dual_music_2 == null:
		# Sem as faixas, cai pra default (não trava a wave).
		_swap_music_to(_default_music)
		return
	# Loop nativo OFF nas duas (o sequenciador é quem encadeia via `finished`).
	if boss_dual_music_1 is AudioStreamMP3:
		(boss_dual_music_1 as AudioStreamMP3).loop = false
	if boss_dual_music_2 is AudioStreamMP3:
		(boss_dual_music_2 as AudioStreamMP3).loop = false
	_dual_music_index = 0
	_dual_music_active = true
	if not music_node.finished.is_connected(_on_dual_music_finished):
		music_node.finished.connect(_on_dual_music_finished)
	music_node.stream = boss_dual_music_1
	music_node.play()


func _on_dual_music_finished() -> void:
	if not _dual_music_active:
		return
	var music_node := get_tree().get_first_node_in_group("music") as AudioStreamPlayer
	if music_node == null:
		return
	# Alterna 0 → 1 → 0 → … em loop.
	_dual_music_index = (_dual_music_index + 1) % 2
	music_node.stream = boss_dual_music_2 if _dual_music_index == 1 else boss_dual_music_1
	music_node.play()


func _stop_dual_music_sequence() -> void:
	if not _dual_music_active:
		return
	_dual_music_active = false
	var music_node := get_tree().get_first_node_in_group("music") as AudioStreamPlayer
	if music_node != null and music_node.finished.is_connected(_on_dual_music_finished):
		music_node.finished.disconnect(_on_dual_music_finished)
```

- [ ] **Step 4: Verificação manual**

Rodar **Boss W21**. Confirmar que a faixa 1 (`Boss 21 wave.mp3`) toca na entrada. Pra testar a troca sem esperar a faixa inteira, opcionalmente reduzir temporariamente a duração não dá — então: deixar a 1ª faixa terminar (ou inspecionar via debug que `_on_dual_music_finished` troca pra faixa 2 e depois volta pra 1). Ao terminar a wave 21 (matar os dois bosses) e a próxima wave começar, confirmar que a música volta pra default (sequenciador desconecta — sem duas músicas sobrepostas).

- [ ] **Step 5: Commit**

```bash
git add scripts/systems/wave_manager.gd
git commit -m "feat(wave21): sequenciador de música de 2 faixas em loop

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 8: Cinematic de 2 alvos (Duskrose → Gorilla → player)

**Objetivo:** Intro da wave 21: câmera mostra a Duskrose (~3s) → pan pro Gorilla (~3s) → pan pro player no canto inferior-esquerdo. Reusa a maquinaria de cinematic existente.

**Files:**
- Modify: `scripts/systems/wave_manager.gd` (`_play_boss_intro_cinematic`)
- Modify: `scripts/ui/hud.gd:935` (`play_boss_intro` — path de overlay pra wave 21)

- [ ] **Step 1: Path de overlay pra wave 21 no HUD**

Em `scripts/ui/hud.gd:935`, trocar:

```gdscript
	if wave_number == 14:
```

por:

```gdscript
	if wave_number == 14 or wave_number == 21:
```

(Assim a wave 21 usa o mesmo path da Duskrose: fade do overlay preto revelando a cena, sem o sprite "surgimento" do Gorilla.)

- [ ] **Step 2: Const dos holds do cinematic duplo**

Em `scripts/systems/wave_manager.gd`, junto aos consts de cinematic (perto de `BOSS_INTRO_HOLD_ON_BOSS`, linha ~86), adicionar:

```gdscript
# Wave 21: tempo parado em cada boss no cinematic de intro (Duskrose, depois Gorilla).
const BOSS_DUAL_INTRO_HOLD: float = 3.0
const BOSS_DUAL_INTRO_PAN: float = 1.6
```

- [ ] **Step 3: Branch da wave 21 em `_play_boss_intro_cinematic`**

Em `scripts/systems/wave_manager.gd`, no início de `_play_boss_intro_cinematic` (após pegar `camera` e `player`, e o `_freeze_entities(true)`, antes do bloco que calcula `camera_target` para o boss único — por volta da linha 1836), inserir o desvio pra wave 21:

```gdscript
	if wave_number == boss_dual_wave:
		await _play_dual_boss_intro_cinematic(hud, camera, player)
		return
```

- [ ] **Step 4: Implementar `_play_dual_boss_intro_cinematic`**

Em `scripts/systems/wave_manager.gd`, logo após `_play_boss_intro_cinematic` (após a linha 1874), adicionar:

```gdscript
func _play_dual_boss_intro_cinematic(hud: Node, camera: Node, player: Node2D) -> void:
	# Acha os dois bosses por grupo.
	var dusk: Node2D = null
	var gorilla: Node2D = null
	for b in get_tree().get_nodes_in_group("boss"):
		if not is_instance_valid(b):
			continue
		if (b as Node).is_in_group("duskrose"):
			dusk = b
		elif (b as Node).is_in_group("mage_monkey"):
			gorilla = b
	# Alvos de câmera (corpo, não os pés). Duskrose usa patrol_y (snap ainda
	# não rodou nesta frame).
	var dusk_target: Vector2 = _wave7_boss_center
	if dusk != null:
		var dy: float = dusk.patrol_y if "patrol_y" in dusk else dusk.global_position.y
		dusk_target = Vector2(dusk.global_position.x, dy - 16.0)
	var gorilla_target: Vector2 = _wave7_boss_center
	if gorilla != null:
		gorilla_target = Vector2(gorilla.global_position.x, gorilla.global_position.y - 16.0)
	# Trava câmera na Duskrose pro reveal do overlay.
	if camera != null and "cinematic_mode" in camera:
		camera.cinematic_mode = true
		if camera is Node2D:
			(camera as Node2D).global_position = dusk_target
	# Overlay "Raid 21" + fade (path da Duskrose no HUD, sem sprite do Gorilla).
	if hud != null and hud.has_method("play_boss_intro"):
		await hud.play_boss_intro(wave_number)
	if stopped:
		_end_dual_cinematic(camera)
		return
	# 1) Segura na Duskrose.
	await get_tree().create_timer(BOSS_DUAL_INTRO_HOLD).timeout
	if stopped:
		_end_dual_cinematic(camera)
		return
	# 2) Pan pro Gorilla + segura.
	if camera != null and camera.has_method("pan_to"):
		var t1: Tween = camera.pan_to(gorilla_target, BOSS_DUAL_INTRO_PAN)
		if t1 != null:
			await t1.finished
	await get_tree().create_timer(BOSS_DUAL_INTRO_HOLD).timeout
	if stopped:
		_end_dual_cinematic(camera)
		return
	# 3) Pan pro player (canto inferior-esquerdo).
	if camera != null and camera.has_method("pan_to") and player != null:
		var t2: Tween = camera.pan_to(player.global_position + Vector2(0, -16), BOSS_INTRO_PAN_DURATION)
		if t2 != null:
			await t2.finished
	_end_dual_cinematic(camera)


func _end_dual_cinematic(camera: Node) -> void:
	if camera != null and "cinematic_mode" in camera:
		camera.cinematic_mode = false
	_freeze_entities(false)
```

- [ ] **Step 5: Verificação manual**

Rodar **Boss W21**. Observar a sequência da intro:
- Overlay "Raid 21" some revelando a Duskrose no topo; câmera segura nela ~3s.
- Câmera faz pan suave pro Gorilla no centro; segura ~3s.
- Câmera faz pan pro player no canto inferior-esquerdo; controle volta ao player e a luta começa (entidades descongelam).

Confirmar que **Boss W7** e **Boss W14** continuam com o cinematic single de sempre (sem regressão).

- [ ] **Step 6: Commit**

```bash
git add scripts/systems/wave_manager.gd scripts/ui/hud.gd
git commit -m "feat(wave21): cinematic de intro de 2 alvos (Duskrose -> Gorilla -> player)

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 9: Coins recebidas só depois do último boss (chuva de moedas)

**Objetivo:** Na wave 21, as moedas dos bosses ficam travadas (não expiram nem são coletáveis) durante a luta; quando o último boss morre, o magnet de fim de wave libera todas de uma vez.

**Files:**
- Modify: `scripts/pickups/gold.gd`
- Modify: `scripts/systems/wave_manager.gd`

- [x] **Step 1:** Em `gold.gd`, adicionar `var _locked: bool = false` (perto de `_picked`).
- [x] **Step 2:** Em `gold.gd._ready`, após o bloco de lifetime do gold magnet, consultar `wave_manager.boss_coins_locked()` e setar `_locked = true` se verdadeiro.
- [x] **Step 3:** Em `gold.gd._process`, se `_locked`: só faz o bobbing (sem `_elapsed`/expiry, sem magnet-upgrade, sem coleta) e `return`.
- [x] **Step 4:** Em `gold.gd.collect`, adicionar `if _locked: return` (bloqueia contato + fenda). `magnet_to_player`/`_magnet_finalize` NÃO checam `_locked` (é a liberação intencional do fim de wave).
- [x] **Step 5:** Em `wave_manager.gd`, adicionar `func boss_coins_locked() -> bool: return wave_number == boss_dual_wave and wave_active`.
- [ ] **Step 6: Verificação manual** — Rodar **Boss W21**. Matar o 1º boss: as moedas dele ficam no chão, não expiram e não são coletáveis (andar por cima/fenda não pega). Matar o 2º boss: todas as moedas voam pro player (chuva de moedas) no fim da wave.
- [ ] **Step 7: Commit**

## Requisitos do spec já cobertos sem tarefa dedicada
- **"Dois spawn points pros magos do Gorilla":** já é nativo — o Gorilla invoca via `mage_monkey._do_summon_horde`, que usa `wave_manager.get_farthest_spawn_points_from_player(2)` (os 2 spawn points mais longes do player) + 25% perto dele. Na arena da Duskrose os spawn point Markers do mapa continuam existindo, então funciona sem markers novos. Se a posição ficar ruim no playtest, adicionar 2 Marker2D dedicados na cena da arena é o ajuste fino.
- **Condição de vitória ("só termina quando os dois morrem"):** automática. O `_process` do wave_manager chama `_finish_wave` quando `_total_alive() == 0`. A morte do Gorilla limpa os magos dele (`mage_monkey._die` itera `_minions`, linhas 640-642+) e a morte da Duskrose limpa os Rose Monsters (`duskrose.take_damage`/morte, linhas ~1115-1140). Logo, a wave só fecha quando os dois bosses + seus súditos somem. Nenhuma tarefa de win-condition necessária — só verificar no playtest que matar um boss não encerra a wave (o outro continua).

## Notas de tuning (ajustar no playtest, não bloqueiam a implementação)
- HP dos bosses (6000 / 8000) — Task 2.
- Horda inicial de magos do Gorilla (`mage` total 4 na config) + cadência de re-invocação dele (`vulnerable_window`, `minion_horde_size` no mage_monkey) — Task 1.
- `BOSS_DUAL_GOLD_MULT` (1.5) — Task 2.
- Layout/escala das barras duplas (`_apply_dual_bar_layout`: scale 0.62, offsets) — Task 6.
- Holds do cinematic (`BOSS_DUAL_INTRO_HOLD` 3.0, `BOSS_DUAL_INTRO_PAN` 1.6) — Task 8.
- Posição exata do canto inferior-esquerdo do player — Task 5.

## Fora de escopo
- Faixa de música própria já fornecida (Task 7 usa os 2 arquivos).
- Mudanças no comportamento intrínseco dos bosses além do escopo do escudo (Task 3) e do dark ball da Duskrose (Task 4).
- Recompensa pós-boss extra (free upgrade da wave 14 NÃO é estendido pra 21; a shop normal abre no fim).
- Bump de versão (só em deploy).
