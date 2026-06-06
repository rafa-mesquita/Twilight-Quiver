# Design — Item Cajado do Crepúsculo (caster: +skill/aliados, −flecha)

## Resumo

Novo item de equipamento **Cajado do Crepúsculo**. Item de build "caster": fortalece
skills e aliados, enfraquece a arquearia básica.

- **+35% de dano** em todas as skills (ativáveis e automáticas) **e em todos os aliados**.
- **−30% de dano** nas flechas (normais e especiais: perfuração, múltipla, dupla,
  ricochete, e o hit direto de água/pedra e dos outros elementais).
- **Drop de Relógios** (reset de cooldown) sobe de 1.5% para **4%**.
- **Desbloqueio:** loja de pétalas por **400 pétalas** (`unlock: shop`).
- **Arte:** decodada de `assets/Hud/itens/Cajado do crepusculo.aseprite`.

## Classificação de dano (3 baldes)

A separação não existe hoje — quase tudo passa por `arrow_damage_multiplier`, direto
([player.gd:1088](../../../scripts/player/player.gd) no spawn da flecha,
[player.gd:2575](../../../scripts/player/player.gd) no terremoto) ou via o helper
`_apply_dmg_pct_to_dps()` ([player.gd:1467](../../../scripts/player/player.gd), usado por
TODOS os DoTs e skills). O item introduz dois fatores aplicados em pontos específicos.

### −30% — FLECHA (`_cajado_arrow_factor()` = 0.70)
- Flecha normal + perfuração + múltipla + dupla + ricochete.
- Hit **direto** de todos os elementais (água, pedra, fogo, maldição, gelo, maré).

Aplicado **uma vez** no spawn ([player.gd:1088](../../../scripts/player/player.gd)). Como
os modificadores especiais e o stone-direct derivam de `arrow.damage` depois desse ponto,
herdam o −30% automaticamente.

### +35% — SKILLS + ALIADOS (`_cajado_power_factor()` = 1.35)
- Skills Q ativáveis: Fogo, Feixe da Maldição, Terremoto da Pedra, Raio da Cadeia,
  Escudo da Maré (tide wave L4).
- Automáticas: auto-raio da cadeia (L2+), Garras do Tigre, Bumerangue, **rastro de fogo
  do player** (L2+).
- **Dano de TODOS os aliados** (Claudio, Leno, Frostwisp, Capivara, Ting turret, etc.).

### INALTERADO — efeitos neutros (sem fator)
- DoTs elementais: queimadura (fogo), DoT da maldição, congelamento (gelo).
- Splash + vulnerabilidade da água.
- Rastro **da flecha** de fogo (arrow trail).
- **AoE da pedra**.
- **Proc da cadeia** (raio que pula ao acertar).
- **Explosão do graviton (L4)**.

## Implementação

### `player.gd`
1. **Campos/consts** (perto de [player.gd:479](../../../scripts/player/player.gd)):
   ```gdscript
   var _cajado_arrow_mult: float = 1.0   # 0.70 quando equipado
   var _cajado_power_mult: float = 1.0   # 1.35 quando equipado
   var _cajado_clock_chance: float = 0.0 # 0.04 quando equipado (0 = sem override)
   func _cajado_arrow_factor() -> float: return _cajado_arrow_mult
   func _cajado_power_factor() -> float: return _cajado_power_mult
   ```
2. **Flecha −30%** ([player.gd:1088](../../../scripts/player/player.gd)): multiplica a
   linha do `arrow.damage` por `_cajado_arrow_factor()`.
   - **Exceção stone AoE** ([player.gd:1221](../../../scripts/player/player.gd)):
     `arrow.stone_aoe_damage` deve ser computado a partir do dano **antes** do fator de
     flecha (dividir de volta por `_cajado_arrow_factor()` ou capturar o valor pré-nerf),
     pra ficar inalterado.
3. **Skills +35%** — adicionar param opcional `is_skill: bool = false` em
   `_apply_dmg_pct_to_dps` ([player.gd:1467](../../../scripts/player/player.gd)); quando
   `true`, multiplica por `_cajado_power_factor()`. Marcar `is_skill=true` SÓ nos sites de
   skill:
   - Fogo Q, Feixe da Maldição Q, Raio da Cadeia Q, auto-raio da cadeia, Garras do Tigre,
     rastro de fogo do player.
   - **NÃO** marcar: burn DoT, arrow fire trail, curse DoT, ice DoT, tide splash, graviton
     (ficam neutros no default).
   - Terremoto da Pedra ([player.gd:2575](../../../scripts/player/player.gd)) usa
     `arrow_damage_multiplier` direto → multiplicar por `_cajado_power_factor()` ali.
4. **Bumerangue** (boomerang.gd) captura `arrow_damage_multiplier` no spawn → multiplicar
   também por `_cajado_power_factor()`.

### Aliados +35%
Cada script de aliado multiplica seu dano final por `player._cajado_power_factor()`. Hoje
os aliados têm base própria e **não** leem multiplicador do player (exceto Ting, que lê o
`arrow_damage_multiplier`); todos passam a aplicar o power factor. Sites a tocar:
Claudio Druida, Leno (projétil), Frostwisp (projétil + field), Capivara Joe (cogumelo),
Ting turret. (Pai do Verde/Verde e Mini Mago não causam dano direto que escale.)

### `clock_drop.gd`
A chance fixa `DROP_CHANCE` (0.015) vira uma chance efetiva lida do player. Com Cajado
equipado, retorna **0.04**. O gate `_player_has_active_skill` e o dev-force continuam
iguais. Hook: `player` expõe a chance efetiva (ex: `get_clock_drop_chance()` que retorna
`_cajado_clock_chance if _cajado_clock_chance > 0 else DROP_CHANCE`); o clock lê isso.

### `inventory_items.gd`
- Item novo no `ITEMS`:
  ```gdscript
  "cajado_crepusculo": {
      "name": "ITEM_CAJADO_CREPUSCULO_NAME",
      "desc": "ITEM_CAJADO_CREPUSCULO_DESC",
      "icon": "res://assets/Hud/itens/cajado_crepusculo.png",
      "effects": [
          {"type": "arrow_damage_mult", "amount": 0.70},
          {"type": "skill_ally_damage_mult", "amount": 1.35},
          {"type": "clock_drop_chance", "amount": 0.04},
      ],
      "unlock": {"type": "shop"},
  },
  ```
- `apply_to_player` ([inventory_items.gd:325](../../../scripts/systems/inventory_items.gd)):
  3 branches novos setando `player._cajado_arrow_mult` / `_cajado_power_mult` /
  `_cajado_clock_chance` a partir do `amount`.

### `loja_petalas.gd`
Entrada no `CATALOG`: `{"cat":"itens","kind":"item","id":"cajado_crepusculo","price":400}`.
Fluxo de compra/posse/unlock já funciona.

### Arte
Decodar `Cajado do crepusculo.aseprite` → `cajado_crepusculo.png` (32×32, todas as layers),
depois importar no editor do Godot (gera `.import`/`.ctex`).

### i18n ([translations.csv](../../../assets/i18n/translations.csv), 4 idiomas)
- `ITEM_CAJADO_CREPUSCULO_NAME` — "Cajado do Crepúsculo"
- `ITEM_CAJADO_CREPUSCULO_DESC` — "+35% de dano em todas as skills (ativáveis e
  automáticas) e nos seus Aliados, e o drop de Relógios sobe para 4%. Em troca, suas
  flechas — normais e especiais (perfuração, múltipla, ricochete, água, pedra) — causam
  −30% de dano."

## Regras assumidas
- −30% = ×0.70, +35% = ×1.35, multiplicativos.
- Relógio: chance **definida** em 4% quando equipado (não multiplicador sobre 1.5%).
- Sem stacks/níveis (item binário equipado/não).

## Fora de escopo
- Efeitos neutros (DoTs, splash, AoE da pedra, proc da cadeia, rastro da flecha de fogo,
  explosão do graviton) — intocados.
- Feedback visual dedicado na HUD (diferente do Sanguinário; o item aparece no display de
  equipados como qualquer outro).

## Arquivos tocados
- `scripts/player/player.gd` — fatores + sites de flecha/skill + stone AoE + terremoto.
- `scripts/skills/boomerang.gd` — power factor.
- aliados: `claudio_druida.gd`, `leno_projectile.gd`, `frostwisp.gd`/`frostwisp_projectile.gd`,
  `capivara_joe.gd`, `ting_turret.gd`.
- `scripts/pickups/clock_drop.gd` — chance efetiva.
- `scripts/systems/inventory_items.gd` — item + branches.
- `scripts/ui/loja_petalas.gd` — CATALOG 400.
- `assets/Hud/itens/cajado_crepusculo.png` (+ `.import`).
- `assets/i18n/translations.csv` — NAME/DESC.
