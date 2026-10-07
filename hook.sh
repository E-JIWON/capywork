#!/bin/sh
# Claude Code hook: append a slim event line to today's log for CapyWork.
d="$HOME/.capywork/log"; mkdir -p "$d"
/usr/bin/jq -c --arg ts "$(date +%s)" \
  '{ts: ($ts|tonumber), e: .hook_event_name, sid: .session_id, cwd, prompt: ((.prompt // "")[0:80]), msg: (.message // "")}' \
  >> "$d/$(date +%F).jsonl"
exit 0
