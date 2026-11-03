# LL launcher — llama.cpp GUI

A standalone GTK launcher for the `llama.cpp` server (`llama-server`).

**Developed with the help of artificial intelligence** — This project was developed with AI assistance.

## Features

- Single-window GTK graphical interface (`llama-server-gui.py`).
- Dynamic `.gguf` model selection with the ability to refresh the list.
- Real-time server status and detailed output.
- GPU metrics (usage %, VRAM, temperature).
- Configuration editor (Settings) allowing options to be modified without editing scripts.
- Centralized `config.conf` configuration file (binary path, library path, model directory, port).
- Automatic detection of the `llama-server` binary and its libraries during installation.
- Installer compatible with apt, dnf and pacman package managers.
- Desktop application menu entry (LL launcher) compatible with GNOME, KDE and Cosmic.

## Installation

```bash
sudo bash install.sh
```

### Automatically installed dependencies

- `python3`, `python3-gi` (PyGObject), `gir1.2-gtk-3.0`.
- `libnotify-bin` (notifications).
- `llama-server` binary (automatically detected; must be installed manually if not found).

The installer reads the `config.conf` file and updates the `BIN=` and `LD_LIB=` parameters using the detected paths.

## Manual Installation

If `install.sh` fails or your distribution is not supported.

### Manually installing dependencies

**Python GTK3 / PyGObject:**

- **Debian / Ubuntu:**

  ```bash
  sudo apt install python3-gi gir1.2-gtk-3.0 gir1.2-glib-2.0 gir1.2-pango-1.0 libnotify-bin
  ```

- **Fedora:**

  ```bash
  sudo dnf install python3-gobject gtk3 libnotify
  ```

- **Arch Linux:**

  ```bash
  sudo pacman -S python-gobject gtk3 libnotify
  ```

### llama-server binary

Download and build `llama.cpp` from the source code available on GitHub (`github.com/ggerganov/llama.cpp`), or install it using your distribution's package manager.

### Graphical launcher

Create the destination directory and copy all the required files into it:

```bash
sudo mkdir -p /opt/llamacpp-launcher
sudo cp llama-server-gui.py llama-server-wrapper.sh config.conf icon.svg /opt/llamacpp-launcher/
```

### Detecting paths in config.conf

```bash
# BIN specifies the path to the llama-server executable
sudo sed -i 's|BIN=.*|BIN="/usr/local/bin/llama-server"|' /opt/llamacpp-launcher/config.conf

# LD_LIB specifies the directory containing the libllama.so library
sudo sed -i 's|LD_LIB=.*|LD_LIB="/usr/local/lib"|' /opt/llamacpp-launcher/config.conf
```

### Setting permissions for a manual installation

```bash
sudo chown -R $(whoami):$(whoami) /opt/llamacpp-launcher
sudo chmod 755 /opt/llamacpp-launcher /opt/llamacpp-launcher/models
sudo chmod 640 /opt/llamacpp-launcher/config.conf
```

### Creating the desktop application entry

```bash
echo "[Desktop Entry]
Name=LL launcher
Comment=LL launcher - Llama.cpp server
Exec=/opt/llamacpp-launcher/llama-server-gui.py
Icon=/opt/llamacpp-launcher/icon.svg
Terminal=false
Type=Application
Categories=Utility;Development;
StartupNotify=true
TryExec=/opt/llamacpp-launcher/llama-server-gui.py
StartupWMClass=llama-server-gui" > ~/.local/share/applications/llama-server.desktop

chmod +x ~/.local/share/applications/llama-server.desktop
update-desktop-database ~/.local/share/applications 2>/dev/null || true
```

For KDE and Cosmic, also copy the file to the system-wide applications directory:

```bash
sudo cp ~/.local/share/applications/llama-server.desktop /usr/share/applications/
update-desktop-database /usr/share/applications 2>/dev/null || true
```

## Usage

### Launching the graphical interface

```bash
/opt/llamacpp-launcher/llama-server-gui.py
```

You can also launch the application from your desktop environment's application menu.

### Wrapper script commands

```bash
/opt/llamacpp-launcher/llama-server-wrapper.sh start
/opt/llamacpp-launcher/llama-server-wrapper.sh status
/opt/llamacpp-launcher/llama-server-wrapper.sh stop
```

## Configuration

Edit the `/opt/llamacpp-launcher/config.conf` file or use the **Settings** button directly in the application.

- `MODEL_DIR` — directory scanned for `.gguf` files.
- `BIN` — path to the `llama-server` binary (automatically set by the installer).
- `LD_LIB` — path to the shared libraries directory (automatically set by the installer).

## Uninstallation

```bash
sudo rm -rf /opt/llamacpp-launcher /var/lib/llamacpp
rm -f ~/.local/share/applications/llama-server.desktop
```

---

**LL launcher — ADNS / LL launcher**
