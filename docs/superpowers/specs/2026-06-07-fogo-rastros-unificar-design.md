# Fogo — Unificar DoT dos rastros + scaling de Dano + textos (design)

**Data:** 2026-06-07
**Tipo:** Ajuste de balance/consistência da Flecha de Fogo (rastros L2-L4).

## Problemas (estado atual)

1. **DoT dos dois rastros diferente:** rastro da flecha `_fire_trail_dps()` = base **4/5/7** (L2/3/4); rastro do player `_fire_player_trail_dps()` = base **3/4/5**.
2. **Scaling de Dano inconsistente:** flecha usa `_apply_dmg_pct_to_dps` (× `arrow_damage_multiplier`, igual à queimadura); player usa `+ float(damage_upgrades)` (flat +1/status, fraco) **e** aplica `_cajado_power_factor()` indevidamente (rastro de fogo é NEUTRO ao Cajado por design — ver [[feature_cajado_crepusculo]]). Resultado: "o Dano não aumenta o DoT dos rastros".
3. **Modal de escolha L2 não mostra número** (`SHOP_FIRE_TRAIL_SUBTITLE` = "Escolha qual rastro vem primeiro").
4. **Texto da carta errado:** `SHOP_FIRE_ARROW_DESC_2` mostra "no player (3 de dano/s) ou na flecha (4 de dano/s)" (valores divergentes). Existe `SHOP_FIRE_ARROW_DESC` (sem sufixo) = "BLABLABLA" — **placeholder morto** (não referenciado em nenhum `.gd`).

## Decisões (aprovadas)

- **DoT unificado: 3 / 4 / 5** (L2/L3/L4) pros DOIS rastros.
- **Scaling de Dano: o padrão** (`_apply_dmg_pct_to_dps`) pros dois — igual à queimadura.
- Carta mostra o número **base** (3 no L2); modal L2 mostra o valor **real** (já escalado pelo Dano atual).

## Mudanças

### `player.gd`

1. **`_fire_trail_dps()`** vira a fonte ÚNICA dos dois rastros. Troca a base de `4/5/7` → **`3/4/5`** (L2/3/4). Mantém `_apply_dmg_pct_to_dps(base * _fire_burn_multiplier())`.
2. **Rastro do player** (`_spawn_player_fire_trail_segment`): trocar
   `seg.damage_per_second = (_fire_player_trail_dps() + float(damage_upgrades)) * _cajado_power_factor()`
   por
   `seg.damage_per_second = _fire_trail_dps()`
   (mesma fonte da flecha; sem Cajado; scaling de Dano vem do `_apply_dmg_pct_to_dps` interno).
3. **Remover `_fire_player_trail_dps()`** (não mais usado). Conferir nenhum outro caller.
   - Nota: o rastro da flecha no spawn já é `arrow.fire_trail_dps = _fire_trail_dps() * trail_scale` (trail_scale 1.0 primária / 0.60 extra) — intocado; herda o novo base 3/4/5.

### `wave_shop.gd` (modal L2)

4. No `_open_fire_trail_choice`, o subtítulo passa a mostrar o DoT real:
   `subtitle.text = tr("SHOP_FIRE_TRAIL_SUBTITLE") % int(round(player._fire_trail_dps()))`
   (o `player` já está disponível no builder; guardar contra player nulo → fallback ao texto sem número). A key `SHOP_FIRE_TRAIL_SUBTITLE` ganha um `%d`.

### i18n (`translations.csv`, 4 línguas)

5. **`SHOP_FIRE_TRAIL_SUBTITLE`** → com placeholder: ex. pt "Ambos causam %d de dano/s — escolha onde o fogo cai".
6. **`SHOP_FIRE_ARROW_DESC_2`** → refletir os dois iguais: ex. pt "Queimadura sobe para 7 de dano/s. Escolha onde o rastro de fogo cai: no player ou na flecha (3 de dano/s)."
7. **Remover** a linha morta `SHOP_FIRE_ARROW_DESC` (sem sufixo).

## Fora de escopo

- Queimadura on-hit (`_fire_burn_dps`), skill Q (fire field), bônus L4 (+30%) — intocados.
- DESC_1/DESC_3/DESC_4 da carta — mantidos (foco é o rastro/DESC_2).
- Sem deploy/bump agora (junta com o resto pra próxima release).

## Critérios de aceite

- Os dois rastros (player e flecha) causam o MESMO DoT por nível (3/4/5 base).
- Comprar Dano aumenta o DoT dos dois rastros de forma perceptível (mesmo % da queimadura).
- Modal L2 mostra o DoT real (ex.: "Ambos causam 5 de dano/s" com Dano comprado).
- Carta L2 não cita mais valores divergentes; placeholder "BLABLABLA" some.
- Sem regressão no rastro da flecha (segue saindo, agora com base 3/4/5).
