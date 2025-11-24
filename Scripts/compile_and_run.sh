#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="RepoBar"
APP_PROCESS_PATTERN="${APP_NAME}.app/Contents/MacOS/${APP_NAME}"
log() { printf '%s\n' "$*"; }
fail() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

# Load signing defaults from Config/Local.xcconfig if present (xcconfig syntax)
if [ -f "${ROOT_DIR}/Config/Local.xcconfig" ]; then
  # extract key/value pairs like KEY = value
  while IFS='=' read -r rawKey rawValue; do
    key="$(printf '%s' "$rawKey" | sed 's,//.*$,,' | xargs)"
    value="$(printf '%s' "$rawValue" | sed 's,//.*$,,' | xargs)"
    case "$key" in
      CODE_SIGN_IDENTITY|CODESIGN_IDENTITY) CODE_SIGN_IDENTITY="${value}" ;;
      DEVELOPMENT_TEAM) DEVELOPMENT_TEAM="${value}" ;;
      PROVISIONING_PROFILE_SPECIFIER) PROVISIONING_PROFILE_SPECIFIER="${value}" ;;
    esac
  done < <(grep -v '^[[:space:]]*//' "${ROOT_DIR}/Config/Local.xcconfig")
fi

kill_existing() {
  for _ in {1..10}; do
    pkill -f "${APP_PROCESS_PATTERN}" 2>/dev/null || true
    pkill -x "${APP_NAME}" 2>/dev/null || true
    pgrep -f "${APP_PROCESS_PATTERN}" >/dev/null || pgrep -x "${APP_NAME}" >/dev/null || return 0
    sleep 0.2
  done
}

log "==> Killing existing ${APP_NAME} instances"
kill_existing

log "==> swift build"
swift build -q

log "==> swift test"
swift test -q

# Ensure Info.plist is copied into the app bundle for LSUIElement/URL scheme.
PLIST_TEMPLATE="${ROOT_DIR}/Resources/Info.plist"
APP_BUNDLE="${ROOT_DIR}/.build/debug/${APP_NAME}.app"
if [ -d "${APP_BUNDLE}" ] && [ -f "${PLIST_TEMPLATE}" ]; then
  log "==> Installing custom Info.plist"
  cp "${PLIST_TEMPLATE}" "${APP_BUNDLE}/Contents/Info.plist"
fi

log "==> Codesigning debug build"
DEFAULT_IDENTITY="${CODE_SIGN_IDENTITY:-${CODESIGN_IDENTITY:-}}"
IDENTITY="${CODESIGN_IDENTITY:-$DEFAULT_IDENTITY}"
if [ -z "$IDENTITY" ]; then
  log "No CODE_SIGN_IDENTITY set; skipping codesign. Set CODE_SIGN_IDENTITY or Config/Local.xcconfig to enable."
else
  if [ -d "${ROOT_DIR}/.build/debug/${APP_NAME}.app" ]; then
    "${ROOT_DIR}/Scripts/codesign_app.sh" "${ROOT_DIR}/.build/debug/${APP_NAME}.app" "$IDENTITY" || true
  else
    codesign --force --sign "$IDENTITY" "${ROOT_DIR}/.build/debug/${APP_NAME}" 2>/dev/null || true
  fi
fi

log "==> Launching debug build"
"${ROOT_DIR}/.build/debug/${APP_NAME}" &

sleep 1
if pgrep -f "${APP_PROCESS_PATTERN}" >/dev/null 2>&1 || pgrep -x "${APP_NAME}" >/dev/null 2>&1; then
  log "OK: ${APP_NAME} is running."
else
  fail "App exited immediately."
fi
