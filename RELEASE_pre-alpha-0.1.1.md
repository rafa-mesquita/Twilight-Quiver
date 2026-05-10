# Twilight Quiver — pre-alpha-0.1.1

**Primeira minor release.** Foco em internacionalização, áudio configurável, preview do personagem na loja com skins equipadas, e nova skin Gingerale.

---

## ✨ Destaques

### Internacionalização (4 idiomas)
- Português (pt_BR), Inglês (en), Espanhol (es) e Francês (fr).
- Fonte única em [`assets/i18n/translations.csv`](assets/i18n/translations.csv) — Godot gera os `.translation` automaticamente.
- Seletor de idioma no menu de **Configurações** (`CustomSelect`).
- `LocaleManager` ([`scripts/systems/locale_manager.gd`](scripts/systems/locale_manager.gd)) persiste a escolha em `user://settings.cfg` e aplica via `TranslationServer` no startup.
- Convenção de chaves: `UPPER_SNAKE_CASE` (ex: `SHOP_HEADER_STRUCTURES`, `PLAYER_QUEST_GINGERALE`).

### Áudio configurável
- Buses **Master / Music / SFX** em [`default_bus_layout.tres`](default_bus_layout.tres).
- Sliders independentes por bus no menu de **Configurações**, com persistência em `user://settings.cfg`.

### Preview animado do personagem na loja
- Estrutura layered em camadas: **Border (back) → Cape → Head → Shirt → Hair → Border (front)**.
- Reflete o loadout equipado em tempo real. Slot vazio (cape/hair/shirt removíveis) cai automaticamente pro `default.png`.
- Sprites em [`assets/Hud/playerHud/`](assets/Hud/playerHud/) — adicionar nova skin = soltar PNG `<nome_lowercase>.png` em cada subpasta.
- Border tem 2 rows (back + front) que sandwicham os layers do personagem.
- Lógica em [`scripts/ui/shop_player_face.gd`](scripts/ui/shop_player_face.gd).

### Skin Gingerale 🍊
- Nova skin completa: cape, hair, legs, quiver, shirt, bow + variantes pra HUD da loja.
- Quest de unlock: **3000 inimigos abatidos no total** (acumulativo entre runs).

### Cards do shop
- Arte nova pra **Fire Arrow**, **Life Steal**, **Coin Master**, **Perfuração**, **Ricochete** e **Dash** (deslizando).
- Fonte das descrições aumentada (22 → 28) pra leitura mais confortável.
- Cores de título/desc ajustadas por upgrade pra contrastar com a arte.

---

## 🐛 Fixes

- **ESC durante animação de morte** não fecha mais o jogo. Atalho dev `get_tree().quit()` removido de `player.gd`; ESC durante a tela de morte é ignorado (a tela já cobre tudo), e em gameplay normal continua abrindo o pause.
- **Skin scan** continua funcionando em build exportado (já estava em 0.0.3, mantido — aceita `.png` e `.png.import` com dedupe).

---

## 🔧 Dev / Polimento

- **Botões dev removidos da loja** ("EDIT LAYOUT" e "PRINT VALUES" no canto inferior direito). ~135 linhas de código de editor de layout removidas de [`wave_shop.gd`](scripts/ui/wave_shop.gd).
- **Debug build libera todas as skins** automaticamente (`OS.is_debug_build()` em `is_unlocked()`) — facilita testar visuais sem grindar quests. Release build mantém o gate normal.
- `.gitignore` atualizado: `/exports/`, `capra_jogo.png`.
- Pequenos ajustes em allies (`capivara_joe`, `capivara_mushroom`, `leno`), enemies (`stone_cube`, `mage`, `monkey`, `insect`, `woodwarden`), pickups (`gold`, `heart`), `arrow.gd`, `wave_manager.gd`.

---

## 📦 Como gerar build

1. Confirme que `application/config/version` em [`project.godot`](project.godot) é `pre-alpha-0.1.1`.
2. Abra o projeto no Godot 4.6, **Project → Export…**, e gere os 3 presets (Mac DMG, Windows EXE, Linux x86_64) em `exports/pre-alpha-0.1.1/`.
3. Crie a tag git: `git tag -a pre-alpha-0.1.1 -m "pre-alpha-0.1.1"` e `git push origin pre-alpha-0.1.1`.

---

🤖 Generated with [Claude Code](https://claude.com/claude-code)
