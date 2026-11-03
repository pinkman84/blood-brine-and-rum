# Blood, Brine & Rum

A pixel-art pirate roguelite for PC. Captain one ship across the seas, node by node, trading broadsides in pausable real-time battles, and break the Honourable Trading Company before it breaks you.

Inspired by FTL, Slay the Spire and Hades.

## Engine

**Godot 4.7** (Forward+ renderer). Everyone working on the project should use the same editor version.

Upgrade rules:

- Patch updates (4.7.x): take them straight away.
- Minor updates (4.8 and later): only between build phases, and only after the first patch release. Upgrade on its own branch, then smoke test one battle, one map and save/load before merging.
- Major versions (Godot 5): don't switch mid-project.
- From the polish phase on, the engine version is frozen apart from patches.

When you upgrade, update the version here and in `config/features` in `project.godot`.

## Running it

1. Install Godot 4.7 (standard build, not .NET).
2. Open Godot, choose **Import**, and select `project.godot` in this folder.
3. Press F5. The main menu opens. Start a voyage and click through the placeholder sea map, battles, events and trading posts. The Output panel lists how much content loaded from `data/`.

## How the code fits together

Three autoloads (always-loaded singletons, set in `project.godot`) hold the game together:

| Autoload | Script | Job |
| --- | --- | --- |
| `Data` | `scripts/core/data_db.gd` | Loads every JSON file in `data/` at startup. `Data.get_item("ships", "sloop")`, `Data.get_all("events")`. |
| `SaveSystem` | `scripts/core/save_system.gd` | Saves the run in progress and long-term progress. |
| `GameState` | `scripts/core/game_state.gd` | Owns the current run and switches screens. Screens call it; they never load each other. |

`RunState` (`scripts/core/run_state.gd`) is everything about the current voyage. Screens extend `ScreenBase` (`scripts/ui/screen_base.gd`), a placeholder layout that each later phase replaces with the real thing.

## Saves

Saves are JSON in Godot's user folder. On Windows that's `%APPDATA%\Godot\app_userdata\Blood, Brine & Rum\`.

- `run.json` is the voyage in progress. It's written after every node and when the window closes, and deleted when the run ends.
- `meta.json` keeps progress between runs: voyages, victories, doubloons, unlocks.

Every save has a `save_version`. When the format changes, bump `SAVE_VERSION` in `save_system.gd` and add a step to `_migrate()`, so players' old saves keep working. Delete the files to reset progress while testing.

## Adding content

Each folder in `data/` is a category, and each `.json` file in it is an array of objects with a unique `id`. Drop in another file or add entries; no code change needed. JSON numbers load as decimals, so wrap them in `int()` in code.

When exporting, add `*.json` to **Filters to export non-resource files** in the export preset, or the data won't be packed into the build.

## Display

The game renders at **640x360** and scales up in whole steps (2x at 720p, 3x at 1080p, 4x at 1440p) so pixels stay crisp. Textures use nearest-neighbour filtering. The stretch mode is `canvas_items`, which keeps sprites pixel-perfect while letting particles, smoke and explosions draw at full screen resolution.

## Folder layout

| Folder | What goes in it |
| --- | --- |
| `scenes/` | Godot scenes: `main`, `battle`, `map`, `ui` |
| `scripts/` | GDScript: `core` (game state, saving), `battle`, `map`, `crew` |
| `data/` | Game content as JSON: `ships`, `ammo`, `crew`, `events`, `factions` |
| `assets/` | `sprites`, `vfx`, `audio`, `fonts` |
| `docs/` | Design notes |

Content lives in `data/` rather than in code, so adding a ship, ammo type or event shouldn't need a script change.

## Code style

- Typed GDScript (`var hull: int`, `func fire() -> void`).
- Tabs for indentation in `.gd` files (Godot's default).
- Avoid engine classes marked experimental in core systems; they make upgrades riskier.

## Design plan

The full design and build checklist lives in the project's grand plan doc.
