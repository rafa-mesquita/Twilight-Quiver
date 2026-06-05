# Próxima Sessão

> Última atualização: 2026-06-05 03:00
> Sessão anterior: deploy **0.9.7** (Fogo L2 escolha de rastro + Cadeia multi-alvo + skin World Cup) → desenho da **Economia de Pétalas** (4 subprojetos) → implementação do **P1 (pétalas moeda-base)** + **Inventário v1** (3 itens equipáveis com drag-and-drop) → 2 fixes pontuais (Fenda pega coins, World Cup body).

## Estado atual

- **PÚBLICO = `pre-alpha-0.9.7`** (deployado nesta sessão, `main` pushada). Fogo L2 escolha de rastro, Cadeia de Raios auto-raio multi-alvo (L3/L4), Auto-raio separado no TAB, skin **World Cup** (bloqueada, easter egg "loja por pétalas"). Site + launcher já têm.
- **⚠️ Branch ativa = `feature/economia-petalas` (NÃO é `main`, NÃO foi pushada).** TODO o trabalho de economia/inventário vive aqui, **só local**. Último commit: `35fab68` (Inventário v1 + Fenda + World Cup body). É experimental — não mergear/pushar até o user aprovar a economia inteira.
- **P1 (pétalas moeda-base) implementado** (`f0e1a96`): `player.petals` (carteira por-run) + `PetalBank` (banco persistente em `settings.cfg [progress]`). Ganho por level-up (tabela de round) + drop 0.75%/mob. HUD mostra ao lado do gold; banco depositado na morte E ao sair pro menu.
- **Inventário v1 implementado** (`35fab68`): tela "Skins"→"Inventário", 2 modos (Skins/**Equipamentos**). Equipamentos = preview + 3 slots verticais + lista de itens, **drag-and-drop** equip/desequip. **3 itens funcionais**: Adaga(+1 dano), Arco Dourado(+1 atk speed), Mestre Elemental (welcome upgrade vira escolha de 1 de 3 elementais).

## Por onde começar (pedido do user, nesta ordem)

1. **Polir o Inventário** — drag-and-drop + layout já funcionam, mas o user estava iterando no visual. Conferir: feel do "mover" (esconde origem ok), tamanho/posição dos slots e da lista, tooltip custom, os 3 cards do popup de elemental. Playtest visual obrigatório (não dá pra ver no headless).
2. **Bloquear os itens (só liberar quando COMPRADOS)** — hoje `InventoryItems.is_owned()` retorna `true` pra TODO item (placeholder). Precisa gatear a posse: item só aparece equipável depois de comprado na loja meta. Adicionar uma flag de posse persistente (ex: `settings.cfg [inventory] owned`) + `is_owned` real.
3. **Fazer a Loja de Pétalas (loja META, fora do jogo)** — onde se GASTA o `PetalBank` em skins + itens. É a "P4" do roadmap (spec do P2/loja-in-game está ADIADO pro fim). Provável nova tela/aba. Destrava a skin World Cup (`shop_petals`) e vende os 3 itens. Vai precisar de brainstorm/spec próprio.
4. **(Depois)** A loja de pétalas IN-GAME (seção ESPECIAL, spec `2026-06-05-p2-loja-petalas-design.md`) é o ÚLTIMO subprojeto.

## Contexto crítico

### Economia de Pétalas (roadmap — ordem reordenada pelo user)
- Ordem de IMPLEMENTAR: **P1 ✅ → Inventário ✅ → Loja meta (gasta o banco) → Loja in-game ESPECIAL (por último)**.
- Specs em `docs/superpowers/specs/`: `2026-06-04-economia-petalas-visao.md` (norte), `-p1-petalas-moeda-base-`, `-p2-loja-petalas-` (in-game, ADIADO), `-inventario-v1-casca-`.
- **Pétala**: carteira por-run (começa do 0) + banco persistente. Gasta in-game (loja ESPECIAL, futura) E fora (loja meta, próxima). Banco NÃO aparece no menu — só no inventário e shop.
- Ganho: level-up (1-5→1-2, 6-10→2-3, 11+→3-4, boss→4-5) no `_finish_wave`; drop 0.75%/mob (pickup `petal.tscn`, ~19s). Sprite `assets/Hud/petals.png`.
- Ver memória [[project_petal_economy]], [[feature_world_cup_skin]].

### Inventário / itens (estado da implementação)
- [scripts/systems/inventory_items.gd](scripts/systems/inventory_items.gd) — catálogo `ITEMS` (3 itens), `get_equipped`/`toggle_equipped` (settings.cfg `[inventory] equipped`, máx 3 slots), `apply_to_player` (efeitos `start_status`), `has_welcome_elemental_choice`. ⚠️ `is_owned()` é PLACEHOLDER (sempre true) — gatear na próxima sessão.
- [scripts/ui/skin_select.gd](scripts/ui/skin_select.gd) — toda a UI do inventário appendada no fim: `_build_mode_bar`/`_set_inv_mode`, `_build_equip_panel`/`_refresh_equip_ui`, `_make_slot`/`_make_owned_item`, drag-drop via `set_drag_forwarding`, tooltip custom (`_show_item_tooltip`, o tooltip DEFAULT não aparece com o cursor custom do jogo), `_build_petal_bank_display`. Sons via `MenuAudio.play_click/play_drop`.
- [scripts/systems/wave_manager.gd](scripts/systems/wave_manager.gd) — Mestre Elemental: `_grant_free_random_upgrade` chama `_grant_elemental_choice`→`_show_elemental_choice_popup` (3 cards, hover cresce, `_play_buy_sfx` -16db). `FREE_REWARD_CARD_PATHS` ganhou stone/tide (estavam faltando → cards invisíveis). Free upgrade exclui status que item já deu (`get_upgrade_count > 0`).
- [scripts/systems/menu_audio.gd](scripts/systems/menu_audio.gd) — `play_click()`/`play_drop()` públicos; `_drop` = `sound drop 2.mp3`; scan ignora arquivos com "drop" (senão viravam música/clique).

### Editar `.gd`/`.csv` deste repo (GOTCHA crítico, vale a sessão toda)
- ⚠️ **Edit tool FALHA muito com indentação por TAB** do GDScript (mismatch tab/espaço; "modified since read" do linter; acentos). Workaround usado a sessão toda: **script Python** (`open(...,encoding='utf-8',newline='\n')` + insere por âncora `strip()==...` ou `startswith`, copia a indentação real com `l[:len(l)-len(l.lstrip('\t'))]`). Pra blocos grandes: escrever o bloco num arquivo temp via Write e anexar/inserir com Python.
- Validar sempre: `Godot ... --headless --editor --quit` (compila com autoloads). `--check-only --script` dá falso-positivo "GameState not found" (autoloads não carregam).

### Decoder de `.aseprite` (Python, validado 0px) — pros itens 32×32
- Itens em `assets/Hud/itens/<Nome>.aseprite` (32×32, **TODAS as layers compostas** = tile completo com fundo). Decoder: header u16@6/8/10 (frames/W/H); chunk 0x2004=layer, 0x2005=cel (x=i16@8,y=i16@10,type@13; type2=zlib@26 pulando header). `canvas.alpha_composite(im,(x,y))` por layer. Export → `assets/Hud/itens/<id>.png`. Importar no Godot (`--import`) gera `.import`.
- Skins (mundo + HUD): ver [[feature_skin_tinting]] / [[feature_nautica_skin]] (grid 6×8, +nada de offset).

### Releases / deploy (evergreen — confirmado na 0.9.7 desta sessão)
- **Deploy = push pro `main`** (deploy.yml builda win/mac/web + Pages + anexa zips na release `twilight-quiver-releases`, tag = `config/version`). **Bump `config/version` ANTES.**
- **Patch notes:** pré-criar a release ANTES do push (`gh release create pre-alpha-X.Y.Z --repo rafa-mesquita/twilight-quiver-releases --notes-file ...`); CI faz `upload --clobber` preservando notas/flags. User quer notas **cumulativas** (novo em cima, mantém as antigas; sem listar fixes técnicos; tom pra jogador). gh login = `rafa-mesquita`.
- **A economia está numa branch separada — quando for deployar 0.9.8+, decidir se a economia entra (merge na main) ou se deploya só fixes da main.**

## Pendências conhecidas

- [ ] **`is_owned()` placeholder** (InventoryItems) — gatear posse por compra (item 2 acima).
- [ ] **Loja meta de pétalas** não existe (item 3) — gasta o banco; vende skins + itens; destrava World Cup.
- [ ] **Loja de pétalas in-game (ESPECIAL)** — spec pronto, implementação adiada pro fim.
- [ ] **Branch `feature/economia-petalas` não mergeada/pushada** — toda a economia é experimental local.
- [ ] Playtest visual do inventário (drag-drop, popup de elemental, tooltip) — não validável no headless.
- [ ] Mestre Elemental: confirmar in-game que os 3 cards aparecem (incl. Maré/Pedra) e a escolha aplica.
- [ ] Carryover 0.9.x: deletar prerelease de diagnóstico `pre-alpha-0.9.4` se o amigo confirmou que o leak sumiu (`gh release delete pre-alpha-0.9.4 --repo rafa-mesquita/twilight-quiver-releases --cleanup-tag --yes`).

## Arquivos / locais relevantes

- `scripts/systems/inventory_items.gd` — catálogo de itens + equip + apply. ⚠️ `is_owned` placeholder.
- `scripts/ui/skin_select.gd` — UI do inventário (modos, equip panel, drag-drop, tooltip) no fim do arquivo.
- `scripts/systems/petal_bank.gd` — banco persistente (`get_total`/`deposit`, key `petal_bank_total`).
- `scripts/pickups/petal.gd` + `scenes/pickups/petal.tscn` + `scripts/pickups/petal_drop.gd` — pickup de pétala.
- `scripts/systems/wave_manager.gd` — ganho de pétala (`_finish_wave`), Mestre Elemental (popup de escolha).
- `assets/Hud/itens/` — sprites dos itens (aseprite + png) + `petals.png`.
- `docs/superpowers/specs/2026-06-0*-*.md` — specs da economia.

## Comandos úteis

```bash
# Validar compile (Godot no Desktop):
& "C:\Users\rafam\Desktop\Godot_v4.6.2-stable_win64.exe" --headless --editor --quit --path .
# Importar assets novos (gera .import/.ctex):
& "C:\Users\rafam\Desktop\Godot_v4.6.2-stable_win64.exe" --headless --import --path .

rtk git status && rtk git log --oneline -8   # branch feature/economia-petalas, NÃO pushar ainda
gh api user --jq .login   # rafa-mesquita
```
