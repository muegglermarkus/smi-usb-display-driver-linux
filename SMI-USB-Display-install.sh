#!/bin/bash
# =============================================================================
# SMI USB Display Driver – Automated Installation
# Tested on:  Ubuntu 26.04 Beta, Kernel 7.0.0-10-generic
# Usage:      sudo ./SMI-USB-Display-install.sh ./SMIUSBDisplay-driver.2.24.7.0.run
# Optional:   EVDI_VERSION=1.15.0 sudo ./SMI-USB-Display-install.sh ./SMI...run
# Version:    3.0
# =============================================================================

set -euo pipefail

# --- Colors ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log()     { echo -e "${GREEN}[✓]${NC} $1"; }
warn()    { echo -e "${YELLOW}[!]${NC} $1"; }
err()     { echo -e "${RED}[✗]${NC} $1"; exit 1; }
info()    { echo -e "${BLUE}[i]${NC} $1"; }
section() { echo -e "\n${BLUE}--- $1 ---${NC}"; }

# =============================================================================
# HILFSFUNKTIONEN
# =============================================================================

check_secure_boot() {
    section "Secure Boot Status prüfen"

    local sb_active=false
    local mok_key="/var/lib/shim-signed/mok/MOK.der"

    # mokutil installieren falls nötig
    if ! command -v mokutil &>/dev/null; then
        warn "mokutil nicht gefunden – wird installiert..."
        apt-get install -y mokutil || warn "mokutil konnte nicht installiert werden"
    fi

    # Secure Boot Status ermitteln
    if mokutil --sb-state 2>/dev/null | grep -q "SecureBoot enabled"; then
        sb_active=true
        warn "Secure Boot ist AKTIV"
    else
        log "Secure Boot ist deaktiviert – kein MOK-Key nötig"
        return 0
    fi

    # Ab hier: Secure Boot ist aktiv

    # MOK-Key Datei vorhanden?
    if [[ ! -f "$mok_key" ]]; then
        echo ""
        echo -e "${RED}╔══════════════════════════════════════════════════════════════╗${NC}"
        echo -e "${RED}║  FEHLER: MOK-Schlüssel nicht gefunden                        ║${NC}"
        echo -e "${RED}╚══════════════════════════════════════════════════════════════╝${NC}"
        echo ""
        info "Secure Boot ist aktiv, aber der MOK-Key fehlt."
        info "Führe zuerst folgende Schritte aus:"
        echo ""
        echo "  1. MOK-Key erstellen:"
        echo "     sudo apt-get install -y shim-signed mokutil"
        echo "     sudo update-secureboot-policy --new-key"
        echo ""
        echo "  2. MOK-Key enrollen:"
        echo "     sudo mokutil --import $mok_key"
        echo "     (Passwort setzen – du brauchst es gleich beim Reboot!)"
        echo ""
        echo "  3. Reboot durchführen:"
        echo "     sudo reboot"
        echo "     Im blauen UEFI-Screen: 'Enroll MOK' → Passwort eingeben"
        echo ""
        echo "  4. Danach dieses Script erneut ausführen."
        echo ""
        err "Abbruch – MOK-Key fehlt. Bitte Anleitung oben befolgen."
    fi

    # MOK-Key im UEFI enrolled?
    if mokutil --test-key "$mok_key" 2>/dev/null | grep -q "is already enrolled"; then
        log "MOK-Key ist im UEFI enrolled ✓"
    else
        echo ""
        echo -e "${YELLOW}╔══════════════════════════════════════════════════════════════╗${NC}"
        echo -e "${YELLOW}║  WARNUNG: MOK-Key noch nicht im UEFI enrolled                ║${NC}"
        echo -e "${YELLOW}╚══════════════════════════════════════════════════════════════╝${NC}"
        echo ""
        info "Secure Boot ist aktiv, aber der MOK-Key ist noch nicht enrolled."
        info "Ohne enrolled Key kann das evdi-Modul nicht geladen werden."
        echo ""
        echo "  Optionen:"
        echo ""
        echo "  A) MOK-Key jetzt enrollen (empfohlen):"
        echo "     sudo mokutil --import $mok_key"
        echo "     sudo reboot"
        echo "     → Im blauen UEFI-Screen: 'Enroll MOK' → Passwort eingeben"
        echo "     → Danach dieses Script erneut ausführen"
        echo ""
        echo "  B) Trotzdem fortfahren (evdi lädt erst nach Reboot + Enroll):"
        echo "     Das Script wird durchlaufen, aber USB-Display funktioniert"
        echo "     erst nach MOK-Enroll und Reboot."
        echo ""

        read -r -p "Trotzdem fortfahren? (j/N): " antwort
        if [[ ! "$antwort" =~ ^[jJyY]$ ]]; then
            echo ""
            info "Script abgebrochen. Bitte erst MOK-Key enrollen, dann erneut ausführen."
            exit 0
        fi

        warn "Fortfahren ohne enrolled MOK-Key – USB-Display erst nach Reboot aktiv."
    fi
}

# =============================================================================
# HAUPTPROGRAMM
# =============================================================================

# --- Check root ---
if [[ $EUID -ne 0 ]]; then
    err "Bitte als root ausführen: sudo $0 $*"
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
echo "  Script: v3.0"
echo "=============================================="

# --- Secure Boot prüfen (vor allem anderen!) ---
check_secure_boot

# --- 1. Dependencies ---
section "Build-Abhängigkeiten installieren"
log "Installing build dependencies..."
apt-get install -y build-essential dkms git linux-headers-"$KERNEL" libdrm-dev \
    || err "apt-get failed"

# --- 2. Check kernel headers ---
if [[ ! -d "/usr/src/linux-headers-$KERNEL" ]]; then
    err "Kernel headers nicht gefunden: /usr/src/linux-headers-$KERNEL"
fi
log "Kernel headers gefunden: /usr/src/linux-headers-$KERNEL"

# --- 3. Clone evdi from GitHub ---
section "evdi von GitHub klonen"
log "Cloning evdi from GitHub..."
mkdir -p "$WORKDIR"
git clone --depth=1 https://github.com/DisplayLink/evdi.git "$WORKDIR/evdi" \
    || err "git clone failed"

# --- 4. Build evdi module ---
section "evdi Kernel-Modul bauen"
log "Building evdi kernel module..."
make -C "$WORKDIR/evdi/module" \
    || err "make failed – siehe Ausgabe oben"

# --- 5. Install evdi module ---
section "evdi Kernel-Modul installieren"
log "Installing evdi kernel module..."
make -C "$WORKDIR/evdi/module" install \
    || err "make install failed"

log "Running depmod..."
depmod -a "$KERNEL"

log "Loading evdi module..."
if modprobe evdi 2>/dev/null; then
    log "evdi erfolgreich geladen ✓"
elif lsmod | grep -q evdi; then
    log "evdi bereits geladen ✓"
else
    warn "modprobe evdi fehlgeschlagen – Modul wird nach Reboot geladen"
fi

# --- 6. Register evdi with DKMS ---
section "evdi mit DKMS registrieren"
EVDI_SRC="/usr/src/evdi-$EVDI_VERSION"

if dkms status evdi/"$EVDI_VERSION" 2>/dev/null | grep -q evdi; then
    warn "Bestehenden DKMS-Eintrag entfernen..."
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
dkms build evdi/"$EVDI_VERSION" \
    || err "dkms build failed – Log: /var/lib/dkms/evdi/$EVDI_VERSION/build/make.log"

# --force: überschreibt das manuell installierte .ko ohne Fehler
log "Installing evdi via DKMS..."
dkms install evdi/"$EVDI_VERSION" --force \
    || err "dkms install failed"

# --- 7. Run SMI installer ---
section "SMI USB Display Installer starten"

# Fake-modprobe: SMI-Installer prüft ob evdi geladen ist.
# Bei Secure Boot (MOK noch nicht enrolled) schlägt modprobe evdi fehl,
# obwohl das Modul korrekt installiert ist. Der Fake täuscht dem SMI-Installer
# vor, dass evdi geladen ist – damit er seine veraltete evdi-Installation überspringt.
FAKE_BIN="/tmp/fake_bin_$$"
mkdir -p "$FAKE_BIN"

cat > "$FAKE_BIN/modprobe" << 'FAKE'
#!/bin/bash
if [[ "${1:-}" == "evdi" ]]; then
    echo "[fake-modprobe] evdi bereits installiert – SMI evdi-Install übersprungen" >&2
    exit 0
fi
exec /sbin/modprobe "$@"
FAKE
chmod +x "$FAKE_BIN/modprobe"

log "Starting SMI USB Display installer..."
PATH="$FAKE_BIN:$PATH" bash "$SMI_INSTALLER" \
    || { rm -rf "$FAKE_BIN"; err "SMI installer failed"; }

rm -rf "$FAKE_BIN"

# --- 8. Cleanup ---
section "Aufräumen"
log "Removing temporary files..."
rm -rf "$WORKDIR"

# --- Abschlussmeldung ---
echo ""
echo -e "${GREEN}=============================================="
echo -e "  Installation abgeschlossen!"
echo -e "==============================================${NC}"
echo ""

MOK_KEY="/var/lib/shim-signed/mok/MOK.der"
if command -v mokutil &>/dev/null && mokutil --sb-state 2>/dev/null | grep -q "SecureBoot enabled"; then
    if ! mokutil --test-key "$MOK_KEY" 2>/dev/null | grep -q "is already enrolled"; then
        echo -e "${YELLOW}Nächste Schritte (Secure Boot aktiv – MOK noch nicht enrolled):${NC}"
        echo ""
        echo "  1. MOK-Key enrollen:"
        echo "     sudo mokutil --import $MOK_KEY"
        echo "     (Passwort setzen)"
        echo ""
        echo "  2. Reboot:"
        echo "     sudo reboot"
        echo "     → Blauer UEFI-Screen: 'Enroll MOK' → Passwort eingeben"
        echo ""
        echo "  USB-Display funktioniert erst nach diesem Schritt."
    else
        echo -e "${YELLOW}Nächster Schritt:${NC}"
        echo "  sudo reboot"
        echo "  (evdi ist installiert und signiert – USB-Display nach Reboot aktiv)"
    fi
else
    echo -e "${YELLOW}Nächster Schritt:${NC}"
    echo "  sudo reboot"
fi
echo ""