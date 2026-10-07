#!/bin/sh
# Removes CapyWork: login item, Claude Code hooks/statusLine it added, and ~/.capywork.
D="$HOME/.capywork"
S="$HOME/.claude/settings.json"
launchctl bootout "gui/$(id -u)/com.capywork" 2>/dev/null
rm -f "$HOME/Library/LaunchAgents/com.capywork.plist"
if [ -f "$S" ]; then
  cp "$S" "$S.bak-capywork-uninstall"
  /usr/bin/jq --arg h "\"$D/hook.sh\"" '
    if .hooks then .hooks |= (with_entries(.value |= map(select(any(.hooks[]?; .command | tostring | contains("/.capywork/hook.sh")) | not)))
                              | with_entries(select(.value | length > 0))) else . end
    | if .hooks == {} then del(.hooks) else . end
    | if (.statusLine.command? // "" | contains(".capywork")) then del(.statusLine) else . end
  ' "$S.bak-capywork-uninstall" > "$S"
fi
rm -rf "$D"
echo "✓ CapyWork 삭제 완료"
