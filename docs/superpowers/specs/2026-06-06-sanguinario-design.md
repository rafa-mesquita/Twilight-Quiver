# Design — Item Sanguinário (buff de dano com vida baixa)

## Resumo

Novo item de equipamento **Sanguinário**. Enquanto o player está com **vida estritamente
abaixo de 40%** do máximo, ganha **+30% de dano em todas as fontes que escalam com o
stat "Dano"**. Se curar de volta pra **≥ 40%**, o buff é removido imediatamente.

- **Desbloqueio:** comprado na loja de pétalas por **660 pétalas** (`unlock: shop`, igual
  ao `midnight_dagger`/`golden_bow`).
- **Arte:** decodada de `assets/Hud/itens/Sangue Quente.aseprite`.
- **Feedback visual:** o slot do item no display de equipados da HUD (canto superior
  direito) ganha um **glow vermelho pulsante** enquanto o buff está ativo.

## Definição de "todas as fontes"

No código não existe um hook universal de dano. O knob global é o
`arrow_damage_multiplier` (o stat "Dano" do player), lido por flechas, DoTs
(queimadura/maldição/veneno), skills elementais (fogo/pedra/raio/gelo/maré) e
aliados que escalam com o Dano. **"Todas as fontes" = tudo que lê esse multiplicador.**
Fontes de dano fixo (ex: base própria do Leno) e dano de contato **não** entram —
está fora de escopo por decisão de design.

## Abordagem do efeito — recompor o `arrow_damage_multiplier`

O `arrow_damage_multiplier` tem **um único ponto de escrita** no código:
[player.gd:3175](../../../scripts/player/player.gd) (`arrow_damage_multiplier += 0.24`,
upgrade de Dano). Por isso, em vez de multiplicar um fator em dezenas de pontos de
leitura, separamos uma **base** e recompomos o multiplicador efetivo. Todos os leitores
existentes herdam o bônus automaticamente, sem alteração.

### Mudanças em `player.gd`

1. **Nova base e estado** (junto da declaração atual de `arrow_damage_multiplier`,
   [player.gd:479](../../../scripts/player/player.gd)):
   ```gdscript
   var _damage_base: float = 1.0          # acumulado por upgrades/itens de Dano
   var _sanguinario_bonus: float = 0.0    # 0.30 quando o item está equipado, senão 0
   var _sanguinario_active: bool = false  # cache do estado (HP < limiar) p/ detectar flip
   const SANGUINARIO_THRESHOLD: float = 0.40
   const SANGUINARIO_BONUS: float = 0.30
   signal sanguinario_active_changed(active: bool)
   ```
   `arrow_damage_multiplier` continua sendo o valor **efetivo** (lido por todos); vira um
   valor derivado de `_damage_base × fator`.

2. **Ponto de escrita do upgrade** ([player.gd:3175](../../../scripts/player/player.gd)):
   ```gdscript
   # antes: arrow_damage_multiplier += 0.24
   _damage_base += 0.24
   _refresh_damage_multiplier()
   ```

3. **Recompute e fator:**
   ```gdscript
   func _sanguinario_factor() -> float:
       if _sanguinario_bonus > 0.0 and hp < max_hp * SANGUINARIO_THRESHOLD:
           return 1.0 + _sanguinario_bonus
       return 1.0

   func _refresh_damage_multiplier() -> void:
       arrow_damage_multiplier = _damage_base * _sanguinario_factor()
   ```

4. **Detecção do flip** (dirigida pelo `hp_changed`, que já é emitido em dano/cura/mudança
   de max_hp). Conecta no `_ready` ou chama a partir do handler interno de `hp_changed`:
   ```gdscript
   func _update_sanguinario_state() -> void:
       var active: bool = _sanguinario_bonus > 0.0 and hp < max_hp * SANGUINARIO_THRESHOLD
       if active == _sanguinario_active:
           return
       _sanguinario_active = active
       _refresh_damage_multiplier()
       sanguinario_active_changed.emit(active)
   ```
   Bidirecional por construção: cair abaixo de 40% → `active=true` (liga o buff e o glow);
   curar pra ≥ 40% → `active=false` (remove o buff e o glow).

### Mudança em `inventory_items.gd`

- Novo item no `ITEMS` ([inventory_items.gd:35+](../../../scripts/systems/inventory_items.gd)):
  ```gdscript
  "sanguinario": {
      "name": "ITEM_SANGUINARIO_NAME",
      "desc": "ITEM_SANGUINARIO_DESC",
      "icon": "res://assets/Hud/itens/sanguinario.png",
      "effect": {"type": "low_hp_damage", "threshold_pct": 40, "bonus": 0.30},
      "unlock": {"type": "shop"},
  },
  ```
- Novo branch em `apply_to_player` ([inventory_items.gd:325](../../../scripts/systems/inventory_items.gd)):
  ```gdscript
  elif t == "low_hp_damage":
      if "_sanguinario_bonus" in player:
          player._sanguinario_bonus = float(eff.get("bonus", 0.30))
          if player.has_method("_update_sanguinario_state"):
              player._update_sanguinario_state()  # caso já entre a run com HP baixo
  ```
  (`threshold_pct` fica no dict para documentação/futuro; o limiar efetivo usa a const do
  player, mantendo uma única fonte de verdade.)

## Loja de pétalas (preço 660)

Entrada nova no `CATALOG` da [loja_petalas.gd](../../../scripts/ui/loja_petalas.gd),
ao lado de `midnight_dagger`/`golden_bow`:
```gdscript
{"cat": "itens", "kind": "item", "id": "sanguinario", "price": 660},
```
O fluxo de compra (`PetalBank.spend(660)` → `InventoryItems.mark_purchased("sanguinario")`),
a checagem de posse (`is_purchased`) e o desbloqueio (`unlock: shop` → `is_unlocked`) já
funcionam sem alteração. Na tela de Equipamentos o item aparece travado com a linha
"como liberar" = `ITEM_UNLOCK_SHOP` (já existente), sem contador de progresso (compra, não
quest de contagem).

## Feedback visual — glow pulsante na HUD

Em [hud.gd](../../../scripts/ui/hud.gd), o `_build_equipped_items_display`
([hud.gd:2430](../../../scripts/ui/hud.gd)) já monta os slots de itens equipados (canto
superior direito, construído uma vez por run).

- Em `_make_hud_item_slot`, quando `id == "sanguinario"`, guardar a referência do slot
  (ex: `_sanguinario_hud_slot`) e adicionar um `Panel`/`ColorRect` de brilho vermelho
  atrás do ícone, inicialmente invisível.
- A HUD conecta em `player.sanguinario_active_changed`:
  - **ativo** → inicia um tween em loop (pulsa o `modulate`/alpha do glow vermelho +
    leve brilho), comunicando o "modo fúria".
  - **inativo** → para o tween e restaura o estado neutro do slot.
- Dirigido por sinal, **sem polling** no `_process`. Se o item não estiver equipado, o
  sinal nunca dispara o estado ativo (`_sanguinario_bonus == 0`).

## Arte do ícone

1. Decodar `assets/Hud/itens/Sangue Quente.aseprite` → `assets/Hud/itens/sanguinario.png`
   (32×32, todas as layers compostas), usando o decoder Python já validado para os outros
   ícones de item.
2. Importar no editor do Godot (gera `.import`/`.ctex`). **Esse passo exige abrir o editor**
   — o `preload`/`load` do ícone só resolve depois da importação.

## i18n

Adicionar em [assets/i18n/translations.csv](../../../assets/i18n/translations.csv)
(colunas `keys,pt_BR,en,es,fr`):

- `ITEM_SANGUINARIO_NAME` — pt: "Sanguinário"
- `ITEM_SANGUINARIO_DESC` — pt: "Enquanto sua vida estiver abaixo de 40%, +30% de dano em
  todas as fontes." (+ en/es/fr)

`ITEM_UNLOCK_SHOP` já existe.

## Regras assumidas

- Limiar **estritamente** `< 40%` ("menos de 40%").
- `×1.30` **multiplicativo** sobre o dano final (stacka multiplicativo com Maré, upgrades, etc.).
- DoTs já aplicados **antes** de cair pra < 40% não são recalculados retroativamente; o
  bônus vale pro dano calculado enquanto o buff está ativo (mesmo comportamento do fator
  do Maré).
- Curar de volta pra ≥ 40% **remove** o buff e o glow no mesmo frame do `hp_changed`.

## Fora de escopo

- Dano de fontes que não escalam com o stat "Dano" (base fixa de aliados, contato, estruturas).
- Stacks/níveis do item (é binário: equipado + HP baixo = ativo).
- Vinheta/borda de tela ou som dedicado (só o glow no slot da HUD).

## Arquivos tocados

- `scripts/player/player.gd` — base + fator + sinal + flip.
- `scripts/systems/inventory_items.gd` — item no `ITEMS` + branch `low_hp_damage`.
- `scripts/ui/loja_petalas.gd` — entrada no `CATALOG` (660).
- `scripts/ui/hud.gd` — glow pulsante no slot do Sanguinário.
- `assets/Hud/itens/sanguinario.png` (+ `.import`) — ícone decodado.
- `assets/i18n/translations.csv` — `ITEM_SANGUINARIO_NAME`/`_DESC`.
