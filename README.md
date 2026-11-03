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
3. Press F5. You should see the title, the engine version and "5 ammo types loaded".

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
