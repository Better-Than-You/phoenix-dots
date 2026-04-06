# phoenix-dots — Agent Instructions

## Overview

Personal Hyprland + Quickshell II dotfiles forked from [illogical-impulse](https://github.com/end-4/dots-hyprland).

**Tech stack**: Hyprland (Wayland compositor) + Quickshell II (QML widget shell) + Nix flakes

---

## Repository Structure

```
phoenix-dots/
├── dots/.config/
│   ├── quickshell/ii/          # Quickshell/II QML config (MAIN CODE)
│   └── hypr/                   # Hyprland config
├── sdata/
│   ├── lib/                    # Shared bash functions for setup
│   ├── subcmd-*/               # Install script modules
│   └── dist-nix/               # Nix flakes for package management
├── AI_prompt.md                # Detailed QML architecture docs (READ FIRST)
├── setup                       # Original ii setup script
├── setup-phoenix.sh            # phoenix-dots install wrapper
└── dev-link.sh                 # Symlink for live development
```

---

## Development Commands

```bash
./dev-link.sh --link      # Symlink ~/.config/{hypr,quickshell} to repo for live dev
./dev-link.sh --status    # Check symlink status
./dev-link.sh --unlink    # Remove symlinks

./setup-phoenix.sh --no-backup   # Install phoenix-dots (skip backup)
./setup install                  # Original ii install (modular steps in sdata/subcmd-*/)

hyprctl reload && pkill -x qs && qs -c ii  # Restart Hyprland + Quickshell
```

---

## Quickshell/II Architecture

### Config Layers

| Layer | Location | Notes |
|-------|----------|-------|
| Defaults | `dots/.config/quickshell/ii/modules/common/Config.qml` | All default settings |
| User overrides | `~/.config/illogical-impulse/config.json` | Runtime user config |

**Always access settings via `Config.options.*`** — this merges both layers.

### Key Services (Singletons)

| Service | File | Purpose |
|---------|------|---------|
| `LauncherSearch` | `services/LauncherSearch.qml` | Core search engine — owns query, results, subprocesses |
| `MprisController` | `services/MprisController.qml` | MPRIS player tracking (`activePlayer`, `players`) |
| `HyprlandData` | `services/HyprlandData.qml` | Hyprland window list (`windowList` with `.class`, `.address`) |
| `Persistent` | `services/Persistent.qml` | JSON state persistence (`Persistent.states.*`) |
| `GlobalStates` | `services/GlobalStates.qml` | Runtime boolean toggles (`overlayOpen`) |
| `LyricsService` | `services/LyricsService.qml` | Lyrics sync |

### Search System (Prefix-Based)

All search modes activated by **single-character prefixes**. Prefixes are user-configurable.

| Prefix | Mode | Backend |
|--------|------|---------|
| `/` | Actions | Built-in + user scripts |
| `>` | Apps | DesktopEntries fuzzy search |
| `;` | Clipboard | Cliphist service |
| `:` | Emojis | Emojis service |
| `=` | Math | `qalc` subprocess |
| `$` | Shell | `bash` subprocess |
| `?` | File search | `fd` subprocess |
| `,` | *(may be remapped)* | *(varies by user config)* |

**Read prefixes from `Config.options.search.prefix.*` — never hardcode characters.**

### Search Data Flow

```
SearchBar.onTextChanged → LauncherSearch.query
    ↓
LauncherSearch.onQueryChanged:
    ├─ fileSearch prefix → strip prefix, call fileProc.searchFiles()
    └─ restart nonAppResultsTimer
    ↓
LauncherSearch.results (binding):
    ├─ Empty → []
    ├─ Clipboard prefix → Cliphist results (early return)
    ├─ Emoji prefix → Emoji results (early return)
    ├─ FileSearch prefix → fileResults (early return)
    └─ Default → math + app + command + web + action
    ↓
SearchWidget ListView renders results
```

File, clipboard, and emoji search use **early return** — when active, other results don't appear.

---

## QML Patterns & Pitfalls

### CRITICAL: Property Bindings Must Be Pure

```qml
// ❌ WRONG — side effect in binding causes binding loops
property list<var> results: {
    root.fileResults = [];  // NO!
    // ...
}

// ✅ CORRECT — side effects go in signal handler
property list<var> results: { /* pure computation only */ }

onQueryChanged: { root.fileResults = []; /* side effects here */ }
```

### CRITICAL: Read-Only Properties Need Setters

```qml
// ❌ WRONG — can't assign to read-only
MprisController.activePlayer = somePlayer;

// ✅ CORRECT — use setter methods
MprisController.setActivePlayer(somePlayer);
```

### CRITICAL: `this` Context in Qt6 Signal Handlers

```qml
// ❌ WRONG — `this.text` unreliable
onStreamFinished: { console.log(this.text); }

// ✅ CORRECT — use bare `text`
onStreamFinished: { console.log(text); }
```

### Process Spawning

`Process` spawns commands **directly** (no shell). Shell aliases don't work.

```qml
// Direct binary (works)
Process { command: ["fd", "--max-results", "50", expr] }

// Shell features (wrap in bash)
Process { command: ["bash", "-c", "cmd with pipes"] }
```

### Window Focusing Pattern

For focusing app windows (used in media controls):

```qml
// Imports: Quickshell.Hyprland, Quickshell.Wayland, qs.services
function focusWindow(appId) {
    // 1. Try Wayland ToplevelManager (exact then prefix match)
    const toplevels = ToplevelManager.toplevels.values;
    const match = toplevels.find(t => t?.appId?.toLowerCase() === appId)
        ?? toplevels.find(t => t?.appId?.toLowerCase().startsWith(appId));
    if (match) { match.activate(); return; }

    // 2. Fall back to HyprlandData window list
    const client = HyprlandData.windowList.find(w =>
        w?.class?.toLowerCase() === appId);
    if (client?.address) Hyprland.dispatch(`focuswindow address:${client.address}`);
}
```

### Player Selection Priority

When multiple MPRIS players exist:
1. Actively playing player (highest priority)
2. Priority player from config (`~/.config/illogical-impulse/config.json`)
3. First available player

### Session Detection Pattern

```qml
const storedId = Persistent.states.idle.sessionId || "";
if (storedId === root._sessionId) {
    // Resumed session
} else {
    // New session — apply startup defaults
}
```

---

## Recorder System (Super+Alt+R)

### Components

| Component | File | Purpose |
|-----------|------|---------|
| Recorder UI | `modules/ii/overlay/recorder/Recorder.qml` | Overlay widget with 4 action buttons |
| Region Selector | `modules/ii/regionSelector/RegionSelection.qml` | Fullscreen region picker with window/layer/content highlighting |
| Recording Script | `scripts/videos/record.sh` | `wf-recorder` wrapper with timer and state |
| Record Indicator | `modules/ii/bar/RecordIndicator.qml` | Bar widget showing recording timer |
| ScreenshotAction | `modules/common/utils/ScreenshotAction.qml` | Command builder for recording actions |

### Recorder UI Buttons

| Button | Icon | Action |
|--------|------|--------|
| Screenshot region | `screenshot_region` | IPC call to `region screenshot` |
| Screenshot | `photo_camera` | `grim - \| wl-copy` |
| Record region | `screen_record` | IPC call to `region recordWithSound` |
| Record screen | `capture` | `record.sh --fullscreen --sound` |

### Region Selector Features

- **Selection modes**: Rectangle corners, Circle
- **Smart targeting**: Detects windows, layers, and AI-detected content regions
- **Actions**: Copy, Edit (Satty/Swappy), Search, OCR (Tesseract), Record, Record with sound
- **Click to select** targeted region instead of dragging
- **SnipAction enum**: `Copy, Edit, Search, CharRecognition, Record, RecordWithSound`

### Recording State

```qml
Persistent.states.screenRecord.active    // boolean - is recording
Persistent.states.screenRecord.seconds   // elapsed time counter
Config.options.screenRecord.savePath     // default: ~/Videos
```

### Recording Script Usage

```bash
record.sh --fullscreen [--sound]         # Fullscreen recording
record.sh --region "x,y WxH" [--sound]  # Region recording
# Click while running to stop
```

---

## Adding a New Search Mode

1. Add prefix property in `Config.qml` under `search.prefix`
2. Add enum value in `SearchBar.SearchPrefixType`
3. Add detection in `SearchBar.searchPrefixType` property
4. Add shape + icon in both `switch` blocks in `SearchBar.qml`
5. Add prefix to `cleanOnePrefix` array in `SearchWidget.qml`
6. Add prefix to `ensurePrefix` array in `LauncherSearch.qml`
7. Add `else if` branch in `LauncherSearch.results` binding
8. If async: add Process + handler triggered from `onQueryChanged`

---

## Reference Files

| File | Content |
|------|---------|
| `AI_prompt.md` | Detailed search architecture, media controls fixes, MPRIS lessons |
| `AI_prompt.md` lines 162-439 | Media controls popup, PlayerControl, bar widget specifics |
| `sdata/dist-nix/home-manager/home.nix` | Nix package list (why each package is needed) |

---

## Common Tasks

**Restart Quickshell after config change:**
```bash
pkill -x qs && qs -c ii
```

**View Quickshell logs:**
```bash
qs -c ii 2>&1 | less
```

**Check if symlinks are active:**
```bash
./dev-link.sh --status
```
