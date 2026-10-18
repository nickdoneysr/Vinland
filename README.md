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

## What plays today (vertical slice)
- **The slice** (title screen, A): sail Eriksfjord to the Strait (six legs, weather cards, pace / rations / animals,
  the star ring every clear night, hand-line fishing on coastal legs), then run the summer camp: share the crew between
  jobs each morning, play the joint or the hand line yourself, raise three booths and the longhouse, stack timber,
  and finish on 1 September with the G1 gate checklist.
- **Practice**: Y star ring · 1 hand line · 2 joint (keyboard 1 / 2 on the title screen).

## Tests
    godot --headless --path . res://tests/test_runner.tscn
Runs the ring rules and bot nights, voyage rules and a 1,200-voyage balance sweep, hand-line and joint bots,
camp rules and a 300-summer sweep, three voyage-screen playthroughs, and one full slice playthrough to the G1 checklist. Run logs land in the Godot user folder under runlog/.
