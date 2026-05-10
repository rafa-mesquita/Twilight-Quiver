# Twilight Quiver — Notas pro Claude

## Deploy / release

**Sempre suba a versão** em `application/config/version` no [project.godot](project.godot) ao fazer deploy ou build de release. Formato atual: `pre-alpha-X.Y.Z`. A versão é exibida no canto inferior direito de todas as telas e enviada junto dos scores pro leaderboard, então jogadores precisam rodar versão consistente entre cliente e backend.

## Internacionalização (i18n)

O projeto é bilingual: **pt_BR** (default) e **en**. Todo texto visível ao jogador passa pelo TranslationServer.

**Toda string nova de UI precisa virar uma key em [assets/i18n/translations.csv](assets/i18n/translations.csv).** Não bote texto hardcoded em pt_BR direto numa cena ou label.

### Convenções

- **Keys em UPPER_SNAKE_CASE** com prefixo por área:
  - `COMMON_*` — reusáveis (Voltar, Salvar, Carregando, etc)
  - `MENU_*` — main menu
  - `SETTINGS_*` — settings menu
  - `PLAYER_*` — tela Player (skin select, slots, progresso, quests)
  - `LEADERBOARD_*` — tela leaderboard
  - `HUD_*` — HUD in-game (death screen, pause, unlock, indicators)
  - `SHOP_*` — wave shop (upgrades, descrições, cards)
  - `NICKNAME_*` — prompt de nickname
- **CSV format:** `keys,pt_BR,en`. Vírgulas dentro de strings → escape com aspas duplas.

### Como adicionar texto novo

1. **Em `.tscn`:** use a key direto no `text =`. Godot auto-traduz Control nodes.
   ```
   text = "MENU_NEW_FEATURE"
   ```

2. **Em `.gd` com atribuição dinâmica:** use `tr()` explícito. Atribuição direta NÃO auto-traduz.
   ```gdscript
   label.text = tr("HUD_MY_MESSAGE")
   # Com placeholders:
   label.text = tr("HUD_DEATH_SURVIVAL") % wave_num
   ```

3. **Adicione a key no CSV** com tradução em pt_BR (texto original) e en (tradução). Mesmo se o en for igual ao pt_BR (ex: nomes próprios, "SCORE"), preencha as duas colunas — manter o esquema consistente.

### Quando NÃO traduzir

- Identifiers internos (slot names `&"body"`, stat keys `"max_wave_reached"`, anim names `"idle"`)
- Display names de skin parts (`"Default"`, `"Red_Velvet"`) — são identificadores, não texto exibido livre
- Resource paths (`res://...`)
- Logs/prints/debug (devs leem em inglês mesmo)
- Nicknames digitados pelo jogador
- Nomes de input actions

### Quest labels e configs com texto

Em dicts como `SKIN_QUESTS` em [skin_loadout.gd](scripts/systems/skin_loadout.gd), o campo `label` deve guardar a **key**, não o texto. Quem renderiza chama `tr(label_key)`.

```gdscript
const SKIN_QUESTS = {
	"Red_Velvet": {
		"type": "wave_reached",
		"value": 10,
		"label": "PLAYER_QUEST_RED_VELVET",   # KEY, não texto
		"hidden": false,
	},
}
```

### Auto-translate em Control

Godot 4 traduz automaticamente o `text` de Controls (Buttons, Labels, etc) via `auto_translate_mode = INHERIT` (default). Não precisa fazer nada extra em `.tscn`.

Em **scripts** que setam `.text` via código, sempre `tr()`. Se atribuir uma string já-traduzida ao `.text`, ela NÃO é re-traduzida quando o locale muda.

### Mudança de locale em runtime

`LocaleManager.apply_locale(code)` em [scripts/systems/locale_manager.gd](scripts/systems/locale_manager.gd) chama `TranslationServer.set_locale()`. Aplicado no startup pelo `GameState._ready()` lendo de `user://settings.cfg [locale] code`. Settings menu tem dropdown que altera + persiste.

### Adicionando novo idioma

1. **Nova coluna no CSV** (`assets/i18n/translations.csv`) — ex: `keys,pt_BR,en,es`. Preenche todas as keys.
2. **Reabre o editor** — Godot importa o CSV e gera `translations.<locale>.translation` ao lado.
3. **Adiciona o path em `project.godot`** na seção `[internationalization]`:
   ```
   locale/translations=PackedStringArray(
	 "res://assets/i18n/translations.pt_BR.translation",
	 "res://assets/i18n/translations.en.translation",
     "res://assets/i18n/translations.es.translation"
   )
   ```
   ⚠ Aponta pros `.translation` (não pro `.csv`). O runtime carrega esses arquivos compilados; CSV direto é ignorado.
4. **Adiciona o idioma em `LocaleManager.SUPPORTED_LOCALES`** ([scripts/systems/locale_manager.gd](scripts/systems/locale_manager.gd)):
   ```gdscript
   {"code": "es", "label": "Español"}
   ```
5. Pronto — aparece automático no dropdown de Settings.
