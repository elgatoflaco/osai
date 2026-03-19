#!/bin/bash
# osai installer — https://github.com/elgatoflaco/osai
set -e

echo "🤖 Instalando OSAI..."

# Check macOS
if [[ "$(uname)" != "Darwin" ]]; then
    echo "❌ osai solo funciona en macOS"
    exit 1
fi

# Check architecture
ARCH=$(uname -m)
if [[ "$ARCH" != "arm64" ]]; then
    echo "⚠️  Binarios solo disponibles para Apple Silicon (arm64)."
    echo "   Para Intel, compila desde source: git clone https://github.com/elgatoflaco/osai && cd osai && swift build -c release"
    exit 1
fi

TMP_DIR=$(mktemp -d)
trap "rm -rf $TMP_DIR" EXIT

# Download latest release
echo "📦 Descargando última versión..."
RELEASE_URL="https://github.com/elgatoflaco/osai/releases/latest/download/osai-latest.zip"
curl -fsSL "$RELEASE_URL" -o "$TMP_DIR/osai-latest.zip"

echo "📦 Descomprimiendo..."
cd "$TMP_DIR"
unzip -q osai-latest.zip

# Install CLI
echo "📦 Instalando CLI..."
sudo cp osai-dist/osai /usr/local/bin/osai
sudo chmod +x /usr/local/bin/osai
sudo xattr -rd com.apple.quarantine /usr/local/bin/osai 2>/dev/null || true
sudo codesign --force --sign - /usr/local/bin/osai 2>/dev/null || true

# Install Desktop App
echo "📦 Instalando OSAI.app..."
rm -rf /Applications/OSAI.app
cp -R osai-dist/OSAI.app /Applications/OSAI.app
xattr -rd com.apple.quarantine /Applications/OSAI.app 2>/dev/null || true
codesign --force --sign - /Applications/OSAI.app/Contents/MacOS/OSAI 2>/dev/null || true

# Create config
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
echo "✅ OSAI instalado!"
echo ""
echo "   • App: Abre OSAI desde /Applications (o Cmd+Space → OSAI)"
echo "   • CLI: Escribe 'osai' en terminal"
echo ""
echo "Configura tu API key:"
echo "  1. Crea cuenta en https://openrouter.ai (tiene \$1 gratis)"
echo "  2. Genera una API key"
echo "  3. Ejecuta:"
echo ""
echo "     osai"
echo "     /config set-key openrouter TU-API-KEY"
echo ""
echo "¡Listo! Prueba: osai \"qué hora es?\""
