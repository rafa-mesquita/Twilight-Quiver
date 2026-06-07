# Essência Vital Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Adicionar o item equipável Essência Vital — cada status de HP comprado dá +5 HP extra e −10% de cooldown global (teto −50%); desbloqueia ao matar o boss da wave 7 (Mage Monkey) com ≥2 status de HP na mesma run.

**Architecture:** Item novo no catálogo `InventoryItems` com efeito `hp_status_bonus` e unlock `quest`. O CDR é global e implementado fazendo cada cooldown **drenar mais rápido** (multiplica `delta` por `cooldown_drain_mult()` no player), mantendo resets e totais da HUD intactos. O +5 HP entra na compra do status de HP. O unlock espelha o padrão composto do Capacete Veloz (flag de run → stat persistente).

**Tech Stack:** Godot 4 / GDScript. Sem framework de teste automatizado — verificação é abrir o editor (sem erro de parse) + playtest com o dev panel (`DEV_UNLOCK_ALL_ITEMS = true` em debug já libera o item).

**Spec:** `docs/superpowers/specs/2026-06-07-essencia-vital-design.md`

---

## File Structure

- `scripts/systems/inventory_items.gd` — entrada `essencia_vital` no `ITEMS` + ramo `hp_status_bonus` em `apply_to_player`.
- `scripts/player/player.gd` — flags/params do item, `cooldown_scale()`/`cooldown_drain_mult()`, +5 HP no `apply_upgrade("hp")`, drain em todos os `_update_*`, flag de unlock em `notify_boss_killed`.
- `scripts/allies/{frostwisp,ting_turret,leno,mini_mago,capivara_joe}.gd` — drain no decremento do timer de auto-cast.
- `scripts/ui/hud.gd` — `essencia_vital_unlock` em `_collect_run_stats`.
- `scripts/systems/skin_loadout.gd` — `STAT_ESSENCIA_VITAL` + commit do stat persistente.
- `assets/i18n/translations.csv` — 3 keys novas.
- `assets/Hud/itens/essencia_vital.png` — ícone (arte pronta).

---

### Task 1: Catálogo do item + flags no player

**Files:**
- Modify: `scripts/systems/inventory_items.gd` (dict `ITEMS` ~138; `apply_to_player` ~435)
- Modify: `scripts/player/player.gd:533` (após `_capacete_veloz_equipped`)

- [ ] **Step 1: Declarar flags/params do item no player**

Em `scripts/player/player.gd`, logo após a linha 533 (`var _capacete_veloz_equipped: bool = false`), adicionar:

```gdscript
# Essência Vital (item): cada status de HP comprado dá +5 HP máx extra e −10% de
# cooldown global (teto −50%). Setado por InventoryItems.apply_to_player. CDR lido
# em cooldown_scale()/cooldown_drain_mult(); +5 HP somado em apply_upgrade("hp").
var _essencia_vital_equipped: bool = false
var _essencia_cdr_per_level: float = 0.10
var _essencia_cdr_cap: float = 0.50
var _essencia_hp_per_level: float = 5.0
```

- [ ] **Step 2: Adicionar a entrada do item no catálogo**

Em `scripts/systems/inventory_items.gd`, dentro do dict `ITEMS`, logo após o bloco `capacete_veloz` (depois da linha 138 `},`), adicionar:

```gdscript
	"essencia_vital": {
		"name": "ITEM_ESSENCIA_VITAL_NAME",
		"desc": "ITEM_ESSENCIA_VITAL_DESC",
		"icon": "res://assets/Hud/itens/essencia_vital.png",
		"effect": {"type": "hp_status_bonus", "cdr_per_level": 0.10, "cdr_cap": 0.50, "hp_per_level": 5},
		"unlock": {"type": "quest", "reqs": [
			{"stat": &"essencia_vital_unlock", "value": 1, "label": "ITEM_REQ_ESSENCIA_VITAL"},
		]},
	},
```

- [ ] **Step 3: Ramo `hp_status_bonus` em `apply_to_player`**

Em `scripts/systems/inventory_items.gd`, dentro de `apply_to_player`, logo após o bloco do `armor_dodge` (linhas 435-438), adicionar este `elif`:

```gdscript
			elif t == "hp_status_bonus":
				# Essência Vital: liga o item e guarda os params (CDR por status de HP + HP extra).
				if "_essencia_vital_equipped" in player:
					player._essencia_vital_equipped = true
					player._essencia_cdr_per_level = float(eff.get("cdr_per_level", 0.10))
					player._essencia_cdr_cap = float(eff.get("cdr_cap", 0.50))
					player._essencia_hp_per_level = float(eff.get("hp_per_level", 5.0))
```

- [ ] **Step 4: Verificar parse no editor**

Abrir o projeto no Godot. Esperado: sem erro de parse no Output. O item Essência Vital aparece na tela Player (debug libera todos via `DEV_UNLOCK_ALL_ITEMS`).

- [ ] **Step 5: Commit**

```bash
rtk git add scripts/systems/inventory_items.gd scripts/player/player.gd
rtk git commit -m "feat: catalogo + flags da Essencia Vital"
```

---

### Task 2: Strings i18n

**Files:**
- Modify: `assets/i18n/translations.csv`

- [ ] **Step 1: Adicionar as 3 keys no CSV**

Em `assets/i18n/translations.csv`, adicionar três linhas novas (manter as duas colunas `pt_BR` e `en` preenchidas; aspas duplas por causa das vírgulas):

```
ITEM_ESSENCIA_VITAL_NAME,Essência Vital,Vital Essence
ITEM_ESSENCIA_VITAL_DESC,"Cada status de HP também dá −10% de cooldown (até −50%) e +5 de HP máximo.","Each HP upgrade also grants −10% cooldown (up to −50%) and +5 max HP."
ITEM_REQ_ESSENCIA_VITAL,Vença o boss da wave 7 com ao menos 2 status de HP,Beat the wave 7 boss with at least 2 HP upgrades
```

- [ ] **Step 2: Reimportar e verificar no editor**

Reabrir/focar o Godot pra reimportar o CSV (gera `translations.pt_BR.translation` / `translations.en.translation`). Na tela Player, o nome/descrição do item aparecem traduzidos (não a key crua `ITEM_ESSENCIA_VITAL_NAME`).

- [ ] **Step 3: Commit**

```bash
rtk git add assets/i18n/translations.csv "assets/i18n/translations.pt_BR.translation" assets/i18n/translations.en.translation
rtk git commit -m "i18n: strings da Essencia Vital"
```

---

### Task 3: +5 HP por status de HP

**Files:**
- Modify: `scripts/player/player.gd:3447-3457` (ramo `"hp"` do `apply_upgrade`)

- [ ] **Step 1: Somar o HP extra do item no ganho do status**

Em `scripts/player/player.gd`, no ramo `"hp":` do `apply_upgrade` (linhas 3447-3457), inserir o bônus do item logo após o `match hp_upgrades:` que define `hp_gain` e **antes** de `max_hp += hp_gain`. O bloco fica assim:

```gdscript
		"hp":
			hp_upgrades += 1
			# Curva por nível: L1=+18, L2=+20, L3=+22, L4+=+25.
			var hp_gain: float = 25.0
			match hp_upgrades:
				1: hp_gain = 18.0
				2: hp_gain = 20.0
				3: hp_gain = 22.0
				_: hp_gain = 25.0
			# Essência Vital: +5 HP máx extra por status de HP comprado.
			if _essencia_vital_equipped:
				hp_gain += _essencia_hp_per_level
			max_hp += hp_gain
			hp = min(hp + hp_gain, max_hp)
			hp_changed.emit(hp, max_hp)
			if hp_bar != null:
				hp_bar.set_ratio(hp / max_hp)
```

- [ ] **Step 2: Verificar em playtest**

Equipar Essência Vital (tela Player) → iniciar run → comprar 1 status de HP na loja. Esperado: o `max_hp` sobe +18 (curva L1) **+5** = +23 no total. Sem o item equipado, sobe só +18.

- [ ] **Step 3: Commit**

```bash
rtk git add scripts/player/player.gd
rtk git commit -m "feat: Essencia Vital da +5 HP por status de HP"
```

---

### Task 4: Métodos de cooldown no player

**Files:**
- Modify: `scripts/player/player.gd:4427` (antes de `func reset_all_cooldowns()`)

- [ ] **Step 1: Adicionar `cooldown_scale()` e `cooldown_drain_mult()`**

Em `scripts/player/player.gd`, inserir logo **antes** da linha 4428 (`func reset_all_cooldowns() -> void:`), separados por uma linha em branco:

```gdscript
# Fator de cooldown (1.0 = sem redução, 0.5 = −50%). Essência Vital reduz 10% por
# status de HP comprado (hp_upgrades), com teto de CDR de 50%. Lido ao vivo.
func cooldown_scale() -> float:
	if not _essencia_vital_equipped:
		return 1.0
	var cdr: float = minf(float(hp_upgrades) * _essencia_cdr_per_level, _essencia_cdr_cap)
	return 1.0 - cdr


# Multiplicador da DRENAGEM de cooldown (>= 1.0; 2.0 no cap de −50%). Os _update_*
# que decrementam cd_remaining usam `delta * cooldown_drain_mult()` — o reset e o
# "total" emitido pra HUD ficam intactos (barra começa cheia, drena mais rápido).
func cooldown_drain_mult() -> float:
	return 1.0 / cooldown_scale()


```

- [ ] **Step 2: Verificar parse no editor**

Abrir o Godot. Esperado: sem erro de parse. (Sem efeito observável ainda — os sites de drain entram na Task 5.)

- [ ] **Step 3: Commit**

```bash
rtk git add scripts/player/player.gd
rtk git commit -m "feat: cooldown_scale/drain_mult no player (Essencia Vital)"
```

---

### Task 5: Drenar cooldowns das skills do player

**Files:**
- Modify: `scripts/player/player.gd` (13 sites de decremento em `_update_*`)

Cada edit troca `- delta` por `- delta * cooldown_drain_mult()` **apenas no decremento** (não no reset). As linhas abaixo são as âncoras exatas.

- [ ] **Step 1: Tide shield (linha 1665)**

```gdscript
		_tide_shield_cd_remaining = maxf(_tide_shield_cd_remaining - delta * cooldown_drain_mult(), 0.0)
```

- [ ] **Step 2: Fenda (linha 2176)**

```gdscript
		_fenda_cd_remaining = maxf(_fenda_cd_remaining - delta * cooldown_drain_mult(), 0.0)
```

- [ ] **Step 3: Fogo (linha 2370)**

```gdscript
		_fire_skill_cd_remaining = maxf(_fire_skill_cd_remaining - delta * cooldown_drain_mult(), 0.0)
```

- [ ] **Step 4: Cadeia de Raios — skill (linha 2403)**

```gdscript
		_chain_lightning_skill_cd_remaining = maxf(_chain_lightning_skill_cd_remaining - delta * cooldown_drain_mult(), 0.0)
```

- [ ] **Step 5: Cadeia de Raios — auto-bolt (linha 2416)**

```gdscript
		_chain_auto_bolt_cd_remaining = maxf(_chain_auto_bolt_cd_remaining - delta * cooldown_drain_mult(), 0.0)
```

- [ ] **Step 6: Boomerangue (linha 2479)**

```gdscript
		_boomerang_cd_remaining = maxf(_boomerang_cd_remaining - delta * cooldown_drain_mult(), 0.0)
```

- [ ] **Step 7: Garras de Tigre (linha 2527)**

```gdscript
		_tiger_claws_cd_remaining = maxf(_tiger_claws_cd_remaining - delta * cooldown_drain_mult(), 0.0)
```

- [ ] **Step 8: Maldição (linha 2723)**

```gdscript
		_curse_skill_cd_remaining = maxf(_curse_skill_cd_remaining - delta * cooldown_drain_mult(), 0.0)
```

- [ ] **Step 9: Pedra — Terremoto (linha 2774)**

```gdscript
		_stone_skill_cd_remaining = maxf(_stone_skill_cd_remaining - delta * cooldown_drain_mult(), 0.0)
```

- [ ] **Step 10: Gelo — Time Freeze (linha 2821)**

```gdscript
		_time_freeze_cd_remaining = maxf(_time_freeze_cd_remaining - delta * cooldown_drain_mult(), 0.0)
```

- [ ] **Step 11: Dash (linha 3017)**

```gdscript
		_dash_cd_remaining = maxf(_dash_cd_remaining - delta * cooldown_drain_mult(), 0.0)
```

- [ ] **Step 12: Adrenalina (linha 3236)**

```gdscript
		_adrenalina_cd_remaining = maxf(_adrenalina_cd_remaining - delta * cooldown_drain_mult(), 0.0)
```

> Nota: Esquivando usa a mesma habilidade do slot de mobilidade via `_adrenalina`/dash? Não — o cooldown da habilidade do Esquivando é gerido pelo mesmo grupo de skills de mobilidade já cobertas (dash/fenda/adrenalina). Se houver um `_update_*` próprio do Esquivando com `cd_remaining -= delta`, aplicar o mesmo padrão. Procurar por `esquivando` + `cd_remaining` antes de fechar a task; se existir um site equivalente, drenar igual.

- [ ] **Step 13: Verificar em playtest**

Equipar Essência Vital, iniciar run, comprar 5 status de HP (ou usar o dev panel pra forçar HP). Com uma skill ativa (ex.: dash), observar a barra de cooldown na HUD: começa cheia e drena **2× mais rápido** (cd efetivo metade). Sem o item, cadência normal.

- [ ] **Step 14: Commit**

```bash
rtk git add scripts/player/player.gd
rtk git commit -m "feat: CDR global drena cooldowns das skills do player (Essencia Vital)"
```

---

### Task 6: Drenar auto-cast dos aliados

**Files:**
- Modify: `scripts/allies/frostwisp.gd:122`
- Modify: `scripts/allies/ting_turret.gd:59`
- Modify: `scripts/allies/leno.gd:67`
- Modify: `scripts/allies/mini_mago.gd:73`
- Modify: `scripts/allies/capivara_joe.gd:55`

Cada aliado já guarda `_player`. O drain lê o player com guarda contra nulo.

- [ ] **Step 1: Frostwisp (linha 122)**

Trocar `_attack_cd_remaining -= delta` por:

```gdscript
	_attack_cd_remaining -= delta * _cd_drain_mult()
```

E adicionar um helper privado no fim do arquivo (ou junto dos outros métodos):

```gdscript
# Drenagem de cooldown acelerada pela Essência Vital do player (1.0 se sem item).
func _cd_drain_mult() -> float:
	if _player != null and is_instance_valid(_player) and _player.has_method("cooldown_drain_mult"):
		return _player.cooldown_drain_mult()
	return 1.0
```

- [ ] **Step 2: Ting Turret (linha 59)**

Trocar por:

```gdscript
		_attack_cd_remaining = maxf(_attack_cd_remaining - delta * _cd_drain_mult(), 0.0)
```

Adicionar o mesmo helper `_cd_drain_mult()`. Conferir o nome da ref de player neste script (pode ser `_player`); ajustar o helper pra usar a ref correta.

- [ ] **Step 3: Leno (linha 67)**

```gdscript
		_attack_cd_remaining = maxf(_attack_cd_remaining - delta * _cd_drain_mult(), 0.0)
```

Adicionar helper `_cd_drain_mult()` (Leno já tem `_player`).

- [ ] **Step 4: Mini-mago (linha 73)**

```gdscript
		_summon_cd = maxf(_summon_cd - delta * _cd_drain_mult(), 0.0)
```

Adicionar helper `_cd_drain_mult()` (conferir a ref de player neste script).

- [ ] **Step 5: Capivara Joe (linha 55)**

```gdscript
		_drop_cd = maxf(_drop_cd - delta * _cd_drain_mult(), 0.0)
```

Adicionar helper `_cd_drain_mult()` (conferir a ref de player neste script).

- [ ] **Step 6: Verificar em playtest**

Equipar Essência Vital + comprar vários HP, ter um aliado com auto-cast (ex.: Frostwisp via Gelo Lv3). Esperado: o aliado ataca/invoca com intervalo ~metade no cap. Sem o item: intervalo normal.

- [ ] **Step 7: Commit**

```bash
rtk git add scripts/allies/frostwisp.gd scripts/allies/ting_turret.gd scripts/allies/leno.gd scripts/allies/mini_mago.gd scripts/allies/capivara_joe.gd
rtk git commit -m "feat: CDR global drena auto-cast dos aliados (Essencia Vital)"
```

---

### Task 7: Unlock — quest composto (boss w7 + 2 HP)

**Files:**
- Modify: `scripts/player/player.gd:638-645` (nova var de run) e `:4797` (set no `notify_boss_killed`)
- Modify: `scripts/ui/hud.gd:2096` (linha do `capacete_veloz_unlock`)
- Modify: `scripts/systems/skin_loadout.gd:283` (const) e `:841` (commit)

- [ ] **Step 1: Var de run no player**

Em `scripts/player/player.gd`, junto das outras stats de run (logo após a linha 645 `var stats_armor_before_w4: bool = false`), adicionar:

```gdscript
# Flag de run: matou o Mage Monkey (boss da wave 7/14) tendo >= 2 status de HP
# comprados nesse instante. Unlock do item Essência Vital. Setada em notify_boss_killed.
var stats_essencia_vital_unlock: bool = false
```

- [ ] **Step 2: Setar a flag no `notify_boss_killed`**

Em `scripts/player/player.gd`, dentro de `notify_boss_killed` (após `stats_bosses_killed.append(boss_id)` na linha 4797), adicionar:

```gdscript
	# Essência Vital: boss da wave 7 (Mage Monkey) morto com >= 2 status de HP na run.
	if boss_id == "mage_monkey" and hp_upgrades >= 2:
		stats_essencia_vital_unlock = true
```

- [ ] **Step 3: Expor no run_stats da HUD**

Em `scripts/ui/hud.gd`, logo após a linha 2096 (`"capacete_veloz_unlock": ...`), adicionar:

```gdscript
		"essencia_vital_unlock": (p != null and "stats_essencia_vital_unlock" in p and bool(p.get("stats_essencia_vital_unlock"))),
```

- [ ] **Step 4: Const do stat persistente no SkinLoadout**

Em `scripts/systems/skin_loadout.gd`, logo após a linha 283 (`const STAT_CAPACETE_VELOZ: ...`), adicionar:

```gdscript
# Flag (0/1): em alguma run, matou o boss da wave 7 (mage_monkey) com >= 2 status de
# HP na mesma run. Unlock do item Essência Vital.
const STAT_ESSENCIA_VITAL: StringName = &"essencia_vital_unlock"
```

- [ ] **Step 5: Commit do stat no record_run**

Em `scripts/systems/skin_loadout.gd`, logo após o bloco do `capacete_veloz_unlock` (linhas 840-841), adicionar:

```gdscript
	# Flag persistente: matou o boss da wave 7 com >= 2 status de HP nesta run
	# (unlock do item Essência Vital).
	if bool(run_stats.get("essencia_vital_unlock", false)) and get_stat(STAT_ESSENCIA_VITAL) < 1:
		set_stat(STAT_ESSENCIA_VITAL, 1)
```

- [ ] **Step 6: Verificar a lógica de unlock**

Como `DEV_UNLOCK_ALL_ITEMS` mascara o unlock em debug, testar o caminho real temporariamente: no editor, com o item travado, confirmar via código/print que `stats_essencia_vital_unlock` vira `true` ao matar o Mage Monkey com `hp_upgrades >= 2`, e `false` com `hp_upgrades < 2`. (Opcional: setar `DEV_UNLOCK_ALL_ITEMS = false` localmente, jogar até a wave 7 com 2 HP, matar o boss, morrer, e confirmar que o item destrava na tela Player. Reverter a flag depois.)

- [ ] **Step 7: Commit**

```bash
rtk git add scripts/player/player.gd scripts/ui/hud.gd scripts/systems/skin_loadout.gd
rtk git commit -m "feat: unlock da Essencia Vital (boss w7 + 2 status de HP)"
```

---

### Task 8: Arte + verificação final

**Files:**
- Create: `assets/Hud/itens/essencia_vital.png` (+ `.import` gerado pelo Godot)

- [ ] **Step 1: Colocar o ícone**

Salvar a arte do item como `assets/Hud/itens/essencia_vital.png`, mesma resolução/padrão dos outros ícones de item (ex.: `sanguinario.png`). Reabrir o Godot pra gerar o `essencia_vital.png.import`.

- [ ] **Step 2: Verificar o ícone na UI**

Tela Player: o slot do item Essência Vital mostra o ícone novo (não o placeholder quebrado). Hover mostra nome + descrição traduzidos; travado, mostra o requisito de unlock.

- [ ] **Step 3: Smoke test integrado**

Equipar Essência Vital, jogar uma run curta: comprar 3 status de HP → confirmar +5 HP por compra e cooldowns ~30% mais rápidos; comprar até 5+ → CDR para em 50% (não passa). Desequipar → tudo volta ao normal (regressão zero).

- [ ] **Step 4: Commit**

```bash
rtk git add "assets/Hud/itens/essencia_vital.png" "assets/Hud/itens/essencia_vital.png.import"
rtk git commit -m "art: icone da Essencia Vital"
```

---

## Self-Review

- **Spec coverage:** efeito (+5 HP por status) → Task 3; CDR global (skills + auto-cast aliados) → Tasks 4-6; teto 50% → Task 4 (`minf` com `_essencia_cdr_cap`); unlock composto → Task 7; i18n → Task 2; arte → Task 8; item travado/inerte sem equipar → garantido por `_essencia_vital_equipped` (default false) + `cooldown_scale()` retornando 1.0.
- **Maldição (duração vs cooldown):** coberto pela abordagem de drain — só o gate `_curse_skill_cd_remaining` drena mais rápido; o beam é nó separado com `lifetime` próprio. Task 5 Step 8.
- **Consistência de tipos:** `cooldown_scale()`/`cooldown_drain_mult()` (player) e `_cd_drain_mult()` (aliados, helper local) — nomes batem entre Tasks 4, 5 e 6. Flag `_essencia_vital_equipped` e params `_essencia_*` definidos na Task 1 e usados nas Tasks 3, 4.
- **Pontos a confirmar durante execução:** (a) nome exato da ref de player em `ting_turret`/`mini_mago`/`capivara_joe` (Task 6 pede pra conferir antes de fechar); (b) existência de um `_update_*` próprio do Esquivando com decremento (Task 5 Step 12 nota) — se houver, drenar igual.
