#!/usr/bin/env bash
# install_rns_nomadnet_meshchat.sh
#
# Installs:
#   - Reticulum (RNS)
#   - NomadNet
#   - Reticulum MeshChat
#
# Target: BSD (primarily FreeBSD) with pkg and Python 3.
# Run as root (or via sudo).

set -euo pipefail

### Helper functions ###########################################################

info()  { printf '\033[1;34m[INFO]\033[0m %s\n' "$*"; }
warn()  { printf '\033[1;33m[WARN]\033[0m %s\n' "$*"; }
err()   { printf '\033[1;31m[ERR]\033[0m %s\n' "$*" >&2; }
die()   { err "$*"; exit 1; }

command_exists() {
  command -v "$1" >/dev/null 2>&1
}

require_root() {
  if [ "$(id -u)" -ne 0 ]; then
    die "This script must be run as root (or via sudo)."
  fi
}

### Detect basic environment ###################################################

require_root

PKG_CMD=""
if command_exists pkg; then
  PKG_CMD="pkg"
  info "Detected FreeBSD-style pkg: $PKG_CMD"
else
  warn "No 'pkg' command found. Will rely on pip and git where possible."
fi

# Detect python3 + pip3
PYTHON_BIN=""
for c in python3 python; do
  if command_exists "$c"; then
    PYTHON_BIN="$c"
    break
  fi
done

[ -z "$PYTHON_BIN" ] && die "Python 3 not found. Please install it first."

PIP_BIN=""
for c in pip3 pip; do
  if command_exists "$c"; then
    PIP_BIN="$c"
    break
  fi
done

[ -z "$PIP_BIN" ] && die "pip/pip3 not found. Please install it first."

info "Using Python: $PYTHON_BIN"
info "Using pip:    $PIP_BIN"

### Install system deps (git etc.) ############################################

if [ -n "$PKG_CMD" ]; then
  info "Ensuring git is installed via pkg..."
  $PKG_CMD install -y git || warn "Could not install git via pkg."
else
  if ! command_exists git; then
    warn "git not found and no pkg available. MeshChat installation may fail."
  fi
fi

### Install Reticulum (RNS) ####################################################

install_rns() {
  if command_exists rnsd; then
    info "Reticulum (rnsd) already installed, skipping."
    return
  fi

  # On FreeBSD (pkg present), preinstall the Python cryptography module
  # via pkg to avoid building it (and Rust/maturin) inside the jail.
  if [ -n "$PKG_CMD" ]; then
    info "Ensuring Python cryptography module is installed via pkg for $PYTHON_BIN..."
    PY_TAG="$($PYTHON_BIN - << 'EOF'
import sys
print(f"py{sys.version_info.major}{sys.version_info.minor}")
EOF
)"
    CRYPTO_PKG="${PY_TAG}-cryptography"
    if ! $PKG_CMD info -e "$CRYPTO_PKG" >/dev/null 2>&1; then
      info "Installing ${CRYPTO_PKG} via pkg..."
      if ! $PKG_CMD install -y "$CRYPTO_PKG"; then
        warn "Failed to install ${CRYPTO_PKG} via pkg; pip will attempt to build cryptography (may require rust)."
      fi
    else
      info "${CRYPTO_PKG} already installed via pkg."
    fi
  fi

  info "Installing Reticulum (RNS) via pip..."
  $PIP_BIN install --upgrade rns || die "Failed to install Reticulum (RNS) via pip."

  if ! command_exists rnsd; then
    warn "rnsd still not in PATH. It may be in ~/.local/bin or site-packages bin."
    warn "Add the appropriate bin directory to PATH."
  else
    info "Reticulum (rnsd) installed successfully."
  fi

  # Generate default config if not already there
  RETIC_CONF="$HOME/.reticulum/config"
  if [ ! -f "$RETIC_CONF" ]; then
    info "Generating example Reticulum config at $RETIC_CONF"
    su - "${SUDO_USER:-$(logname 2>/dev/null || echo root)}" -c \
      "mkdir -p \$HOME/.reticulum && rnsd --exampleconfig > \$HOME/.reticulum/config"
    info "Please edit $RETIC_CONF to suit your interfaces (LoRa/Ethernet/etc.)."
  else
    info "Reticulum config already exists at $RETIC_CONF, not overwriting."
  fi
}

### Install NomadNet ###########################################################

install_nomadnet() {
  if command_exists nomadnet; then
    info "NomadNet already installed, skipping."
    return
  fi

  if [ -n "$PKG_CMD" ]; then
    info "Trying to install NomadNet via pkg..."
    if $PKG_CMD install -y nomadnet; then
      info "NomadNet installed via pkg."
      return
    else
      warn "pkg install nomadnet failed, falling back to pip."
    fi
  fi

  info "Installing NomadNet via pip..."
  $PIP_BIN install --upgrade nomadnet || die "Failed to install NomadNet via pip."

  if ! command_exists nomadnet; then
    warn "NomadNet script not in PATH. Check ~/.local/bin or your site-packages bin dir."
  else
    info "NomadNet installed successfully."
  fi
}

### Install MeshChat ###########################################################

install_meshchat() {
  # We won’t check for a command, because MeshChat is usually run from a dir.
  # Instead, we install into /opt/reticulum-meshchat (or similar).

  MESHCHAT_DIR="/opt/reticulum-meshchat"
  MESHCHAT_REPO="https://github.com/liamcottle/reticulum-meshchat.git"

  if [ -d "$MESHCHAT_DIR/.git" ]; then
    info "MeshChat repo already present at $MESHCHAT_DIR, updating..."
    git -C "$MESHCHAT_DIR" pull || warn "Failed to update MeshChat, continuing with existing copy."
  else
    info "Cloning MeshChat to $MESHCHAT_DIR..."
    mkdir -p "$MESHCHAT_DIR"
    git clone "$MESHCHAT_REPO" "$MESHCHAT_DIR" || {
      warn "Failed to clone MeshChat repo; MeshChat will not be available."
      return
    }
  fi

  # Setup virtualenv for MeshChat
  info "Setting up Python virtualenv for MeshChat..."
  cd "$MESHCHAT_DIR"
  if ! command_exists "$PYTHON_BIN"; then
    warn "Python not found when setting up MeshChat venv; skipping MeshChat install."
    return
  fi

  # Always recreate venv with access to system site-packages so we can
  # reuse the pkg-installed cryptography/rns instead of rebuilding them.
  if [ -d "venv" ]; then
    info "Removing existing MeshChat venv to recreate with system site-packages..."
    rm -rf venv
  fi

  $PYTHON_BIN -m venv --system-site-packages venv || {
    warn "Failed to create venv for MeshChat; skipping MeshChat install."
    return
  }

  # shellcheck disable=SC1091
  source venv/bin/activate
  info "Installing MeshChat Python dependencies..."
  if [ -f requirements.txt ]; then
    pip install --upgrade pip
    pip install -r requirements.txt || warn "Failed to install some MeshChat deps."
  else
    warn "requirements.txt not found in MeshChat repo; installation may be incomplete."
  fi

  deactivate || true

  cat <<EOF

[INFO] MeshChat installed (or updated) in:
  $MESHCHAT_DIR

To run MeshChat as the regular user:

  cd $MESHCHAT_DIR
  . venv/bin/activate
  python meshchat.py

(Ensure Reticulum 'rnsd' is running first.)

EOF
}

### Main #######################################################################

info "Starting installation of Reticulum, NomadNet, and MeshChat..."

install_rns
install_nomadnet
install_meshchat

info "Done. Next steps:"
echo "  1) Edit your Reticulum config at \$HOME/.reticulum/config"
echo "  2) Start rnsd (e.g. 'rnsd &' as your normal user)."
echo "  3) Run 'nomadnet' for the CLI/TTY service."
echo "  4) Run MeshChat from /opt/reticulum-meshchat as shown above."
