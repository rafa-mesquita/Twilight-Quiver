# Pet Tilisko Arqueiro (design)

**Data:** 2026-06-07
**Tipo:** Novo aliado (pet) que dispara junto com o player.

## Resumo

Pinguim arqueiro que fica perto de você. **Toda vez que você atira, ele atira uma flecha**
na mesma direção que você mirou. Não tem HP e não é alvo dos inimigos. A flecha causa uma
% do seu dano e aplica os efeitos de contato do seu tiro atual.

| Nível | Dano (% do dano nominal da sua flecha) | Extras |
|---|---|---|
| L1 | 20% | flecha simples (sem perfuração/ricochete/espectral/múltiplas) |
| L2 | 30% | — |
| L3 | 60% | **30% de chance** de mirar num inimigo aleatório da tela (em vez da sua mira) |
| L4 | 60% | as flechas seguem TODAS as categorias (perfura/ricocheteia/múltiplas/duplas/espectral + elementais) |

- **Efeitos de contato (todos os níveis):** pacote completo do seu tiro atual — queimar
  (fogo), maldição, gelo, vulnerabilidade da maré, AoE+stun da pedra, **cadeia de raios e
  graviton** inclusos. Reusa `player._stamp_spectral_effects`.
- **Crit:** a flecha do Tilisko **rola crit próprio** (usa a chance/mult de crit do player).
- **1 Tilisko só**, levela 1-4 (não spawna múltiplos).

## Arquitetura

### O pet — `scripts/allies/tilisko.gd` + `scenes/allies/tilisko.tscn`

Molde do **Leno** (`leno.gd`): `CharacterBody2D` voador, **sem HP**, grupos `ally` + `tilisko`,
NÃO entra em `tank_ally` (inimigos ignoram; flechas do player atravessam). Segue o player em
formação (bob vertical + sombra fixa). Anims `idle`/`walk`/`atirar` do `Tilisko.aseprite`
(exportado pra sheet → SpriteFrames no `.tscn`). Tem `Muzzle` (origem da flecha).

**Diferença do Leno:** NÃO tem cooldown/targeting próprio. É **event-driven** — método
`on_player_shot()` que só toca a anim "atirar" (o spawn da flecha é feito pelo player, que
tem todo o config de flecha). Anda em `walk` quando se move, `idle` parado.

### O disparo — no `player.gd`

No fim de `_release_arrow()` (depois da volley do player), chamar
`_fire_tilisko_shots(locked_aim_dir)`:

```
func _fire_tilisko_shots(aim_dir):
    for t in get_tree().get_nodes_in_group("tilisko"):
        if t inválido: continue
        t.on_player_shot()                      # toca anim "atirar"
        var origin = t.muzzle.global_position
        var dir = aim_dir
        if tilisko_level >= 3 and randf() < 0.30:
            var e = _random_enemy_on_screen()
            if e != null: dir = (e.global_position - origin).normalized()
        var mult = [0.2, 0.3, 0.6, 0.6][tilisko_level-1]
        if tilisko_level < 4:
            _spawn_tilisko_arrow(origin, dir, mult)      # 1 flecha, pacote elemental
        else:
            _fire_volley(origin, dir, mult)              # volley completa a 60%
```

- **`_spawn_tilisko_arrow(origin, dir, mult)` (L1-L3):** instancia `arrow.gd` (NÃO spectral),
  `arrow.damage = <dano nominal da flecha base> * mult`, `_stamp_spectral_effects(arrow)`
  (elementais + cadeia + graviton; NÃO pierce/ricochet/multi/spectral), `source = self`,
  `telemetry_source_id = "tilisko"`, posição em `origin`, `set_direction(dir)`. A flecha é
  normal → o `_on_hit` dela já rola crit (via player) e aplica os efeitos. Sem volley.
  - "Dano nominal da flecha base" = o mesmo que o player usa pra UMA flecha primária:
    `arrow_base_damage * arrow_damage_multiplier * _mare_damage_factor() * _cajado_arrow_factor()`
    (sem dmg_mult de volley, sem crit). Encapsular num helper `_base_arrow_damage()` reusado
    pelo `_spawn_arrow` e aqui (DRY).
- **`_fire_volley(origin, dir, dmg_scale)` (L4 + refactor do player):** extrai o miolo de
  `_release_arrow` que constrói a volley (`_build_volley`) e spawna cada flecha. Hoje o
  `_spawn_arrow` usa `muzzle.global_position` fixo — adicionar parâmetro `origin` (default =
  muzzle) e um `dmg_scale` global (default 1.0) propagado pro `arrow.damage`. O player chama
  `_fire_volley(muzzle.global_position, locked_aim_dir, 1.0)`; o Tilisko-L4 chama com o muzzle
  dele + 0.6. Assim o L4 herda pierce/ricochet/multi/duplas/espectral/elementais de graça.
  - As flechas do Tilisko-L4 levam `telemetry_source_id = "tilisko"` (param no `_fire_volley`).

### Seleção de inimigo (L3)

`_random_enemy_on_screen()` — sorteia um inimigo vivo do grupo `enemy` dentro dos bounds
visíveis da câmera (ou simplesmente qualquer vivo, já que "qualquer inimigo na tela").
Retorna `null` se não houver (aí usa a mira normal).

## Integração de aliado (checklist — [[feedback_new_upgrade_integration_checklist]])

- **Player:** `var tilisko_level: int = 0`; `apply_upgrade("tilisko")` → `+1` + `_refresh_tiliskos()`;
  `get_upgrade_count("tilisko")` → `tilisko_level`; `reset_pet("tilisko")`; `_refresh_tiliskos()`
  (spawna/garante 1 Tilisko no player, no molde de `_refresh_lenos`).
- **Loja:** `_ALL_ALLY_IDS` += `"tilisko"` (`wave_shop.gd`); `_build_ally_slot`/descrições via
  `TILISKO_DESCS` + `_get_upgrade_descs_array`; arte `CARD_PATH_OVERRIDES["tilisko"] =
  "res://assets/Hud/shop/aliado/tilisko/tilosko card.png"`; **texto branco** no card do Tilisko
  (override de `ALIADO_TEXT_COLOR` só pra esse id).
- **Starter pack (pool de boas-vindas):** `FREE_UPGRADE_POOL` (`wave_manager.gd`) += `tilisko`.
- **Dev mode:** `dev_panel._ALL_UPGRADE_IDS` += `"tilisko"`; `UPGRADE_BTNS` += entry
  `{"id":"tilisko","node":"UpgTiliskoBtn",...}`; nó `UpgTiliskoBtn` no `dev_panel.tscn`
  (seção de aliados, ao lado de `UpgLenoBtn`).
- **HUDs:** `hud.UPGRADE_DISPLAY_ORDER` += `tilisko` (chip in-game); `hud._BUILD_UPGRADE_IDS`
  += `tilisko` (build do fim de jogo + leaderboard); arte do chip: `hud._UPG_PATHS["tilisko"]`
  = a mesma carta (ou um ícone) + garantir que `tilisko` seja tratado como aliado em
  `_UPG_ALIADO_IDS` se existir esse set.
- **Painel de dano (TAB):** `damage_panel.SOURCE_LABELS["tilisko"] = "DMG_PANEL_TILISKO"` +
  key i18n.

## i18n (`translations.csv`, 4 línguas)

- `SHOP_ALLY_TILISKO` (nome do card).
- `SHOP_ALLY_TILISKO_DESC_1..4` (uma por nível).
- `DMG_PANEL_TILISKO` ("Tilisko").

## Arte

- `Tilisko.aseprite` (em `assets/aliados/Tilisko Arqueiro/`) → exportar sheet + tags
  idle/walk/atirar (via Aseprite CLI), montar SpriteFrames no `.tscn`.
- Card: `assets/Hud/shop/aliado/tilisko/tilosko card.png` (já existe).

## Fora de escopo (YAGNI)

- Sem HP/morte do Tilisko (nunca morre; cleanup no `_die` do player).
- Sem som próprio de tiro do Tilisko nesta versão (reusa o som da flecha, ou silencioso —
  decidir no playtest; default: a flecha dele NÃO toca shoot sound pra não dobrar o áudio).
- Sem deploy/bump agora (junta no próximo release).

## Critérios de aceite

- Comprar Tilisko spawna 1 pinguim que segue o player, sem HP, ignorado pelos inimigos.
- A cada tiro do player, o Tilisko toca "atirar" e solta 1 flecha na sua direção (L1-L3) com
  20/30/60% do dano + efeitos de contato + crit próprio.
- L3: ~30% dos tiros do Tilisko miram num inimigo aleatório da tela.
- L4: a flecha do Tilisko vira volley completa (perfura/ricocheteia/múltiplas/espectral) a 60%.
- Aparece na loja (card texto branco), no dev panel (botão), no starter pack, no chip da HUD,
  no build de fim de jogo/leaderboard e no painel de dano (linha "Tilisko").
- Sem o pet, nada muda (regressão zero).
