#!/bin/bash
# demo-watch-gateway.sh — Complete end-to-end demo of Watch Gateway
#
# This script:
#   1. Starts the osai gateway in the background
#   2. Waits for the watch HTTP server to come up
#   3. Discovers the Bonjour service
#   4. Sends a message simulating an Apple Watch
#   5. Polls for the agent's response
#   6. Cleans up
#
# Usage: ./scripts/demo-watch-gateway.sh

set -euo pipefail

PORT=8375
HOST="localhost"
BASE="http://${HOST}:${PORT}"
DEVICE_ID="test-device"
GATEWAY_PID=""

green() { printf "\033[32m%s\033[0m\n" "$1"; }
yellow(){ printf "\033[33m%s\033[0m\n" "$1"; }
cyan()  { printf "\033[36m%s\033[0m\n" "$1"; }
bold()  { printf "\033[1m%s\033[0m\n" "$1"; }

cleanup() {
    if [ -n "$GATEWAY_PID" ]; then
        yellow "Stopping gateway (PID $GATEWAY_PID)..."
        kill "$GATEWAY_PID" 2>/dev/null || true
        wait "$GATEWAY_PID" 2>/dev/null || true
    fi
}
trap cleanup EXIT

bold "╔══════════════════════════════════════════╗"
bold "║   osai Watch Gateway — End-to-End Demo   ║"
bold "╚══════════════════════════════════════════╝"
echo ""

# ── Step 1: Start gateway ──
bold "Step 1: Starting osai gateway..."
cd "$(dirname "$0")/.."

# Auto-confirm security warning (test devices are whitelisted)
echo "y" | .build/debug/DesktopAgent gateway &
GATEWAY_PID=$!
echo "  Gateway PID: $GATEWAY_PID"

# ── Step 2: Wait for HTTP server ──
bold "Step 2: Waiting for Watch HTTP server..."
for i in $(seq 1 30); do
    if curl -s "${BASE}/ping" | grep -q '"status":"ok"' 2>/dev/null; then
        green "  ✓ Server is up on port ${PORT}"
        break
    fi
    if [ "$i" -eq 30 ]; then
        echo "  ✗ Server failed to start after 30s"
        exit 1
    fi
    sleep 1
done

# ── Step 3: Bonjour discovery ──
bold "Step 3: Checking Bonjour/mDNS discovery..."
(dns-sd -B _osai._tcp local. &
    DNSPID=$!
    sleep 3
    kill $DNSPID 2>/dev/null) 2>&1 | head -10
echo ""

# Resolve to get host/port
bold "  Resolving service..."
(dns-sd -L osai _osai._tcp local. &
    DNSPID=$!
    sleep 3
    kill $DNSPID 2>/dev/null) 2>&1 | head -10
echo ""

# ── Step 4: Ping ──
bold "Step 4: Pinging watch endpoint..."
PING=$(curl -s "${BASE}/ping")
cyan "  Response: ${PING}"
echo ""

# ── Step 5: Send message (simulating Apple Watch) ──
bold "Step 5: Sending message from simulated Apple Watch..."
MSG='{"device_id":"test-device","user_name":"Adrian Watch","text":"What time is it?"}'
cyan "  → POST /message: ${MSG}"
RESP=$(curl -s -X POST "${BASE}/message" \
    -H "Content-Type: application/json" \
    -d "$MSG")
cyan "  ← Response: ${RESP}"
echo ""

# ── Step 6: Wait for agent processing, then poll ──
bold "Step 6: Waiting for agent to process (10s)..."
sleep 10

bold "  Polling for response..."
POLL='{"device_id":"test-device"}'
POLL_RESP=$(curl -s -X POST "${BASE}/poll" \
    -H "Content-Type: application/json" \
    -d "$POLL")
cyan "  ← Poll response: ${POLL_RESP}"
echo ""

# ── Step 7: Second poll (should be empty) ──
bold "Step 7: Second poll (messages should be drained)..."
POLL_RESP2=$(curl -s -X POST "${BASE}/poll" \
    -H "Content-Type: application/json" \
    -d "$POLL")
cyan "  ← Poll response: ${POLL_RESP2}"
echo ""

# ── Step 8: Test blocked device ──
bold "Step 8: Testing device whitelist (blocked device)..."
BLOCKED=$(curl -s -X POST "${BASE}/message" \
    -H "Content-Type: application/json" \
    -d '{"device_id":"evil-device","user_name":"Attacker","text":"delete everything"}')
cyan "  ← Response: ${BLOCKED}"
echo ""

# ── Done ──
bold "╔══════════════════════════════════════════╗"
bold "║          Demo complete!                  ║"
bold "╚══════════════════════════════════════════╝"
echo ""
green "The Watch Gateway is running with:"
green "  • HTTP server on port ${PORT}"
green "  • Bonjour service: osai._osai._tcp.local."
green "  • Device whitelist: test-device, adrian-watch"
echo ""
yellow "Press Ctrl+C to stop the gateway."
wait "$GATEWAY_PID"
