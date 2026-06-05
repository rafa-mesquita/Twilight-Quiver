# P4 — Loja de Pétalas (loja meta, fora do jogo) — Design

> Data: 2026-06-05
> Branch: `feature/economia-petalas`
> Subprojeto P4 da [economia de pétalas](2026-06-04-economia-petalas-visao.md).
> Depende de: P1 (PetalBank) ✅ + P3 (Inventário/itens) ✅.

## Objetivo

Tela **fora do jogo** onde o jogador gasta o **banco de pétalas** (`PetalBank`,
persistente) pra comprar skins e itens equipáveis. É a primeira (e por ora única)
torneira de gasto do banco. Destrava o que hoje está com "Disponível na loja":
skin **World Cup** + itens **Adaga da Meia-Noite** e **Arco Dourado**.

## Navegação

- Novo botão **"Loja"** no menu principal, em `$Center/VBox` **logo abaixo de
  "Inventário"** (`SkinsButton`), antes de `LeaderboardButton`. Label `MENU_SHOP`.
- `pressed` → `change_scene_to_file("res://scenes/ui/loja_petalas.tscn")`.
- Adicionar `loja_petalas.tscn` em `MenuAudio._MENU_SCENES` (música + clique de menu).

## Tela (`scenes/ui/loja_petalas.tscn` + `scripts/ui/loja_petalas.gd`)

Estrutura mínima na cena (resto construído em código, padrão do `skin_select`):
- Título "LOJA" (`LOJA_TITLE`).
- **Saldo do banco**: ícone da pétala (`assets/Hud/petals.png`) + total (`PetalBank.get_total()`),
  no topo. Atualiza após cada compra.
- `GridContainer` de **cards** (construído em `_build_catalog`).
- Botão **Voltar** (`COMMON_BACK`) → volta pro `main_menu.tscn`.

### Catálogo (v1) — dado no script
```
[
  {"kind": "skin", "id": "World_Cup",      "price": 120},
  {"kind": "item", "id": "midnight_dagger", "price": 200},
  {"kind": "item", "id": "golden_bow",      "price": 200},
]
```

### Card
- **Skin** (World Cup): thumbnail da skin (reusa o mecanismo de thumbnail de kit do
  `skin_select` / `player_preview` com as parts da World Cup via
  `SkinLoadout.get_parts_by_skin_name`) + nome + preço.
- **Item** (Adaga/Arco): ícone do item (`InventoryItems.get_icon_path`, 32×32 nearest,
  ampliado) + nome (`tr(ITEMS[id].name)`) + descrição curta do efeito + preço.
- **Linha de preço/estado** (3 estados):
  - **Comprado**: selo "Comprado ✓" (`LOJA_OWNED`), sem botão.
  - **Pode comprar** (banco ≥ preço): botão "Comprar  N 🌸" (`LOJA_BUY` + preço + ícone).
  - **Sem saldo** (banco < preço): botão desabilitado/cinza, "N 🌸" + dica
    `LOJA_INSUFFICIENT` ("Pétalas insuficientes") no hover/abaixo.

## Compra

1. Clique em "Comprar" → **modal de confirmação** (`LOJA_CONFIRM` = "Comprar %s por %d pétalas?")
   com **Confirmar** (`COMMON_CONFIRM`) / **Cancelar** (`COMMON_CANCEL`).
2. Confirmar → `PetalBank.spend(price)`:
   - sucesso → marca como comprado (persistente), `MenuAudio.play_drop()` (som de compra),
     refaz saldo + cards.
   - falha (saldo mudou / insuficiente) → não faz nada (botão já vinha gated).
3. O unlock **vira liberado na hora** (o `is_unlocked`/`shop_petals` lê o set de comprados):
   o item aparece equipável no Inventário → Equipamentos; a World Cup destrava na aba Skins.

## Persistência + encaixe no unlock existente

- **`PetalBank.spend(amount: int) -> bool`** (novo): se `get_total() >= amount > 0`,
  debita e salva, retorna true; senão false.
- **Itens comprados** — `InventoryItems`:
  - `is_purchased(id) -> bool` e `mark_purchased(id)` em `settings.cfg [inventory] purchased`
    (CSV de ids).
  - `is_unlocked` tipo **"shop"**: troca `return false` por `return is_purchased(id)`.
- **Skins compradas** — `SkinLoadout`:
  - `is_skin_purchased(name) -> bool` e `mark_skin_purchased(name)` em
    `settings.cfg [progress] purchased_skins` (CSV).
  - tipo **"shop_petals"** nas **duas** avaliações (`_is_quest_satisfied` e
    `_is_quest_satisfied_live`): troca `return false` por `return is_skin_purchased(skin_name)`
    (a live precisa do nome da skin — passar/derivar o skin_name no branch).
  - ⚠ A World Cup está em `DEV_QUEST_LOCKED = ["World_Cup"]` (força bloqueada mesmo em
    debug). Manter — assim a compra é testável de verdade; `DEV_QUEST_LOCKED` ignora o
    estado real só pra UI de bloqueio. **Decisão:** tirar World_Cup de `DEV_QUEST_LOCKED`
    pra a compra refletir de fato no debug (senão compra mas continua locked no editor).

## Preços (definidos pelo user)

- Adaga da Meia-Noite: **200** · Arco Dourado: **200** · World Cup: **120**.

## i18n (novas keys em `translations.csv`, 5 colunas pt/en/es/fr)

- `MENU_SHOP` ("Loja")
- `LOJA_TITLE` ("LOJA")
- `LOJA_BUY` ("Comprar")
- `LOJA_OWNED` ("Comprado")
- `LOJA_INSUFFICIENT` ("Pétalas insuficientes")
- `LOJA_CONFIRM` ("Comprar %s por %d pétalas?")
- `COMMON_CONFIRM` ("Confirmar") — se não existir.
- Reusa: `COMMON_BACK`, `COMMON_CANCEL`, nomes/descrições dos itens, nome da skin.

## Arquivos afetados

- `scenes/ui/main_menu.tscn` — novo `LojaButton` no VBox (abaixo de SkinsButton).
- `scripts/ui/main_menu.gd` — `@onready` + `pressed` → troca de cena.
- `scenes/ui/loja_petalas.tscn` + `scripts/ui/loja_petalas.gd` — a tela (novos).
- `scripts/systems/petal_bank.gd` — `spend()`.
- `scripts/systems/inventory_items.gd` — `is_purchased`/`mark_purchased` + `is_unlocked` shop.
- `scripts/systems/skin_loadout.gd` — `is_skin_purchased`/`mark_skin_purchased` + `shop_petals`
  eval + tirar World_Cup de `DEV_QUEST_LOCKED`.
- `scripts/systems/menu_audio.gd` — registra a cena nova.
- `assets/i18n/translations.csv` — keys novas.

## Edge cases

- Comprar com saldo exato → banco fica 0 (ok). `spend` rejeita amount <= 0 e saldo < amount.
- Reabrir a loja após comprar → card mostra "Comprado ✓" (lê o set persistente).
- Item já equipado nunca acontece antes de comprar (locked não equipa); após comprar fica
  equipável normalmente.
- Sem pétala nenhuma → todos os cards desabilitados (mas visíveis com preço).

## Fora de escopo (YAGNI)

- Vender outras skins por pétala (só World Cup na v1).
- Reembolso / vender de volta.
- Preview animado elaborado (thumbnail estático/animado simples já basta).
- Categorias/abas dentro da loja (catálogo pequeno → grid único).

## Validação

- Compile headless (autoloads).
- Playtest: comprar item → aparece equipável no Inventário; comprar World Cup → destrava
  na aba Skins; saldo desconta e persiste; modal confirma/cancela; estados do card.
