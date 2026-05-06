# Próxima Sessão

> Última atualização: 2026-05-06
> Sessão anterior: Shop pós-wave (upgrades + estruturas) + perfuração proc-based + scaling de waves + UX polish (rerolls, confirmação, sons)

## Estado atual

- **Branch:** `main`. Último commit `a9f3e30` ("Add mage enemy with ranged projectile"). **TODAS as mudanças desde fev/26 ainda não commitadas** — gold system, shop, perfuração, torre, rerolls, sons.
- **Loja pós-wave funcional**: 3 estruturas (Torre de Flechas + 2 placeholders) + 3 upgrades (HP/Dano/Perfuração) com tier (1★→4★ + cor) + reroll por categoria (1 coin, 1× por turno) + confirmação 2-cliques + popup ao prosseguir com upgrade selecionado.
- **Torre de Flechas viva**: HP 300, 2 muzzles, 80% dano da flecha, FadeArea, off-screen alert, renasce entre waves se for destruída.
- **Perfuração refeita** conforme spec do excalidraw: a cada 3 ataques próxima flecha procca (atravessa inimigos E objetos). Lv 1=+30% dmg, lv 2=+60%+hitbox 1.8×, lv 3=+90%, lv 4=todo ataque procca. Visual: sprite dourado + trail laranja + 1.1× scale, 3º target tem efeito 2.2× dourado.
- **Wave scaling**: +12% HP / +8% dano por wave (linear). Mage propaga `damage_mult` pro inseto invocado. Wave 1 nerfada (sem invocador), wave 2 leve.
- **Sons** wireados: morte (música pausa + fade-in 1.8s), buy (-16dB), coin pickup (-16dB). Wave start REMOVIDO a pedido.

## Por onde começar

1. **Commitar tudo desta sessão** — pelo volume (≈30+ arquivos), sugiro 3 commits temáticos. Ver seção "Commits sugeridos" abaixo.

2. **Implementar mais 2 estruturas** (slots "Em breve" no shop) — sugestões: armadilha de espinho (área), barreira (parede destrutível bloqueia inimigos). Já tem `STRUCTURE_CATALOG` em [scripts/wave_shop.gd](scripts/wave_shop.gd) preparado pra extensão.

3. **Validar overlap nos 5 spots de placement** — atualmente posições randômicas não checam colisão com árvores/casas, podem cravar dentro de obstáculos. Solução: physics raycast ou check overlap com nodes do grupo "world" antes de listar spot como válido.

4. **Roadmap upgrades fase Movimentação + Aliados** — falta toda parte do excalidraw que não é Arco/HP/Perfuração. Ver `memory/project_upgrades_design.md`.

## Contexto crítico

### Perfuração é PROC, não pierce-per-level

A spec do excalidraw é que cada nível desbloqueia/intensifica uma flecha proc — **não** acumula pierces. Errei na primeira implementação (pierce += 1 por nível) e o user corrigiu mostrando o doc. Agora:
- Player tem `_perf_shot_counter` que conta ataques. A cada 3 procca.
- Lv 4: todo ataque procca (counter ignorado).
- `reset_perf_counter()` chamado no `_start_next_wave` pra evitar carry-over.

### Friendly fire na arrow.gd

- Flecha (player ou torre) NÃO causa dano em targets do grupo `"ally"` — bate como parede e crava.
- Torre passa `arrow.source = self` pra arrow ignorar SUA própria torre (atravessa, sem cravar nem dar dano).
- `_find_damageable(node)` sobe parent chain pra achar `take_damage` — necessário porque torre tem `Body` (StaticBody2D) filho que recebe a colisão sem ter o método.
- Mage projectile tem mesma lógica de parent walk (sem ally check — projétil de inimigo dá dano em torre, é objetivo do mago).

### Câmera overview no placement

`_set_camera_overview(true)` durante placement pra mostrar mapa inteiro (zoom 2.1×, pos 250,150). Tween 0.4s. Restaura zoom anterior ao sair (`_saved_zoom`). Se gameplay zoom mudar, overview se ajusta automaticamente.

### Renascimento de estruturas

Wave_manager guarda `owned_structures: Array<{scene_path, position}>` populado pelo wave_shop em `register_structure()`. No `_start_next_wave` chama `_respawn_owned_structures()` — varre o registro, e onde não tem estrutura viva (raio 8px), instancia uma nova. Estrutura sobrevivente continua intacta.

### Cards do shop com tier visual

Estrelas em Label SEPARADO (não dentro do TitleLabel) sem `theme_override_fonts/font` → usa fonte default do Godot (a at01 não tem ★). Cor do card e do título mudam por tier:
- Lv 1: branco
- Lv 2: azulado
- Lv 3: roxeado
- Lv 4+: dourado (com `+x` extra a partir do 5)

### Reroll widget

Estrutura: `HBoxContainer [IconWrap, Price]` onde IconWrap é um Control com Halo (TextureRect dourado scale 1.35×) + Btn (TextureButton da imagem do dado). Hover anima ambos via tween 0.12s. Disabled esconde halo + esmaece btn+price. Asset: `assets/Hud/reroll.png` (carregado via `load()` runtime — não preload — pra não quebrar se faltar).

### UpgHeader fix

`UpgHeader` tinha `size_flags_horizontal = 3` (EXPAND_FILL), o que jogava o reroll pro extremo direito ao lado do gold. Removi o expand e adicionei spacer Control entre reroll e gold pra manter o gold no canto.

### Sons

- `audios/effects/buy_1.mp3` — compra (-16dB)
- `audios/effects/dead effect.mp3` — morte (-14dB), pausa música via fade 0.25s e retoma com fade 1.8s ao terminar
- `audios/effects/coin-collect.mp3` — pickup (-16dB)
- `audios/effects/wave start.mp3` — **EXISTE NO DISCO MAS NÃO É USADO** (user removeu o trigger porque incomodava)

### Editor traíras (lembrança permanente)

- **NÃO Ctrl+V em instâncias** — Godot cola como filho. Use Ctrl+Shift+A.
- **Origem nos pés** pra todo prop/inimigo (offset.y negativo).
- **Pixel font (at01)** não tem ★/↻/glifos especiais — use fonte default do Godot pra esses ou um asset.

## Pendências conhecidas

### Da sessão anterior (ainda valem)
- [ ] **Skill do botão direito** placeholder em `player.gd:_use_skill`
- [ ] **CasaB fora do mapa jogável** em `main.tscn` (pos `(1220, -26)`)
- [ ] **Duplicatas**: `hud.tscn` no root vs `scenes/hud.tscn`; `scenes/cerca_cima.tscn` vs `scenes/props/cerca_cima.tscn`
- [ ] **`capra jogo.png` no root** — screenshot acidental, não commitar
- [ ] **TileMap autotile** — tiles pintados manualmente, sem terrains

### Novas desta sessão
- [ ] **Estruturas 2 e 3** são placeholder "Em breve"
- [ ] **5 posições randômicas** de placement não checam overlap com obstáculos (árvores/casas)
- [ ] **Mecânica de melhoria de hitbox no lv 2 da Perfuração** está aplicada como `hitbox_scale = 1.8`. Pode estar grande demais — testar.
- [ ] **Sons no main menu / outros menus** ainda nada
- [ ] **Música de boss / wave 5+** ainda só `Moonglass Catacombs.mp3`
- [ ] **Roadmap upgrades**: faltam categorias Movimentação, Aliados, Elementais do excalidraw

## Arquivos / locais relevantes

### Cenas principais (mudanças desta sessão)
- `scenes/wave_shop.tscn` — UI da loja; 2 colunas, ConfirmationDialog programático, PlacementHint
- `scenes/structures/arrow_tower.tscn` — torre com Body+FadeArea+HpBar (lilás, agora visível desde o início)
- `scenes/dev_panel.tscn` — debug; tem seção "Shop / Test" com botões de spawn/upgrade direto
- `scenes/main_menu.tscn`, `scenes/insect_*.tscn`, `scenes/gold.tscn`, etc. — várias cenas novas

### Scripts (mudanças desta sessão)
- `scripts/wave_shop.gd` — toda lógica de loja, rolls, placement, rerolls, popups
- `scripts/wave_manager.gd` — scaling por wave + register/respawn estruturas
- `scripts/arrow_tower.gd` — torre HP=300, _destroy com efeito dramático
- `scripts/arrow.gd` — `is_piercing`, friendly fire ally check, `_find_damageable`
- `scripts/player.gd` — `_perf_shot_counter`, `reset_perf_counter`, death sound + music fade
- `scripts/mage_enemy.gd` — `damage_mult`, `hp_mult` (propaga pro inseto)
- `scripts/insect_enemy.gd` — `damage_mult` aplica em proj.damage e poison_damage_total
- `scripts/camera_follow.gd` — `set_overview_mode()` para placement
- `scripts/gold.gd` — magnet to player, blink fade, pickup -16dB

### Assets novos
- `assets/Hud/reroll.png` — ícone do dado (do user, salvo manualmente)
- `assets/Hud/hud.png` — spritesheet de progresso
- `assets/estruturas/torre de flechas.png` — sprite da torre
- `assets/enemies/insect/` — sprites do inseto
- `assets/player/player death.png` — anim morte
- `audios/effects/buy_1.mp3`, `dead effect.mp3`, `wave start.mp3`, `coin-collect.mp3`, `mage/`

### Memória relevante
- `feature_shop_and_upgrades.md` — atualizado com perfuração proc-based correta
- `feature_gold_system.md` — drop rules e anti-exploit insect
- `project_upgrades_design.md` — spec original do excalidraw com 4 categorias

### Constantes-chave
- `scripts/arrow_tower.gd:max_hp = 300.0`, `damage_multiplier = 0.8`
- `scripts/wave_manager.gd:hp_growth_per_wave = 0.12`, `damage_growth_per_wave = 0.08`
- `scripts/wave_shop.gd:PRICE_TABLE = [4, 6, 10, 15, 20]`, `TOWER_PRICE = 10`, `REROLL_COST = 1`
- `scripts/camera_follow.gd:overview_zoom = Vector2(2.1, 2.1)`, `overview_position = Vector2(250, 150)`

## Commits sugeridos

**Não commitar:**
- `capra jogo.png` (root, screenshot acidental)
- `hud.tscn` (root, versão antiga)
- `scenes/cerca_cima*.tscn` (duplicatas, manter só `scenes/props/`)
- `.claude/settings.local.json` (preferência local)

**Commit 1 — Gold + Coin pickup + Anti-exploit insect**
- scripts/gold.gd, gold_drop.gd
- scenes/gold.tscn
- assets/obecjts map/coins.png + .import
- audios/effects/coin-collect.mp3 + .import
- assets/source/coin.aseprite

**Commit 2 — Insect enemy + Summoner mage + Wave manager scaling**
- scripts/insect_enemy.gd, insect_projectile.gd, summon_effect.gd, enemy_separation.gd
- scenes/insect_enemy.tscn, insect_projectile.tscn, insect_hit_effect.tscn, summoner_mage.tscn, summon_effect.tscn
- assets/enemies/insect/*, assets/source/insect.aseprite
- scripts/wave_manager.gd (scaling), mage_enemy.gd (damage_mult), insect_enemy.gd (damage_mult)
- audios/effects/mage/*

**Commit 3 — Shop + Tower + Perfuração + Reroll + Polish UX**
- scripts/wave_shop.gd, arrow_tower.gd, dev_panel.gd, camera_follow.gd, hud_editor.gd, main_menu.gd, game_state.gd
- scripts/arrow.gd (friendly fire + piercing), player.gd (perf counter + death sound + fade music)
- scenes/wave_shop.tscn, structures/arrow_tower.tscn, dev_panel.tscn, hud_editor.tscn, main_menu.tscn
- assets/Hud/* (incluindo reroll.png), assets/estruturas/*
- audios/effects/buy_1.mp3, dead effect.mp3, wave start.mp3
- Outros polishings (cercas top-down, player death, etc.)

## Comandos úteis

```bash
# Status compacto
rtk git status

# Ver dimensões PNG
python -c "from PIL import Image; print(Image.open('caminho/file.png').size)"

# Buscar referências de asset
grep -rn "reroll.png" scripts/ scenes/

# Listar exports do wave_manager
grep "@export" scripts/wave_manager.gd

# Reimport de fonte/asset (via Godot CLI):
# Abrir o projeto no editor → click direito no arquivo → Reimportar
```
