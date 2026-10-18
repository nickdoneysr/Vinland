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

## What plays today (Production, in progress)
- **New voyage** (title, A): Eriksfjord to the Strait. Weather cards, pace / rations / animals, the star ring on
  clear nights, the storm bail on storm nights, hand-line fishing on coastal legs.
- **The camp**: a full year at the Strait. Share the crew each morning, play the joint or the hand line yourself,
  dry surplus fish on the rack, cut hay in August, raise booths, the longhouse and the byre, and get people and
  animals through the first winter to the second spring.
- **Continue** (title, Start/Tab): autosaves every watch at sea and every day ashore (three rolling slots).
- **Difficulty** (title, D-pad or Z/C): Forgiving (default), Standard, Hard.
- **Practice**: Y star ring · 1 hand line · 2 joint · 3 storm bail.

## Tests
    godot --headless --path . res://tests/test_runner.tscn      # rules, bots, balance sweeps, saves, full playthrough
    godot --headless --path . res://tests/novice_runner.tscn    # first-time player model, every game x difficulty x input
    godot --headless --path . res://tests/camp_runner.tscn      # camp year sweeps only
Runs the ring rules and bot nights, voyage rules and a 1,200-voyage balance sweep, hand-line and joint bots,
camp rules and a 300-summer sweep, three voyage-screen playthroughs, and one full slice playthrough to the G1 checklist. Run logs land in the Godot user folder under runlog/.
