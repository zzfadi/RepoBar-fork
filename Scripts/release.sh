#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"

source "$ROOT/version.env"
source "$HOME/Projects/agent-scripts/release/sparkle_lib.sh"

APPCAST="$ROOT/appcast.xml"
APP_NAME="RepoBar"
ARTIFACT_PREFIX="RepoBar-"
BUNDLE_ID="com.steipete.repobar"
TAG="v${MARKETING_VERSION}"

err() { echo "ERROR: $*" >&2; exit 1; }

git status --porcelain | grep . && err "Working tree not clean"
ensure_changelog_finalized "$MARKETING_VERSION"

swiftformat Sources Tests >/dev/null
swiftlint --strict
swift test

"$ROOT/Scripts/sign-and-notarize.sh"

clear_sparkle_caches "$BUNDLE_ID"

KEY_FILE=$(clean_key "$SPARKLE_PRIVATE_KEY_FILE")
NOTES_HTML=$(mktemp /tmp/repobar-notes.XXXX.html)
"$ROOT/Scripts/changelog-to-html.sh" "$MARKETING_VERSION" "$ROOT/CHANGELOG.md" >"$NOTES_HTML"
NOTES_MD=$(mktemp /tmp/repobar-notes.XXXX.md)
"$ROOT/Scripts/generate-release-notes.sh" "$MARKETING_VERSION" "$NOTES_MD"
trap 'rm -f "$KEY_FILE" "$NOTES_HTML" "$NOTES_MD"' EXIT

echo "Generating Sparkle signature for appcast entry"
SIGNATURE=$(sign_update --ed-key-file "$KEY_FILE" -p "${APP_NAME}-${MARKETING_VERSION}.zip")
SIZE=$(stat -f%z "${APP_NAME}-${MARKETING_VERSION}.zip")
PUBDATE=$(LC_ALL=C date '+%a, %d %b %Y %H:%M:%S %z')

python3 - "$APPCAST" "$MARKETING_VERSION" "$BUILD_NUMBER" "$SIGNATURE" "$SIZE" "$PUBDATE" "$NOTES_HTML" <<'PY'
import pathlib
import sys
from xml.dom import minidom

appcast, ver, build, sig, size, pub, notes_path = sys.argv[1:]
notes = pathlib.Path(notes_path).read_text().strip()

doc = minidom.parse(appcast)
channel = doc.getElementsByTagName("channel")[0]

item = doc.createElement("item")

def add_text(tag, text):
    node = doc.createElement(tag)
    node.appendChild(doc.createTextNode(text))
    item.appendChild(node)

add_text("title", ver)
add_text("pubDate", pub)
add_text("link", "https://raw.githubusercontent.com/steipete/RepoBar/main/appcast.xml")

if notes:
    notes = notes.replace("]]>", "]]]]><![CDATA[>")
    desc = doc.createElement("description")
    desc.appendChild(doc.createCDATASection(notes))
    item.appendChild(desc)

add_text("sparkle:version", build)
add_text("sparkle:shortVersionString", ver)
add_text("sparkle:minimumSystemVersion", "15.0")

enc = doc.createElement("enclosure")
enc.setAttribute("url", f"https://github.com/steipete/RepoBar/releases/download/v{ver}/RepoBar-{ver}.zip")
enc.setAttribute("length", size)
enc.setAttribute("type", "application/octet-stream")
enc.setAttribute("sparkle:edSignature", sig)
item.appendChild(enc)

title_nodes = channel.getElementsByTagName("title")
if title_nodes:
    ref = title_nodes[0].nextSibling
    if ref:
        channel.insertBefore(item, ref)
    else:
        channel.appendChild(item)
else:
    channel.appendChild(item)

with open(appcast, "wb") as f:
    f.write(doc.toxml(encoding="utf-8"))
PY

verify_appcast_entry "$APPCAST" "$MARKETING_VERSION" "$KEY_FILE"

if [[ "${RUN_SPARKLE_UPDATE_TEST:-0}" == "1" ]]; then
  PREV_TAG=$(git tag --sort=-v:refname | sed -n '2p')
  [[ -z "$PREV_TAG" ]] && err "RUN_SPARKLE_UPDATE_TEST=1 set but no previous tag found"
  "$ROOT/Scripts/test_live_update.sh" "$PREV_TAG" "v${MARKETING_VERSION}"
fi

gh release create "$TAG" ${APP_NAME}-${MARKETING_VERSION}.zip ${APP_NAME}-${MARKETING_VERSION}.dSYM.zip \
  --title "${APP_NAME} ${MARKETING_VERSION}" \
  --notes-file "$NOTES_MD"

check_assets "$TAG" "$ARTIFACT_PREFIX"

git tag -f "$TAG"
git push origin main --tags

echo "Release ${MARKETING_VERSION} complete."
