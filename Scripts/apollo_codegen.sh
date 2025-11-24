#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if ! command -v apollo-ios >/dev/null; then
  echo "apollo-ios (Apollo codegen CLI) not found. Install with: brew install apollo-ios" >&2
  exit 1
fi

cd "$ROOT"
apollo-ios download-schema --path GraphQL/schema.graphqls --endpoint https://api.github.com/graphql
apollo-ios generate --config apollo-codegen.json
