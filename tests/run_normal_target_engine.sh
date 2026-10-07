#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TEMP="$(mktemp -d)"
trap 'rm -rf "$TEMP"' EXIT
mkdir -p "$TEMP/core" "$TEMP/data" "$TEMP/tests/fixtures/normal_target" "$TEMP/home" "$TEMP/config" "$TEMP/cache" "$TEMP/userdata"
printf 'config_version=5\n[application]\nconfig/name="normal-target scene-free tests"\n' > "$TEMP/project.godot"
cp "$ROOT/core/character_sim.gd" "$TEMP/core/"
cp "$ROOT/data/character_skills.json" "$ROOT/data/native-skill-contacts.json" "$TEMP/data/"
cp "$ROOT"/tests/*normal_target*.gd "$TEMP/tests/"
cp "$ROOT"/tests/fixtures/normal_target/*.json "$TEMP/tests/fixtures/normal_target/" 2>/dev/null || true
TEST="${1:-test_normal_target_engine.gd}"
HOME="$TEMP/home" XDG_CONFIG_HOME="$TEMP/config" XDG_CACHE_HOME="$TEMP/cache" XDG_DATA_HOME="$TEMP/userdata" timeout 90s godot --headless --path "$TEMP" --script "tests/$TEST"
if [[ "$TEST" == "capture_normal_target_baseline.gd" ]]; then
  cp "$TEMP/tests/fixtures/normal_target/accepted4990a6b.json" "$ROOT/tests/fixtures/normal_target/"
fi
