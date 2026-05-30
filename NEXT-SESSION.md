# Próxima Sessão

> Última atualização: 2026-05-30
> Sessão anterior: v0.7.1 — skin Terracota (+cicatriz na HUD), preview do rosto na tela de Personagem, e correção dos bugs de export da HUD de skin

## Estado atual

- **v0.7.1 publicada, pushada e deployada** (`pre-alpha-0.7.1` em [project.godot](project.godot) + [export_presets.cfg](export_presets.cfg)). Branch `main` clean, working tree limpo. Deploy do GitHub Pages **concluiu com sucesso**. Release: https://github.com/rafa-mesquita/Twilight-Quiver/releases/tag/pre-alpha-0.7.1
- **🎮 No ar:** https://rafa-mesquita.github.io/Twilight-Quiver/ — auto-deploy a cada push pro `main`.
- **Disparo de Pedra** (elemental L1-L4) shipou na **0.7.0**. A **0.7.1** trouxe: skin **Terracota** (marrom terroso + cicatriz, unlock por stun acumulado), **preview do rosto do shop na tela de Personagem** (ao vivo, ao lado do modelo), e uma leva de fixes.
- ⚠️ **A tela de Personagem nova NÃO foi validada com Godot rodando** (não há binário no ambiente). O build/export passou no CI, mas o layout/UX renderizado não foi visto. **Conferir in-game.**

## Por onde começar

1. **Validar a tela de Personagem (Player) renderizada** — abrir o jogo (editor ou site) e conferir: os dois quadros (modelo do mundo + rosto do shop) do mesmo tamanho, lado a lado na esquerda; stats de progresso pequenos/discretos na margem esquerda FORA do painel; cards em 4 colunas; o rosto atualizando ao vivo ao trocar corpo/capa/camisa/cabelo. Ajustes em [scenes/ui/skin_select.tscn](scenes/ui/skin_select.tscn) (posições/escala) + [scripts/ui/skin_select.gd](scripts/ui/skin_select.gd).
2. **Adicionar a cicatriz da Terracota no WORLD skin** — hoje a cicatriz só existe na HUD do shop (decisão do user: "por enquanto só na HUD, depois na skin"). A layer `Cicatriz` está em `assets/Hud/playerHud/Terracota.aseprite`. Pro mundo, adicionar/recolorir nos sprites de `assets/player/skin/Terracota.png` (32×32, grid 6×8).
3. **Playtest do balance da Terracota** — unlock exige **750s de stun acumulado** (qualquer fonte: claudio, pedra, gelo, etc.). Ver se é muito/pouco; ajustar em `SKIN_QUESTS["Terracota"].value` no skin_loadout.gd.
4. **Próxima feature** — possíveis: meta-progressão entre runs, mais skins/quests, wave 20+ / próximo boss, polish de UX.

## Contexto crítico

### Montagem de skin (HUD do shop) — workflow CORRIGIDO nesta sessão
**Fonte de verdade: a memória `feature_skin_tinting` (atualizada nesta sessão).** Resumo dos acertos:
- **Mapeamento canônico layer→slot** (igual gingerale): `Mask→cape` (atrás), `Rosto+Olho→head`, `Roupa/ombros→shirt`, `Cabelo→hair`. ⚠️ NÃO usar Mask→shirt (era o bug que sumia o torso no mix de skins).
- **Ordem real do aseprite (Rosto < Cabelo < Mask < Roupa) reproduzida via CLIP**: como o slot `hair` é sempre frontmost no shop-face, clipa-se o cabelo onde a máscara/roupa estão (e o rosto onde a máscara está). Layer extra na face tipo `Cicatriz` (entre Rosto e Cabelo): compõe no `head`, deixa o hair cobrir naturalmente.
- **Shift −1 frame cíclico OBRIGATÓRIO**: o `aseprite_reader` exporta com fase +1 (bob no frame 7); as skins-padrão fazem bob no frame 6. Sem isso, o cabelo dessincroniza 1px nos frames 6/12 em mixes de skin.
- **Cores 100% do aseprite — NÃO escurecer no Python** (a máscara é #975715; ter escurecido pra #6c410e foi o bug "marrom diferente").
- O snippet de tint antigo (zlib raw) que estava neste arquivo ficou **obsoleto** — usar `render.layer_to_image` + clip (na memória).
- Validação: composite da HUD deve dar **0px diff** vs ground-truth do aseprite; bob no frame 6; cape y≈50 / shirt y≈60 = gingerale.

### Tela de Personagem — preview do rosto
- `shop_player_face.gd` ganhou `apply_loadout(loadout)` (a shop usa o loadout salvo no `_ready`; a tela Player passa o loadout EM EDIÇÃO a cada clique). O rosto reusa os MESMOS PNGs da HUD.
- Os 2 bugs de mix de skin que o user reportou (cabelo dessincronizado + "camisa sumiu") eram da MINHA export antiga (timing +1 e slot swap), NÃO do jogo.

### Evergreen (releases anteriores)
- **Duskrose (boss W14)**: HP 5500 com override em DOIS lugares no wave_manager (~628 E ~1519 — mudar os dois). DoT detection via metadata `_dot_damage_pending`. Collision mask=0 durante dash. Ver memória `feature_duskrose_boss`.
- **Dev Vida Infinita**: `GameState.dev_godmode`, gate em `player.take_damage` E `player._apply_poison_tick` (os dois).
- **Capivara**: volta a curar em rounds de boss a **50%** (mudança da 0.7.1).

## Pendências conhecidas

- [ ] Validar tela de Personagem renderizada (build passou no CI, runtime não testado)
- [ ] Cicatriz da Terracota no world skin (hoje só na HUD do shop)
- [ ] Conferir balance do unlock da Terracota (750s de stun acumulado)
- [ ] (Stale check) A memória `feature_stone_arrow` diz "Lv3/Lv4 pendentes", mas o Disparo de Pedra shipou L1-L4 na 0.7.0 — confirmar in-game e atualizar a memória

## Arquivos / locais relevantes

### Tela de Personagem + shop face (0.7.1)
- [scenes/ui/skin_select.tscn](scenes/ui/skin_select.tscn) — layout: LeftCol (PreviewSection modelo + ShopFaceSection rosto, quadros iguais); StatsOverlay (progresso discreto, child do root, margem esquerda fora do painel); EditSection cards 4 colunas
- [scripts/ui/skin_select.gd](scripts/ui/skin_select.gd) — `_refresh_shop_face()` no `_ready` + em `_on_card_picked`/`_on_kit_picked`; `stats_vbox = $StatsOverlay`
- [scripts/ui/shop_player_face.gd](scripts/ui/shop_player_face.gd) — `apply_loadout(loadout)`

### Skin Terracota
- World: `assets/player/{skin,legs,shirt,cape,hair,quiver}/Terracota.png` + `bow/Terracota_{front,back}.png`
- HUD: `assets/Hud/playerHud/{head,hair,cape,shirt}/terracota.png` + source `assets/Hud/playerHud/Terracota.aseprite` (7 layers; ordem back→front: FUNDO, Rosto+Olho, Cicatriz, Cabelo, Mask, Roupa, Borda)
- [scripts/systems/skin_loadout.gd](scripts/systems/skin_loadout.gd) — `SKIN_QUESTS["Terracota"]` type `stun_seconds` value 750; unlock de kit via `is_kit_unlocked(kit_name)`

### Sistemas globais
- [scripts/systems/wave_manager.gd](scripts/systems/wave_manager.gd) — wave config, boss overrides
- [scripts/systems/game_state.gd](scripts/systems/game_state.gd) — autoload (dev_mode, dev_godmode, settings)

## Comandos úteis

```bash
rtk git status
rtk git log --oneline -10
rtk gh run list --limit 4          # status do deploy do Pages

# Deploy: basta push pro main (workflow .github/workflows/deploy.yml dispara sozinho).
# Acompanhar: gh run watch <run_id> --exit-status

# Re-exportar HUD de skin do aseprite (método CORRETO — detalhes na memória feature_skin_tinting):
#   from aseprite_reader import AsepriteFile, render
#   render.layer_to_image(af, af.frame(i), af.layers[li])  # trata linked cel (cel_type==1)
#   mapeia Mask->cape, Rosto->head, Roupa->shirt, Cabelo->hair; clipa hair atras de mask/roupa;
#   shift -1 frame ciclico; valida 0px vs composite do aseprite.
```
