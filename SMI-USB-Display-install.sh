#!/bin/bash
# =============================================================================
# SMI USB Display Driver – Automated Installation
# Tested on:  Ubuntu 26.04 Beta, Kernel 7.0.0-10-generic
# Usage:      sudo ./SMI-USB-Display-install.sh ./SMIUSBDisplay-driver.2.24.7.0.run
# Optional:   EVDI_VERSION=1.15.0 sudo ./SMI-USB-Display-install.sh ./SMI...run
# Version:    2.0
# =============================================================================

set -euo pipefail

# --- Colors ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log()  { echo -e "${GREEN}[✓]${NC} $1"; }
warn() { echo -e "${YELLOW}[!]${NC} $1"; }
err()  { echo -e "${RED}[✗]${NC} $1"; exit 1; }

# --- Check root ---
if [[ $EUID -ne 0 ]]; then
    err "Please run as root: sudo $0 $*"
fi

# --- Argument: SMI .run file ---
SMI_INSTALLER="${1:-}"
if [[ -z "$SMI_INSTALLER" || ! -f "$SMI_INSTALLER" ]]; then
    err "Usage: sudo $0 /path/to/SMIUSBDisplay-driver.x.x.x.x.run"
fi

KERNEL=$(uname -r)
EVDI_VERSION="${EVDI_VERSION:-1.14.11}"
WORKDIR="/tmp/evdi_build_$$"

echo ""
echo "=============================================="
echo "  SMI USB Display – Driver Installation"
echo "  Kernel: $KERNEL"
echo "  evdi:   $EVDI_VERSION (GitHub)"
echo "=============================================="
echo ""

# --- 1. Dependencies ---
log "Installing build dependencies..."
apt-get install -y build-essential dkms git linux-headers-"$KERNEL" libdrm-dev \
    || err "apt-get failed"

# --- 2. Check kernel headers ---
if [[ ! -d "/usr/src/linux-headers-$KERNEL" ]]; then
    err "Kernel headers not found: /usr/src/linux-headers-$KERNEL"
fi
log "Kernel headers found: /usr/src/linux-headers-$KERNEL"

# --- 3. Clone evdi from GitHub ---
log "Cloning evdi from GitHub..."
mkdir -p "$WORKDIR"
git clone --depth=1 https://github.com/DisplayLink/evdi.git "$WORKDIR/evdi" \
    || err "git clone failed"

# --- 4. Build evdi module ---
log "Building evdi kernel module..."
make -C "$WORKDIR/evdi/module" \
    || err "make failed – see output above"

# --- 5. Install evdi module ---
log "Installing evdi kernel module..."
make -C "$WORKDIR/evdi/module" install \
    || err "make install failed"

# Run depmod
log "Running depmod..."
depmod -a "$KERNEL"

# Load module
log "Loading evdi module..."
modprobe evdi || warn "modprobe evdi failed – will be retried after reboot"

if lsmod | grep -q evdi; then
    log "evdi loaded successfully"
else
    warn "evdi not in lsmod – will be loaded after reboot"
fi

# --- 6. Register evdi with DKMS ---
EVDI_SRC="/usr/src/evdi-$EVDI_VERSION"

# Remove existing entry if present
if dkms status evdi/"$EVDI_VERSION" 2>/dev/null | grep -q evdi; then
    warn "Removing existing evdi DKMS entry..."
    dkms remove evdi/"$EVDI_VERSION" --all 2>/dev/null || true
fi
rm -rf "$EVDI_SRC"

log "Copying evdi to $EVDI_SRC..."
cp -r "$WORKDIR/evdi" "$EVDI_SRC"

log "Creating dkms.conf..."
cat > "$EVDI_SRC/dkms.conf" << EOF
PACKAGE_NAME="evdi"
PACKAGE_VERSION="$EVDI_VERSION"
BUILT_MODULE_NAME[0]="evdi"
BUILT_MODULE_LOCATION[0]="module"
DEST_MODULE_LOCATION[0]="/kernel/drivers/gpu/drm/evdi"
MAKE[0]="make -C /lib/modules/\${kernelver}/build M=\${dkms_tree}/\${PACKAGE_NAME}/\${PACKAGE_VERSION}/build/module modules"
CLEAN="make -C /lib/modules/\${kernelver}/build M=\${dkms_tree}/\${PACKAGE_NAME}/\${PACKAGE_VERSION}/build/module clean"
AUTOINSTALL="yes"
EOF

log "Registering evdi with DKMS..."
dkms add evdi/"$EVDI_VERSION" || err "dkms add failed"

log "Building evdi via DKMS..."
dkms build evdi/"$EVDI_VERSION" || err "dkms build failed – log: /var/lib/dkms/evdi/$EVDI_VERSION/build/make.log"

log "Installing evdi via DKMS..."
dkms install evdi/"$EVDI_VERSION" || err "dkms install failed"

# --- 7. Run SMI driver installer ---
log "Starting SMI USB Display installer..."
bash "$SMI_INSTALLER" || err "SMI installer failed"

# --- 8. Cleanup ---
log "Cleaning up temporary files..."
rm -rf "$WORKDIR"

echo ""
echo "=============================================="
log "Installation complete!"
echo "=============================================="
echo ""
warn "Please reboot now: sudo reboot"
echo ""
