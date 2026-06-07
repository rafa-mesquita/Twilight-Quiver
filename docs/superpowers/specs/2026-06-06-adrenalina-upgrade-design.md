# Upgrade "Adrenalina" (mobilidade, 4º do grupo mutex) — 2026-06-06

Novo upgrade de movimentação, mutuamente exclusivo com Dash/Esquivando/Fenda
(só 1 de mobilidade por run). Reusa a carta `deslizando.png` e a barra de cooldown
de mobilidade. Sem bump de versão (só em deploy).

## Mecânicas (decisões confirmadas com o user)

- **L1 (passivo):** +5% move speed fixo **+ 0,5%** por cada 1 de HP **atual** abaixo de
  **100 fixo** (`max(100 − hp, 0)`). HP cheio (100) = só +5%; cresce ao perder vida.
- **L2 (passivo):** o por-HP vira **0,7%** (era 1%, nerfado no playtest). **Sem teto.**
- **L3 (skill no Espaço):** por **5s** → **+15% atk speed** e **cura 10 HP por DISPARO**
  ao acertar inimigo (1 cura por disparo, NÃO por flecha — multishot/perfuração não
  multiplicam). **Cooldown 17s** (era 14s, nerfado no playtest). Visual: vermelho aditivo
  do Sanguinário + rastro branco no chão do Esquivando, durante os 5s.
- **L4 (skill):** mesma skill + **+25% move speed** durante os 5s e atk speed sobe pra
  **+30%**. **Cooldown 15s** (era 12s).
- Skill (L3+) é mutex no Espaço com dash/esquivando/fenda; usa a barra de mobilidade.
- Escala de HP é vs **100 fixo** usando HP atual (não max_hp). Recalculada por frame.

### "10 por disparo, não por flecha"
Player mantém `_shot_counter` (incrementa a cada `_start_attack`). Cada flecha guarda o
`shot_id` do disparo. No `arrow.gd:_on_hit`, chama `player.adrenalina_try_heal(shot_id)`;
o player cura 10 só se a skill está ativa E `shot_id != _adrenalina_heal_last_shot`,
então atualiza o last. Garante 1 cura por disparo.

## Valores (constantes em player.gd)
`ADRENALINA_LEVEL_MAX=4`, `ADRENALINA_SKILL_MIN_LEVEL=3`, `ADRENALINA_FLAT_MS=0.05`,
`ADRENALINA_MS_PER_HP_L1=0.005`, `ADRENALINA_MS_PER_HP_L2=0.01`, `ADRENALINA_HP_REF=100.0`,
`ADRENALINA_SKILL_DURATION=5.0`, `ADRENALINA_CD_L3=14.0`, `ADRENALINA_CD_L4=12.0`,
`ADRENALINA_ATK_L3=0.15`, `ADRENALINA_ATK_L4=0.30`, `ADRENALINA_SKILL_MS=0.25`,
`ADRENALINA_HEAL_PER_SHOT=10.0`.

## Lógica em player.gd
- `var adrenalina_level: int`, `_adrenalina_cd_remaining`, `_adrenalina_skill_remaining`,
  `_adrenalina_heal_last_shot := -1`, `_shot_counter := 0`.
- `_adrenalina_move_buff() -> float`: 0 se nível 0. Senão `FLAT + rate*max(100−hp,0)` onde
  rate = L1/L2; + `SKILL_MS` se skill ativa e nível>=4. Somar na velocidade (player.gd:~741).
- `_adrenalina_atk_buff() -> float`: 0; se skill ativa → 0.15 (L3) / 0.30 (L4). Somar no
  `atk_mult` (player.gd:~964).
- `_try_start_adrenalina_ability()`: checa nível>=3 + cooldown; conta uso; seta
  `_adrenalina_skill_remaining = 5`, cooldown por nível; liga visual vermelho; emite
  `dash_cooldown_changed`. `_update_adrenalina(delta)`: decrementa cd e skill; enquanto
  skill ativa e player se move, cospe rastro (reusa `_spawn_esquivando_trail_segment`);
  ao acabar a skill, desliga o vermelho. `_adrenalina_cooldown()` por nível.
- `adrenalina_try_heal(shot_id)`: cura `ADRENALINA_HEAL_PER_SHOT` 1×/disparo durante a skill.
- `apply_upgrade("adrenalina")`: mutex (return se dash/esquivando/fenda > 0), incrementa
  nível (cap 4), no nível 1 emite `dash_unlocked` (reusa barra) + reseta cd.
- `get_upgrade_count`: caso `"adrenalina"`.
- Dispatch do Espaço (player.gd:~716): `elif adrenalina_level >= ADRENALINA_SKILL_MIN_LEVEL:
  _try_start_adrenalina_ability()`.
- Visual vermelho: reaproveitar a lógica do overlay do Sanguinário
  (`_sanguinario_overlay` / `_set_sanguinario_visual`) num overlay próprio da skill, sem
  conflitar com o estado do Sanguinário (item). Se mais simples, generalizar uma função
  `_set_red_overlay(active)` que ambos usam por contagem/flag.
- `_start_attack`: `_shot_counter += 1`; passar `shot_id` às flechas criadas.

## Lógica em arrow.gd
- `var shot_id: int = -1` (setado no spawn pelo player). No `_on_hit`, após o dano, chamar
  o player `adrenalina_try_heal(shot_id)` (padrão do `_arbusto_heal_player`).

## CHECKLIST de superfícies (TODAS as interfaces)
**wave_shop.gd:** (1) `UPGRADE_POOL` +entry; (2) novo `ADRENALINA_DESCS`; (3) `EXCLUSIVE_PAIRS`
grupo mobilidade +adrenalina; (4) `UPGRADE_CATEGORIES` → `SHOP_UPG_CAT_MOBILITY`;
(5) `UPGRADE_TITLE_COLORS` → marrom de movimentação; (6) `CARD_PATH_OVERRIDES` → deslizando.png;
(7) `_get_upgrade_descs_array` → ADRENALINA_DESCS; (8) `_augment_title_for` → SHOP_UPG_ADRENALINA.

**hud.gd:** (9) `UPGRADE_DISPLAY_ORDER` +adrenalina; (10) dict de max-level (~184) → `"adrenalina": 4`;
(11) mapa de ícone (~207) → deslizando.png; (12) `_BUILD_UPGRADE_IDS` (~2108) +adrenalina
(snapshot do leaderboard); (13) lista de respawn snapshot (~1924) +adrenalina.

**dev_panel.gd:** (14) `_ALL_UPGRADE_IDS` +adrenalina; (15) `_UPGRADE_BUTTONS` +entry
`UpgAdrenalinaBtn` (e adicionar o botão no `dev_panel.tscn`) pra testar.

**run_build_modal.gd:** (16) `_CATEGORIES` lista STANDARD +`["adrenalina","SHOP_UPG_ADRENALINA"]`
(aparece no "ver build" do leaderboard).

**player.gd / arrow.gd:** (17) toda a lógica acima.

**translations.csv:** (18) `SHOP_UPG_ADRENALINA` + `SHOP_ADRENALINA_DESC_1..4` (pt/en/es/fr),
tom de jogador.

## Textos (rascunho, tom de jogador)
- Nome: Adrenalina.
- DESC_1: "Ganha +5% de velocidade de movimento — e quanto menor sua vida (abaixo de 100), mais rápido você fica."
- DESC_2: "O ganho por vida perdida dobra: fica ainda mais veloz conforme apanha."
- DESC_3: "Espaço: por 5s, +15% de cadência de ataque e seus tiros curam 10 de vida ao acertar. Recarga 14s."
- DESC_4: "A fúria também te dá +25% de velocidade e a cadência sobe pra +30% durante a skill. Recarga 12s."

## Fora de escopo
Arte própria da carta/ícone (reusa a de movimentação). Balanceamento fino fica pra playtest.
