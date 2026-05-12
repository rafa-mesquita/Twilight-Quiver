# Próxima Sessão

> Última atualização: 2026-05-12
> Sessão anterior: Balance pass (Life Steal nerf + electric mage + boss gold pool + curse beam fix + armor slow res + insect nerf) + novo upgrade **Esquivando** completo (4 níveis, mutex com Dash, HUD com stacks/glow/rastro) + heart magnet limitado por raio + curse ally drops gold.

## Estado atual

- **Branch:** `main` em `https://github.com/rafa-mesquita/Twilight-Quiver`. Último commit local `07f4c7b` (push feito). Working tree limpo (só CRLF warning no `.import` do esquivando, sem conteúdo).
- **Versão:** `pre-alpha-0.3.3` (0.3.2 já foi pro download pelo Henrique; 0.3.3 ainda não deployed).
- **🎮 Auto-deploy GH Pages:** `https://rafa-mesquita.github.io/Twilight-Quiver/` (push pro main → Actions builda ~1-3min).
- **Novidade principal:** upgrade **Esquivando** (categoria movimentação) com 4 níveis, mutuamente exclusivo com Dash. Compartilha card art (`deslizando.png`) e barra de cooldown na HUD.

## Por onde começar

1. **Playtest do Esquivando** — Buff de +50% move por 3s (lv3+) com rastro branco no player. Confirmar feel: tempo, cooldown (15s lv3 / 10s lv4), buff stack 5/8/10% no atk+move speed, dodge 2/5%. Validar que ícone na HUD reposiciona corretamente: à esquerda (x=150) sem elemental, à direita (x=330) com elemental.

2. **Confirmar visualmente** os fixes do balance pass anterior:
   - Boss curse beam: hitbox menor (17 vs 31), sem dano durante fade
   - Heart magnet L4: só puxa dentro de 220px (não mais mapa todo)
   - Fim de wave: corações fora de 260px somem silenciosamente
   - Insect dmg -25%, electric mage atk speed 6.25s, dmg 12.75
   - Fogo splash DoT (50% nos 2 inimigos mais próximos no raio 70px)

3. **Validar curse_ally agora dropa gold** — qualquer inimigo virado aliado via Maldição (mage, monkey, stone_cube) dropa gold com a mesma % original quando morre. Insect e boss minions (gold_drop_chance=0) continuam sem dropar.

4. **Coletar feedback dos novos números** — armor slow resistance (metade da % de dano), boss gold 16-30 com pool ponderada (80% rola 16-23, 20% rola 24-30; wave 14 escala via BOSS_REDUX_GOLD_MULT 3.5 cobrindo min/max/pivot).

## Contexto crítico

### NÃO desfazer: arrow.source/volley_id FORA do `if is_graviton:`
Bug pré-existente: `arrow.source = self` estava indentado dentro do `if is_graviton:` em [scripts/player/player.gd](scripts/player/player.gd) `_spawn_arrow`. Resultado: pra flechas não-graviton, source era null e `notify_esquivando_hit` no arrow.gd retornava silenciosamente. Fix moveu source e volley_id pra fora do bloco. Se refatorar o `_spawn_arrow`, manter source/volley_id no nível do corpo da função.

### Esquivando + Dash são mutuamente exclusivos
Compartilham slot da barra de espaço. Adicionado a `EXCLUSIVE_PAIRS` em [scripts/ui/wave_shop.gd](scripts/ui/wave_shop.gd) e filtro bidirecional em `_grant_free_random_upgrade` ([scripts/systems/wave_manager.gd](scripts/systems/wave_manager.gd)). `apply_upgrade` em player.gd recusa defensivamente o segundo.

### Esquivando volley_id: lv1-3 só 1 stack por volley
[scripts/player/player.gd](scripts/player/player.gd) `notify_esquivando_hit`: lv1-3 bloqueia stacks adicionais se `arrow.gave_esquivando_stack` (flecha já stackou) OU `arrow.volley_id == _esquivando_last_stack_volley` (volley já stackou). Lv4 ignora ambos os flags — cada hit conta (multi-arrow, pierce, ricochet, cada um). Volley_id incrementa em `_release_arrow` e `_dash_auto_attack_volley`.

### Esquivando ícone HUD reposiciona dinamicamente
[scripts/ui/hud.gd](scripts/ui/hud.gd) `_update_esquivando_icon_position`: se player tem fire/chain lv3+ OU curse lv4+ → ícone vai pra x=330. Senão → x=150 (slot do elemental, ainda vago). Chamado em `_on_esquivando_unlocked`, `_on_fire_skill_unlocked`, `_on_chain_lightning_skill_unlocked`, `_on_curse_skill_unlocked`.

### Heart magnet AGORA tem raio limitado
[scripts/pickups/heart.gd](scripts/pickups/heart.gd):
- `MAGNET_RADIUS_L3 = 110` (mesmo de antes)
- `MAGNET_RADIUS_L4 = 220` (NOVO — antes era "mapa todo")
- `MAGNET_END_WAVE_RADIUS = 260` (NOVO — fim de wave também limita)

[scripts/systems/wave_manager.gd](scripts/systems/wave_manager.gd) `_magnet_remaining_gold`: hearts fora de 260px do player fazem `queue_free()` silencioso. Não acumulam entre waves.

### Curse_ally dropa gold mas NÃO heart nem conta como enemy_killed
[scripts/enemies/mage_enemy.gd, monkey_enemy.gd, stone_cube_enemy.gd]: o `if not is_curse_ally:` agora envolve apenas heart drop + `notify_enemy_killed`. Gold drop foi movido pra FORA. Mesma chance % do inimigo original. Insect continua sem dropar (script nunca chama GoldDrop). Boss minions continuam sem dropar (gold_drop_chance=0 setado no spawn).

### Boss gold pool ponderada (range 16-30)
[scripts/enemies/mage_monkey.gd](scripts/enemies/mage_monkey.gd) tem `gold_drop_min=16`, `gold_drop_max=30`, `gold_drop_pivot=23`, `gold_drop_pivot_chance=0.80`. No death: 80% rola randi_range(16, 23), 20% rola randi_range(24, 30). Wave 14 boss escala min/max/pivot por `BOSS_REDUX_GOLD_MULT = 3.5` → range 56-105 com pivot 80.

### Boss curse beam: hitbox alinhada ao sprite
[scripts/skills/curse_beam.gd](scripts/skills/curse_beam.gd) + [scripts/enemies/mage_monkey.gd](scripts/enemies/mage_monkey.gd): `beam.hit_radius = 17.0` setado explicitamente quando is_enemy_source (era 31 antes, sprite tile é ±16). Também: o `_apply_tick` retorna early durante a fase fade — beam visualmente apagando não machuca mais.

### Armor agora dá slow resistance
[scripts/player/player.gd](scripts/player/player.gd) `apply_slow`: `multiplier = lerp(multiplier, 1.0, slow_resistance_pct)`. `slow_resistance_pct = damage_reduction_pct × 0.5`. Ex: L1 = 8% dmg / 4% slow res; L4 = 20% / 10%. Stat panel do shop mostra `dmg% / slow%`.

### Fogo splash: pure dano, sem propagar burn
[scripts/skills/burn_dot.gd](scripts/skills/burn_dot.gd) `_apply_splash`: a cada tick do BurnDoT no inimigo principal, os 2 inimigos vivos mais próximos (raio 70px, exceto o queimando) levam 50% do tick_dmg como dano direto. NÃO propaga BurnDoT, NÃO aplica status — só dano. Aplica em todos os níveis da Flecha de Fogo.

### Versão segue regra: bump SÓ em deploy
Memória `feedback_version_bump.md` documenta isso. 0.3.2 foi pro download pelo Henrique, então 0.3.3 já é o bump correto. Próxima versão só sobe quando o Henrique falar que vai deploy nova.

### Decisões antigas a preservar (do session anterior)

- **Curse antes do take_damage** em TODOS os call sites de aliado.
- **damage_sound como filho do enemy** — morre com o enemy.
- **`_base_scale` no hp_bar.gd** — preservar squash multiplicativo.
- **`cc_immune` é exclusivamente pra CC** (stun/slow/knockback), não pra damage.
- **Boss music precisa de loop runtime** em `_swap_to_boss_music`.
- **Cinematic do boss congela TUDO** via PROCESS_MODE_DISABLED.
- **Tower vs Woodwarden colisão de flecha**: tower em structure+ally (PARA), woodwarden em structure+ally+tank_ally+insect_immune (PASSA).
- **Web export config:** thread_support=true + PWA enabled + cross_origin_isolation_headers=true em export_presets.cfg.
- **PWA service worker cacheia agressivo** — testar versão fresca em aba anônima.

## Pendências conhecidas

- [ ] **Playtest Esquivando** — buff de 50% move + rastro branco pode estar muito strong, ou cd 15s/10s muito longo
- [ ] **Validar dodge** (lv1-2: 2%, lv3+: 5%) — visual feedback (modulate ou flash) seria útil pra player perceber que dodgeou
- [ ] **Restrição "uma categoria elemental por jogo"** (pendência antiga) — chain agora é skill ativa, confirmar
- [ ] **Archer enemy** não suporta conversão por Maldição (pendência antiga)
- [ ] **Skin "Linked"** — testar caminho de unlock (200 macacos convertidos via curse arrow lv2+)
- [ ] **Cinematic intro (~14.6s)** — verificar se não é tedioso após primeiro replay (skippable?)
- [ ] **Boss redux drops** — wave 14 boss agora dropa 56-105 gold com pivot 80, validar se está ok
- [ ] Confirmar visualmente: stone cube toma dano da Q de raio (bug fix antigo)
- [ ] Confirmar visualmente: HP bar do boss não encolhe no 1º hit (bug fix antigo)

## Arquivos / locais relevantes (mudanças desta sessão)

- [scripts/player/player.gd](scripts/player/player.gd) — Esquivando completo (state, helpers, hit/coin notify, dodge in take_damage, spacebar handler, trail spawn), armor slow_resistance_pct, mutex bidirecional dash↔esquivando
- [scripts/skills/arrow.gd](scripts/skills/arrow.gd) — `volley_id` + `gave_esquivando_stack` + chamada `source.notify_esquivando_hit(self)` após take_damage
- [scripts/skills/burn_dot.gd](scripts/skills/burn_dot.gd) — `_apply_splash` 50% do tick_dmg nos 2 inimigos vivos mais próximos (raio 70px)
- [scripts/skills/curse_beam.gd](scripts/skills/curse_beam.gd) — `return` no fade phase (sem dano), hit_radius default 33 (boss override pra 17)
- [scripts/pickups/heart.gd](scripts/pickups/heart.gd) — `MAGNET_RADIUS_L3=110`, `MAGNET_RADIUS_L4=220` (NOVO), `MAGNET_END_WAVE_RADIUS=260` (NOVO), `MAGNET_PULL_SPEED=75`, `MAGNET_END_WAVE_SPEED=55`, `_end_wave_magnet` flag, `_magnet_chase_player(delta, speed)`
- [scripts/pickups/heart_drop.gd](scripts/pickups/heart_drop.gd) — `HEAL_PCT_PER_STACK=0.05` (L4 cap 35% heal), `BOSS_CONTEXT_CHANCE_PENALTY=0.05` (boss/boss_minion -5% drop chance), `try_drop(world, scene, pos, source)` signature nova
- [scripts/pickups/gold.gd](scripts/pickups/gold.gd) — chama `notify_esquivando_coin_pickup` no body_entered E magnet_finalize
- [scripts/enemies/mage_enemy.gd](scripts/enemies/mage_enemy.gd), [monkey_enemy.gd](scripts/enemies/monkey_enemy.gd), [stone_cube_enemy.gd](scripts/enemies/stone_cube_enemy.gd) — gold drop fora do `if not is_curse_ally:`; passa `self` pro HeartDrop.try_drop
- [scripts/enemies/mage_monkey.gd](scripts/enemies/mage_monkey.gd) — gold range 16-30 + pivot 23 + pivot_chance 0.80 + ponderada no _on_death; beam hit_radius = 17.0
- [scripts/enemies/electric_mage.gd](scripts/enemies/electric_mage.gd) + [scenes/enemies/electric_mage.tscn](scenes/enemies/electric_mage.tscn) — bolt_damage 12.75, shoot_interval 6.25s, preferred_distance 210, detection_range 325 (nerf)
- [scripts/enemies/insect_projectile.gd](scripts/enemies/insect_projectile.gd) — damage 6, poison_damage_total 13.5 (-25%)
- [scripts/systems/wave_manager.gd](scripts/systems/wave_manager.gd) — `_magnet_next_heart_sequential` sequencial via tree_exited, end-of-wave radius filter, double_arrows/esquivando no FREE_UPGRADE_POOL com exclusão, gold_drop_pivot scaling no boss_redux_wave
- [scripts/ui/wave_shop.gd](scripts/ui/wave_shop.gd) — esquivando no UPGRADE_POOL + EXCLUSIVE_PAIRS `["dash", "esquivando"]` + ESQUIVANDO_DESCS + icon path reusa `deslizando.png` + augment_title_for + UPGRADE_DESC_COLORS
- [scripts/ui/hud.gd](scripts/ui/hud.gd) — `esquivando_skill_icon` + `esquivando_stack_label` + `_update_esquivando_icon_position` + reposicionamento via signals de fire/chain/curse + glow ciano via `esquivando_ability_active_changed`
- [scripts/ui/dev_panel.gd](scripts/ui/dev_panel.gd) + [scenes/ui/dev_panel.tscn](scenes/ui/dev_panel.tscn) — botão `+1 Esquivando`
- [scenes/ui/hud.tscn](scenes/ui/hud.tscn) — `EsquivandoSkillIcon` Control com Bg/FrameRing/Inner/Sprite/StackLabel (frame verde, posição inicial 330,160 — overridden dinamicamente)
- [assets/Hud/skillsIcons/esquivando.png](assets/Hud/skillsIcons/esquivando.png) — arte do upgrade (novo asset)
- [assets/i18n/translations.csv](assets/i18n/translations.csv) — SHOP_UPG_ESQUIVANDO + SHOP_ESQUIVANDO_DESC_1-4 (PT/EN/ES/FR), SHOP_ARMOR_8/12/16/20/3 reformatadas com slow res, SHOP_ARMOR_DESC_1-5 reformatadas

## Comandos úteis

```bash
# Push (auto-deploya pro GH Pages via Actions)
rtk git push

# Pull (Henrique pode estar pushando paralelamente)
rtk git pull --no-rebase

# Ver builds do GH Actions
gh run list --limit 5
gh run view --log

# Testar build atual (anônima evita cache PWA)
# https://rafa-mesquita.github.io/Twilight-Quiver/

# Bump version pre-deploy (Henrique avisa quando vai sair release)
# Editar application/config/version em project.godot pra pre-alpha-X.Y.Z
```

## Decisões tomadas nesta sessão

- **Life Steal nerf**: HEAL_PCT_PER_STACK 0.10 → 0.05 (L4 cap 35% heal em vez de 50%). Chance preservada (12-27%).
- **Heart magnet sequencial no fim de wave** + speed baixa (55px/s) — sem fountain instantâneo.
- **Heart magnet L4 com raio 220px** (não mais mapa todo). End-of-wave radius 260px, hearts mais longe vanish.
- **Boss/boss_minion -5% heart drop chance** em todos os níveis de Life Steal (`BOSS_CONTEXT_CHANCE_PENALTY`).
- **Boss gold 16-30 com pool ponderada 80/20** (16-23 comum, 24-30 raro). Pivot escala junto no wave 14 (×3.5).
- **Curse beam hitbox boss = 17** (alinhado ao sprite ±16, era 31). Sem dano durante fade phase.
- **Armor agora dá slow reduction** = metade da % de redução de dano. Stat panel mostra `dmg% / slow%`.
- **Insect dmg -25%** (impacto 8→6, veneno 18→13.5, total 26→19.5).
- **Electric mage nerf**: dmg 15→12.75 (-15%), atk speed 5s→6.25s (-25%), range -10%.
- **Fogo splash**: 50% do tick DoT nos 2 inimigos vivos mais próximos (raio 70px), todos os níveis.
- **Esquivando**: novo upgrade movimentação mutex com Dash, 4 níveis com escalas 5%/8%/8%/10%, dodge 2%/2%/5%/5%, cap 3/3/3/4, skill espaço +50% move 3s cd 15s→10s.
- **Esquivando ícone reposiciona** — slot esquerdo (150) sem elemental, direito (330) com elemental.
- **Esquivando feedback visual** — glow ciano no ícone + rastro branco no player durante skill ativa.
- **Curse_ally agora dropa gold** com a mesma % do inimigo original (insect/boss_minion seguem sem dropar via gold_drop_chance=0).
- **Double Arrows** adicionado ao pool de boas-vindas com exclusão mútua vs Multi Arrow.
- **Bug pré-existente corrigido**: arrow.source/volley_id estavam aninhados dentro do `if is_graviton:` em _spawn_arrow.
- **Versão**: 0.3.1 → 0.3.2 (download Henrique) → 0.3.3 (atual, ainda não deployed).

## Histórico de commits da sessão (últimos)

```
07f4c7b Bump pre-alpha-0.3.3
99f4e68 Novo upgrade Esquivando + ajustes de heart magnet e curse ally
3ccf720 Curse beam Y align + telemetria de mago types + killed_by (Henrique)
4442c83 Bump pre-alpha-0.3.2: balance pass + boss beam hitbox fix
21df1c3 Atualiza NEXT-SESSION.md com estado da sessao 2026-05-11 (Henrique)
13ad87c Bump pre-alpha-0.3.1: hotfix de boss balance + bugfixes (Henrique)
ad86fe8 Boss balance + bugfixes: ice/electric summon + hp bar + chain Q
```
