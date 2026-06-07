# Flecha Espectral Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Novo upgrade de loja "Flecha Espectral" (categoria tipo-de-flecha, mutex com Perfuração/Ricochete): ao matar com uma flecha, nasce uma flecha-fantasma homing que voa até um inimigo aleatório em 180px, causa % do dano + o pacote completo de efeitos da flecha atual, e encadeia (exponencial, 60%/geração) com travas de segurança.

**Architecture:** A espectral É uma instância de `arrow.gd` num modo novo `is_spectral` (homing, sem colisão de bloqueio). Reusa os métodos de efeito já isolados na `arrow.gd` (`_apply_burn_to`/`_apply_curse_to`/`_apply_freeze_to`/`_apply_tide_on_hit`/`_spawn_stone_aoe`/`_spawn_graviton_pulse`/`_proc_chain_lightning`). O spawn do burst + contador estático + SFX vivem na `arrow.gd`; o player só fornece `_stamp_spectral_effects(arrow)` e os números de nível. SEM refatorar `_spawn_arrow`/`_on_hit` (additivo).

**Tech Stack:** Godot 4 / GDScript. Sem teste automatizado — valida com import headless `Godot_v4.6.2-stable_win64.exe --headless --editor --quit --path <proj>` (EXIT=0 = compila limpo) + playtest com dev panel.

**Spec:** `docs/superpowers/specs/2026-06-07-flecha-espectral-design.md`

---

## File Structure

- `scripts/player/player.gd` — `spectral_arrow_level` + `apply_upgrade` + helpers (`_spectral_count`/`_spectral_pct`/`_has_spectral`) + `_stamp_spectral_effects(arrow)`.
- `scripts/skills/arrow.gd` — modo `is_spectral` (campos + homing + alvo + `_spectral_strike` + `_spawn_spectral_burst` + caps + SFX) + hook de kill no `_on_hit`.
- `scripts/ui/wave_shop.gd` — entrada no `UPGRADE_POOL`, `EXCLUSIVE_PAIRS`, `SPECTRAL_DESCS`, `_get_upgrade_descs_array`, `UPGRADE_ART`.
- `scripts/systems/wave_manager.gd` — `FREE_UPGRADE_POOL`.
- `assets/i18n/translations.csv` — 5 keys (nome + 4 descrições).

---

### Task 1: Player — nível, apply_upgrade e helpers

**Files:**
- Modify: `scripts/player/player.gd:103` (vars de nível), ramo `apply_upgrade` (perto de `"perfuracao"`), e um helper novo.

- [ ] **Step 1: Declarar o nível**

Em `scripts/player/player.gd`, logo após a linha 103 (`var perfuracao_level: int = 0  # capa em 4 (níveis 1-4)`), adicionar:

```gdscript
var spectral_arrow_level: int = 0  # Flecha Espectral (tipo-de-flecha), capa em 4
```

- [ ] **Step 2: Caso no `apply_upgrade`**

No `match upgrade_id` do `apply_upgrade`, logo após o bloco `"perfuracao":`:

```gdscript
		"perfuracao":
			perfuracao_level = mini(perfuracao_level + 1, 4)
			perfuracao_counter_changed.emit(_perf_shot_counter, perfuracao_level)
		"spectral_arrow":
			spectral_arrow_level = mini(spectral_arrow_level + 1, 4)
```

- [ ] **Step 3: Helpers de nível**

Adicionar (perto dos outros helpers de flecha; pode ser logo após o bloco do `_perf_damage_bonus` ou qualquer ponto de função no player). Inserir como funções novas:

```gdscript
# --- Flecha Espectral ---
func _has_spectral() -> bool:
	return spectral_arrow_level > 0


# Quantas espectrais saem por burst, por nível (L1=1, L2=1, L3=2, L4=3).
func _spectral_count() -> int:
	match spectral_arrow_level:
		3: return 2
		4: return 3
		_: return 1


# % do dano da flecha que matou (L1=50%, L2=75%, L3=75%, L4=85%).
func _spectral_pct() -> float:
	match spectral_arrow_level:
		1: return 0.50
		2, 3: return 0.75
		4: return 0.85
		_: return 0.0
```

- [ ] **Step 4: Validar parse**

Run: `Godot_v4.6.2-stable_win64.exe --headless --editor --quit --path <proj>`, filtrando `SCRIPT ERROR|Compile Error`.
Expected: EXIT=0, sem erros.

- [ ] **Step 5: Commit**

```bash
rtk git add scripts/player/player.gd
rtk git commit -m "feat: nivel + helpers da Flecha Espectral no player"
```

---

### Task 2: Player — `_stamp_spectral_effects(arrow)`

**Files:**
- Modify: `scripts/player/player.gd` (nova função; espelha os flags de efeito do `_spawn_arrow` ~1214-1367, SEM mexer em damage/speed/lifetime/pierce/ricochet)

- [ ] **Step 1: Escrever o stamp**

Adicionar a função nova no player (junto dos helpers da Task 1):

```gdscript
# Carimba na flecha espectral SÓ os flags+params de efeito da flecha atual (mesmos
# helpers do _spawn_arrow). NÃO mexe em damage/speed/lifetime/pierce/ricochet — o dano
# da espectral é setado absoluto por quem spawna. fire_trail (efeito de caminho, não de
# contato) é omitido de propósito.
func _stamp_spectral_effects(arrow: Node) -> void:
	if chain_lightning_level > 0:
		arrow.chain_count = _chain_target_count()
		arrow.chain_dmg_pct = _chain_damage_pct()
		arrow.chain_bonus_chance = _chain_bonus_chance()
		arrow.is_chain = true
	if fire_arrow_level > 0:
		arrow.is_fire = true
		arrow.burn_dps = _fire_burn_dps()
		arrow.burn_duration = _fire_burn_duration()
		arrow.burn_final_bonus = 5.0
		arrow.burn_max_stacks = clampi(fire_arrow_level, 1, 4)
	if curse_arrow_level > 0:
		arrow.is_curse = true
		arrow.curse_dps = _curse_dps()
		arrow.curse_duration = _curse_duration()
		arrow.curse_slow_factor = _curse_slow_factor()
	if ice_arrow_level > 0:
		arrow.is_ice = true
		arrow.freeze_duration = _ice_freeze_duration()
		arrow.freeze_dps = _ice_freeze_dps()
		if ice_arrow_level >= 2:
			arrow.ice_area_enabled = true
			arrow.ice_area_slow_factor = _ice_area_slow_factor()
			arrow.ice_area_lifetime = _ice_area_lifetime()
	if stone_arrow_level > 0:
		arrow.is_stone = true
		arrow.stone_aoe_radius = _stone_radius()
		# AoE = dano da espectral (anula o −30% do Cajado igual no _spawn_arrow).
		arrow.stone_aoe_damage = arrow.damage / _cajado_arrow_factor()
		arrow.stone_aoe_knockback = _stone_knockback()
		arrow.stone_stun_duration = _stone_stun_duration()
		arrow.stone_size_scale = _stone_size_scale()
	if tide_arrow_level > 0:
		arrow.is_tide = true
		arrow.tide_radius = TIDE_AOE_RADIUS
		arrow.tide_debuff_duration = TIDE_DEBUFF_DURATION
		arrow.tide_debuff_max_stacks = TIDE_DEBUFF_MAX_STACKS
		arrow.tide_per_stack = _tide_per_stack()
		arrow.tide_splash_damage = _apply_dmg_pct_to_dps(TIDE_SPLASH_DAMAGE)
	if graviton_level > 0:
		arrow.is_graviton = true
		arrow.graviton_radius = _graviton_radius()
		arrow.graviton_lifetime = _graviton_lifetime()
		arrow.graviton_slow_factor = _graviton_slow_factor()
		arrow.graviton_explosion_damage = _graviton_explosion_damage()
```

- [ ] **Step 2: Validar parse**

Run: import headless. Expected: EXIT=0. (Os nomes de helper/const acima são exatamente os usados no `_spawn_arrow` — se algum acusar "identifier not found", conferir o nome no `_spawn_arrow`.)

- [ ] **Step 3: Commit**

```bash
rtk git add scripts/player/player.gd
rtk git commit -m "feat: _stamp_spectral_effects (espelha efeitos da flecha atual)"
```

---

### Task 3: arrow.gd — modo `is_spectral` (campos + homing + alvo)

**Files:**
- Modify: `scripts/skills/arrow.gd` (campos perto da linha 217; `_ready` ~220; `_physics_process` ~610; `_die` ~996; funções novas)

- [ ] **Step 1: Campos e constantes do modo espectral**

Adicionar logo após a linha 217 (`var _spawn_pos: Vector2 = Vector2.ZERO`):

```gdscript
# --- Flecha Espectral (modo homing) ---
# Setado por _spawn_spectral_burst. Em modo spectral a flecha NÃO colide (body_entered
# não conectado); voa até spectral_target corrigindo a direção, atravessa tudo, re-mira
# se o alvo morre, e ao chegar aplica dano+efeitos via _spectral_strike.
var is_spectral: bool = false
var spectral_target: Node = null
var spectral_count: int = 1   # quantas spawnar se ESTA matar (contagem do nível)
var spectral_gen: int = 0     # geração (cap de profundidade via piso de dano)
const SPECTRAL_ARRIVE_DIST: float = 10.0
const SPECTRAL_RETARGET_RADIUS: float = 180.0   # = TIGER_CLAWS_RADIUS
const SPECTRAL_HOMING_SPEED: float = 320.0
const SPECTRAL_MAX_ALIVE: int = 120             # teto global de espectrais vivas
const SPECTRAL_MIN_DAMAGE: float = 1.0          # piso de dano pra encadear
const SPECTRAL_SFX: AudioStream = preload("res://audios/upgrades/flecha espectral/flecha espectral effect.mp3")
const SPECTRAL_SFX_THROTTLE_MS: int = 80
static var _spectral_alive: int = 0
static var _spectral_sfx_until_ms: int = 0
```

- [ ] **Step 2: Branch espectral no `_ready`**

No `_ready` (linha ~220), logo no começo do corpo (antes de `rotation = direction.angle()` conectar colisão), adicionar o branch. Substituir o início do `_ready`:

```gdscript
func _ready() -> void:
	rotation = direction.angle()
	if is_spectral:
		# Fantasma: opacidade reduzida + NÃO conecta colisão (atravessa tudo; chegada
		# é por distância ao alvo). Conta no teto global.
		modulate.a = 0.5
		_spectral_alive += 1
	else:
		body_entered.connect(_on_hit)
	_arm_lifetime()
```

(O resto do `_ready` — som, visuais elementais via flags — continua igual abaixo. As flags `is_fire`/`is_curse`/etc. carimbadas disparam os `_apply_*_visuals` normalmente, dando o visual elemental fantasma.)

- [ ] **Step 3: Homing no `_physics_process`**

No `_physics_process` (linha ~610), adicionar o branch espectral no topo (antes do movimento reto normal):

```gdscript
func _physics_process(delta: float) -> void:
	if is_stuck:
		return
	if is_spectral:
		_update_spectral(delta)
		return
	position += direction * speed * delta
```

(o resto do `_physics_process` — trail, fire_trail — segue igual abaixo.)

- [ ] **Step 4: Lógica de homing + alvo + chegada**

Adicionar as funções novas (ex.: logo após `_physics_process`):

```gdscript
func _update_spectral(delta: float) -> void:
	# Re-mira se o alvo sumiu/morreu.
	if spectral_target == null or not is_instance_valid(spectral_target) \
			or (spectral_target as Node).is_queued_for_deletion() \
			or (("hp" in spectral_target) and float(spectral_target.hp) <= 0.0):
		spectral_target = _pick_random_enemy_in(global_position, SPECTRAL_RETARGET_RADIUS, null)
		if spectral_target == null:
			_die()
			return
	var tp: Vector2 = (spectral_target as Node2D).global_position
	direction = (tp - global_position).normalized()
	rotation = direction.angle()
	if trail != null:
		trail.add_point(global_position)
		while trail.get_point_count() > trail_max_points:
			trail.remove_point(0)
	if global_position.distance_to(tp) <= SPECTRAL_ARRIVE_DIST:
		_spectral_strike()
		return
	position += direction * SPECTRAL_HOMING_SPEED * delta


# Sorteia um inimigo vivo dentro de `radius` de `center`, ignorando aliados/estruturas
# e o `exclude`. Retorna null se não houver candidato.
func _pick_random_enemy_in(center: Vector2, radius: float, exclude: Node) -> Node:
	var rsq: float = radius * radius
	var candidates: Array[Node] = []
	for e in get_tree().get_nodes_in_group("enemy"):
		if e == exclude or not is_instance_valid(e) or not (e is Node2D):
			continue
		if (e as Node).is_queued_for_deletion():
			continue
		if ("hp" in e) and float(e.hp) <= 0.0:
			continue
		if (e as Node).is_in_group("tank_ally") or (e as Node).is_in_group("structure") or (e as Node).is_in_group("ally"):
			continue
		if center.distance_squared_to((e as Node2D).global_position) <= rsq:
			candidates.append(e)
	if candidates.is_empty():
		return null
	return candidates[randi() % candidates.size()]
```

- [ ] **Step 5: Decrementar o contador no `_die`**

Substituir `_die` (linha ~996):

```gdscript
func _die() -> void:
	if is_spectral:
		_spectral_alive = maxi(_spectral_alive - 1, 0)
		is_spectral = false  # idempotente: não decrementa 2×
	if is_inside_tree():
		queue_free()
```

- [ ] **Step 6: Validar parse**

Run: import headless. Expected: EXIT=0.

- [ ] **Step 7: Commit**

```bash
rtk git add scripts/skills/arrow.gd
rtk git commit -m "feat: arrow.gd modo is_spectral (homing + alvo aleatorio)"
```

---

### Task 4: arrow.gd — `_spawn_spectral_burst` (caps + SFX)

**Files:**
- Modify: `scripts/skills/arrow.gd` (função nova)

- [ ] **Step 1: Spawner do burst**

Adicionar a função (ex.: após `_pick_random_enemy_in`):

```gdscript
# Spawna `count` flechas espectrais a partir de `origin`, cada uma com `base_dmg`. Aplica
# as travas: piso de dano (não spawna abaixo de SPECTRAL_MIN_DAMAGE) e teto global de
# espectrais vivas. `gen` = geração (pro decaimento). `exclude` = o inimigo recém-morto
# (não vira alvo). Toca o SFX 1× por burst (throttle global).
func _spawn_spectral_burst(origin: Vector2, base_dmg: float, count: int, gen: int, exclude: Node) -> void:
	if base_dmg < SPECTRAL_MIN_DAMAGE:
		return
	var player := get_tree().get_first_node_in_group("player")
	if player == null or not player.has_method("_stamp_spectral_effects"):
		return
	if player.arrow_scene == null:
		return
	var spawned: int = 0
	for _i in count:
		if _spectral_alive >= SPECTRAL_MAX_ALIVE:
			break
		var tgt := _pick_random_enemy_in(origin, SPECTRAL_RETARGET_RADIUS, exclude)
		if tgt == null:
			break
		var sp = player.arrow_scene.instantiate()
		sp.is_spectral = true
		sp.damage = base_dmg
		sp.spectral_count = count
		sp.spectral_gen = gen
		sp.spectral_target = tgt
		sp.source = source            # propaga o atirador original (player)
		sp.play_shoot_sound = false   # SFX é o da espectral, tocado abaixo
		sp.telemetry_source_id = "spectral"
		sp.global_position = origin
		player._stamp_spectral_effects(sp)
		_get_world().add_child(sp)
		if sp.has_method("set_direction"):
			var d: Vector2 = ((tgt as Node2D).global_position - origin)
			sp.set_direction(d if d.length() > 0.01 else Vector2.RIGHT)
		spawned += 1
	if spawned > 0:
		_play_spectral_sfx(origin)


func _play_spectral_sfx(pos: Vector2) -> void:
	var now: int = Time.get_ticks_msec()
	if now - _spectral_sfx_until_ms < SPECTRAL_SFX_THROTTLE_MS:
		return
	_spectral_sfx_until_ms = now
	_play_oneshot(SPECTRAL_SFX, pos, -10.0, 1.0)
```

- [ ] **Step 2: Validar parse**

Run: import headless. Expected: EXIT=0. (Confirmar que `_play_oneshot(stream, pos, db, pitch)` existe na arrow.gd com essa assinatura — é usado em vários pontos, ex. `_apply_tide_on_hit`.)

- [ ] **Step 3: Commit**

```bash
rtk git add scripts/skills/arrow.gd
rtk git commit -m "feat: arrow.gd _spawn_spectral_burst (travas + SFX)"
```

---

### Task 5: arrow.gd — `_spectral_strike` (dano + efeitos + encadeia)

**Files:**
- Modify: `scripts/skills/arrow.gd` (função nova; reusa os `_apply_*`/`_spawn_*` existentes)

- [ ] **Step 1: Strike**

Adicionar a função:

```gdscript
# Chegada da espectral no alvo: aplica dano (sem crit, sem curva de perfuração) + o
# pacote de efeitos via os helpers já existentes. Se matar, encadeia o próximo burst a
# 60% do dano. Sempre termina com _die.
func _spectral_strike() -> void:
	var target: Node = spectral_target
	if target == null or not is_instance_valid(target):
		_die()
		return
	var death_pos: Vector2 = (target as Node2D).global_position
	# Curse antes do dano (conversão precisa enxergar o debuff se o hit matar).
	if is_curse:
		_apply_curse_to(target)
	if target.is_in_group("stone_cube"):
		target._arrow_hit_flag = true
	var was_alive: bool = (not ("hp" in target)) or float(target.hp) > 0.0
	target.take_damage(damage)
	_notify_player_dmg_kill(damage, "spectral", was_alive, target)
	if target.has_method("apply_knockback"):
		target.apply_knockback(direction, knockback_strength)
	_proc_chain_lightning(target)
	if is_fire and is_instance_valid(target):
		_apply_burn_to(target)
	if is_ice and is_instance_valid(target):
		_apply_freeze_to(target)
		if ice_area_enabled:
			_spawn_ice_slow_area_at(global_position)
	if is_tide:
		_apply_tide_on_hit(death_pos, target if is_instance_valid(target) else null)
	if is_stone:
		var do_stun: bool = _consume_stone_stun_token()
		if do_stun and is_instance_valid(target):
			_apply_stone_stun(target, stone_stun_duration)
		_spawn_stone_aoe(target if is_instance_valid(target) else null, STONE_SPLASH_PCT, do_stun)
	if is_graviton:
		_spawn_graviton_pulse()
	# Matou? → encadeia (contagem do nível, 60% do dano). Travas no _spawn_spectral_burst.
	var killed: bool = was_alive and (not is_instance_valid(target) \
		or (("hp" in target) and float(target.hp) <= 0.0))
	if killed:
		_spawn_spectral_burst(death_pos, damage * 0.60, spectral_count, spectral_gen + 1, target)
	_die()
```

- [ ] **Step 2: Validar parse**

Run: import headless. Expected: EXIT=0.

- [ ] **Step 3: Commit**

```bash
rtk git add scripts/skills/arrow.gd
rtk git commit -m "feat: arrow.gd _spectral_strike (dano + efeitos + encadeamento)"
```

---

### Task 6: arrow.gd — hook de kill da flecha normal → burst inicial

**Files:**
- Modify: `scripts/skills/arrow.gd:711` (logo após o `_notify_player_dmg_kill` do hit normal em inimigo)

- [ ] **Step 1: Disparar o burst inicial quando a flecha NORMAL mata**

No `_on_hit`, no branch `if target != null:`, logo após a linha 711
(`_notify_player_dmg_kill(dmg_to_apply, _resolve_dmg_source_id(), _was_alive_arrow, target, true)`),
adicionar:

```gdscript
			# Flecha Espectral: se ESTA flecha (não-espectral) matou e o player tem o
			# upgrade, nasce o burst inicial do cadáver. Espectrais NÃO entram aqui
			# (não conectam body_entered), evitando recursão dupla.
			if not is_spectral and _was_alive_arrow and (not is_instance_valid(target) \
					or (("hp" in target) and float(target.hp) <= 0.0)):
				var _p_sp := get_tree().get_first_node_in_group("player")
				if _p_sp != null and _p_sp.has_method("_has_spectral") and _p_sp._has_spectral():
					var _dpos: Vector2 = global_position
					if is_instance_valid(target):
						_dpos = (target as Node2D).global_position
					_spawn_spectral_burst(_dpos, dmg_to_apply * _p_sp._spectral_pct(), _p_sp._spectral_count(), 1, target)
```

- [ ] **Step 2: Validar parse**

Run: import headless. Expected: EXIT=0.

- [ ] **Step 3: Playtest funcional**

Equipar nada; via dev panel dar o upgrade `spectral_arrow` (ou comprar na loja após Task 7). Matar um inimigo no meio de um grupo. Esperado: nasce uma flecha-fantasma (opacidade ~0.5) que voa até outro inimigo em 180px, não erra, e some ao chegar. Com elemental ativo (ex.: fogo), a espectral aplica o efeito. Se a espectral matar, sai outra a 60%.

- [ ] **Step 4: Commit**

```bash
rtk git add scripts/skills/arrow.gd
rtk git commit -m "feat: flecha normal que mata gera o burst espectral inicial"
```

---

### Task 7: Loja — carta, mutex, descrições, arte e pool grátis

**Files:**
- Modify: `scripts/ui/wave_shop.gd:62` (UPGRADE_POOL), `:95` (EXCLUSIVE_PAIRS), `:116` (nova const de descs), `:1292` (`_get_upgrade_descs_array`), `:1689` (UPGRADE_ART)
- Modify: `scripts/systems/wave_manager.gd:1471` (FREE_UPGRADE_POOL)

- [ ] **Step 1: Entrada no `UPGRADE_POOL`**

Em `scripts/ui/wave_shop.gd`, no `UPGRADE_POOL`, logo após a linha do `perfuracao` (linha 62):

```gdscript
	{"id": "perfuracao", "name": "SHOP_UPG_PERFURACAO", "max_level": 4},
	{"id": "spectral_arrow", "name": "SHOP_UPG_SPECTRAL", "max_level": 4},
```

- [ ] **Step 2: Mutex**

Substituir o par de tipo-de-flecha no `EXCLUSIVE_PAIRS` (linha 95):

```gdscript
	# Tipo de flecha (modifier on-hit): perfuração, ricochete OU espectral.
	["perfuracao", "ricochet_arrow", "spectral_arrow"],
```

- [ ] **Step 3: Const de descrições**

Adicionar perto das outras `*_DESCS` (ex.: após `PERFURACAO_DESCS`, linha ~121):

```gdscript
const SPECTRAL_DESCS: Array[String] = [
	"SHOP_SPECTRAL_DESC_1",
	"SHOP_SPECTRAL_DESC_2",
	"SHOP_SPECTRAL_DESC_3",
	"SHOP_SPECTRAL_DESC_4",
]
```

- [ ] **Step 4: Mapear no `_get_upgrade_descs_array`**

Em `_get_upgrade_descs_array` (linha ~1292), logo após `"perfuracao": return PERFURACAO_DESCS`:

```gdscript
		"perfuracao": return PERFURACAO_DESCS
		"spectral_arrow": return SPECTRAL_DESCS
```

- [ ] **Step 5: Arte da carta (placeholder)**

No dicionário `UPGRADE_ART` (perto da linha 1689, onde está `"ricochet_arrow": ...`), adicionar:

```gdscript
	"spectral_arrow": "res://assets/Hud/shop/upgrade/ricochete.png",
```

- [ ] **Step 6: Pool de boas-vindas**

Em `scripts/systems/wave_manager.gd`, no `FREE_UPGRADE_POOL`, logo após a linha do `perfuracao` (linha 1471):

```gdscript
	{"id": "perfuracao", "name": "SHOP_UPG_PERFURACAO"},
	{"id": "spectral_arrow", "name": "SHOP_UPG_SPECTRAL"},
```

- [ ] **Step 7: Validar parse**

Run: import headless. Expected: EXIT=0. (Keys de i18n ainda cruas até a Task 8 — ok.)

- [ ] **Step 8: Commit**

```bash
rtk git add scripts/ui/wave_shop.gd scripts/systems/wave_manager.gd
rtk git commit -m "feat: Flecha Espectral na loja (mutex tipo-de-flecha + descs + arte + pool gratis)"
```

---

### Task 8: i18n

**Files:**
- Modify: `assets/i18n/translations.csv`

- [ ] **Step 1: Adicionar as 5 keys (5 colunas: keys,pt_BR,en,es,fr)**

Em `assets/i18n/translations.csv`, adicionar (descrições com vírgula → entre aspas):

```
SHOP_UPG_SPECTRAL,Flecha Espectral,Spectral Arrow,Flecha Espectral,Flèche Spectrale
SHOP_SPECTRAL_DESC_1,"Ao matar um inimigo, nasce uma flecha espectral que persegue (sem errar) outro inimigo próximo, causando 50% do dano e os mesmos efeitos. Se ela matar, repete a 60% do dano.","On a kill, a spectral arrow seeks (never missing) a nearby enemy, dealing 50% damage and the same effects. If it kills, it repeats at 60% damage.","Al matar, una flecha espectral persigue (sin fallar) a un enemigo cercano, causando 50% del daño y los mismos efectos. Si mata, repite al 60% del daño.","À la mort d'un ennemi, une flèche spectrale poursuit (sans rater) un ennemi proche, infligeant 50% des dégâts et les mêmes effets. Si elle tue, elle répète à 60% des dégâts."
SHOP_SPECTRAL_DESC_2,"A flecha espectral causa 75% do dano.","The spectral arrow deals 75% damage.","La flecha espectral causa 75% del daño.","La flèche spectrale inflige 75% des dégâts."
SHOP_SPECTRAL_DESC_3,"Saem duas flechas espectrais, em dois inimigos aleatórios.","Two spectral arrows spawn, at two random enemies.","Salen dos flechas espectrales, hacia dos enemigos aleatorios.","Deux flèches spectrales apparaissent, vers deux ennemis aléatoires."
SHOP_SPECTRAL_DESC_4,"85% do dano e três flechas espectrais, em três inimigos aleatórios.","85% damage and three spectral arrows, at three random enemies.","85% del daño y tres flechas espectrales, hacia tres enemigos aleatorios.","85% des dégâts et trois flèches spectrales, vers trois ennemis aléatoires."
```

- [ ] **Step 2: Reimportar + validar**

Run: import headless (gera os `.translation`). Expected: EXIT=0. Na loja, a carta Espectral mostra nome/descrição traduzidos.

- [ ] **Step 3: Commit**

```bash
rtk git add assets/i18n/translations.csv
rtk git commit -m "i18n: strings da Flecha Espectral (pt/en/es/fr)"
```

---

### Task 9: Integração final + playtest

**Files:** nenhum novo (verificação).

- [ ] **Step 1: Smoke test integrado**

Comprar Flecha Espectral na loja (confirmar que Perfuração/Ricochete somem — mutex). Jogar:
- Matar inimigo em grupo → espectral nasce, homing, não erra, re-mira se alvo morre.
- L3/L4: 2/3 espectrais por morte. Encadeamento exponencial visível mas termina (piso de dano 1).
- Com elemental ativo (fogo/maldição/gelo/pedra/maré): espectral aplica o efeito, visual fantasma.
- SFX toca quando nasce a espectral.
- Sem o upgrade: nenhuma espectral (regressão zero).
- Sem alvo em 180px: espectral dissipa sem travar.

- [ ] **Step 2: Validar import final**

Run: import headless na branch. Expected: EXIT=0.

- [ ] **Step 3: Commit (se houver ajuste)**

```bash
rtk git add -A
rtk git commit -m "chore: ajustes finais da Flecha Espectral"
```

---

## Self-Review

- **Spec coverage:** níveis/dano/contagem → Task 1 (`_spectral_count`/`_spectral_pct`) + Task 6 hook (pct/count) + Task 5 (×0.60); homing/180px/não-erra/re-mira/atravessa → Task 3; pacote completo de efeitos → Task 2 (stamp) + Task 5 (strike reusa helpers); visual fantasma → Task 3 (`modulate.a=0.5`) + flags elementais; travas (piso 1, teto 120) → Task 4; encadeamento exponencial → Task 5 + Task 6; SFX → Task 4; mutex/carta/arte/descs/pool → Task 7; i18n → Task 8; regressão zero → guardas `_has_spectral()`/`is_spectral`.
- **Placeholder scan:** sem TBD; SFX e arte com caminhos concretos.
- **Consistência de tipos/nomes:** `is_spectral`, `spectral_target`, `spectral_count`, `spectral_gen`, `_spectral_alive`, `_spawn_spectral_burst(origin,base_dmg,count,gen,exclude)`, `_spectral_strike`, `_pick_random_enemy_in(center,radius,exclude)`, `_update_spectral`, `_play_spectral_sfx` — usados de forma consistente entre Tasks 3-6. Player: `_has_spectral`/`_spectral_count`/`_spectral_pct`/`_stamp_spectral_effects` — Tasks 1,2 definem; Tasks 4,6 consomem.
- **Pontos a confirmar na execução:** (a) assinatura exata de `_play_oneshot` (stream,pos,db,pitch) na arrow.gd; (b) que `arrow_scene` é acessível como `player.arrow_scene` (é `@export`, público); (c) que os helpers de efeito (`_chain_target_count` etc.) batem com os nomes do `_spawn_arrow` (Task 2 Step 2 cobre).
