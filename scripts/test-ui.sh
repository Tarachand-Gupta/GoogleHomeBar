#!/usr/bin/env bash
set -euo pipefail

# End-to-end live UI verification for GoogleHomeBar using agent-desktop.
# Checks:
#  1. Devices load in Modern popover
#  2. Clicking an OFF device card expands full controls without turning it on,
#     dims/disables all controls except Turn On
#  3. Clicking Web tab mounts a live WKWebView (AXWebArea) with a top-right Reload button
#  4. Repeated tab switches (Web -> Cast -> Web -> Settings -> Web -> Devices -> Web)
#     never strand or blank out the WKWebView
#  5. Classic UX Web tab also renders live AXWebArea + Reload, then restores Modern UX

APP_BIN="/Applications/GoogleHomeBar.app/Contents/MacOS/GoogleHomeBar"
DEMO_FLAG=""
if [[ "${1:-}" == "--demo" ]]; then
  DEMO_FLAG="--demo"
fi
if [[ ! -x "$APP_BIN" ]]; then
  echo "ERROR: $APP_BIN not found. Run ./scripts/build-app.sh --install first." >&2
  exit 1
fi

cleanup() {
  pkill -x GoogleHomeBar 2>/dev/null || true
}
trap cleanup EXIT

pkill -x GoogleHomeBar 2>/dev/null || true
defaults write com.playground.GoogleHomeBar uiExperienceStyle -string "modern"

"$APP_BIN" --open-popover $DEMO_FLAG >/tmp/ghb_ui_test.log 2>&1 &

# Poll until Devices load (up to 15s)
SNAP=""
for _ in $(seq 1 30); do
  SNAP=$(agent-desktop snapshot --app "GoogleHomeBar" -i --compact 2>/dev/null || true)
  if echo "$SNAP" | grep -q '"Full controls for '; then
    break
  fi
  sleep 0.5
done

echo "$SNAP" | grep -q '"Full controls for ' || { echo "FAIL: Devices did not load in popover"; exit 1; }
echo "PASS [1/5]: Devices loaded in Modern popover"

# Helper to find button ref_id by exact name or prefix via python3
find_ref() {
  local json="$1"
  local pattern="$2"
  local wanted_role="${3:-button}"
  python3 - "$json" "$pattern" "$wanted_role" <<'PY'
import json, sys
data = json.loads(sys.argv[1])
pat = sys.argv[2]
wanted_role = sys.argv[3]
def walk(node):
    name = node.get("name") or ""
    role = node.get("role") or ""
    if (wanted_role == "*" or role == wanted_role) and (name == pat or name.startswith(pat)):
        if node.get("ref_id"):
            print(node["ref_id"])
            sys.exit(0)
    for c in node.get("children") or []:
        walk(c)
walk(data.get("data", {}).get("tree", {}))
sys.exit(1)
PY
}

# 2. Click an OFF card body -> MUST expand detail view AND stay OFF
find_off_card() {
  python3 - "$1" <<'PY'
import json, sys
data = json.loads(sys.argv[1])
def walk(node):
    name = node.get("name") or ""
    role = node.get("role") or ""
    if role == "button" and ", " in name and " · " not in name and "Toggle " not in name and "Full controls" not in name and "Window Blinds" not in name:
        print(node["ref_id"])
        sys.exit(0)
    for c in node.get("children") or []:
        walk(c)
walk(data.get("data", {}).get("tree", {}))
sys.exit(1)
PY
}

OFF_CARD_REF=$(find_off_card "$SNAP" || true)
if [[ -z "$OFF_CARD_REF" ]]; then
  BEDROOM_REF=$(find_ref "$SNAP" "Bedroom" || true)
  if [[ -n "$BEDROOM_REF" ]]; then
    agent-desktop click "$BEDROOM_REF" >/dev/null
    sleep 0.35
    SNAP=$(agent-desktop snapshot --app "GoogleHomeBar" -i --compact)
    OFF_CARD_REF=$(find_off_card "$SNAP")
  fi
fi

agent-desktop click "$OFF_CARD_REF" >/dev/null
sleep 0.5
DETAIL_SNAP=$(agent-desktop snapshot --app "GoogleHomeBar" -i --compact)
echo "$DETAIL_SNAP" | grep -q '"Back to Devices"' || { echo "FAIL: Clicking card body did not expand full controls"; exit 1; }
echo "$DETAIL_SNAP" | grep -q '"Turn On"' || { echo "FAIL: Clicking OFF card body unexpectedly toggled device ON"; exit 1; }
echo "$DETAIL_SNAP" | grep -q '"disabled"' || { echo "FAIL: Off-state controls were not disabled"; exit 1; }
echo "PASS [2/5]: Clicking card body expands full controls without toggling power, and off-state controls are disabled"

BACK_REF=$(find_ref "$DETAIL_SNAP" "Back to Devices")
agent-desktop click "$BACK_REF" >/dev/null
sleep 0.4

# 3. Switch to Web tab and verify Reload button + live AXWebArea (webarea role)
assert_web_live() {
  local label="$1"
  local full_snap=""
  for _ in $(seq 1 12); do
    full_snap=$(agent-desktop snapshot --app "GoogleHomeBar" --compact 2>/dev/null || true)
    if echo "$full_snap" | grep -q '"role":"webarea"'; then
      break
    fi
    sleep 0.4
  done
  echo "$full_snap" | grep -q '"name":"Reload"' || { echo "FAIL [$label]: Reload button missing from Web toolbar"; exit 1; }
  echo "$full_snap" | grep -q '"role":"webarea"' || { echo "FAIL [$label]: WKWebView (webarea) is missing/blank!"; exit 1; }
  echo "PASS [$label]: Live WKWebView (webarea) + Reload button verified"
}

DASH_SNAP=$(agent-desktop snapshot --app "GoogleHomeBar" -i --compact)
WEB_REF=$(find_ref "$DASH_SNAP" "Web")
agent-desktop click "$WEB_REF" >/dev/null
assert_web_live "3/5 Modern Web tab initial switch"

# 4. Cycle Web -> Cast -> Web -> Settings -> Web -> Devices -> Web
for next_tab in "Cast" "Settings" "Devices"; do
  CUR_SNAP=$(agent-desktop snapshot --app "GoogleHomeBar" -i --compact)
  NEXT_REF=$(find_ref "$CUR_SNAP" "$next_tab")
  agent-desktop click "$NEXT_REF" >/dev/null
  sleep 0.35
  CUR_SNAP=$(agent-desktop snapshot --app "GoogleHomeBar" -i --compact)
  WEB_REF=$(find_ref "$CUR_SNAP" "Web")
  agent-desktop click "$WEB_REF" >/dev/null
  assert_web_live "4/5 After $next_tab -> Web"
done

# 5. Reload button click works and keeps webarea mounted
WEB_I_SNAP=$(agent-desktop snapshot --app "GoogleHomeBar" -i --compact)
RELOAD_REF=$(find_ref "$WEB_I_SNAP" "Reload")
agent-desktop click "$RELOAD_REF" >/dev/null
sleep 0.6
assert_web_live "5/6 After clicking Reload button"

# 6. Classic UX Web tab also renders live webarea + Reload, then restore Modern UX
CUR_SNAP=$(agent-desktop snapshot --app "GoogleHomeBar" -i --compact)
SETTINGS_REF=$(find_ref "$CUR_SNAP" "Settings")
agent-desktop click "$SETTINGS_REF" >/dev/null
sleep 0.4
SET_SNAP=$(agent-desktop snapshot --app "GoogleHomeBar" -i --compact)
CLASSIC_REF=$(find_ref "$SET_SNAP" "Classic" "*")
agent-desktop click "$CLASSIC_REF" >/dev/null
sleep 0.4
CLASSIC_SNAP=$(agent-desktop snapshot --app "GoogleHomeBar" -i --compact)
CLASSIC_WEB_REF=$(find_ref "$CLASSIC_SNAP" "Web")
agent-desktop click "$CLASSIC_WEB_REF" >/dev/null
assert_web_live "6/6 Classic UX Web tab"

# Restore Modern UX
CLASSIC_SNAP=$(agent-desktop snapshot --app "GoogleHomeBar" -i --compact)
CLASSIC_SET_REF=$(find_ref "$CLASSIC_SNAP" "Settings")
agent-desktop click "$CLASSIC_SET_REF" >/dev/null
sleep 0.4
SET_SNAP=$(agent-desktop snapshot --app "GoogleHomeBar" -i --compact)
MODERN_REF=$(find_ref "$SET_SNAP" "Modern" "*")
agent-desktop click "$MODERN_REF" >/dev/null
sleep 0.3

echo "ALL LIVE UI CHECKS PASSED!"
