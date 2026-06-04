# Design — Buff da Cadeia de Raios (L2) + visual amarelo + balance da Fúria da Maré

Data: 2026-06-04

## Objetivo

Três mudanças relacionadas a elementais:

1. **Cadeia de Raios L2** ganha um poder novo (além do proc que já tem): a cada 5s
   um raio automático de 20 de dano atinge um inimigo aleatório numa área ao redor
   do player.
2. **Identidade visual da Cadeia**: a flecha e o rastro ficam amarelos em todos os
   níveis (L1–L4) quando a Cadeia está equipada.
3. **Balance da Fúria da Maré**: reduzir a penalidade de dano do tiro de água — o
   tiro base passa de 19 para 21.

---

## Parte 1 — Cadeia de Raios L2: raio automático

### Comportamento

- **Gatilho:** auto-cast a cada **5,0s** enquanto `chain_lightning_level >= 2`.
  Persiste em L3 e L4 (é um poder cumulativo do L2+).
- **Seleção de alvo:** 1 inimigo **aleatório** dentro de **180px** ao redor do
  player — mesma área e mesma regra de filtro das Garras de Tigre
  (`_try_cast_tiger_claws`): ignora `ally` e `boss_shielded`. Se não houver inimigo
  no raio, **não dispara** e o cooldown **não inicia** (retenta no próximo frame),
  igual ao tiger claws.
- **Dano:** base **20**, escalando com o stat "Dano" via
  `_apply_dmg_pct_to_dps(20.0)`. Rola crítico (mesma `roll_crit()` que o proc de
  cadeia usa por alvo).
- **Visual/áudio:** faísca elétrica (zig-zag amarelo) desenhada **do player até o
  inimigo** + som de cadeia. Reaproveita exatamente o visual e o áudio do proc de
  cadeia padrão.

### Arquitetura — util compartilhado `ChainVfx`

Hoje o desenho da faísca (`_spawn_lightning_visual`) e o som (`_play_chain_sound` +
throttle estático `_last_chain_sound_msec` + `CHAIN_SOUND`/volume/throttle) vivem
dentro de `scripts/skills/arrow.gd`. Para o player reusar sem duplicar:

- Criar `scripts/effects/chain_vfx.gd` com `class_name ChainVfx`, expondo:
  - `static func spark_between(world: Node, from: Vector2, to: Vector2) -> void`
    — move o corpo de `_spawn_lightning_visual` (cria o `Line2D` zig-zag amarelo,
    adiciona no `world`, tween de fade + `queue_free`).
  - `static func play_chain_sound(world: Node, pos: Vector2) -> void` — move o
    corpo de `_play_chain_sound` (inclui o throttle estático e o `CHAIN_SOUND`).
- `arrow.gd` passa a chamar `ChainVfx.spark_between(_get_world(), origin_pos, alvo)`
  e `ChainVfx.play_chain_sound(_get_world(), origin_pos)`. **Comportamento idêntico**
  ao atual (mesma cor, throttle, volume).
- `player.gd` chama os mesmos métodos no novo auto-bolt.

### Mudanças em `player.gd`

- Constantes novas (perto das de tiger claws / chain):
  - `const CHAIN_AUTO_BOLT_INTERVAL: float = 5.0`
  - `const CHAIN_AUTO_BOLT_RADIUS: float = 180.0` (mesma área das Garras de Tigre)
  - `const CHAIN_AUTO_BOLT_DAMAGE: float = 20.0`
- Estado: `var _chain_auto_bolt_cd_remaining: float = 0.0`
- `_update_chain_auto_bolt(delta)` chamado no `_process` (perto de
  `_update_chain_lightning_skill`):
  - Sai cedo se `chain_lightning_level < 2` ou `is_dead`.
  - Tica o cooldown; quando zera, tenta `_try_cast_chain_auto_bolt()` e, se
    disparou, reinicia o cooldown em `CHAIN_AUTO_BOLT_INTERVAL`.
- `_try_cast_chain_auto_bolt() -> bool`:
  - Coleta candidatos dentro de `CHAIN_AUTO_BOLT_RADIUS` com o mesmo filtro do
    tiger claws (ignora `ally` e `boss_shielded`, exige `take_damage`).
  - Se vazio, retorna `false`.
  - Sorteia 1 (`candidates.pick_random()` ou shuffle+0).
  - `dmg = _apply_dmg_pct_to_dps(CHAIN_AUTO_BOLT_DAMAGE)`, rola crit
    (`roll_crit()`), aplica `take_damage`, notifica dano/kill por source
    `"chain_lightning"` (mesmo source id do proc, pro tracking/telemetria).
  - `ChainVfx.spark_between(world, global_position, alvo.global_position)` e
    `ChainVfx.play_chain_sound(world, global_position)`.
  - Retorna `true`.
- Resetar `_chain_auto_bolt_cd_remaining = 0.0` nos pontos de reset relevantes
  (ex: respawn/run reset, junto dos outros cooldowns).

### Texto da loja (i18n)

Atualizar `SHOP_CHAIN_LIGHTNING_DESC_2` em `assets/i18n/translations.csv` (colunas
pt_BR, en, es, fr) pra mencionar o novo poder. Ex (pt_BR):
"Causa 50% do dano em 2 a 3 inimigos próximos. A cada 5s, um raio atinge um inimigo
por perto." (traduções equivalentes nas demais colunas.)

---

## Parte 2 — Flecha e rastro amarelos (Cadeia, todos os níveis)

- Novo flag no `arrow.gd`: `var is_chain: bool = false`.
- `_apply_chain_visuals()`:
  - Tinta o sprite normal (`Sprite2D`) de amarelo elétrico (`modulate`).
  - Troca a cor do `Trail` (gradiente + `default_color`) para amarelo, no mesmo
    estilo dos outros blocos (`_apply_tide_visuals` / pierce). Cauda transparente →
    cabeça amarela.
  - Cor base proposta: amarelo elétrico saturado, ex. `Color(1.0, 0.85, 0.2)`
    (cabeça do trail) — alinhado com o amarelo da faísca `Color(2.2, 1.9, 0.4)`.
- Chamado no `_ready` do arrow junto dos outros `if is_xxx: _apply_xxx_visuals()`.
- No `player.gd._spawn_arrow`, setar `arrow.is_chain = true` quando
  `chain_lightning_level > 0` (a Cadeia é exclusiva dos outros elementais, então
  não há conflito de tint).

---

## Parte 3 — Fúria da Maré: dano base 19 → 21

- `scripts/player/player.gd`: `const TIDE_DAMAGE_FACTOR: float` de `0.76` para
  `0.84`. Cálculo: dano base da flecha = 25; `25 × 0.84 = 21`.
- Sem outras mudanças (o fator já é aplicado em `_mare_damage_factor()` no
  `_spawn_arrow`; o debuff de Vulnerabilidade e o +20% atk speed continuam iguais).
- Atualizar o comentário no `apply_upgrade` ("tide_arrow") que ainda diz "-15%"
  (stale) pra refletir o novo fator, se fizer sentido durante a implementação.

---

## Fora de escopo

- Não mexer no proc de cadeia existente (alvos/dano/throttle) além da extração do
  VFX pro util.
- Não mexer na skill de cursor L3/L4 (`lightning_bolt`).
- Sem bump de versão (`project.godot`) — só em deploy/release.
- Sem release notes em arquivo.

## Verificação

- Cadeia L2: ao atingir L2, observar um raio automático a cada ~5s mirando inimigo
  aleatório dentro de ~180px; dano ~20 (mais com Dano comprado); faísca do player
  ao alvo + som.
- Em L1 (sem o auto-bolt) e em L3/L4 (com o auto-bolt mantido).
- Flecha/rastro amarelos em todos os níveis da Cadeia.
- Tiro de água base mostra 21 de dano (sem upgrades de Dano).
