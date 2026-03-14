# Quickshell II — Search System Architecture

> Context document for AI agents. Read this before modifying any search-related code.

## Overview

This is an **Illogical Impulse (ii)** Quickshell configuration — a Wayland shell written in QML.
The search system powers the **overview search bar** (opened via keyboard shortcut) and the **Waffle start menu** search. Both share the same `LauncherSearch` singleton service.

## Key Principle: Prefixes

Every search mode is activated by a **single-character prefix** typed at the start of the query.
Prefixes are **user-configurable** at runtime via `~/.config/illogical-impulse/config.json` — never hardcode prefix characters. Always read them from `Config.options.search.prefix.*`.

### Default prefixes (user may have changed these)

| Config key       | Default | Mode            | Backend                 |
|------------------|---------|-----------------|-------------------------|
| `action`         | `/`     | Run actions     | Built-in + user scripts |
| `app`            | `>`     | App search      | DesktopEntries fuzzy    |
| `clipboard`      | `;`     | Clipboard       | Cliphist service        |
| `emojis`         | `:`     | Emoji search    | Emojis service          |
| `math`           | `=`     | Calculator      | `qalc` process          |
| `shellCommand`   | `$`     | Shell command   | `bash` process          |
| `webSearch`      | `?`     | Web search      | URL open                |
| `fileSearch`     | `,`     | File search     | `fd` process            |

**Important**: The user has remapped some of these (e.g. `?` for file search). Always reference `Config.options.search.prefix.<key>`, never literal characters.

## File Map

### Services (singletons, stateful logic)

| File | Role |
|------|------|
| `services/LauncherSearch.qml` | **Core search engine**. Owns `query`, `fileResults`, `results` binding. Spawns `fd`/`qalc` subprocesses. All search logic lives here. |
| `services/AppSearch.qml` | App fuzzy search via `DesktopEntries`. Called by LauncherSearch. |
| `services/LauncherApps.qml` | Pin/unpin apps in launcher. Not search logic. |
| `services/SearchRegistry.qml` | **Settings page search only** — indexes QML config files for the settings UI. Unrelated to overview search. |

### UI — II Overview panel

| File | Role |
|------|------|
| `modules/ii/overview/Overview.qml` | Overlay window, focus grab, animation. |
| `modules/ii/overview/SearchWidget.qml` | Results container. 200ms debounce, 15-result display limit. Connects `LauncherSearch.results` → `ScriptModel` → `ListView`. |
| `modules/ii/overview/SearchBar.qml` | Text input + prefix icon. Has `SearchPrefixType` enum for icon/shape switching. |
| `modules/ii/overview/SearchItem.qml` | Individual result row. Handles image previews, blur, actions, highlight. |

### UI — Waffle start menu

| File | Role |
|------|------|
| `modules/waffle/startMenu/StartMenuContent.qml` | Search input routing. |
| `modules/waffle/startMenu/StartMenuContext.qml` | Category management. |
| `modules/waffle/startMenu/searchPage/SearchResults.qml` | Categorized result display (max 4 per category, 20 total). |

### Models & Utilities

| File | Role |
|------|------|
| `modules/common/models/LauncherSearchResult.qml` | Result data model. Props: `type`, `name`, `iconName`, `iconType`, `verb`, `execute`, `actions`, `blurImage`, `category`. Enums: `IconType {Material, Text, System, None}`, `FontType {Normal, Monospace}`. |
| `modules/common/functions/StringUtils.qml` | `cleanPrefix(str, prefix)`, `cleanOnePrefix(str, prefixes[])`, `escapeHtml()`, etc. |
| `modules/common/functions/fuzzysort.js` | Fuzzy matching algorithm used by AppSearch. |
| `modules/common/Config.qml` | All user settings. Search config at `Config.options.search.*`. |

### Configuration

| File | Role |
|------|------|
| `modules/common/Config.qml` | Default values for all settings including search prefixes, `fileSearchDirectory` (default `/home`), `blurFileSearchResultPreviews`, `nonAppResultDelay`, etc. |
| `~/.config/illogical-impulse/config.json` | **Runtime user overrides**. This is where the user's actual prefix mappings live. This file is NOT in the quickshell/ii tree. |

## How Search Works — Data Flow

```
User types in SearchBar
    ↓
SearchBar.onTextChanged → LauncherSearch.query = text
    ↓
LauncherSearch.onQueryChanged:
    ├─ If fileSearch prefix → strip prefix, call fileProc.searchFiles(expr)
    ├─ Else → clear fileResults
    └─ Always → restart nonAppResultsTimer (for math/qalc)
    ↓
LauncherSearch.results (reactive property binding):
    ├─ Empty query → return []
    ├─ Clipboard prefix → early return with Cliphist results
    ├─ Emoji prefix → early return with Emojis results 
    ├─ FileSearch prefix → early return with root.fileResults mapped to result objects
    └─ Default → build math + app + command + web + action results, prioritize by prefix
    ↓
SearchWidget receives results via Connections { target: LauncherSearch }
    ↓
resultModel.values = LauncherSearch.results.slice(0, 15)
    ↓
ListView renders SearchItem delegates
```

## File Search — Detailed Flow

1. **Trigger**: `onQueryChanged` detects file search prefix, strips it, calls `fileProc.searchFiles(expr)`
2. **Guard**: `expr.length < 2` → skip (prevents searching with 0-1 chars)
3. **Process**: Spawns `fd --max-results 50 <expr> <fileSearchDirectory>`
4. **Collection**: `StdioCollector.onStreamFinished` splits stdout by newlines, filters empties → sets `root.fileResults`
5. **Display**: The `results` binding detects file search prefix, maps `root.fileResults` into `LauncherSearchResult` objects with type "File", verb "Open", icon "file_open"
6. **Execution**: `xdg-open <filepath>` when clicked

### File search is a "special case" section
Like clipboard and emoji, file search does an **early return** from the `results` binding. When active, no app/math/command/web results appear — only files.

### Dependencies
- **`fd` (fd-find)**: Must be installed. On Fedora: `sudo dnf install fd-find`. Binary is at `/usr/bin/fd`.
- **`qalc`**: For math. Separate concern.

## SearchBar Icon System

`SearchBar.qml` has a `SearchPrefixType` enum that maps prefix → icon + shape:

```
enum SearchPrefixType { Action, App, Clipboard, Emojis, Math, ShellCommand, WebSearch, FileSearch, DefaultSearch }
```

Each type gets a `MaterialShape.Shape.*` and a Material icon string. FileSearch uses `Shape.Pill` and icon `"file_open"`.

**If you add a new prefix type**, update:
1. The enum in `SearchBar.qml`
2. The `searchPrefixType` detection property
3. Both `switch` blocks (shape + icon text)
4. The `cleanOnePrefix` call in `SearchWidget.qml` delegate's `query` prop
5. The `ensurePrefix` array in `LauncherSearch.qml`

## Common Pitfalls

### 1. No side effects in property bindings
QML property bindings (like `property list<var> results: { ... }`) must be **pure**. Writing to other properties (e.g., `root.fileResults = []`) inside a binding creates binding loops and breaks reactivity. All side effects go in `onQueryChanged` or signal handlers.

### 2. StdioCollector `text` access
Use bare `text` in `onStreamFinished`, not `this.text`. The `this` context is unreliable in Qt6 QML signal handlers.

### 3. Process spawning
`Process` spawns commands **directly** (no shell). Shell aliases don't work. The binary must be in PATH or use an absolute path. If you need shell features (pipes, redirects), wrap in `["bash", "-c", "..."]`.

### 4. Prefix detection ordering
In the `results` binding, prefix checks use `if/else if` chains. More specific prefixes should come first if there's any ambiguity. Currently clipboard → emoji → fileSearch → (general flow).

### 5. User config vs defaults
`Config.qml` defines defaults. `~/.config/illogical-impulse/config.json` has user overrides. Always access via `Config.options.search.*` which merges both.

## Adding a New Search Mode

1. Add a prefix property in `Config.qml` under `search.prefix`
2. Add an enum value in `SearchBar.SearchPrefixType`
3. Add detection in `SearchBar.searchPrefixType` property
4. Add shape + icon in both `switch` blocks in `SearchBar.qml`
5. Add the prefix to `cleanOnePrefix` array in `SearchWidget.qml`
6. Add the prefix to `ensurePrefix` array in `LauncherSearch.qml`
7. In `LauncherSearch.results`: add an `else if` branch for early return (if exclusive mode) or add to the general flow section
8. If async (subprocess), add a Process + handler in `LauncherSearch.qml`, trigger from `onQueryChanged`

---

# II Panel — Features & Architecture

> Extended context documenting panel services, bar widgets, and settings added during AI-assisted sessions.

## Key Singletons & Services

| Singleton | File | Notes |
|-----------|------|-------|
| `MprisController` | `services/MprisController.qml` | Tracks active MPRIS player. `activePlayer` → current player; `players` → all. Each `MprisPlayer` has `.desktopEntry` (lowercase app name e.g. `"spotify"`, `"firefox"`), `.trackTitle`, `.trackArtist`, `.trackArtUrl`, `.isPlaying`, `.position`, `.length`, `.togglePlaying()`, `.previous()`, `.next()` |
| `HyprlandData` | `services/HyprlandData.qml` | Imported via `qs.services`. `windowList` → list of Hyprland client objects with `.class`, `.initialClass`, `.address`. Uses `import Quickshell.Wayland` for `ToplevelManager` internally. |
| `Persistent` | `services/Persistent.qml` | JSON state persistence. `Persistent.states.*` for runtime state. `Persistent.states.idle.inhibit`, `.sessionId`. `Persistent.states.media.popupRect`. |
| `GlobalStates` | `services/GlobalStates.qml` | Global boolean toggles. `GlobalStates.mediaControlsOpen` — toggled to show/hide the media controls popup. |
| `LyricsService` | `services/LyricsService.qml` | `hasSyncedLines` (bool), `initiliazeLyrics()`. |
| `ToplevelManager` | From `import Quickshell.Wayland` | Wayland toplevel manager. `ToplevelManager.toplevels.values` → list; each has `.appId` and `.activate()`. |
| `Hyprland` | From `import Quickshell.Hyprland` | `Hyprland.dispatch('focuswindow address:0x...')` to focus a window by address. |

## Config System

- **`modules/common/Config.qml`**: All default settings, under `Config.options.*`
- Runtime user overrides: `~/.config/illogical-impulse/config.json`
- Adding a new config block example (as done for idle):

```qml
property JsonObject idle: JsonObject {
    property bool keepAwakeOnStartup: true
}
```

## Idle / Keep-Awake System

**`services/Idle.qml`** — Singleton keep-awake service via Wayland `IdleInhibitor`.

Key logic: On `Persistent.onReadyChanged`, a `restoreTimer` fires:
- If `Persistent.states.idle.sessionId` matches current Hyprland instance signature → restore saved `inhibit` state.
- Else (new session) → read `Config.options.idle.keepAwakeOnStartup` (default `true`) and apply it.

**Settings UI**: `modules/settings/GeneralConfig.qml` — added a "Idle" `ContentSection` with a `ConfigSwitch` bound to `Config.options.idle.keepAwakeOnStartup`.

## Media Controls Popup Structure

**`modules/ii/mediaControls/MediaControls.qml`** — The floating popup window (`PanelWindow`).
- Opens when `GlobalStates.mediaControlsOpen === true`.
- Position is anchored based on `Persistent.states.media.popupRect` (set when bar widget is clicked).
- Contains a `Repeater` over `root.meaningfulPlayers` (deduplicated via `filterDuplicatePlayers()`), rendering one `PlayerControl` per player.

**`modules/ii/mediaControls/PlayerControl.qml`** — Individual player card.
- Props: `required property MprisPlayer player`, `visualizerPoints`, `radius`.
- Has `component TrackChangeButton: RippleButton` defined inline. Each button: `iconName`, `buttonSize` (default 24), `fill`, `downAction`.
- Controls row (`sliderRow` RowLayout) contains: skip_previous → progress slider/bar → skip_next → keep (pin as active) → open_in_new (focus window).
- `focusPlayerWindow()` function: ToplevelManager exact/prefix match on `player.desktopEntry`, fallback to HyprlandData `windowList` by class/initialClass.
- Imports needed: `Quickshell.Hyprland`, `Quickshell.Wayland` (added alongside existing Quickshell imports).

## Bar Media Widget

**`modules/ii/bar/Media.qml`** — Bar widget showing current track.

Mouse handling:
| Button | Action |
|--------|--------|
| Left | Opens media controls popup (`GlobalStates.mediaControlsOpen = !...`; sets `Persistent.states.media.popupRect`) |
| Middle | `activePlayer.togglePlaying()` |
| Back | `activePlayer.previous()` |
| Right / Forward | `activePlayer.next()` |

To open popup correctly, the bar widget first captures its own position:
```qml
var globalPos = root.mapToItem(null, 0, 0);
Persistent.states.media.popupRect = Qt.rect(globalPos.x, globalPos.y, root.width, root.height);
GlobalStates.mediaControlsOpen = !GlobalStates.mediaControlsOpen;
```

## Focusing a Media App Window (Pattern)

Used in `PlayerControl.focusPlayerWindow()`. Reusable pattern for any QML component:

```qml
// Imports needed: Quickshell.Hyprland, Quickshell.Wayland, qs.services
function focusPlayerWindow() {
    const desktopEntry = (root.player?.desktopEntry ?? "").toLowerCase();
    if (!desktopEntry) return;
    // 1. Try Wayland ToplevelManager (exact then prefix)
    const toplevels = ToplevelManager.toplevels.values;
    const byToplevel = toplevels.find(t => (t?.appId ?? "").toLowerCase() === desktopEntry)
        ?? toplevels.find(t => (t?.appId ?? "").toLowerCase().startsWith(desktopEntry));
    if (byToplevel) { byToplevel.activate(); return; }
    // 2. Fallback: Hyprland window list by class/initialClass
    const byClient = HyprlandData.windowList.find(w =>
        (w?.class ?? "").toLowerCase() === desktopEntry ||
        (w?.initialClass ?? "").toLowerCase() === desktopEntry)
        ?? HyprlandData.windowList.find(w =>
            (w?.class ?? "").toLowerCase().includes(desktopEntry) ||
            (w?.initialClass ?? "").toLowerCase().includes(desktopEntry));
    if (byClient?.address) Hyprland.dispatch(`focuswindow address:${byClient.address}`);
}
```

## Settings Pages

| File | Contents |
|------|---------|
| `modules/settings/GeneralConfig.qml` | General settings. Has sections: Battery, **Idle** (added), Language, etc. |
| `modules/settings/ServicesConfig.qml` | Service-related settings. |
| Common widgets: `ConfigSwitch`, `ContentSection` (with `icon` + `title` props). | |

## Common Patterns

### RippleButton with downAction
```qml
RippleButton {
    downAction: () => someFunction()
    contentItem: MaterialSymbol { text: "icon_name" }
}
```

### Persistent state access
```qml
Persistent.states.someKey.someValue = newValue;
// On load:
const val = Persistent.states.someKey.someValue ?? defaultValue;
```

### Session detection (new vs resumed)
```qml
const storedId = Persistent.states.idle.sessionId || "";
if (storedId === root._sessionId) {
    // resumed
} else {
    // new session — apply startup defaults
}
```
