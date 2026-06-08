# Spec — Leva 0.13.x: Amuleto + Matilha + Leaderboard "minhas runs" + Morte em GIF

Data: 2026-06-08. Quatro peças independentes para a próxima versão. A e B (itens) passaram
por brainstorming; C e D são mudanças diretas que o usuário pediu para implementar sem brainstorm.

> Bump de versão só no deploy (não a cada batch). Release notes vão na tag do GitHub, não em `.md`.

---

## A. Item — Amuleto da Descoberta (`amuleto_descoberta`)

Item equipável (inventário pré-jogo). A cada 5 rounds, presenteia um upgrade/status novo de graça.

### Efeito (em jogo, item equipado)
- Gatilho em [wave_manager.gd:1235](../../../scripts/systems/wave_manager.gd) (bloco pós-wave-cleared,
  junto dos grants de boas-vindas/pet/owned). Condição: `InventoryItems.is_equipped("amuleto_descoberta")
  and wave_number % 5 == 0` (waves 5, 10, 15, 20...). Roda **antes** de `_open_shop()`.
- Concede **1** upgrade/status que o player **ainda não tem** (count 0), no **nível 1**, grátis.
- Fonte do sorteio: `FREE_UPGRADE_POOL` (já completo: 5 status + 28 upgrades, incluindo pets,
  `spectral_arrow`, `adrenalina`).
- **Mutex (completo):** o filtro atual em `_grant_free_random_upgrade` está desatualizado (só trata
  `perfuracao↔ricochet`, `multi↔double`, `dash↔esquivando↔fenda`). Criar um helper compartilhado
  `_player_blocks_upgrade(player, id)` cobrindo **todos** os grupos:
  - Tipo-de-flecha: `perfuracao` / `ricochet_arrow` / `spectral_arrow` (mutuamente exclusivos)
  - Volley: `multi_arrow` / `double_arrows`
  - Mobilidade: `dash` / `esquivando` / `fenda` / `adrenalina`
  Refatorar `_grant_free_random_upgrade` para usar o mesmo helper (corrige o bug latente lá também).
- **Pets:** ids de aliado só entram no pool se o player estiver **abaixo do cap de pets distintos**
  (espelhar `wave_shop._distinct_pets_owned` / `_effective_pet_cap` — extrair helper ou recomputar
  no wave_manager). Se no cap, pets ficam fora do sorteio nesse round.
- **Carta:** reusa `_show_card_reward_popup(id, lvl, "HUD_AMULET_DISCOVERY_TITLE", name)` — mesma
  animação de boas-vindas. A arte da carta é a **do upgrade sorteado** (não do amuleto).
- **Caso "tem tudo":** se o pool filtrado ficar vazio, concede **4 gold** no lugar e mostra uma carta
  "+4 Gold" (título `HUD_AMULET_DISCOVERY_TITLE`, corpo de gold). Nunca desperdiça o gatilho.

### Desbloqueio (quest persistente, entre runs)
- Libera ao **comprar na loja (qualquer run, acumulado) os 5 status distintos E 15 upgrades distintos**.
- **Status (5):** `hp`, `damage`, `attack_speed`, `move_speed`, `armor` (= `STATUS_POOL` da loja direita).
- **Upgrade (28):** todo o resto de `_ALL_UPGRADE_IDS` (inclui `critical_chance`, `gold_magnet`,
  `perfuracao`, `multi_arrow`, `double_arrows`, elementais, aliados, mobilidade, flechas especiais,
  `life_steal`, `tiger_claws`).
- **Tracking (SkinLoadout, `settings.cfg [progress]`):**
  - Dois sets CSV: `distinct_status_bought`, `distinct_upgrade_bought` (ids já comprados alguma vez).
  - Dois contadores int: `distinct_status_bought_count`, `distinct_upgrade_bought_count` —
    incrementam **só quando um id novo** entra no set correspondente.
  - Helper `SkinLoadout.record_purchase(id)`: classifica o id (status vs upgrade via lista),
    adiciona ao set se novo e bumpa o contador.
  - Chamada no ponto de compra de upgrade/status em [wave_shop.gd](../../../scripts/ui/wave_shop.gd)
    (onde `player.apply_upgrade` é chamado após pagar). Pets contam como upgrade (são ids de upgrade).
- **Reqs no `ITEMS`:** quest com dois reqs — `distinct_status_bought_count >= 5` **e**
  `distinct_upgrade_bought_count >= 15`. O sistema de quest do `InventoryItems` já compara
  `SkinLoadout.get_stat(stat) >= value`, então os contadores encaixam direto.

### Entry no `ITEMS` (inventory_items.gd)
```gdscript
"amuleto_descoberta": {
    "name": "ITEM_AMULETO_DESCOBERTA_NAME",
    "desc": "ITEM_AMULETO_DESCOBERTA_DESC",
    "icon": "res://assets/Hud/itens/amuleto_descoberta.png",
    "effect": {"type": "amulet_discovery", "interval": 5, "gold_fallback": 4},
    "unlock": {"type": "quest", "reqs": [
        {"stat": &"distinct_status_bought_count", "value": 5, "label": "ITEM_REQ_AMULETO_STATUS"},
        {"stat": &"distinct_upgrade_bought_count", "value": 15, "label": "ITEM_REQ_AMULETO_UPGRADES"},
    ]},
},
```
O `effect` tipo `amulet_discovery` não tem `apply_to_player` (é gatilho de wave_manager, não start_status).
wave_manager lê via `InventoryItems.is_equipped(...)`.

---

## B. Item — Chamado da Matilha (`chamado_da_matilha`)

Item equipável. Faz pets aparecerem em **toda loja** a partir da wave 5, em vez de a cada 2 waves.

### Efeito
- Estado atual: pets abrem na wave 5 e depois a cada `ALIADO_SHOP_INTERVAL = 2` waves (5, 7, 9...).
  Lógica em [wave_shop.gd:2526](../../../scripts/ui/wave_shop.gd) (`_aliado_lock_remaining`).
- Com o item equipado: `_aliado_lock_remaining(w)` retorna **0 para todo `w >= ALIADO_SHOP_FIRST_WAVE`**
  (wave 5+), ignorando o intervalo. Mantém o gate da wave 5 e o pet grátis da wave 3 intactos.
- Checagem: `InventoryItems.is_equipped("chamado_da_matilha")` no topo do `_aliado_lock_remaining`
  (e onde mais decidir abrir slots de aliado, ex: `_roll_aliado_slots`).
- **Texto da carta/descrição:** deixar explícito "Pets à venda em toda loja a partir da wave 5".

### Desbloqueio (loja de pétalas — tipo `shop`)
- Entry no `CATALOG` de [loja_petalas.gd:15](../../../scripts/ui/loja_petalas.gd):
  `{"cat": "itens", "kind": "item", "id": "chamado_da_matilha", "price": 200}`.
- `unlock: {"type": "shop"}` no `ITEMS` (já suportado: `is_purchased`/`mark_purchased`).

### Entry no `ITEMS`
```gdscript
"chamado_da_matilha": {
    "name": "ITEM_CHAMADO_MATILHA_NAME",
    "desc": "ITEM_CHAMADO_MATILHA_DESC",
    "icon": "res://assets/Hud/itens/chamado_da_matilha.png",
    "effect": {"type": "pets_every_shop"},
    "unlock": {"type": "shop"},
},
```
wave_shop lê o efeito via `InventoryItems.is_equipped(...)` (flag, sem start_status).

---

## C. Leaderboard — filtrar "minhas runs" pelo nick

100% client-side, sem mudança no backend (cada entry do JSON já tem `nickname`).

- Tela: [leaderboard.gd](../../../scripts/ui/leaderboard.gd) + [leaderboard.tscn](../../../scenes/ui/leaderboard.tscn).
- Adicionar toggle "Minhas runs" na `FilterRow` (irmão do `VersionFilter`). Botão `CheckButton` ou
  `Button` toggle, com label i18n `LEADERBOARD_MY_RUNS`.
- Estado: `var _filter_player_only: bool = false`. Ao alternar, re-render (não refaz fetch).
- Nick local: `BirthdayEvent.load_current_nickname()` (static, já existe).
- Filtro aplicado em `_render_waves()` e `_render_time21()` **antes** de cortar em `_MAX_ROWS`:
  se `_filter_player_only`, `rows = rows.filter(func(r): return str(r.get("nickname","")) == nick)`.
- Compõe com o filtro de versão existente (aplicar os dois).
- Edge: nick vazio → toggle desabilitado ou mostra lista vazia com mensagem (`StatusLabel`).

---

## D. Morte — salvar GIF em vez de PNGs soltos

Hoje "Gravar em disco" salva `frame_###.png` individuais ([death_replay.gd:179](../../../scripts/ui/death_replay.gd)).
Trocar para gerar **um `.gif` animado**. Godot não tem encoder de GIF → escrever um.

- Novo arquivo `scripts/systems/gif_encoder.gd` — `class_name GifEncoder` (RefCounted, métodos static):
  - `static func encode_to_file(frames: Array, delay_cs: int, path: String) -> bool`
  - Frames são `Image` (480×270, ~74 frames, 20fps → `delay_cs ≈ 5` centésimos = ~3cs por frame a 20fps... usar 5 (=12.5fps visível) ou 3 (≈33ms). Definir no plano).
  - **Quantização:** paleta global única de ≤256 cores via median-cut sobre amostra dos frames.
    Mapear pixels pra índice (nearest na paleta). Pixel-art escuro → paleta global aceitável.
  - **GIF89a:** header, Logical Screen Descriptor, Global Color Table, Netscape loop extension
    (loop infinito), por frame: Graphic Control Extension (delay) + Image Descriptor + dados
    LZW-comprimidos. Trailer `0x3B`.
  - **LZW:** implementação variável-bit padrão GIF (clear code, end code, dicionário até 4096).
- Em `death_replay.gd`: trocar o loop de `save_png` por uma chamada a `GifEncoder.encode_to_file(
  frames, delay, "<dir>/replay_<timestamp>.gif")`. Manter o resto do fluxo (botão "Gravar", pasta de saída).
- Frames já estão em memória como `Array[Image]` (`stats_replay_frames`), capturados em
  [player.gd:2813](../../../scripts/player/player.gd) (`_capture_replay_frame`). Sem mudança na captura.
- **Risco:** é o item mais pesado (quantização + LZW). Se o encoder ficar problemático, fallback:
  manter PNGs e/ou oferecer WebP animado. (Usuário escolheu GIF de verdade.)

---

## Assets
- Decodificar `.aseprite` → PNG (pipeline aseprite já validado no projeto):
  - `assets/Hud/itens/Amuleto da descoberta.aseprite` → `assets/Hud/itens/amuleto_descoberta.png`
  - `assets/Hud/itens/Chamado da Matilha.aseprite` → `assets/Hud/itens/chamado_da_matilha.png`
- ⚠️ Commitar os PNGs antes do deploy (asset untracked referenciado por `res://` quebra build
  exportado, não o editor) — ver convenção de "commitar assets antes de deploy".

## i18n (assets/i18n/translations.csv — pt_BR + en)
- `ITEM_AMULETO_DESCOBERTA_NAME` / `_DESC`
- `ITEM_REQ_AMULETO_STATUS` / `ITEM_REQ_AMULETO_UPGRADES`
- `HUD_AMULET_DISCOVERY_TITLE`
- `ITEM_CHAMADO_MATILHA_NAME` / `_DESC` (desc menciona "toda loja a partir da wave 5")
- `LEADERBOARD_MY_RUNS`
- (GIF/morte: revisar se algum texto de UI muda no botão "Gravar".)

## Checklist de integração (itens novos)
- `ITEMS` entry (icon + effect + unlock) — ambos.
- i18n keys — todas acima.
- `DEV_UNLOCK_ALL_ITEMS` já libera ambos em debug build.
- Matilha: preço no `CATALOG` da loja de pétalas.
- Conferir se itens equipados aparecem no build modal/leaderboard (exibição) — checar no plano.

## Arquivos tocados (estimativa)
- `scripts/systems/inventory_items.gd` — 2 entries + (Amuleto) nenhum apply_to_player novo.
- `scripts/systems/wave_manager.gd` — `_grant_amulet_discovery()` + helper de mutex + gatilho %5.
- `scripts/ui/wave_shop.gd` — `record_purchase` no ponto de compra + Matilha no `_aliado_lock_remaining`.
- `scripts/systems/skin_loadout.gd` — sets + contadores de compra distinta + `record_purchase`.
- `scripts/ui/loja_petalas.gd` — preço do Matilha.
- `scripts/ui/leaderboard.gd` + `scenes/ui/leaderboard.tscn` — toggle "minhas runs".
- `scripts/ui/death_replay.gd` — chamar GifEncoder.
- `scripts/systems/gif_encoder.gd` — NOVO.
- `assets/Hud/itens/*.png` — 2 ícones decodificados.
- `assets/i18n/translations.csv` — keys novas.

## Fora de escopo
- Bump de versão (só no deploy).
- Loja meta de pétalas para itens tipo `shop` já existe (Matilha entra nela).
