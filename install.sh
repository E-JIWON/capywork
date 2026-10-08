#!/bin/sh
# CapyWork installer: builds from source (no Gatekeeper prompt), wires Claude Code hooks,
# and starts the app at login. Re-run any time to update.
set -e
cd "$(dirname "$0")"
APP="$HOME/Applications/CapyWork.app"

command -v swiftc >/dev/null || { echo "Xcode Command Line Tools가 필요해요 → xcode-select --install"; exit 1; }
[ -x /usr/bin/jq ] || { echo "macOS 15 (Sequoia) 이상이 필요해요"; exit 1; }

echo "▸ 빌드 중..."
rm -rf "$HOME/.capywork/CapyWork"
scripts/bundle.sh "$APP"
APP="$APP" exec scripts/setup.sh
