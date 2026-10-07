#!/bin/sh
# CapyWork installer: builds from source (no Gatekeeper prompt), wires Claude Code hooks,
# and starts the app at login. Re-run any time to update.
set -e
cd "$(dirname "$0")"
D="$HOME/.capywork"
S="$HOME/.claude/settings.json"
L="$HOME/Library/LaunchAgents/com.capywork.plist"
APP="$HOME/Applications/CapyWork.app"

command -v swiftc >/dev/null || { echo "Xcode Command Line Tools가 필요해요 → xcode-select --install"; exit 1; }
[ -x /usr/bin/jq ] || { echo "macOS 15 (Sequoia) 이상이 필요해요"; exit 1; }

echo "▸ 빌드 중..."
mkdir -p "$D/log"
swift build -c release --product CapyWork >/dev/null
rm -rf "$APP" "$D/CapyWork"
mkdir -p "$APP/Contents/MacOS"
cp "$(swift build -c release --show-bin-path)/CapyWork" "$APP/Contents/MacOS/CapyWork"
cat > "$APP/Contents/Info.plist" <<INFO
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key><string>CapyWork</string>
  <key>CFBundleIdentifier</key><string>com.capywork.app</string>
  <key>CFBundleName</key><string>CapyWork</string>
  <key>CFBundleDisplayName</key><string>카피 출근부</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>LSMinimumSystemVersion</key><string>15.0</string>
  <key>LSUIElement</key><true/>
</dict>
</plist>
INFO
codesign --force --sign - "$APP" 2>/dev/null
cp scripts/hook.sh scripts/statusline.sh "$D/" && chmod +x "$D/hook.sh" "$D/statusline.sh"

echo "▸ 지난 근무 기록으로 잔디 채우는 중..."
python3 scripts/backfill.py >/dev/null || echo "  (건너뜀)"

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
  | reduce ("PostToolUse", "PostToolUseFailure") as $ev
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
service="gui/$(id -u)/com.capywork"
launchctl bootout "$service" 2>/dev/null || true
# bootout returns before the old process is gone; bootstrapping too early fails with error 5.
for _ in 1 2 3 4 5 6 7 8 9 10; do launchctl print "$service" >/dev/null 2>&1 || break; sleep 0.5; done
launchctl bootstrap "gui/$(id -u)" "$L"

echo "✓ 설치 완료! 상단바에 카피바라가 보일 거예요 🍊"
[ "$had_statusline" = "yes" ] && echo "  ※ 이미 쓰는 statusLine이 있어서 그대로 뒀어요. 사용량 초기화 시각은 표시되지 않을 수 있어요."
exit 0
