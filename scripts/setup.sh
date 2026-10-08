#!/bin/sh
# Wires an installed CapyWork.app into your account: Claude Code hooks, statusLine, the grass
# backfill and the login item. `--uninstall` undoes all of it (the app itself stays).
# APP points at the app (default ~/Applications/CapyWork.app). Safe to re-run; it restarts the app.
set -e
HERE="$(cd "$(dirname "$0")" && pwd)"
D="$HOME/.capywork"
S="$HOME/.claude/settings.json"
L="$HOME/Library/LaunchAgents/com.capywork.plist"
APP="${APP:-$HOME/Applications/CapyWork.app}"
service="gui/$(id -u)/com.capywork"

[ -x /usr/bin/jq ] || { echo "macOS 15 (Sequoia) 이상이 필요해요"; exit 1; }

if [ "$1" = "--uninstall" ]; then
  launchctl bootout "$service" 2>/dev/null || true
  rm -f "$L"
  if [ -f "$S" ]; then
    cp "$S" "$S.bak-capywork-uninstall"
    /usr/bin/jq '
      if .hooks then .hooks |= (with_entries(.value |= map(select(any(.hooks[]?; .command | tostring | contains("/.capywork/hook.sh")) | not)))
                                | with_entries(select(.value | length > 0))) else . end
      | if .hooks == {} then del(.hooks) else . end
      | if (.statusLine.command? // "" | contains(".capywork")) then del(.statusLine) else . end
    ' "$S.bak-capywork-uninstall" > "$S"
  fi
  rm -rf "$D"
  echo "✓ CapyWork 연결 해제 완료 (hook · statusLine · 자동 실행 · 기록)"
  exit 0
fi

[ -x "$APP/Contents/MacOS/CapyWork" ] || { echo "앱을 찾을 수 없어요: $APP"; exit 1; }
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$APP" 2>/dev/null || true
mkdir -p "$D/log"
cp "$HERE/hook.sh" "$HERE/statusline.sh" "$D/" && chmod +x "$D/hook.sh" "$D/statusline.sh"

echo "▸ 지난 근무 기록으로 잔디 채우는 중..."
python3 "$HERE/backfill.py" >/dev/null || echo "  (건너뜀)"

echo "▸ Claude Code hook 연결 중..."
mkdir -p "$HOME/.claude"
[ -f "$S" ] || echo '{}' > "$S"
cp "$S" "$S.bak-capywork"
had_statusline=$(/usr/bin/jq -r 'if .statusLine and (.statusLine.command | tostring | contains(".capywork") | not) then "yes" else "no" end' "$S")
/usr/bin/jq --arg h "\"$D/hook.sh\"" --arg sl "\"$D/statusline.sh\"" '
  def add(ev; e): .hooks[ev] = ([(.hooks[ev] // [])[] | select(any(.hooks[]?; .command | tostring | contains("/.capywork/hook.sh")) | not)] + [e]);
  .hooks //= {}
  | reduce ("SessionStart", "UserPromptSubmit", "Notification", "Stop", "SessionEnd") as $ev
      (.; add($ev; {hooks: [{type: "command", command: $h}]}))
  | reduce ("PreToolUse", "PostToolUse", "PostToolUseFailure") as $ev
      (.; add($ev; {matcher: "*", hooks: [{type: "command", command: $h}]}))
  | if .statusLine == null then .statusLine = {type: "command", command: $sl} else . end
' "$S.bak-capywork" > "$S"

echo "▸ 로그인 시 자동 실행 등록 중..."
mkdir -p "$(dirname "$L")"
cat > "$L" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>com.capywork</string>
  <key>ProgramArguments</key><array><string>$APP/Contents/MacOS/CapyWork</string></array>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><dict><key>SuccessfulExit</key><false/></dict>
</dict>
</plist>
PLIST
launchctl bootout "$service" 2>/dev/null || true
# bootout returns before the old process is gone; bootstrapping too early fails with error 5.
for _ in 1 2 3 4 5 6 7 8 9 10; do launchctl print "$service" >/dev/null 2>&1 || break; sleep 0.5; done
launchctl bootstrap "gui/$(id -u)" "$L"

echo "✓ 설치 완료! 상단바에 카피바라가 보일 거예요 🍊"
[ "$had_statusline" = "yes" ] && echo "  ※ 이미 쓰는 statusLine이 있어서 그대로 뒀어요. 사용량 초기화 시각은 표시되지 않을 수 있어요."
exit 0
