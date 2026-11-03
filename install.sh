#!/bin/bash
# Llama.cpp launcher installer (multi-distro, multi-desktop)
# Usage: sudo bash install.sh
set -e
RED='\033[0;31m'
NC='\033[0m'
SOURCE_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_DIR="/opt/llamacpp-launcher"
MODELS_DIR="$APP_DIR/models"
ICON_SOURCE="$SOURCE_DIR/icon.svg"
ICON="$APP_DIR/icon.svg"
REAL_HOME="$HOME"
[ -n "$SUDO_USER" ] && REAL_HOME="/home/$SUDO_USER"
DESKTOP_FILE="$REAL_HOME/.local/share/applications/llama-server.desktop"
WRAPPER="$SOURCE_DIR/llama-server-wrapper.sh"
GUI="$SOURCE_DIR/llama-server-gui.py"
CONFIG="$SOURCE_DIR/config.conf"

echo "=== Llama.cpp launcher installation ==="

# 1. Create directories
mkdir -p "$MODELS_DIR" 2>/dev/null || sudo mkdir -p "$MODELS_DIR"
echo "[1/7] Creating directories..."
sudo mkdir -p "$APP_DIR" 2>/dev/null || mkdir -p "$APP_DIR"
mkdir -p "$(dirname "$DESKTOP_FILE")" 2>/dev/null || sudo mkdir -p "$(dirname "$DESKTOP_FILE")"

# 2. Check dependencies + auto-detect llama-server binary
echo "[2/7] Checking dependencies..."
LLAMA_BIN=""
for p in $(echo "/usr/local/sbin:/usr/local/bin:/usr/bin:$PATH" | tr ':' ' '); do
    [ -x "$p/llama-server" ] && LLAMA_BIN="$p/llama-server" && break
    done
    [ -z "$LLAMA_BIN" ] && for p in /usr/local/sbin /usr/local/bin /usr/bin /bin /snap/bin; do [ -x "$p/llama-server" ] && LLAMA_BIN="$p/llama-server" && break; done
if [ -z "$LLAMA_BIN" ]; then echo -e "${RED}WARNING: llama-server binary not found${NC}"; else echo "Binary detected: $LLAMA_BIN"; fi

if ! command -v python3 &>/dev/null; then echo -e "${RED}ERROR: python3 required${NC}"; exit 1; fi
if ! python3 -c "import gi; gi.require_version('Gtk', '3.0'); from gi.repository import Gtk" 2>/dev/null; then
    echo "Installing PyGObject + GTK3 introspection..."
    if command -v apt &>/dev/null; then sudo apt-get update -qq && sudo apt-get install -y -qq python3-gi gir1.2-gtk-3.0 gir1.2-glib-2.0 gir1.2-pango-1.0; fi
    if command -v dnf &>/dev/null; then sudo dnf install -y python3-gobject gtk3; fi
    if command -v pacman &>/dev/null; then sudo pacman -S --noconfirm python-gobject gtk3; fi
fi
if ! command -v notify-send &>/dev/null; then
    echo "Installing libnotify..."
    command -v apt &>/dev/null && sudo apt install -y libnotify-bin || true
    command -v dnf &>/dev/null && sudo dnf install -y libnotify || true
    command -v pacman &>/dev/null && sudo pacman -S --noconfirm libnotify || true
fi

# 3. Copy files + update config paths
if [ -f "$SOURCE_DIR/models/"*.gguf ]; then sudo cp "$SOURCE_DIR/models/"*.gguf "$MODELS_DIR/" 2>/dev/null || true; echo "Models copied to $MODELS_DIR"; fi
sudo cp "$WRAPPER" "$GUI" "$CONFIG" "$ICON_SOURCE" "$APP_DIR/" 2>/dev/null || true
sudo chmod +x "$WRAPPER" "$GUI"
sudo chown -R "$USER":"$USER" "$APP_DIR"
if [ -n "$LLAMA_BIN" ]; then
    sudo sed -i "s|BIN=.*|BIN=\"$LLAMA_BIN\"|" "$APP_DIR/config.conf"
    LLAMA_LIB_DIR=""
    for p in $(echo "$LLAMA_BIN" | sed 's|/[^/]*$||'); do [ -d "$p/../lib" ] && LLAMA_LIB_DIR="$p/../lib" && break; done
    for d in /usr/local/lib /usr/lib /opt/llama/lib; do [ -f "$d/libllama.so" ] && LLAMA_LIB_DIR="$d" && break; done
    [ -n "$LLAMA_LIB_DIR" ] && sudo sed -i "s|LD_LIB=.*|LD_LIB=\"$LLAMA_LIB_DIR\"|" "$APP_DIR/config.conf" && echo "Libraries detected: $LLAMA_LIB_DIR"
fi

# 4. Desktop entry
cat > "$DESKTOP_FILE" <<EOF
[Desktop Entry]
Name=LL launcher
Comment=LL launcher - Llama.cpp server
Exec=$APP_DIR/llama-server-gui.py
Icon=$ICON
Terminal=false
Type=Application
Categories=Utility;Development;
StartupNotify=true
TryExec=$APP_DIR/llama-server-gui.py
StartupWMClass=llama-server-gui
EOF
chmod +x "$DESKTOP_FILE"
REAL_USER="${SUDO_USER:-$USER}"
REAL_UID="$(id -u "$REAL_USER" 2>/dev/null || echo 1000)"
REAL_GID="$(id -g "$REAL_USER" 2>/dev/null || echo 1000)"
chown "$REAL_UID:$REAL_GID" "$DESKTOP_FILE" 2>/dev/null || true
update-desktop-database "$REAL_HOME/.local/share/applications" 2>/dev/null || true
echo "Desktop launcher created: $DESKTOP_FILE"

# 5. Skip
# 6. Permissions
echo "[6/7] Setting permissions..."
sudo chown -R "$USER":"$USER" "$APP_DIR"
sudo chmod 755 "$APP_DIR" "$MODELS_DIR"
sudo chmod 640 "$APP_DIR/config.conf" 2>/dev/null || true
# 7. Final
echo "=== Installation finished ==="
echo "Dependencies installed/detected:"
echo "  - python3: $(command -v python3 || echo 'missing')"
echo "  - python3-gi: $(python3 -c 'import gi' 2>/dev/null && echo 'OK' || echo 'missing')"
echo "  - libnotify: $(command -v notify-send || echo 'missing')"
echo "  - llama-server: $LLAMA_BIN"
echo ""
echo "Next steps:"
echo "1. Download a .gguf model in /opt/llamacpp-launcher/models (or your choice folder)"
echo "2. Edit /opt/llamacpp-launcher/config.conf if needed (model path, port, etc)"
echo "3. Launch GUI via Applications menu or: $APP_DIR/llama-server-gui.py"
echo ""
echo "To test:"
echo "  $APP_DIR/llama-server-wrapper.sh start"
echo "  $APP_DIR/llama-server-wrapper.sh status"
echo "  $APP_DIR/llama-server-wrapper.sh stop"
echo ""
echo "To uninstall:"
echo "  sudo rm -rf $APP_DIR /var/lib/llamacpp"
echo "  rm -f $DESKTOP_FILE"
echo "Good luck!"
