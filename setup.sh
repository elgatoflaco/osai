#!/bin/bash
# Desktop Agent - Setup Script

set -e

echo "🖥  Building Desktop Agent..."
swift build -c release 2>&1

BINARY=".build/release/DesktopAgent"

if [ ! -f "$BINARY" ]; then
    echo "❌ Build failed"
    exit 1
fi

echo "✅ Build complete: $(ls -lh $BINARY | awk '{print $5}')"

# Optional: install to /usr/local/bin
if [ "$1" = "--install" ]; then
    echo "📦 Installing to /usr/local/bin/desktop-agent..."
    cp "$BINARY" /usr/local/bin/desktop-agent
    echo "✅ Installed! Run with: desktop-agent"
else
    echo ""
    echo "To run:"
    echo "  export ANTHROPIC_API_KEY=your-key-here"
    echo "  .build/release/DesktopAgent"
    echo ""
    echo "To install globally:"
    echo "  ./setup.sh --install"
fi
