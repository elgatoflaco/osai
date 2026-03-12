#!/bin/bash
# test-watch-gateway.sh — End-to-end test for Watch Gateway (HTTP + Bonjour)
#
# Usage: ./scripts/test-watch-gateway.sh [port]
# Requires: osai gateway running with watch enabled

set -euo pipefail

PORT="${1:-8375}"
HOST="localhost"
BASE="http://${HOST}:${PORT}"
DEVICE_ID="test-device"
PASS=0
FAIL=0

green() { printf "\033[32m%s\033[0m\n" "$1"; }
red()   { printf "\033[31m%s\033[0m\n" "$1"; }
bold()  { printf "\033[1m%s\033[0m\n" "$1"; }

check() {
    local desc="$1" expected="$2" actual="$3"
    if echo "$actual" | grep -q "$expected"; then
        green "  ✓ $desc"
        PASS=$((PASS + 1))
    else
        red "  ✗ $desc (expected '$expected', got '$actual')"
        FAIL=$((FAIL + 1))
    fi
}

bold "━━━ Watch Gateway Test Suite ━━━"
echo ""

# ── 1. Ping ──
bold "1. Ping endpoint"
PING=$(curl -s "${BASE}/ping" 2>&1) || true
check "GET /ping returns JSON" '"status":"ok"' "$PING"
check "Reports platform=watch" '"platform":"watch"' "$PING"
check "Reports service=osai" '"service":"osai"' "$PING"

# ── 2. Send message ──
bold "2. Send message"
MSG_RESP=$(curl -s -X POST "${BASE}/message" \
    -H "Content-Type: application/json" \
    -d "{\"device_id\":\"${DEVICE_ID}\",\"user_name\":\"Test Watch\",\"text\":\"Hello from test\"}" 2>&1) || true
check "POST /message returns received" '"status":"received"' "$MSG_RESP"

# ── 3. Poll for response ──
bold "3. Poll for response (after brief delay)"
sleep 2
POLL_RESP=$(curl -s -X POST "${BASE}/poll" \
    -H "Content-Type: application/json" \
    -d "{\"device_id\":\"${DEVICE_ID}\"}" 2>&1) || true
check "POST /poll returns messages array" '"messages"' "$POLL_RESP"

# ── 4. Invalid request handling ──
bold "4. Error handling"
BAD_MSG=$(curl -s -X POST "${BASE}/message" \
    -H "Content-Type: application/json" \
    -d '{"bad":"data"}' 2>&1) || true
check "Bad message returns 400" '"error"' "$BAD_MSG"

NOT_FOUND=$(curl -s "${BASE}/nonexistent" 2>&1) || true
check "Unknown path returns 404" '"error":"not found"' "$NOT_FOUND"

# ── 5. Device whitelist ──
bold "5. Device whitelist"
BLOCKED=$(curl -s -X POST "${BASE}/message" \
    -H "Content-Type: application/json" \
    -d '{"device_id":"unknown-device","user_name":"Hacker","text":"inject"}' 2>&1) || true
check "Blocked device gets 403" '"error":"device not allowed"' "$BLOCKED"

# ── 6. Bonjour/mDNS discovery ──
bold "6. Bonjour/mDNS discovery"
echo "  Scanning for _osai._tcp services (5s timeout)..."
BONJOUR=$(dns-sd -B _osai._tcp local. 2>&1 &
    BGPID=$!
    sleep 5
    kill $BGPID 2>/dev/null
    wait $BGPID 2>/dev/null) || true
if echo "$BONJOUR" | grep -q "osai"; then
    green "  ✓ Bonjour service 'osai._osai._tcp.local.' discovered"
    PASS=$((PASS + 1))
else
    red "  ✗ Bonjour service not found (is gateway running?)"
    FAIL=$((FAIL + 1))
fi

# ── Summary ──
echo ""
bold "━━━ Results: ${PASS} passed, ${FAIL} failed ━━━"
[ "$FAIL" -eq 0 ] && green "All tests passed!" || red "Some tests failed."
exit "$FAIL"
