# Vinland

Oregon Trail structure on the Karlsefni voyage. Godot 4.3, 2D painted, gamepad-first.
Plan: `docs/Vinland_Game_Development_Plan.xlsx`. Art list: `docs/Vinland_Art_Asset_List.xlsx`.

## Dropping in art
Save a finished PNG at the path in the asset list's File path column (for example
`art/navigate/nav_01_star_ring_instrument.png`). The game uses it on the next run; until then it
draws the placeholder of the same size from `art_placeholder/`. Variants add a suffix before `.png`.

## Tuning
All numbers come from the plan's Assumptions sheet. After changing the plan, run:

    python3 tools/export_knobs.py docs/Vinland_Game_Development_Plan.xlsx
    python3 tools/make_manifest.py docs/Vinland_Art_Asset_List.xlsx

## Layout
- `scripts/autoload/` Knobs (tuning), Art (asset lookup), Controls (gamepad grammar), Game (run state)
- `scenes/` playable scenes, starting with `boot.tscn`
- `art/` your finished art, by category · `art_placeholder/` generated stand-ins · `art_source/` layered sources
- `data/` knobs.json, art_manifest.json · `tools/` pipeline scripts · `marketing/` store art

## Checks
    godot --headless --path . -- --smoke      # prints SMOKE ... result=PASS

## What plays today
- **Voyage** (title screen, A): Eriksfjord to the Strait, six legs, weather card each dawn, pace / rations / animal ration,
  coastal fishing (Y), the star ring every clear night, landfalls, loss on the season clock, a daily run log.
- **Star ring practice** (title screen, Y): five sky conditions on keys 1–5.

## Tests
    godot --headless --path . res://tests/test_runner.tscn
Runs the ring rules, bot nights, voyage rules, a 1,200-voyage balance sweep with four captains, and three full
playthroughs of the voyage screen. Run logs land in the Godot user folder under runlog/.
