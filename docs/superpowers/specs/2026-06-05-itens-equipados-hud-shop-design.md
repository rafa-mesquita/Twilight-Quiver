# Itens equipados na HUD e no Shop — Design

> Data: 2026-06-05
> Branch: `feature/economia-petalas`
> Relacionado: Inventário v1 (`35fab68`), economia de pétalas ([project_petal_economy]).

## Problema

O jogador equipa até 3 itens no Inventário (pré-jogo), mas durante a run **não há nenhum
feedback** de quais itens estão ativos. Ele esquece com o que entrou e não sabe se tem slot
vazio. Queremos que os 3 slots de equipamento fiquem **sempre visíveis** em dois lugares:

1. **HUD in-game** — durante a partida.
2. **Shop pós-wave** — entre as waves.

Read-only nos dois: equipar/desequipar continua sendo só no Inventário do menu.

## Fonte de dados

- `InventoryItems.get_equipped()` (já existe) → `Array` de até 3 ids, na ordem equipada.
- `InventoryItems.MAX_SLOTS` = 3.
- Para cada slot `i` em `0..MAX_SLOTS`:
  - `i < equipped.size()` → renderiza o ícone do item `equipped[i]`.
  - senão → slot **vazio** (moldura limpa, só borda).
- Itens são fixos durante a run (equipados pré-jogo, aplicados em `player._ready`), então a
  exibição **não muda no meio da partida** — pode ser construída uma vez.

## Ícone do item

Os itens têm sprite próprio em `assets/Hud/itens/<id>.png` (32×32, PNG standalone), referenciado
em `InventoryItems.ITEMS[id].icon`. **Não** estão no atlas de upgrades — diferente de Pets/Estruturas,
que usam `hud._get_upgrade_icon_atlas`.

Adicionar um helper estático em `inventory_items.gd`:

```gdscript
static func get_icon_path(id: String) -> String:
    return String(ITEMS.get(id, {}).get("icon", ""))
```

Quem renderiza carrega a textura direto (`load(path) as Texture2D`) num `TextureRect` com
`STRETCH_KEEP_ASPECT_CENTERED` + `TEXTURE_FILTER_NEAREST`.

## HUD in-game

**Posição:** canto superior direito, em linha horizontal, **acima** do `GoldDisplay`/`PetalDisplay`
(validado com o jogador via screenshot). À esquerda da coluna de upgrades.

**Construção:** novo Control `EquippedItemsDisplay`, criado em código no `hud.gd` seguindo o mesmo
padrão de `_build_petal_display()` (`_build_equipped_items_display()`), chamado uma vez no `_ready`.
Como os itens não mudam na run, não precisa de signal nem refresh.

**Cada slot:**
- Quadro pequeno (tamanho a calibrar no playtest; partir de ~48×48 com algum gap).
- `mouse_filter = MOUSE_FILTER_IGNORE` (não captura input — o mouse é a mira).
- **Vazio:** moldura limpa — borda + fundo translúcido escuro, **sem** "—" (decisão do jogador,
  bate com o print).
- **Equipado:** ícone do item preenchendo o quadro.
- **Sem tooltip** (o cursor in-game é a mira; tooltip poluiria/confundiria).

## Shop pós-wave

**Posição:** nova linha **"ITENS"** no StatsCard (canto inferior direito), junto das linhas de
Pets e Estruturas, seguindo o padrão existente (`_refresh_pets_box` / `_refresh_structures_box` +
`_build_mini_owned_chip`).

**Cada slot:** 3 mini-chips no mesmo estilo dos slots de Pet/Estrutura:
- Preenchido → ícone do item (via `get_icon_path`, **não** pelo atlas de upgrades).
- Vazio → mesmo visual de slot vazio dos outros (moldura/`bg` cinza, sem "—" pra ficar consistente
  com a HUD; se o slot vazio de Pet/Estrutura usa "—", manter a consistência com ELES e alinhar
  depois no playtest).
- **Com tooltip** no hover: nome + efeito do item (reusa o sistema de tooltip do shop). Como itens
  não têm `_get_upgrade_icon_atlas` nem entram em `get_upgrade_count`, o `_build_mini_owned_chip`
  atual não serve direto — criar uma variante `_build_item_chip(id)` (ou um branch no helper) que:
  - carrega o ícone do item;
  - mostra tooltip com `tr(ITEM_*_NAME)` + `tr(ITEM_*_DESC)`;
  - **não** é sellable (sem right-click).

**Header da seção:** label "ITENS" traduzido (nova key CSV, ver i18n).

**Refresh:** `_refresh_items_box()` chamado quando o StatsCard renderiza (junto de
`_refresh_pets_box`/`_refresh_structures_box`).

## i18n

Strings novas em `assets/i18n/translations.csv`:

- `SHOP_ITEMS_SECTION` → pt_BR "ITENS", en "ITEMS" (header da linha no StatsCard).

Reusadas (já existem no catálogo de itens): `ITEM_MIDNIGHT_DAGGER_NAME/DESC`,
`ITEM_GOLDEN_BOW_NAME/DESC`, `ITEM_ELEMENTAL_MASTER_NAME/DESC` — usadas no tooltip do shop.

## Arquivos afetados

- `scripts/systems/inventory_items.gd` — novo `get_icon_path(id)`.
- `scripts/ui/hud.gd` — `_build_equipped_items_display()` + chamada no `_ready`; nó
  `EquippedItemsDisplay`.
- `scripts/ui/wave_shop.gd` — `_refresh_items_box()` + `_build_item_chip(id)`; container `items_box`
  no StatsCard; chamada no refresh do card.
- `scenes/ui/wave_shop.tscn` — nó container da linha "ITENS" no StatsCard (se os boxes de
  Pet/Estrutura forem nós da cena) **ou** construído em código (seguir o que Pets/Estruturas fazem).
- `assets/i18n/translations.csv` — key `SHOP_ITEMS_SECTION`.

## Edge cases

- **0 itens equipados:** mostra os 3 slots vazios (é justamente o ponto — "ou se está com slot vazio").
- **Item órfão** (id salvo mas removido do catálogo): `get_equipped()` já filtra ids inexistentes.
- **Ícone faltando** (`load` retorna null): renderiza como slot vazio (não quebra).

## Fora de escopo (YAGNI)

- Equipar/desequipar pela HUD ou pelo shop (continua só no Inventário do menu).
- Badge de nível (itens não têm níveis).
- Tooltip na HUD in-game.
- Animação de "item equipado" (estático).
- Mudança de itens no meio da run.

## Validação

- Compile headless: `Godot --headless --editor --quit --path .` (carrega autoloads).
- Playtest visual obrigatório (não dá pra ver no headless): posição/tamanho dos slots na HUD,
  slot vazio vs preenchido, tooltip no shop, alinhamento com gold/pétalas e coluna de upgrades.
- O jogador vai calibrar tamanho/posição após testar.
