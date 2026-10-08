#!/bin/sh
# Removes CapyWork: login item, Claude Code hooks/statusLine it added, ~/.capywork, and the app.
cd "$(dirname "$0")"
scripts/setup.sh --uninstall
rm -rf "$HOME/Applications/CapyWork.app"
echo "✓ CapyWork 삭제 완료"
