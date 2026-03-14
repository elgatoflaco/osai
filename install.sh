#!/bin/bash
# osai installer — https://github.com/elgatoflaco/osai
set -e

echo "🤖 Instalando osai..."

# Check macOS
if [[ "$(uname)" != "Darwin" ]]; then
    echo "❌ osai solo funciona en macOS"
    exit 1
fi

# Check Swift
if ! command -v swift &>/dev/null; then
    echo "❌ Swift no encontrado. Instala Xcode Command Line Tools:"
    echo "   xcode-select --install"
    exit 1
fi

INSTALL_DIR="${HOME}/.osai-src"

# Clone or update
if [ -d "$INSTALL_DIR" ]; then
    echo "📦 Actualizando repo..."
    cd "$INSTALL_DIR" && git pull --quiet
else
    echo "📦 Clonando repo..."
    git clone --quiet https://github.com/elgatoflaco/osai.git "$INSTALL_DIR"
    cd "$INSTALL_DIR"
fi

# Build
echo "🔨 Compilando (puede tardar 1-2 min)..."
swift build -c release 2>&1 | tail -3

BINARY=".build/release/DesktopAgent"
if [ ! -f "$BINARY" ]; then
    echo "❌ Build falló"
    exit 1
fi

# Install
echo "📦 Instalando en /usr/local/bin/osai..."
sudo cp "$BINARY" /usr/local/bin/osai
sudo chmod +x /usr/local/bin/osai
codesign --force --sign - /usr/local/bin/osai 2>/dev/null || true

# Install zsh completions
if [ -d /usr/local/share/zsh/site-functions ]; then
    sudo cp "$INSTALL_DIR/completions/_osai" /usr/local/share/zsh/site-functions/_osai 2>/dev/null || true
fi

# Create config dir
mkdir -p "${HOME}/.desktop-agent"

if [ ! -f "${HOME}/.desktop-agent/config.json" ]; then
    cat > "${HOME}/.desktop-agent/config.json" << 'EOF'
{
  "activeModel": "openrouter/minimax/minimax-m2.5",
  "apiKeys": {},
  "maxTokens": 2048
}
EOF
    chmod 600 "${HOME}/.desktop-agent/config.json"
fi

echo ""
echo "✅ osai instalado!"
echo ""
echo "Siguiente paso — configura tu API key:"
echo "  1. Crea cuenta en https://openrouter.ai (tiene \$1 gratis)"
echo "  2. Genera una API key"
echo "  3. Ejecuta:"
echo ""
echo "     osai"
echo "     /config set-key openrouter TU-API-KEY"
echo ""
echo "¡Listo! Prueba: osai \"toma un screenshot y dime qué ves\""
