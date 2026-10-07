#!/usr/bin/env bash
set -euo pipefail
project_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# These sentinels catch a source-only checkout, not an incomplete asset import.
for required in data/character-presentations.json data/character_skills.json shaders/native_body_layer4.gdshader; do
  if [[ ! -f "$project_dir/$required" ]]; then
    printf 'Missing runtime input: %s\nSee docs/ASSET_IMPORT.zh-CN.md to prepare authorized local inputs.\nThis early guard is not full asset validation.\n' "$required" >&2
    exit 2
  fi
done
godot_bin="${GODOT_BIN:-godot}"
if ! command -v "$godot_bin" >/dev/null 2>&1; then
  printf '%s\n' 'Godot executable not found. Install Godot 4.6.3 or set GODOT_BIN to its executable path.' >&2
  exit 127
fi
if godot_version="$("$godot_bin" --version)"; then
  case "$godot_version" in
    4.6.3.stable|4.6.3.stable.*) ;;
    *) printf 'Expected Godot 4.6.3 stable; found: %s\n' "$godot_version" >&2; exit 2 ;;
  esac
else
  status=$?
  printf '%s\n' 'Godot version check failed.' >&2
  exit "$status"
fi
"$godot_bin" --headless --editor --path "$project_dir" --import
exec "$godot_bin" --path "$project_dir" "$@"
