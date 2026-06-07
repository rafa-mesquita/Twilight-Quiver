# Pet Tilisko Arqueiro Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Novo pet "Tilisko Arqueiro" (pinguim) que dispara junto com o player — flecha a 20/30/60/60% do seu dano (com efeitos de contato + crit próprio), evoluindo de flecha simples (L1-L3) pra volley completa com categorias (L4).

**Architecture:** Pet no molde do Leno (CharacterBody2D voador, sem HP), mas **event-driven**: o player, no `_release_arrow`, dispara a(s) flecha(s) do Tilisko a partir do muzzle dele. L1-L3 = 1 flecha com o pacote elemental (reusa `_stamp_spectral_effects`), sem pierce/ricochet/multi/spectral. L4 = reusa a volley + flags do player via `_spawn_arrow` (com `origin`/`source_id` novos). Integração de aliado completa (loja/starter pack/dev/HUDs/painel de dano).

**Tech Stack:** Godot 4 / GDScript. Validação por import headless `Godot_v4.6.2-stable_win64.exe --headless --editor --quit --path <proj>` (EXIT=0) + playtest pelo dev panel.

**Spec:** `docs/superpowers/specs/2026-06-07-tilisko-arqueiro-design.md`

**Aseprite:** `assets/aliados/Tilisko Arqueiro/Tilisko.aseprite` — 10 frames 32×32, sheet horizontal. Tags: `idle` 0-2, `walk` 3-4, `Flechada` 5-9.

---

## File Structure

- Create: `assets/aliados/Tilisko Arqueiro/Tilisko.png` (sheet exportado) + `.import`.
- Create: `scripts/allies/tilisko.gd` (pet event-driven).
- Create: `scenes/allies/tilisko.tscn` (cena).
- Modify: `scripts/skills/arrow.gd` (`suppress_spectral`).
- Modify: `scripts/player/player.gd` (params do `_spawn_arrow`, nível/upgrade/refresh, disparo do Tilisko).
- Modify: `scripts/ui/wave_shop.gd` (`_ALL_ALLY_IDS`, descs, arte, texto branco).
- Modify: `scripts/systems/wave_manager.gd` (`FREE_UPGRADE_POOL`).
- Modify: `scripts/ui/dev_panel.gd` + `scenes/ui/dev_panel.tscn` (botão de teste).
- Modify: `scripts/ui/hud.gd` (`UPGRADE_DISPLAY_ORDER`, `_BUILD_UPGRADE_IDS`, `_UPG_PATHS`, `_UPG_ALIADO_IDS`).
- Modify: `scripts/ui/damage_panel.gd` (`SOURCE_LABELS`).
- Modify: `assets/i18n/translations.csv`.

---

### Task 1: Exportar o sheet do Tilisko

**Files:** Create `assets/aliados/Tilisko Arqueiro/Tilisko.png`

- [ ] **Step 1: Exportar via Aseprite CLI (sheet horizontal)**

Run (PowerShell):
```powershell
$ase = "C:\Program Files (x86)\Steam\steamapps\common\Aseprite\Aseprite.exe"
$src = "c:\Users\rafam\Desktop\Rpositórios Github - claude\Pessoal\Twilight-Quiver\assets\aliados\Tilisko Arqueiro\Tilisko.aseprite"
$out = "c:\Users\rafam\Desktop\Rpositórios Github - claude\Pessoal\Twilight-Quiver\assets\aliados\Tilisko Arqueiro\Tilisko.png"
& $ase -b $src --sheet $out --sheet-type horizontal
```
Esperado: `Tilisko.png` (320×32) criado.

- [ ] **Step 2: Importar no Godot + verificar**

Run: import headless. Esperado: EXIT=0; gera `Tilisko.png.import`.

- [ ] **Step 3: Commit**

```bash
rtk git add "assets/aliados/Tilisko Arqueiro/Tilisko.png" "assets/aliados/Tilisko Arqueiro/Tilisko.png.import"
rtk git commit -m "art: sheet do Tilisko (idle/walk/atirar 32x32)"
```

---

### Task 2: `tilisko.gd` (pet event-driven)

**Files:** Create `scripts/allies/tilisko.gd`

- [ ] **Step 1: Escrever o script**

Molde do Leno (voa, bob, segue em formação, sem HP, grupos `ally`+`tilisko`), MAS sem cooldown/targeting — só anima e expõe o muzzle. `on_player_shot()` toca "atirar"; volta pra idle/walk no fim.

```gdscript
extends CharacterBody2D

# Pet pinguim arqueiro. Sem HP, não-alvo (enemies ignoram; flechas do player passam).
# NÃO atira sozinho: o player.gd dispara a flecha dele no _release_arrow e chama
# on_player_shot() pra tocar a anim. Aqui só tem follow/voo/anim + muzzle.

@export var speed: float = 38.0
@export var follow_min_distance: float = 22.0
@export var follow_max_distance: float = 40.0
@export var phase_offset: float = 0.0
@export var separation_radius: float = 18.0
@export var separation_strength: float = 30.0
const SPRITE_BASE_OFFSET_Y: float = -16.0
const MUZZLE_BASE_OFFSET_Y: float = -8.0
const BOB_HEIGHT: float = 2.0
const BOB_SPEED: float = 3.0

@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var muzzle: Marker2D = $Muzzle

var _player: Node2D = null
var _is_shooting: bool = false
var _bob_t: float = 0.0


func _ready() -> void:
	add_to_group("ally")
	add_to_group("tilisko")
	_player = get_tree().get_first_node_in_group("player")
	sprite.animation_finished.connect(_on_anim_finished)
	sprite.play("idle")


func _physics_process(delta: float) -> void:
	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player")
		if _player == null:
			return
	_bob_t += delta
	var bob: float = sin(_bob_t * BOB_SPEED) * BOB_HEIGHT
	sprite.offset.y = SPRITE_BASE_OFFSET_Y + bob
	muzzle.position.y = MUZZLE_BASE_OFFSET_Y + bob
	# Posição de formação ao redor do player (órbita por phase_offset).
	var t: float = _bob_t * 0.6 + phase_offset
	var orbit_r: float = (follow_min_distance + follow_max_distance) * 0.5
	var desired: Vector2 = _player.global_position + Vector2(cos(t), sin(t) * 0.6) * orbit_r
	var to_desired: Vector2 = desired - global_position
	var sep: Vector2 = _separation()
	velocity = to_desired * 2.2 + sep
	move_and_slide()
	# Flip pro lado do movimento/player.
	if absf(velocity.x) > 4.0:
		sprite.flip_h = velocity.x < 0.0
		muzzle.position.x = -absf(muzzle.position.x) if sprite.flip_h else absf(muzzle.position.x)
	# Anim: shooting > walk > idle.
	if not _is_shooting:
		if velocity.length() > 12.0:
			if sprite.animation != &"walk":
				sprite.play("walk")
		elif sprite.animation != &"idle":
			sprite.play("idle")


func _separation() -> Vector2:
	var force: Vector2 = Vector2.ZERO
	for other in get_tree().get_nodes_in_group("tilisko"):
		if other == self or not is_instance_valid(other) or not (other is Node2D):
			continue
		var d: Vector2 = global_position - (other as Node2D).global_position
		var dist: float = d.length()
		if dist > 0.01 and dist < separation_radius:
			force += d.normalized() * (separation_radius - dist) / separation_radius * separation_strength
	return force


# Chamado pelo player no _release_arrow: toca a anim de tiro (o spawn da flecha é
# feito pelo player a partir de get_muzzle_pos()).
func on_player_shot() -> void:
	_is_shooting = true
	sprite.play("atirar")


func get_muzzle_pos() -> Vector2:
	return muzzle.global_position


func _on_anim_finished() -> void:
	if sprite.animation == &"atirar":
		_is_shooting = false
		sprite.play("idle")
```

- [ ] **Step 2: Validar parse** (import headless após criar o `.tscn` na Task 3 — `@onready` precisa dos nodes). Por ora só confere sintaxe; erros de node aparecem em runtime.

- [ ] **Step 3: Commit**

```bash
rtk git add scripts/allies/tilisko.gd
rtk git commit -m "feat: tilisko.gd (pet event-driven, follow + anim)"
```

---

### Task 3: `tilisko.tscn` (cena)

**Files:** Create `scenes/allies/tilisko.tscn`

- [ ] **Step 1: Escrever a cena** (sheet horizontal: idle x=0/32/64, walk x=96/128, atirar x=160/192/224/256/288; todos y=0, 32×32). Espelha `leno.tscn` (Shadow + AnimatedSprite2D scale 0.5 offset -16 + CollisionShape + Muzzle).

```
[gd_scene load_steps=2 format=3]

[ext_resource type="Script" path="res://scripts/allies/tilisko.gd" id="1_script"]
[ext_resource type="Texture2D" path="res://assets/aliados/Tilisko Arqueiro/Tilisko.png" id="2_sheet"]

[sub_resource type="AtlasTexture" id="idle_0"]
atlas = ExtResource("2_sheet")
region = Rect2(0, 0, 32, 32)
[sub_resource type="AtlasTexture" id="idle_1"]
atlas = ExtResource("2_sheet")
region = Rect2(32, 0, 32, 32)
[sub_resource type="AtlasTexture" id="idle_2"]
atlas = ExtResource("2_sheet")
region = Rect2(64, 0, 32, 32)
[sub_resource type="AtlasTexture" id="walk_0"]
atlas = ExtResource("2_sheet")
region = Rect2(96, 0, 32, 32)
[sub_resource type="AtlasTexture" id="walk_1"]
atlas = ExtResource("2_sheet")
region = Rect2(128, 0, 32, 32)
[sub_resource type="AtlasTexture" id="atk_0"]
atlas = ExtResource("2_sheet")
region = Rect2(160, 0, 32, 32)
[sub_resource type="AtlasTexture" id="atk_1"]
atlas = ExtResource("2_sheet")
region = Rect2(192, 0, 32, 32)
[sub_resource type="AtlasTexture" id="atk_2"]
atlas = ExtResource("2_sheet")
region = Rect2(224, 0, 32, 32)
[sub_resource type="AtlasTexture" id="atk_3"]
atlas = ExtResource("2_sheet")
region = Rect2(256, 0, 32, 32)
[sub_resource type="AtlasTexture" id="atk_4"]
atlas = ExtResource("2_sheet")
region = Rect2(288, 0, 32, 32)

[sub_resource type="SpriteFrames" id="frames"]
animations = [{
"frames": [{"duration": 1.0, "texture": SubResource("atk_0")}, {"duration": 1.0, "texture": SubResource("atk_1")}, {"duration": 1.0, "texture": SubResource("atk_2")}, {"duration": 1.0, "texture": SubResource("atk_3")}, {"duration": 1.0, "texture": SubResource("atk_4")}],
"loop": false,
"name": &"atirar",
"speed": 14.0
}, {
"frames": [{"duration": 1.0, "texture": SubResource("idle_0")}, {"duration": 1.0, "texture": SubResource("idle_1")}, {"duration": 1.0, "texture": SubResource("idle_2")}],
"loop": true,
"name": &"idle",
"speed": 6.0
}, {
"frames": [{"duration": 1.0, "texture": SubResource("walk_0")}, {"duration": 1.0, "texture": SubResource("walk_1")}],
"loop": true,
"name": &"walk",
"speed": 8.0
}]

[sub_resource type="CapsuleShape2D" id="shape"]
radius = 5.0
height = 12.0

[node name="Tilisko" type="CharacterBody2D"]
collision_layer = 0
collision_mask = 2
script = ExtResource("1_script")

[node name="Shadow" type="Node2D" parent="."]
position = Vector2(0, 1)

[node name="Outer" type="Polygon2D" parent="Shadow"]
color = Color(0, 0, 0, 0.18)
polygon = PackedVector2Array(6, 0, 5, 1, 4, 2, 2, 2, 0, 2, -2, 2, -4, 2, -5, 1, -6, 0, -5, -1, -4, -2, -2, -2, 0, -2, 2, -2, 4, -2, 5, -1)

[node name="AnimatedSprite2D" type="AnimatedSprite2D" parent="."]
texture_filter = 1
scale = Vector2(0.5, 0.5)
sprite_frames = SubResource("frames")
animation = &"idle"
autoplay = "idle"
offset = Vector2(0, -16)

[node name="CollisionShape2D" type="CollisionShape2D" parent="."]
position = Vector2(0, -6)
shape = SubResource("shape")

[node name="Muzzle" type="Marker2D" parent="."]
position = Vector2(0, -4)
```

- [ ] **Step 2: Validar** (import headless). Esperado: EXIT=0, sem erro de cena/script.

- [ ] **Step 3: Commit**

```bash
rtk git add scenes/allies/tilisko.tscn
rtk git commit -m "feat: tilisko.tscn (cena do pet, anims idle/walk/atirar)"
```

---

### Task 4: arrow.gd — suprimir espectral nas flechas L1-L3 do Tilisko

**Files:** Modify `scripts/skills/arrow.gd` (campo + guarda no hook de kill)

- [ ] **Step 1: Campo**

Junto dos campos do is_spectral (após `var is_spectral: bool = false`):

```gdscript
# Flecha do Tilisko L1-L3: não dispara o burst espectral on-kill (não tem propriedade
# de flecha espectral nesses níveis). L4 deixa false (segue todas as categorias).
var suppress_spectral: bool = false
```

- [ ] **Step 2: Guarda no hook de kill**

No `_on_hit`, na condição do burst espectral (a que começa `if not is_spectral and _was_alive_arrow`), adicionar `and not suppress_spectral`:

```gdscript
			if not is_spectral and not suppress_spectral and _was_alive_arrow and (not is_instance_valid(target) \
					or (("hp" in target) and float(target.hp) <= 0.0)):
```

- [ ] **Step 3: Validar + commit**

Run: import headless (EXIT=0).
```bash
rtk git add scripts/skills/arrow.gd
rtk git commit -m "feat: arrow.suppress_spectral (flecha do Tilisko L1-L3 nao proca espectral)"
```

---

### Task 5: player.gd — params do `_spawn_arrow` (origin + source_id)

**Files:** Modify `scripts/player/player.gd:1174` (assinatura) e `:1177` (posição) e o bloco de telemetria (~1381)

- [ ] **Step 1: Assinatura + posição**

Trocar a assinatura do `_spawn_arrow` e a linha da posição:

```gdscript
func _spawn_arrow(dir: Vector2, dmg_mult: float, is_pierce: bool, play_sound: bool, is_primary: bool = true, is_ricochet: bool = false, is_graviton: bool = false, origin: Vector2 = Vector2.INF, source_id: String = "") -> void:
	var arrow := arrow_scene.instantiate()
	# Configura ANTES de add_child pra _ready() já enxergar os flags.
	arrow.global_position = origin if origin != Vector2.INF else muzzle.global_position
```

- [ ] **Step 2: Source id override**

No bloco de telemetria (logo após `if "is_primary_arrow" in arrow: arrow.is_primary_arrow = is_primary`), antes do `telemetry_source_id_extra`:

```gdscript
	if source_id != "" and "telemetry_source_id" in arrow:
		arrow.telemetry_source_id = source_id
```

- [ ] **Step 3: Validar + commit**

Run: import headless (EXIT=0). Chamadas existentes do `_spawn_arrow` não passam os novos params → defaults preservam o comportamento.
```bash
rtk git add scripts/player/player.gd
rtk git commit -m "feat: _spawn_arrow aceita origin + source_id (reuso pro Tilisko L4)"
```

---

### Task 6: player.gd — nível, upgrade, refresh e reset do Tilisko

**Files:** Modify `scripts/player/player.gd` (vars perto de `leno_level`, `apply_upgrade`, `get_upgrade_count`, `reset_pet`, novo `_refresh_tiliskos`)

- [ ] **Step 1: Vars**

Perto de `var leno_level: int = 0` (linha ~165), adicionar:

```gdscript
var tilisko_level: int = 0
var _tiliskos: Array[Node2D] = []
const TILISKO_SCENE: PackedScene = preload("res://scenes/allies/tilisko.tscn")
```

- [ ] **Step 2: apply_upgrade**

No `apply_upgrade`, após o bloco `"leno":`:

```gdscript
		"tilisko":
			tilisko_level = mini(tilisko_level + 1, 4)
			_refresh_tiliskos()
```

- [ ] **Step 3: get_upgrade_count**

No `get_upgrade_count`, após `"leno": return leno_level`:

```gdscript
		"tilisko": return tilisko_level
```

- [ ] **Step 4: reset_pet**

No `reset_pet`, após o bloco `"leno":` (que zera leno_level), adicionar tratamento do tilisko (zera nível + remove instâncias):

```gdscript
		"tilisko":
			tilisko_level = 0
			for t in _tiliskos:
				if is_instance_valid(t):
					t.queue_free()
			_tiliskos.clear()
```

- [ ] **Step 5: `_refresh_tiliskos` (1 instância)**

Adicionar (após `_refresh_lenos`/`_leno_target_count`):

```gdscript
func _refresh_tiliskos() -> void:
	# Sempre 1 Tilisko (o nível muda o dano/categorias da flecha, não a contagem).
	var alive: Array[Node2D] = []
	for t in _tiliskos:
		if is_instance_valid(t):
			alive.append(t)
	_tiliskos = alive
	if tilisko_level <= 0:
		return
	if _tiliskos.is_empty():
		var t: Node2D = TILISKO_SCENE.instantiate()
		_tiliskos.append(t)
		_get_world().add_child(t)
		t.global_position = global_position
```

- [ ] **Step 6: Validar + commit**

Run: import headless (EXIT=0).
```bash
rtk git add scripts/player/player.gd
rtk git commit -m "feat: nivel/upgrade/refresh/reset do pet Tilisko no player"
```

---

### Task 7: player.gd — disparo do Tilisko (hook no _release_arrow)

**Files:** Modify `scripts/player/player.gd` (fim do `_release_arrow`; novos helpers)

- [ ] **Step 1: Hook no fim do `_release_arrow`**

No fim do `_release_arrow` (depois do loop que spawna a volley do player), adicionar:

```gdscript
	# Tilisko: dispara junto com o player (mesma volley/flags pro L4).
	if tilisko_level > 0:
		_fire_tilisko_shots(locked_aim_dir, is_pierce, is_ricochet, is_graviton, volley)
```

(`is_pierce`, `is_ricochet`, `is_graviton` e `volley` já são variáveis locais do `_release_arrow`.)

- [ ] **Step 2: Helpers**

Adicionar (perto dos helpers de flecha):

```gdscript
func _fire_tilisko_shots(aim_dir: Vector2, is_pierce: bool, is_ricochet: bool, is_graviton: bool, volley: Array) -> void:
	var mult: float = [0.2, 0.3, 0.6, 0.6][clampi(tilisko_level - 1, 0, 3)]
	for t in get_tree().get_nodes_in_group("tilisko"):
		if not is_instance_valid(t):
			continue
		if t.has_method("on_player_shot"):
			t.on_player_shot()
		var origin: Vector2 = t.get_muzzle_pos() if t.has_method("get_muzzle_pos") else (t as Node2D).global_position
		var dir: Vector2 = aim_dir
		# L3+: 30% de chance de mirar num inimigo aleatório da tela (só na flecha única).
		if tilisko_level >= 3 and tilisko_level < 4 and randf() < 0.30:
			var e := _random_enemy_on_screen()
			if e != null:
				dir = ((e as Node2D).global_position - origin).normalized()
		if tilisko_level < 4:
			_spawn_tilisko_arrow(origin, dir, mult)
		else:
			# L4: volley completa do player (categorias + elementais) a 60%, do muzzle do Tilisko.
			for i in volley.size():
				var shot: Dictionary = volley[i]
				_spawn_arrow(shot["dir"], float(shot["dmg_mult"]) * mult, is_pierce, false, i == 0, is_ricochet, is_graviton, origin, "tilisko")


func _spawn_tilisko_arrow(origin: Vector2, dir: Vector2, mult: float) -> void:
	# L1-L3: 1 flecha simples com o pacote elemental do tiro atual (sem pierce/ricochet/
	# multi/spectral). Rola crit próprio no _on_hit (flecha normal).
	if arrow_scene == null:
		return
	var a = arrow_scene.instantiate()
	a.global_position = origin
	a.damage = a.damage * arrow_damage_multiplier * mult * _mare_damage_factor() * _cajado_arrow_factor()
	_stamp_spectral_effects(a)   # chain/fire/curse/ice/stone/tide/graviton (sem pierce/ricochet)
	a.source = self
	a.telemetry_source_id = "tilisko"
	a.suppress_spectral = true   # L1-L3 não tem propriedade de espectral
	a.play_shoot_sound = false   # não dobra o áudio do tiro
	_get_world().add_child(a)
	if a.has_method("set_direction"):
		a.set_direction(dir)


func _random_enemy_on_screen() -> Node:
	var vp_rect := get_viewport().get_visible_rect()
	var cam_xform := get_viewport().get_canvas_transform()
	var candidates: Array[Node] = []
	for e in get_tree().get_nodes_in_group("enemy"):
		if not is_instance_valid(e) or not (e is Node2D):
			continue
		if (e as Node).is_queued_for_deletion():
			continue
		if ("hp" in e) and float(e.hp) <= 0.0:
			continue
		var screen_pos: Vector2 = cam_xform * (e as Node2D).global_position
		if vp_rect.has_point(screen_pos):
			candidates.append(e)
	if candidates.is_empty():
		return null
	return candidates[randi() % candidates.size()]
```

- [ ] **Step 3: Validar + playtest**

Run: import headless (EXIT=0). Playtest: dev panel → dar `tilisko` → atirar → o pinguim atira junto na sua mira; checar dano (20%) + efeito elemental se tiver; L3 mira random às vezes; L4 vira volley.

- [ ] **Step 4: Commit**

```bash
rtk git add scripts/player/player.gd
rtk git commit -m "feat: Tilisko dispara junto com o player (L1-L3 flecha unica, L4 volley)"
```

---

### Task 8: Loja — pool de aliados, descrições, arte e texto branco

**Files:** Modify `scripts/ui/wave_shop.gd`

- [ ] **Step 1: `_ALL_ALLY_IDS`**

```gdscript
const _ALL_ALLY_IDS: Array[String] = ["claudio_druida", "leno", "capivara_joe", "ting", "mini_mago", "arbusto", "tilisko"]
```

- [ ] **Step 2: Const de descrições + mapeamento**

Adicionar perto das `*_DESCS` de aliado (ex.: após `LENO_DESCS`):

```gdscript
const TILISKO_DESCS: Array[String] = [
	"SHOP_ALLY_TILISKO_DESC_1",
	"SHOP_ALLY_TILISKO_DESC_2",
	"SHOP_ALLY_TILISKO_DESC_3",
	"SHOP_ALLY_TILISKO_DESC_4",
]
```

No `_get_upgrade_descs_array`, após `"leno": return LENO_DESCS`:

```gdscript
		"tilisko": return TILISKO_DESCS
```

- [ ] **Step 3: Arte do card (CARD_PATH_OVERRIDES)**

Adicionar no `CARD_PATH_OVERRIDES`:

```gdscript
	"tilisko": "res://assets/Hud/shop/aliado/tilisko/tilosko card.png",
```

- [ ] **Step 4: Nome do card + texto branco**

Conferir como o card de aliado pega o `name` (provavelmente via id → `SHOP_ALLY_<ID>`). Garantir a key `SHOP_ALLY_TILISKO` (Task 11). Para o **texto branco**: localizar onde o card de aliado aplica `ALIADO_TEXT_COLOR` (no `_build_card`/`_apply_card_art` do grupo aliado) e adicionar override por id:

```gdscript
# Tilisko usa texto branco (a arte do card é escura).
var _txt_color: Color = Color.WHITE if slot_id == "tilisko" else ALIADO_TEXT_COLOR
```
(usar `_txt_color` onde hoje usa `ALIADO_TEXT_COLOR` no card de aliado; conferir o ponto exato na execução.)

- [ ] **Step 5: Validar + commit**

Run: import headless (EXIT=0).
```bash
rtk git add scripts/ui/wave_shop.gd
rtk git commit -m "feat: Tilisko na loja (pool + descricoes + arte + texto branco)"
```

---

### Task 9: Starter pack (pool de boas-vindas)

**Files:** Modify `scripts/systems/wave_manager.gd` (`FREE_UPGRADE_POOL`)

- [ ] **Step 1: Adicionar tilisko**

No `FREE_UPGRADE_POOL`, após a entry do `claudio_druida` (ou junto dos aliados):

```gdscript
	{"id": "tilisko", "name": "SHOP_ALLY_TILISKO"},
```

- [ ] **Step 2: Validar + commit**

Run: import headless (EXIT=0).
```bash
rtk git add scripts/systems/wave_manager.gd
rtk git commit -m "feat: Tilisko entra no starter pack (FREE_UPGRADE_POOL)"
```

---

### Task 10: Dev mode + HUDs + painel de dano

**Files:** Modify `scripts/ui/dev_panel.gd`, `scenes/ui/dev_panel.tscn`, `scripts/ui/hud.gd`, `scripts/ui/damage_panel.gd`

- [ ] **Step 1: Dev panel — UPGRADE_BTNS**

Em `dev_panel.gd`, no `UPGRADE_BTNS`, após a entry do leno:

```gdscript
	{"id": "tilisko", "node": "UpgTiliskoBtn", "max": 4, "base_text": "+1 Tilisko"},
```

- [ ] **Step 2: Dev panel — `_ALL_UPGRADE_IDS`**

Adicionar `"tilisko"` ao array `_ALL_UPGRADE_IDS` (junto dos aliados, ex.: após `"leno"`).

- [ ] **Step 3: Dev panel `.tscn` — botão**

Em `dev_panel.tscn`, clonar o `UpgLenoBtn` (achar o nó e o container dele) criando `UpgTiliskoBtn` com `text = "+1 Tilisko"` no mesmo container de aliados.

- [ ] **Step 4: HUD — listas**

Em `hud.gd`: adicionar `"tilisko"` em `UPGRADE_DISPLAY_ORDER` (perto dos aliados) e em `_BUILD_UPGRADE_IDS` (seção Aliados). Em `_UPG_PATHS`, adicionar `"tilisko": "res://assets/Hud/shop/aliado/tilisko/tilosko card.png"`. Se existir `_UPG_ALIADO_IDS`, adicionar `"tilisko"` (pro fallback/categoria de aliado).

- [ ] **Step 5: Painel de dano — SOURCE_LABELS**

Em `damage_panel.gd`, no `SOURCE_LABELS`, após `"leno": "DMG_PANEL_LENO"`:

```gdscript
	"tilisko": "DMG_PANEL_TILISKO",
```

- [ ] **Step 6: Validar + commit**

Run: import headless (EXIT=0).
```bash
rtk git add scripts/ui/dev_panel.gd scenes/ui/dev_panel.tscn scripts/ui/hud.gd scripts/ui/damage_panel.gd
rtk git commit -m "feat: Tilisko no dev panel + HUD chip/build + painel de dano"
```

---

### Task 11: i18n

**Files:** Modify `assets/i18n/translations.csv`

- [ ] **Step 1: Adicionar keys (5 colunas: keys,pt_BR,en,es,fr)**

```
SHOP_ALLY_TILISKO,Tilisko Arqueiro,Tilisko Archer,Tilisko Arquero,Tilisko Archer
SHOP_ALLY_TILISKO_DESC_1,"Um pinguim arqueiro que fica perto de você e atira junto a cada disparo seu, mirando na sua direção. A flecha causa 20% do seu dano e aplica os mesmos efeitos.","A penguin archer that stays near you and shoots with every shot you take, aiming your way. The arrow deals 20% of your damage and applies the same effects.","Un pingüino arquero que se queda cerca de ti y dispara con cada tiro tuyo, apuntando en tu dirección. La flecha causa 20% de tu daño y aplica los mismos efectos.","Un pingouin archer qui reste près de vous et tire à chacun de vos tirs, visant dans votre direction. La flèche inflige 20% de vos dégâts et applique les mêmes effets."
SHOP_ALLY_TILISKO_DESC_2,A flecha do Tilisko causa 30% do seu dano.,Tilisko's arrow deals 30% of your damage.,La flecha de Tilisko causa 30% de tu daño.,La flèche de Tilisko inflige 30% de vos dégâts.
SHOP_ALLY_TILISKO_DESC_3,"A flecha causa 60% do seu dano, e o Tilisko tem 30% de chance de mirar num inimigo aleatório da tela.","The arrow deals 60% of your damage, and Tilisko has a 30% chance to aim at a random enemy on screen.","La flecha causa 60% de tu daño, y Tilisko tiene 30% de probabilidad de apuntar a un enemigo aleatorio en pantalla.","La flèche inflige 60% de vos dégâts, et Tilisko a 30% de chance de viser un ennemi aléatoire à l'écran."
SHOP_ALLY_TILISKO_DESC_4,"As flechas do Tilisko passam a seguir TODAS as suas categorias: perfuram, ricocheteiam, saem múltiplas/duplas e espectrais.","Tilisko's arrows now follow ALL your categories: they pierce, ricochet, fire multiple/double and spectral.","Las flechas de Tilisko ahora siguen TODAS tus categorías: perforan, rebotan, salen múltiples/dobles y espectrales.","Les flèches de Tilisko suivent désormais TOUTES vos catégories : perforation, ricochet, multiples/doubles et spectrales."
DMG_PANEL_TILISKO,Tilisko,Tilisko,Tilisko,Tilisko
```

- [ ] **Step 2: Reimportar + validar**

Run: import headless (gera os `.translation`, EXIT=0). Loja mostra nome/descrição traduzidos; card do Tilisko com texto branco.

- [ ] **Step 3: Commit**

```bash
rtk git add assets/i18n/translations.csv
rtk git commit -m "i18n: strings do Tilisko (nome + 4 niveis + painel de dano)"
```

---

### Task 12: Playtest integrado final

- [ ] **Step 1: Smoke test**

Pelo dev panel (botão +1 Tilisko): comprar L1 → 1 pinguim segue, sem HP, ignorado pelos inimigos. Atirar: ele toca "atirar" e solta flecha na sua mira, 20% dano + efeitos (testar com fogo/maré/pedra). Subir L2 (30%), L3 (60% + mira random às vezes), L4 (volley: comprar perfuração/múltiplas e ver o Tilisko perfurar/abrir leque a 60%; com espectral, as flechas L4 procam espectral). Confirmar: card na loja (texto branco), chip na HUD, linha "Tilisko" no TAB, build no fim de jogo, starter pack. Sem o pet: regressão zero.

- [ ] **Step 2: Import final + commit (se ajuste)**

Run: import headless (EXIT=0).

---

## Self-Review

- **Spec coverage:** pet/follow/sem-HP → Tasks 2-3,6; dispara junto (L1-L3 flecha única, pacote elemental, sem pierce/ricochet/multi/spectral) → Task 7 (`_spawn_tilisko_arrow` + `suppress_spectral` Task 4); L3 mira random → Task 7 (`_random_enemy_on_screen`); L4 volley categorias 60% → Task 7 + `_spawn_arrow` origin/source_id (Task 5); crit próprio → flecha normal (não-spectral) rola crit no `_on_hit`; dano 20/30/60/60 → Task 7 `mult`; efeitos completos → `_stamp_spectral_effects`; integração loja/starter/dev/HUDs/painel → Tasks 8-11; arte → Tasks 1,3.
- **Placeholder scan:** sem TBD. Pontos "conferir na execução": cor de texto do card de aliado (Task 8 Step 4), nó do container de botões do dev panel (Task 10 Step 3), `_UPG_ALIADO_IDS` (Task 10 Step 4) — todos com âncora descrita.
- **Consistência:** `tilisko` id em todos os pontos; `telemetry_source_id="tilisko"` ↔ `DMG_PANEL_TILISKO`; `suppress_spectral` definido (Task 4) e usado (Task 7); `_spawn_arrow` novos params (Task 5) usados no L4 (Task 7); `on_player_shot`/`get_muzzle_pos` definidos (Task 2) e chamados (Task 7).
- **Risco:** o `_spawn_arrow` ganha 2 params opcionais (defaults preservam comportamento) — validar regressão das flechas normais no playtest. L4 reusa a volley do player (mira do player; o random-aim do L3 é só pra flecha única — decisão registrada no spec).
