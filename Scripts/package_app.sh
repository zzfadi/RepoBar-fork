#!/usr/bin/env bash
set -euo pipefail
CONFIGURATION=${1:-debug}
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="RepoBar"

log() { printf '%s\n' "$*"; }
fail() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

log "==> Building ${APP_NAME} (${CONFIGURATION})"
swift build -c "${CONFIGURATION}"

APP_BUNDLE="${ROOT_DIR}/.build/${CONFIGURATION}/${APP_NAME}.app"
if [ -d "${APP_BUNDLE}" ]; then
  log "Built app at ${APP_BUNDLE}"
else
  fail "App bundle not found (SwiftPM may not have produced a bundle)."
fi

# Override Info.plist with packaged settings (LSUIElement, URL scheme).
PLIST_TEMPLATE="${ROOT_DIR}/Resources/Info.plist"
if [ -f "${PLIST_TEMPLATE}" ] && [ -d "${APP_BUNDLE}" ]; then
  log "==> Installing custom Info.plist"
  cp "${PLIST_TEMPLATE}" "${APP_BUNDLE}/Contents/Info.plist"
fi

# Codesign for distribution/debug
IDENTITY="${CODESIGN_IDENTITY:-${CODE_SIGN_IDENTITY:-Apple Development: Peter Steinberger}}"
if [ -n "${IDENTITY}" ] && [ -d "${APP_BUNDLE}" ]; then
  log "==> Codesigning with ${IDENTITY}"
  "${ROOT_DIR}/Scripts/codesign_app.sh" "${APP_BUNDLE}" "${IDENTITY}" || true
fi
