#!/usr/bin/env bash

set -euo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
readonly DEPLOY_CONFIG="$PROJECT_ROOT/.itchio.env"
readonly WEB_BUILD_DIR="$PROJECT_ROOT/builds/web"

die() {
  printf 'Web deployment stopped safely: %s\n' "$*" >&2
  exit 1
}

if [[ -f "$DEPLOY_CONFIG" ]]; then
  # This local, gitignored file contains the itch.io page identifiers.
  # shellcheck disable=SC1090
  source "$DEPLOY_CONFIG"
fi

itchio_user="${ITCHIO_USER:-}"
itchio_project="${ITCHIO_PROJECT:-}"
itchio_channel="${ITCHIO_CHANNEL:-html5}"

[[ -n "$itchio_user" ]] || die \
  "ITCHIO_USER is not configured. Copy .itchio.env.example to .itchio.env and add your itch.io username."
[[ -n "$itchio_project" ]] || die \
  "ITCHIO_PROJECT is not configured. Add the existing itch.io page URL slug to .itchio.env as ITCHIO_PROJECT."
[[ "$itchio_user" =~ ^[A-Za-z0-9_-]+$ ]] || die "ITCHIO_USER contains unsupported characters."
[[ "$itchio_project" =~ ^[A-Za-z0-9_-]+$ ]] || die "ITCHIO_PROJECT contains unsupported characters."
[[ "$itchio_channel" =~ ^[A-Za-z0-9_.-]+$ ]] || die "ITCHIO_CHANNEL contains unsupported characters."

find_butler() {
  local candidate=""
  local chosen_version=""
  local itch_butler_root="$HOME/Library/Application Support/itch/broth/butler"

  if [[ -n "${BUTLER_BIN:-}" ]]; then
    candidate="$BUTLER_BIN"
  elif command -v butler >/dev/null 2>&1; then
    candidate="$(command -v butler)"
  elif [[ -x "$HOME/bin/butler" ]]; then
    candidate="$HOME/bin/butler"
  elif [[ -f "$itch_butler_root/.chosen-version" ]]; then
    chosen_version="$(tr -d '\r\n' < "$itch_butler_root/.chosen-version")"
    if [[ "$chosen_version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
      candidate="$itch_butler_root/versions/$chosen_version/butler"
    fi
  fi

  [[ -n "$candidate" && -x "$candidate" ]] || die \
    "itch.io butler is not installed. Follow https://itch.io/docs/butler/installing.html or set BUTLER_BIN."
  printf '%s\n' "$candidate"
}

butler_bin="$(find_butler)"
identity_file="${BUTLER_IDENTITY_FILE:-$HOME/Library/Application Support/itch/butler_creds}"
butler_auth_args=()

if [[ -n "${BUTLER_API_KEY:-}" ]]; then
  : # Butler reads BUTLER_API_KEY directly; never print it.
elif [[ -s "$identity_file" ]]; then
  butler_auth_args=(--identity "$identity_file")
else
  die "butler is not authenticated. Run 'butler login' once, then rerun this command."
fi

"$butler_bin" version
"$SCRIPT_DIR/build-web.sh"

[[ -s "$WEB_BUILD_DIR/index.html" ]] || die "the verified Web build entrypoint is missing: $WEB_BUILD_DIR/index.html"
"$butler_bin" "${butler_auth_args[@]}" validate "$WEB_BUILD_DIR"

target="$itchio_user/$itchio_project:$itchio_channel"
printf 'Uploading verified Web build to %s\n' "$target"
"$butler_bin" "${butler_auth_args[@]}" push --if-changed "$WEB_BUILD_DIR" "$target"
printf 'itch.io deployment completed: %s\n' "$target"
