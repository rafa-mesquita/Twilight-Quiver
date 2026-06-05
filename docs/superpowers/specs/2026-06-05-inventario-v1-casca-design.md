# Inventário v1 (casca visual) — Design

**Data:** 2026-06-05
**Subprojeto:** Inventário da [Economia de Pétalas](2026-06-04-economia-petalas-visao.md)
(originalmente "P3"). Implementado ANTES da loja in-game (ver ordem reordenada).
**Status:** Design aprovado, pronto pra implementação.
**Depende de:** P1 (pétalas / `PetalBank`) — implementado.

## Objetivo

A tela "Skins" vira "**Inventário**". v1 é só a **casca visual**: rename, banco de
pétalas visível, e uma aba "Itens" com slots vazios. **Sem** sistema de
equipar/salvar/aplicar buff e **sem** itens — isso vem junto da loja meta depois.
As skins continuam funcionando igual.

## Contexto

[skin_select.gd](../../../scripts/ui/skin_select.gd) / `skin_select.tscn`:
- Barra de tabs `tabs_container` montada em `_build_tabs()`
  ([:230](../../../scripts/ui/skin_select.gd#L230)) — uma tab por slot, com a tab
  **Kits** primeiro via sentinel `_KIT_SLOT` ([:15](../../../scripts/ui/skin_select.gd#L15)).
- `cards_grid` mostra os cards da tab atual; `empty_label` pro estado vazio.
- Botão do menu = `MENU_PLAYER` ("Skins") em [main_menu.gd](../../../scripts/ui/main_menu.gd)
  (`skins_button`), abre `skin_select.tscn`.

## Design

### 1. Rename (i18n)
- `MENU_PLAYER`: "Skins" → **"Inventário"** (4 línguas) em
  [translations.csv](../../../assets/i18n/translations.csv). (Mantém a key
  `MENU_PLAYER` pra não mexer no .tscn do botão.)
- **Título da tela** em `skin_select.tscn` → "Inventário" (trocar o texto/label
  do título; se for key i18n, atualizar a key correspondente).

### 2. Banco de pétalas visível
- Na tela do inventário, mostra o total do banco (`PetalBank.get_total()`) num
  canto (ícone pétala `assets/Hud/petals.png` + número), construído em código no
  `_ready` (mesmo padrão dos displays do P1). É o novo lar do banco (foi tirado
  do menu).

### 3. Aba "Itens" (placeholder)
- Novo sentinel `_ITEMS_SLOT` (análogo a `_KIT_SLOT`, não bate com slot real).
- `_build_tabs()`: adicionar a tab **"Itens"** no FIM da barra (depois da Aljava).
- Ao selecionar a tab Itens: o `cards_grid` mostra **3 slots vazios** (cards
  placeholder cinza) + a mensagem **"Nenhum item desbloqueado ainda"**
  (via `empty_label` ou um label no grid).
- **Sem lógica de equipar/salvar.** Clicar nos slots não faz nada (ou um
  no-op). O número 3 e os slots são placeholder do sistema futuro.
- A seleção de tab existente (`_select_tab`/equivalente) precisa tratar o
  `_ITEMS_SLOT` como caso especial (mostra os placeholders em vez de peças).

### 4. i18n
Keys novas: `INVENTORY_ITEMS_TAB` ("Itens"), `INVENTORY_NO_ITEMS` ("Nenhum item
desbloqueado ainda"), e o título da tela (`INVENTORY_TITLE` se aplicável). +
editar `MENU_PLAYER`.

## Fora de escopo (v1)
- Sistema de equipar/desequipar/salvar itens.
- Aplicar buffs pré-jogo.
- Os itens em si (vêm com a loja meta).
- Unlock de item por missão.

## Arquivos afetados
- `scripts/ui/skin_select.gd` — sentinel `_ITEMS_SLOT`, tab "Itens" em
  `_build_tabs`, render placeholder dos 3 slots + mensagem, banco code-built.
- `scenes/ui/skin_select.tscn` — título "Inventário" (se for texto no .tscn).
- `assets/i18n/translations.csv` — `MENU_PLAYER` editado + keys novas.

## Notas
Número de slots (3) é placeholder/tunável. A casca deixa claro pro jogador que
"vão existir itens equipáveis aqui", sem prometer mecânica ainda.
