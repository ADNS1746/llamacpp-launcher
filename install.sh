#!/bin/bash
# Install script for llama.cpp launcher (GTK GUI + wrapper + .desktop)
# Usage: sudo bash install.sh
set -e

# Paths
APP_DIR="/opt/llamacpp-launcher"
MODELS_DIR="$APP_DIR/models"
ICON="$APP_DIR/icon.svg"
DESKTOP_FILE="$HOME/.local/share/applications/llama-server.desktop"
WRAPPER="$APP_DIR/llama-server-wrapper.sh"
GUI="$APP_DIR/llama-server-gui.py"
CONFIG="$APP_DIR/config.conf"

echo "=== Installation du lanceur llama.cpp ==="

# 1. Créer les dossiers nécessaires
echo "[1/7] Création des dossiers..."
sudo mkdir -p "$APP_DIR" "$MODELS_DIR" "$HOME/.local/share/applications"

# 2. Vérifier les dépendances
echo "[2/7] Vérification des dépendances..."
if ! command -v python3 &>/dev/null; then
    echo "ERREUR : python3 requis"
    exit 1
fi
if ! python3 -c "import gi" 2>/dev/null; then
    echo "Installation de PyGObject (PyGtk)..."
    if command -v pacman &>/dev/null; then
        sudo pacman -S --noconfirm python-gobject python-gi pygobject3-gtk python-pip python3-pip
    elif command -v dnf &>/dev/null; then
        sudo dnf install -y python3-gobject python3-gtk3 libnotify llama-cpp 2>/dev/null || sudo dnf install -y python3-gobject python3-gtk libnotify llama-cpp
    elif command -v apt &>/dev/null; then
        sudo apt install -y python3-gi python3-gi-cairo python3-gtk-3 gir1.2-gtk-3.0
    else
        echo "AVERTISSEMENT : installez manuellement python-gi (PyGObject) et PyGtk"
    fi
fi

if ! command -v notify-send &>/dev/null; then
    echo "Installation de libnotify (notifications)..."
    if command -v pacman &>/dev/null; then
        sudo pacman -S --noconfirm libnotify
    elif command -v apt &>/dev/null; then
        sudo apt install -y libnotify-bin
    else
        echo "AVERTISSEMENT : installez manuellement libnotify (notify-send)"
    fi
fi

if ! command -v llama-server &>/dev/null; then
    echo "Installation de llama-cpp..."
    if command -v pacman &>/dev/null; then
        sudo pacman -S --noconfirm llama-cpp
    elif command -v apt &>/dev/null; then
        echo "AVERTISSEMENT : installez manuellement llama-cpp (binaire llama-server)"
    else
        echo "AVERTISSEMENT : installez manuellement llama-cpp (binaire llama-server)"
    fi
fi

# 3. Copier les fichiers de l'application
echo "[3/7] Copie des fichiers de l'application..."
if [ ! -f "$WRAPPER" ]; then
    echo "ERREUR : $WRAPPER introuvable. Assurez-vous d'être dans le répertoire de l'application."
    exit 1
fi
if [ ! -f "$GUI" ]; then
    echo "ERREUR : $GUI introuvable. Assurez-vous d'être dans le répertoire de l'application."
    exit 1
fi
if [ ! -f "$CONFIG" ]; then
    echo "ERREUR : $CONFIG introuvable. Assurez-vous d'être dans le répertoire de l'application."
    exit 1
fi
sudo cp "$WRAPPER" "$GUI" "$CONFIG" "$ICON" "$APP_DIR/" 2>/dev/null || true
sudo chmod +x "$WRAPPER" "$GUI"
sudo chown -R "$USER":"$USER" "$APP_DIR"

# 4. Configurer le .desktop
echo "[4/7] Configuration du lanceur GNOME..."
cat > "$DESKTOP_FILE" <<EOF
[Desktop Entry]
Name=llama Server
Comment=Interface graphique pour le serveur llama.cpp
Exec=$APP_DIR/llama-server-gui.py
Icon=$ICON
Terminal=false
Type=Application
Categories=Development;Server;
StartupNotify=true
EOF
chmod +x "$DESKTOP_FILE"
echo "Lanceur GNOME créé : $DESKTOP_FILE"

# 5. Configurer la clé API (optionnel)
echo "[5/7] Configuration de la clé API (optionnel)..."
if [ ! -f "/var/lib/llamacpp/api-keys.txt" ]; then
    echo "Création d'un fichier de clé API par défaut..."
    sudo mkdir -p /var/lib/llamacpp
    echo "sk-llamacpp-default-$(date +%s)" | sudo tee /var/lib/llamacpp/api-keys.txt > /dev/null
    sudo chmod 600 /var/lib/llamacpp/api-keys.txt
    sudo chown root:root /var/lib/llamacpp/api-keys.txt
    echo "Clé API créée : /var/lib/llamacpp/api-keys.txt"
else
    echo "Une clé API existe déjà : /var/lib/llamacpp/api-keys.txt"
fi

# 6. Vérifier les permissions
echo "[6/7] Vérification des permissions..."
sudo chown -R "$USER":"$USER" "$APP_DIR"
sudo chmod 755 "$APP_DIR"
sudo chmod 755 "$MODELS_DIR"
sudo chmod 640 "$CONFIG"
sudo chmod 640 "$APP_DIR/llama-server.log" 2>/dev/null || true
echo "Permissions configurées."

# 7. Finalisation
echo "[7/7] Finalisation..."
echo ""
echo "=== Installation terminée ==="
echo ""
echo "Prochaines étapes :"
echo "1. Téléchargez un modèle .gguf dans $MODELS_DIR"
echo "2. Modifiez $CONFIG si nécessaire (chemin du modèle, port, etc.)"
echo "3. Lancez le GUI via le menu Applications ou : $APP_DIR/llama-server-gui.py"
echo ""
echo "Pour tester :"
echo "  $APP_DIR/llama-server-wrapper.sh start"
echo "  $APP_DIR/llama-server-wrapper.sh status"
echo "  $APP_DIR/llama-server-wrapper.sh stop"
echo ""
echo "Pour désinstaller :"
echo "  sudo rm -rf $APP_DIR /var/lib/llamacpp"
echo "  rm -f $DESKTOP_FILE"
echo ""
echo "Bon usage !"