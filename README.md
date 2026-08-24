# QuickCenter — Quick Actions & Control Center Patch for KOReader

> **QuickCenter: a fast, configurable and gesture-friendly shortcut hub — Quick Actions + Control Center in a single drop-in patch.**

> **Author**: [Arin-Chin](https://github.com/Arin-Chin) | **License**: AGPL-3.0 | **Compatible**: KOReader (LuaJIT)

---

## 📖 Overview

QuickCenter is a standalone KOReader **patch** (a single `.lua` file placed in `koreader/patches/`) that combines two core experiences:

| Feature | Description |
| :--- | :--- |
| ⚡ **Quick Actions** | Custom actions — record, edit and manage the actions you use most; run them from the shortcut menu or via gesture |
| 🎛️ **Control Center** | A one-tap action panel plus everything about its buttons: layout, shapes, sliders, filters and gesture behaviors |

<img src="pictures/1.QCpreview.png" alt="QuickCenter preview" width="400" />

> 💡 **Inspiration**:
> - [kopatches](https://github.com/gytwo/kopatches)
> - [quickui.koplugin](https://github.com/gytwo/quickui.koplugin)
> - [simpleui.koplugin](https://github.com/doctorhetfield-cmd/simpleui.koplugin)
> - [KOReader.patches](https://github.com/joshuacant/KOReader.patches)

---

## 🚀 Core Features

### 1. ⚡ Quick Actions

Create, edit and manage the actions you use most, then run them from the shortcut menu or via a bound gesture.

| Feature | Description |
| :--- | :--- |
| **Custom Actions** | 5 types: folder, collection, plugin, system action (Dispatcher), **recorded menu action** |
| **Menu Recording** | Record any menu path as a reusable quick action; its interface (view) can be customized later when editing |
| **Edit Quick Actions** | Add / rename / delete actions; existing custom actions grouped under **Existing Actions (已有操作)**; mark each as a shortcut via **Add to Shortcut Menu** |
| **Shortcut Menu** | Manage added shortcuts (check/uncheck to remove); a gesture can open the runnable list without a title bar |

<table>
  <tr>
    <td><img src="pictures/02-quick-actions-menu.png" alt="Quick Actions menu" width="400" /></td>
    <td><img src="pictures/03-edit-quick-actions.png" alt="Edit Quick Actions" width="400" /></td>
  </tr>
</table>

<table>
  <tr>
    <td><img src="pictures/04-shortcut-menu.png" alt="Shortcut menu" width="400" /></td>
    <td><img src="pictures/05-shortcut-menu-gesture.png" alt="Gesture-launched shortcut menu" width="400" /></td>
  </tr>
</table>

### 2. 🎛️ Control Center

A customizable action panel injected as the first tab of the top menu bar (Filemanager & Reader), plus everything about its buttons.

| Setting | Options / Description |
| :--- | :--- |
| **Built-in Actions** | Wi-Fi, night mode, rotate, screenshot, continue reading, search, restart, quit, power, HTTP server, font list, reading stats, etc. |
| **Arrange (排列按钮)** | Reorder panel buttons with ▲ / ▼ in a QuickCenter-style box (gray title bar, back navigation) |
| **Add Buttons (编辑按钮)** | Add / remove panel buttons with checkboxes (QuickCenter-style box with back navigation) |
| **Button Layout** | Auto layout (flow by panel width) or a custom fixed grid (**rows × buttons per row**) |
| **Interface Filter** | Show/hide actions per context (Filemanager / Reader / Common) |
| **Gesture Behaviors** | Long-press a button to edit · long-press the panel to open settings |
| **Button Shape** | Round / Rounded Square / Bare |
| **Button Background** | Transparent / Solid / Light Gray |
| **Slider Style** | Line / Segmented buttons |
| **Button Size** | 60% ~ 150% (step 5%) |
| **Label Size** | 50% ~ 200% (step 10%) |
| **Show Labels** | Toggle |
| **Frontlight / Warmth Sliders** | With value display and Min / Max shortcuts |

<img src="pictures/06-control-center-panel.png" alt="Control Center panel" width="400" />

<img src="pictures/07-control-center-menu.png" alt="Control Center menu" width="400" />

### 3. ⚙️ Settings

`Tools → QuickCenter` opens the settings menu:

| Feature | Description |
| :--- | :--- |
| **Enable QuickCenter** | Enable / disable the panel tab (restart required) |
| **Config Management** | Named presets: **Save Config** · **Edit Config** · **Reset Config** |
| **Appearance** | Panel icon · System icon replace · UI font switch |

#### Config Management

| Function | Description |
| :--- | :--- |
| **Save Config** | Save the current configuration as a **named preset** |
| **Edit Config** | Browse saved presets: **long-press to overwrite** with current settings, or open the submenu for update / rename / delete |
| **Reset Config** | Restore factory defaults |

> Presets can be saved, overwritten and restored at any time — convenient for switching between reading / night / travel setups.

<img src="pictures/08-settings-menu.png" alt="Settings menu" width="400" />

<img src="pictures/09-config-management.png" alt="Config management" width="400" />

#### 🖼️ Icon Picker

| Source | Description |
| :--- | :--- |
| **Nerd Font** | Auto-scanned glyphs from the symbols font with codepoint search |
| **SVG / PNG Files** | Browse `koreader/icons/` and built-in icon directories, with name filter |
| **System Icon Replace** | Replace KOReader's built-in icons (grid preview, batch apply / reset) |

#### 🔤 UI Font Switcher

Replace KOReader's UI font (Regular / Bold / Mono) from installed fonts, with a live preview and one-tap reset.

---

## 🔧 Gesture / Shortcut Support

Bind any gesture in KOReader's gesture manager to these Dispatcher actions (the on-screen title is localized to your UI language):

| Action | Dispatcher Action Key | Description |
| :--- | :--- | :--- |
| Control Center Panel | `quick_actions_panel` | Open the Control Center panel tab |
| QuickCenter Settings | `qa_settings_action` | Open QuickCenter settings |
| Shortcut Menu | `qa_shortcuts_menu` | Open the runnable shortcut menu (no title bar) |

> Gesture bindings survive restarts — the patch flushes settings on quit, so bindings made in a session are persisted.

---

## 📦 Installation

1. Copy `2-quickcenter.lua` to KOReader's `patches` folder: `koreader/patches/`
2. **Remove any older `2-quickactions.lua`** from `patches/` (they would conflict)
3. *(Optional)* Copy `quickcenter.lua` to `koreader/settings/quickcenter.lua` — it contains ready-made settings (custom actions, button overrides, …). If omitted, the file is auto-generated with defaults on first run
4. Restart KOReader

> **Upgrade from `2-quickactions.lua`**: rename `koreader/settings/quickactions.lua` → `quickcenter.lua` to keep all your existing custom actions and settings.

**Uninstall**: delete the patch file; optionally delete `koreader/settings/quickcenter.lua`.

---

## 📁 File Structure

```
QuickCenter/
├── 2-quickcenter.lua   # The whole patch (single file, drop-in)
├── quickcenter.lua     # Settings file (optional, place in koreader/settings/)
├── README.md           # Documentation (English)
├── README.zh_CN.md     # Documentation (Simplified Chinese)
└── pictures/           # Screenshots
```

| File | Purpose |
| :--- | :--- |
| `2-quickcenter.lua` | Quick Actions + Control Center + config management + icon/font tools |
| `quickcenter.lua` | Ready-made settings file — copy to `koreader/settings/quickcenter.lua` |
| `README.md` | Documentation (English) |
| `README.zh_CN.md` | Documentation (Simplified Chinese) |

---

## ⚙️ Configuration

All settings are stored in `koreader/settings/quickcenter.lua` (auto-generated on first run).

Key configuration groups:

| Group | Keys | Description |
| :--- | :--- | :--- |
| Panel | `qa_enabled`, `qa_slots`, `qa_*` | Panel enable, button order, shape, size, labels, sliders |
| Layout | `qa_layout_*` | Custom button grid (enabled / rows / per-row) |
| Shortcuts | `qa_shortcuts` | Actions added to the shortcut menu |
| Configs | `saved_configs` | Named configuration presets |
| Appearance | `qa_tab_icon`, `qa_icon_overrides`, `ui_font_overrides` | Panel icon, system icon replacement, UI fonts |

---

## 🔌 Compatibility & Dependencies

| Item | Requirement |
| :--- | :--- |
| **KOReader** | Any recent build (LuaJIT); verified on v2026.07 |
| **Device** | Frontlight / warmth sliders require device support |
| **Icons** | Nerd Font feature requires a Nerd Font symbols face |

---

## 📝 Changelog

### 2026-08-24 — Bugfix: icon picker cache regression

Fixed a crash introduced by the refactor: `showIconPicker`'s cache was written as an array table while reads still used named fields, so reopening the icon picker left `icons_list` nil → `attempt to get length of local 'display_list' (a nil value)`.

- Cache restored to a named-field table (write/read consistent); read side now validates integrity (size + `icons_list` present)
- `getDisplayList` guarded with `icons_list or {}` so the same class of regression can never crash again
- View-picker dialog (`showViewPickerDialog`) now sets `tap_close_callback`: closing via outside tap / hardware back rebuilds the edit dialog, preventing state loss and UI confusion after backing out

### 2026-08-24 — Bugfix: view picker never closed + plugin back crash

- `showViewPickerDialog`: `local view_dialog` was declared after the button callbacks, so `UIManager:close(view_dialog)` inside the closures resolved to the *global* nil — the dialog was never removed from the window stack and resurfaced after saving. Fixed with a forward declaration.
- Plugin/patch submenu: `showPluginSubMenu` / `showPluginList` referenced each other without forward declarations, so “Back” called a global nil and crashed. Forward declarations added.

### 2026-08-24 — Bugfix: Dispatcher cache crash

Fixed a crash when picking “System Actions” in New Action: `getDispatcherSettingsList` cached on the function itself (`getDispatcherSettingsList._cache`), but LuaJIT cannot index a function value → `attempt to index upvalue ... (a function value)`. Switched to a dedicated local variable cache.

---

## 📝 Changelog (refactor)

### 2026-08-24 — Deep refactor & optimization

Single-file patch restructured for smaller size, higher robustness and smoother e-ink performance. **No functional or config-format changes** — existing `koreader/settings/quickcenter.lua` files keep working as-is.

- **Size** — `2-quickcenter.lua` cut from ~314 KB / 8189 lines to ~260 KB / 5739 lines (−17%): removed dead code (unused requires, `_batch_depth`, unused `PluginScan.exists`), merged duplicated implementations (action executors, menu font patches, action-list builders, restart dialogs), extracted shared helpers (`menuSubTable`, `findMenuItem`, `askRestart`, `moveSlot`, `showViewPickerDialog`, …)
- **Performance** — Dispatcher settings table (`settingsList`) now parsed once and cached instead of re-scanned per action (O(n²) → O(n)); Nerd Font glyph scan looks up the symbols face once instead of per codepoint (~900 → 1 lookups); slider button height measured lazily instead of per panel build
- **Robustness** — fixed 3 latent bugs: `clearFileIconsCache` cleared the wrong (global) cache table, `TOUCHMENU_STUB` was referenced before its declaration (resolved to global nil), and `replayPath` / `_stopPicking` / `injectPanelTab` were called from closures bound before their `local` declarations; action execution is now wrapped in `pcall` so a failing action can never crash KOReader
- **Maintainability** — top-level locals reduced from 202 to 195 (safely under Lua's 200-slot limit); naming unified, deep nesting simplified, key logic documented in Chinese comments

---

## 📄 License

This project is licensed under the **GNU Affero General Public License v3.0 (AGPL-3.0)**.

See: [https://www.gnu.org/licenses/agpl-3.0.en.html](https://www.gnu.org/licenses/agpl-3.0.en.html)
