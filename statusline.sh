#!/bin/sh
# Claude Code statusLine: stash the plan rate limits for the menu bar app. Prints nothing.
d="$HOME/.capywork"; mkdir -p "$d"
/usr/bin/jq -c --arg ts "$(date +%s)" 'select(.rate_limits) | {ts: ($ts|tonumber), rate_limits}' > "$d/limits.tmp" 2>/dev/null \
  && [ -s "$d/limits.tmp" ] && mv "$d/limits.tmp" "$d/limits.json"
exit 0
