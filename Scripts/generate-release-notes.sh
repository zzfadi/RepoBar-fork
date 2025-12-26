#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"

source "$ROOT/version.env"
source "$HOME/Projects/agent-scripts/release/sparkle_lib.sh"

VERSION=${1:-$MARKETING_VERSION}
OUT=${2:-}

if [[ -z "$OUT" ]]; then
  tmp=$(mktemp /tmp/repobar-notes.XXXX.md)
  extract_notes_from_changelog "$VERSION" "$tmp"
  cat "$tmp"
  rm -f "$tmp"
else
  extract_notes_from_changelog "$VERSION" "$OUT"
fi
