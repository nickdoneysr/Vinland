#!/usr/bin/env bash
# Regression pass (Backlog F64): run every automated gate check on this build and write a dated report.
# Usage: tools/regression.sh [path-to-godot]   (from the repository root)
set -u
G="${1:-${GODOT:-godot}}"
STAMP="$(date -u +%Y-%m-%d)"
COMMIT="$(git rev-parse --short HEAD 2>/dev/null || echo unknown)"
OUT="docs/regression/${STAMP}_${COMMIT}.txt"
run() {  # name, scene, extra args
  local name="$1"; shift; local scene="$1"; shift
  local log; log="$(timeout 1500 "$G" --headless --path . "$scene" "$@" 2>&1)"
  local pass fail result
  pass=$(grep -c '^PASS' <<<"$log"); fail=$(grep -c '^FAIL' <<<"$log")
  result=$(grep -E '^RESULT|^SMOKE' <<<"$log" | tail -1)
  printf '%-22s pass %4d  fail %3d  %s\n' "$name" "$pass" "$fail" "$result" >>"$OUT"
  grep -E '^FAIL|^INFO' <<<"$log" | sed 's/^/    /' >>"$OUT"
}
{
  echo "Vinland regression pass  ·  $STAMP  ·  commit $COMMIT"
  echo "Godot: $("$G" --version 2>/dev/null | head -1)"
  echo
} >"$OUT"
"$G" --headless --path . --editor --quit >/dev/null 2>&1
run "Boot smoke"          res://scenes/boot.tscn -- --smoke
run "Full suite"          res://tests/test_runner.tscn
run "Novice sweep"        res://tests/novice_runner.tscn
run "Save and load"       res://tests/save_runner.tscn
run "Balance sweep (n=20)" res://tests/balance_runner.tscn -- --n=20
echo >>"$OUT"
echo "Manual items: see the plan's Regression sheet; tick them on this build and note the report file name there." >>"$OUT"
cat "$OUT"
