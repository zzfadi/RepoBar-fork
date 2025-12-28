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
swift build -q --product repobarcli

log "==> swift test"
swift test -q

log "==> Packaging debug app bundle"
DEFAULT_IDENTITY="${CODE_SIGN_IDENTITY:-${CODESIGN_IDENTITY:-}}"
IDENTITY="${CODESIGN_IDENTITY:-$DEFAULT_IDENTITY}"
if [ -n "$IDENTITY" ]; then
  SKIP_BUILD=1 CODESIGN_IDENTITY="$IDENTITY" "${ROOT_DIR}/Scripts/package_app.sh" debug
else
  SKIP_BUILD=1 "${ROOT_DIR}/Scripts/package_app.sh" debug
fi

log "==> Launching debug build"
APP_BUNDLE="${ROOT_DIR}/.build/debug/${APP_NAME}.app"
if [ -d "${APP_BUNDLE}" ]; then
  # Launch via LaunchServices so the process has a proper bundle identifier (menubar item, single-instance, URL handlers).
  open -n -g "${APP_BUNDLE}"
else
  "${ROOT_DIR}/.build/debug/${APP_NAME}" &
fi

sleep 1
if pgrep -f "${APP_PROCESS_PATTERN}" >/dev/null 2>&1 || pgrep -x "${APP_NAME}" >/dev/null 2>&1; then
  log "OK: ${APP_NAME} is running."
else
  fail "App exited immediately."
fi
