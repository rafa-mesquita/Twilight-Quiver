# Próxima Sessão

> Última atualização: 2026-06-05 17:30
> Sessão anterior: deploy da **pre-alpha-0.10.0** — economia de pétalas inteira (P1+P3+P4): inventário de itens equipáveis (7 itens), loja meta de pétalas, animação de unlock de item, cursor de menu pixel-art, balance. Mergeado na `main`, no ar.

## Estado atual

- **PÚBLICO = `pre-alpha-0.10.0`** (deploy 2026-06-05). `main` sincronizada com origin, tree limpo. Site + launcher já têm. Release é Latest com zips win/mac. A branch `feature/economia-petalas` foi **mergeada (ff) na main** — não é mais experimental.
- **Economia de pétalas: P1 (moeda) + P3 (inventário) + P4 (loja meta) SHIPPADOS.** Falta só o **P2 (loja in-game "ESPECIAL")** — é o que o user quer fazer a seguir pra fechar a economia.
- `DEV_UNLOCK_ALL_ITEMS = false` (revertido pro release). `DEV_UNLOCK_ALL = true` no skin_loadout (libera skins em debug; ignorado em release).

## Por onde começar

1. **P2 — Loja de pétalas IN-GAME ("ESPECIAL"), no lugar das Estruturas.** É o último subprojeto da economia. Spec PRONTO: [docs/superpowers/specs/2026-06-05-p2-loja-petalas-design.md](docs/superpowers/specs/2026-06-05-p2-loja-petalas-design.md). Resumo: a seção **Estruturas do `wave_shop`** vira a loja ESPECIAL — aparece **10%/shop a partir da wave 6** + pity (≥1× antes da wave 14); pool de 3 (Torre comprada em pétala, Segunda Vida = revive 50% HP empilhável, Super-Upgrade = +1 em cada status), rola 2. Precisa de `player.spend_petals` (já tem `add_petals`; `PetalBank.spend` existe mas é só pro banco/loja meta — a loja in-game gasta a **carteira por-run** `player.petals`). Custo em pétala SEPARADO do gold. **Brainstorm rápido + writing-plans antes** (revisar o spec, que é de 2026-06-05 e pode precisar de ajuste pós-0.10.0).
2. **Deletar a prerelease de diagnóstico `pre-alpha-0.9.4`** se o amigo confirmou que o leak de FPS sumiu: `gh release delete pre-alpha-0.9.4 --repo rafa-mesquita/twilight-quiver-releases --cleanup-tag --yes`.
3. **(Opcional) Tunar a economia** — drop de pétalas até W21 ≈ **52-73 por wave-clear (média ~62) + ~8-18 de drop de mob** = ~60-90/run. Preços loja meta: Cabelo 150, World Cup 350, Adaga/Arco 750. Faixas por round no `wave_manager._finish_wave`; `DROP_CHANCE = 0.0075` em `petal_drop.gd`.

## Contexto crítico

### Itens equipáveis (sistema, [scripts/systems/inventory_items.gd](scripts/systems/inventory_items.gd))
- Cada item tem **`effects: []`** (múltiplos efeitos) OU `effect: {}` (single, legado) — `_item_effects(id)` abstrai. Tipos: `start_status` (apply_upgrade ×amount), `welcome_elemental_choice`, `pet_slot`, `gold_per_round`, `free_first_roll`, `max_hp_override`, `disable_shop_hp`.
- **Unlock:** `default` (sempre), `shop` (→ `is_purchased`, comprado na loja meta), `quest` (reqs com stat persistente >= value). Guard `shop_petals` pra skins em `is_unlocked`/`is_kit_unlocked` do skin_loadout.
- **7 itens:** Adaga(+1 dano, loja), Arco(+1 atk speed, loja), Mestre Elemental(escolha elemental, quest: 10× roleta), Adote Mais Um(+1 slot pet, quest: 1500 cura aliado + 1000 kills aliado), Dividendo Arcano(+1 gold/round, quest: 2500 gold gasto), Estou com Sorte(40% 1º reroll grátis, quest: 1 wave limpa), **No Limite**(glass cannon: HP 50 + sem HP na loja + começa move_speed+chuva coins L2, quest: 500 kills com player ≤50% HP).
- **Stats persistentes novos (SkinLoadout):** ally_heal_total, ally_kills_total, gold_spent_total, waves_cleared_total, elemental_roulette_buys_total, low_hp_kills_total. Trackeados no player (`stats_*`) → `hud._collect_run_stats` → `SkinLoadout.record_run`. ⚠ **Sempre que adicionar stat: tem que aparecer no `_collect_run_stats` E no `record_run`** (um edit antigo da Roleta falhou no meio e o stat nunca foi exposto — corrigido nesta sessão).
- `InventoryItems.start_granted_amount(status)` impede o presente pós-boss (wave 14) subir um upgrade que só veio do item (No Limite não vira gold_magnet L3 / move_speed L2).

### Loja meta ([scripts/ui/loja_petalas.gd](scripts/ui/loja_petalas.gd) + .tscn)
- Tela própria via botão "Loja" no menu (abaixo de Inventário). Layout C: sidebar categorias + grid + painel de detalhe à direita. Frame 1440×820 centralizado (igual inventário). Inclui nó **Cursor** (`menu_cursor.tscn`) como os outros menus.
- Vende `kind`: "skin", "part" (peça avulsa, ex Cabelo Vermelho — thumbnail = Default + a peça via `SkinLoadout.find_part`), "item". `PetalBank.spend` + `mark_purchased`/`mark_skin_purchased`. ⚠ `_parts_cache` evita re-scan caro do filesystem.

### Cursor de menu ([scripts/ui/menu_cursor.gd](scripts/ui/menu_cursor.gd))
- Mãozinha pixel-art (hardware cursor). Mapeia `menu_grab` nas shapes de drag (DRAG/CAN_DROP/FORBIDDEN) — senão o Godot mostrava o "bloqueado". As 5 telas de menu trocaram `cursor.tscn` (mira) por `menu_cursor.tscn`. In-game mantém a mira animada.

### Editar `.gd`/`.csv` (GOTCHA crítico)
- ⚠ **Edit tool falha com TAB do GDScript.** Workaround: **Python** (`open(...,encoding='utf-8')` universal-read + `newline='\r\n' ou '\n'` detectado por arquivo, replace por âncora exata; assert `count(old)==1`). **player.gd e skin_loadout.gd são CRLF**; hud/wave_shop/inventory_items/skin_select/loja são LF. Acento no anchor quebra às vezes — prefira âncora ASCII.
- Validar: `Godot --headless --editor --quit --path .` (carrega autoloads). Depois `git checkout project.godot` (o editor suja com import noise).

### Deploy (evergreen)
- Deploy = push pro `main` (deploy.yml builda + Pages + anexa zips na release `twilight-quiver-releases`, tag = `config/version`). **Bump `config/version` ANTES.**
- Patch notes: **pré-criar a release ANTES do push** (`gh release create pre-alpha-X.Y.Z --repo rafa-mesquita/twilight-quiver-releases --notes-file ...`); CI faz `upload --clobber` preservando notas. **Cumulativas** (novo em cima, mantém antigas; tom de jogador, sem detalhe técnico). gh logado = **rafaelmesquita-spec** (tem acesso à releases repo). git push = rafa-mesquita.

## Pendências conhecidas

- [ ] **P2 — loja in-game ESPECIAL** (último subprojeto da economia; spec pronto).
- [ ] Deletar prerelease `pre-alpha-0.9.4` (diagnóstico) se o leak foi confirmado resolvido.
- [ ] Playtest in-game da 0.10.0 (a maior parte foi validada só no headless): efeitos do No Limite, compra na loja meta refletindo no inventário, toast/death-screen de unlock de item, highlight verde de drop, cursor de menu + grab.
- [ ] (Tuning) calibrar economia de pétalas vs preços se sentir desbalanceado.

## Arquivos / locais relevantes

- `scripts/systems/inventory_items.gd` — catálogo de itens, effects, unlock, purchased.
- `scripts/ui/loja_petalas.gd` + `scenes/ui/loja_petalas.tscn` — loja meta.
- `scripts/ui/wave_shop.gd` — **seção Estruturas é o que o P2 transforma**; roll de status (filtro de HP do No Limite em `_roll_status_slots`); StatsCard.
- `scripts/systems/wave_manager.gd` — `_finish_wave` (recompensa de pétala + gold/round), `_grant_free_random_upgrade`/`_grant_free_owned_upgrade` (presentes), `_build_wave_config`.
- `scripts/systems/skin_loadout.gd` — STAT_*, record_run, is_unlocked/is_kit_unlocked (guard shop_petals), find_part, mark_skin_purchased.
- `scripts/player/player.gd` — stats_* da run, notify_kill_by_source (low_hp_kills), apply_upgrade, add_petals/spend_gold.
- `scripts/ui/skin_select.gd` — inventário (aba Equipamentos: cards, drag-drop, highlight verde de drop, seções liberados/travados).
- `scripts/ui/menu_cursor.gd` + `scenes/ui/menu_cursor.tscn` — cursor de menu.
- `docs/superpowers/specs/2026-06-05-p2-loja-petalas-design.md` — spec do P2.
- `assets/Hud/itens/` — sprites + aseprite dos 7 itens. `assets/Hud/cursor/` — mãozinhas.

## Comandos úteis

```bash
# Validar compile (Godot no Desktop):
& "C:\Users\rafam\Desktop\Godot_v4.6.2-stable_win64.exe" --headless --editor --quit --path .
git checkout project.godot   # descarta o import-noise do editor

# Importar assets novos:
& "C:\Users\rafam\Desktop\Godot_v4.6.2-stable_win64.exe" --headless --import --path .

rtk git status && rtk git log --oneline -8
gh release list --repo rafa-mesquita/twilight-quiver-releases --limit 3
```
