#!/bin/bash
# test-bonjour-discovery.sh — Verify Bonjour/mDNS service registration
#
# Tests that the osai Watch Gateway registers and resolves via Bonjour.
# Run this while the gateway is active.
#
# Usage: ./scripts/test-bonjour-discovery.sh

set -euo pipefail

green() { printf "\033[32m%s\033[0m\n" "$1"; }
red()   { printf "\033[31m%s\033[0m\n" "$1"; }
bold()  { printf "\033[1m%s\033[0m\n" "$1"; }
cyan()  { printf "\033[36m%s\033[0m\n" "$1"; }

bold "━━━ Bonjour/mDNS Discovery Test ━━━"
echo ""

# ── Browse for service type ──
bold "1. Browsing for _osai._tcp services..."
BROWSE_OUTPUT=$(mktemp)
dns-sd -B _osai._tcp local. > "$BROWSE_OUTPUT" 2>&1 &
BROWSE_PID=$!
sleep 4
kill $BROWSE_PID 2>/dev/null || true
wait $BROWSE_PID 2>/dev/null || true

cat "$BROWSE_OUTPUT"
echo ""

if grep -q "osai" "$BROWSE_OUTPUT"; then
    green "  ✓ Service 'osai' found via browse"
else
    red "  ✗ Service 'osai' NOT found — is the gateway running?"
    rm -f "$BROWSE_OUTPUT"
    exit 1
fi

# ── Resolve service to get host and port ──
bold "2. Resolving service to host:port..."
RESOLVE_OUTPUT=$(mktemp)
dns-sd -L osai _osai._tcp local. > "$RESOLVE_OUTPUT" 2>&1 &
RESOLVE_PID=$!
sleep 4
kill $RESOLVE_PID 2>/dev/null || true
wait $RESOLVE_PID 2>/dev/null || true

cat "$RESOLVE_OUTPUT"
echo ""

if grep -q "port" "$RESOLVE_OUTPUT" || grep -q "8375" "$RESOLVE_OUTPUT"; then
    green "  ✓ Service resolved successfully"
else
    red "  ✗ Service resolution failed"
fi

# ── Query via mDNS directly ──
bold "3. Querying _osai._tcp.local. PTR record..."
QUERY_OUTPUT=$(mktemp)
dns-sd -Q _osai._tcp.local. PTR > "$QUERY_OUTPUT" 2>&1 &
QUERY_PID=$!
sleep 4
kill $QUERY_PID 2>/dev/null || true
wait $QUERY_PID 2>/dev/null || true

cat "$QUERY_OUTPUT"
echo ""

# ── Verify HTTP connectivity after discovery ──
bold "4. Verifying HTTP endpoint after Bonjour discovery..."
PING=$(curl -s "http://localhost:8375/ping" 2>&1) || true
if echo "$PING" | grep -q '"status":"ok"'; then
    green "  ✓ HTTP ping successful: $PING"
else
    red "  ✗ HTTP ping failed: $PING"
fi

# Cleanup
rm -f "$BROWSE_OUTPUT" "$RESOLVE_OUTPUT" "$QUERY_OUTPUT"

echo ""
bold "━━━ Bonjour Discovery Test Complete ━━━"
