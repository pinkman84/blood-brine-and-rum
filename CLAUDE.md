# CLAUDE.md

Context for Claude sessions working on **Blood, Brine & Rum**. Read this first. The README covers running the game, saves and the folder layout; this file covers the design, the code and how we work.

## The game

A PC pirate roguelite in Godot 4.7 (GDScript), inspired by FTL, Slay the Spire and Hades. Working title "Brine & Blackpowder" is pinned as an alternative; the repo uses "Blood, Brine & Rum". Low-res pixel art later (placeholders are drawn in code for now), with high-quality explosions and effects on top. Target: Steam Early Access with 3 seas.

**Story.** Every voyage starts with you holding the **Aeolus Horn**, an ancient artifact: blow it and the wind blows the way you point it. That's why you can sail any route on the map. The **Honourable Trading Company** ("the Company") knows you have it and will stop at nothing to take it. Its reputation with you is fixed at Hostile (Hated in a stolen Company ship) and nothing changes it. The Company hunt meter is them tracking the Horn. The final boss is the Company flagship.

**A run:** 5 of 7 seas, 60-90 minutes. Each sea is an FTL-style web of ~23 nodes; you sail to any neighbour (forwards, sideways or back), each move costing a day, a rum ration and Company hunt. A faction-owned port sits on a strait in the middle of every sea; an elite captain guards the exit. At each exit you pick the next sea on a sea chart. The last sea is always the South China Sea: all Company ships, a fortress port, a two-frigate blockade, then the flagship.

**Battles:** pausable real-time, always 1v1, top-down FTL-style cutaway. Two broadsides; "come about" swaps sides (a ship mid-turn can be raked for double damage). Rooms take damage, catch fire, spring leaks and flood. Ammo: round (unlimited), chain (sails), grape (crew), heated (fires, with a mishap risk). Two-way grappling and boarding. Fleeing fills an escape bar.

**Crew:** *hands* are a ship stat (a number, not people); the share of hands left scales every timing (reload, repairs, turning, dodge). *Specialists* are named crew, up to 8, the dots you move between rooms: master gunner, helmsman, carpenter, bosun, surgeon, boarding master. They buff the room they're in, get wounded, and die. Ranks: ordinary, seasoned, veteran (buffs +25% per rank). *Morale* 0-100 scales effort; below 20 the crew mutinies.

**Factions:** the Company, Royal Navy, Pirate Brotherhood, rival pirates, slavers. Reputation -100..100 per faction, per run (Hated, Hostile, Wary, Friendly, Allied); the starting ship shifts it. It sets port prices, whether ports trade, whether ships at sea salute you, take a bribe or fight, and which event choices are open. Each faction has a light, medium and heavy ship; early in a run they're mostly light, under-crewed and short of specialists, late they're heavy and fully fitted out.

**Progression in a run:** plunder after every win (pick 1 of 3; sometimes a relic), 15 relics with passive effects, shipyard upgrades at ports, random outposts (FTL-style stores) at sea.

**Between runs:** the home port, Blackwater Cay (working name). Doubloons build and improve a tavern (better specialists), cartographer (more treasure), carpenter (more starting hull) and old captain (more hands). Ships unlock by deeds: Privateer cutter for reaching the last sea, Black frigate for beating the flagship, Turncoat brigantine for Jonas Pike's quest.

**The flagship (Sovereign, a first-rate):** three banks of guns a side firing in a rolling sequence, no boarding or running. Phase 1 gun duel; empty her hull pool and a gun deck explodes, then a breather choice. Phase 2 marines come in boats you can target (X); they stop when her hands fall to 25%. Phase 3 the great gun: slow, 25% of your hull per hit, holes every lower room. Sink her and the run is won.

## How we work

- **Aidan** is the designer and owner. He describes features in his own words; build a working, simple version (KISS placeholders), then he plays it and asks for changes. Balance is deliberately left for a later tuning pass, so first-guess numbers are fine; put them in constants or data, never scattered.
- One **feature branch** per step (e.g. `phase-8/final-boss-and-story`), opened as a **pull request**; Aidan reviews, plays it and merges to `main`.
- Write commit messages and PR descriptions in plain English: what changed for the player, then what changed in the code.
- Keep the plan in step: the living plan is a Claude Doc and project notes in Aidan's Cowork project. Mention anything that should be updated there in the PR description.

## Code map

Autoloads (set in `project.godot`): `Data`, `SaveSystem`, `GameState`.

| Area | Files |
| --- | --- |
| Data loading | `scripts/core/data_db.gd`: `CATEGORIES` lists every `data/` folder; add new categories there |
| Run state and saves | `scripts/core/run_state.gd` (every field goes in `to_dict` and `from_dict`, with a default for old saves), `scripts/core/save_system.gd` (`meta` = progress between runs, `SAVE_VERSION`, `_migrate`) |
| Flow and screens | `scripts/core/game_state.gd`: `Screen` enum and `SCREEN_SCENES`, `start_new_run`, `finish_node` (end of every node; also the blockade chain, mutiny check and sea change), `take_plunder`, `resume_map`, `end_run` |
| Voyage | `scripts/core/voyage.gd`: seas, sea chart, enemy scaling, `progress()`, ship class weights and `fit_out`, the Company hunt, last-sea constants |
| Morale, events, reputation, perks, home port | `scripts/core/morale.gd`, `events.gd` (requirements and effects of event choices), `reputation.gd`, `perks.gd` (relics and upgrades: `Perks.add` / `Perks.mult`), `hub.gd` (home port, ship unlocks, quests, specialist ranks) |
| Sea map | `scripts/map/sea_map_gen.gd` (generator), `sea_map_screen.gd` (fog, movement, ambushes), `sea_chart_screen.gd` |
| Battle | `scripts/battle/battle_screen.gd` (the big one: setup, enemy picking, stations, firing, AI, boarding UI, hailing, victory and defeat), `battle_ship.gd`, `battle_crew.gd`, `damage_control.gd`, `boarding.gd`, `boss_fight.gd`, `ship_view.gd` (drawing), `battle_vfx.gd` (particles) |
| Other screens | `scripts/ui/`: `screen_base.gd` (placeholder layout: info on the left, a scrolling column of buttons on the right), ship select, port (`shop_screen.gd`), outpost, event, loot, home port (`hub_screen.gd`), menu, game over |

Data (`data/<category>/*.json`, arrays of objects with an `id`): ammo, ships, enemies, layouts, crew, names, factions, events, seas, relics, upgrades, outposts, hub, quests. Most content and tuning lives here. Each script's header comment documents the fields it reads.

## Conventions

- Typed GDScript. Tabs. Write a `##` comment at the top of each script explaining what it's for and how the pieces fit; keep the comments current when behaviour changes.
- Game numbers go in named constants at the top of a script or in `data/`, with a short comment on what they mean.
- Placeholder art is drawn in code (`ShipView._draw`, `CPUParticles2D`). Don't add image assets until the art pass.
- Screen size is 640x360. Keep text inside it: use autowrap and fixed widths, and put long lists in the button column (it scrolls).

GDScript pitfalls we've hit:
- JSON numbers load as floats: wrap in `int()`, including ids read back from saves.
- `Array.filter()` returns an untyped `Array`; build a typed array with a loop when a function returns `Array[String]` etc.
- Avoid multi-line lambdas inside call arguments and backslash-continued ternaries; use a named function or separate lines.
- Don't use an autoload's enum as a type hint.
- Don't call `_log` in the battle screen before `_build_ui` has run.
- After adding a new `class_name`, run the editor import once (see Testing) or other scripts won't find it.

## Testing

There are no unit tests yet. Before opening a PR, at minimum:

1. Import the project headless so every script compiles: `godot --headless --editor --quit --path .` and check for `SCRIPT ERROR` / `Parse Error`.
2. Smoke-test the feature with a throwaway runner scene. A scene's root node is freed when the game changes screen, so add a separate runner node to the root:

```gdscript
# _t.gd, attached to the root node of _t.tscn
extends Node
func _ready() -> void:
	var r := Node.new()
	r.set_script(load("res://_r.gd"))
	get_tree().root.add_child.call_deferred(r)
```

`_r.gd` then drives the game (`GameState.start_new_run("sloop")`, `GameState.change_screen(...)`, poke `get_tree().current_scene`, `await get_tree().create_timer(t).timeout`) and prints what it finds. Run it with `godot --headless --path . res://_t.tscn`, or under `xvfb-run` with `--rendering-driver opengl3` to save screenshots via `get_viewport().get_texture().get_image().save_png(...)`. Delete the runner files (and any `.uid` files they created) before committing.

In-game testing aids (both in `battle_screen.gd`, to be switched off before release): **B** = lash the ships together (`DEBUG_BOARDING`), **T** = god mode (`DEBUG_CHEATS`: 999 hull and hands, 1-second reloads, 99 of each ammo).

## Status (November 2026)

Built and merged: Phases 0-8a. Core battles, boarding, crew and morale; the map, events, storms, treasure, ports and forts; factions and reputation; faction rosters; plunder, relics, the shipyard and outposts; the home port and ship unlocks; the last sea, blockade and flagship.

Next, roughly in order (confirm with Aidan):
- **Ship augments:** outposts already roll an augment stall (`stock["augments"]` is an empty list). Design what augments are and how they differ from relics and shipyard upgrades.
- **Phase 8 remainder:** story beats across runs (home port characters with new lines after milestones), branching endings (the Horn's fate).
- **A ship screen** to inspect relics, upgrades and crew.
- **Combat depth before tuning:** weather in battle, sea swell, timing. Fights are currently too easy to just "fit and hit".
- **Tuning pass**, then art (Phase 9), audio (10) and polish (11).
