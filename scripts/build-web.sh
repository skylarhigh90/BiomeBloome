#!/usr/bin/env bash

set -euo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
readonly REQUIRED_GODOT_VERSION="4.7.2.stable.official.ed1daf0bf"
readonly TEMPLATE_VERSION="4.7.2.stable"
readonly PRESET_NAME="Web"
readonly BUILD_DIR="$PROJECT_ROOT/builds/web"
readonly STAGING_DIR="$PROJECT_ROOT/builds/.web-staging-$$"

die() {
  printf 'Web build failed: %s\n' "$*" >&2
  exit 1
}

find_godot() {
  local candidate=""
  local candidate_version=""
  local candidates=()
  local found_any=0

  if [[ -n "${GODOT_BIN:-}" ]]; then
    candidate="$GODOT_BIN"
    [[ -x "$candidate" ]] || die "GODOT_BIN is not executable: $candidate"
    printf '%s\n' "$candidate"
    return
  fi

  if command -v godot >/dev/null 2>&1; then
    candidates+=("$(command -v godot)")
  fi
  if command -v godot4 >/dev/null 2>&1; then
    candidates+=("$(command -v godot4)")
  fi
  candidates+=(
    "/Applications/Godot.app/Contents/MacOS/Godot"
    "$HOME/Applications/Godot.app/Contents/MacOS/Godot"
  )

  for candidate in "${candidates[@]}"; do
    [[ -x "$candidate" ]] || continue
    found_any=1
    candidate_version="$("$candidate" --version 2>/dev/null || true)"
    if [[ "$candidate_version" == "$REQUIRED_GODOT_VERSION" ]]; then
      printf '%s\n' "$candidate"
      return
    fi
  done

  if [[ $found_any -eq 1 ]]; then
    die "Godot was found, but no candidate reports $REQUIRED_GODOT_VERSION. Set GODOT_BIN to the matching editor executable."
  fi

  die "Godot was not found. Install Godot $REQUIRED_GODOT_VERSION or set GODOT_BIN to its editor executable."
}

cleanup() {
  if [[ -d "$STAGING_DIR" ]]; then
    rm -rf "$STAGING_DIR"
  fi
}
trap cleanup EXIT

[[ -f "$PROJECT_ROOT/project.godot" ]] || die "project.godot is missing from $PROJECT_ROOT"
[[ -f "$PROJECT_ROOT/export_presets.cfg" ]] || die "export_presets.cfg is missing from $PROJECT_ROOT"

godot_bin="$(find_godot)"
godot_version="$("$godot_bin" --version)"
[[ "$godot_version" == "$REQUIRED_GODOT_VERSION" ]] || die \
  "expected Godot $REQUIRED_GODOT_VERSION, but $godot_bin reports $godot_version"

template_dir="${GODOT_TEMPLATE_DIR:-$HOME/Library/Application Support/Godot/export_templates/$TEMPLATE_VERSION}"
template_file="$template_dir/web_nothreads_release.zip"
[[ -s "$template_file" ]] || die \
  "matching single-threaded Web release template is missing: $template_file. Install the Godot $TEMPLATE_VERSION Web Single-Threaded release template or set GODOT_TEMPLATE_DIR."

mkdir -p "$PROJECT_ROOT/builds" "$STAGING_DIR"

printf 'Building Biome Bloome Web release with %s\n' "$godot_version"
"$godot_bin" --headless --path "$PROJECT_ROOT" --export-release "$PRESET_NAME" "$STAGING_DIR/index.html"

required_artifacts=(
  index.html
  index.js
  index.wasm
  index.pck
)

for artifact in "${required_artifacts[@]}"; do
  [[ -s "$STAGING_DIR/$artifact" ]] || die "export did not produce required artifact: $artifact"
done

grep -q 'index\.wasm' "$STAGING_DIR/index.html" || die "index.html does not reference index.wasm"
grep -q 'index\.pck' "$STAGING_DIR/index.html" || die "index.html does not reference index.pck"

[[ "$BUILD_DIR" == "$PROJECT_ROOT/builds/web" ]] || die "refusing to replace unexpected build directory: $BUILD_DIR"
rm -rf "$BUILD_DIR"
mv "$STAGING_DIR" "$BUILD_DIR"
trap - EXIT

printf 'Web release built successfully: %s\n' "$BUILD_DIR/index.html"
du -sh "$BUILD_DIR"
