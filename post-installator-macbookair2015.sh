#!/usr/bin/env bash
# Zorin Post-Install Script (Tailored for MacBook Air 2015 series)
# Eurobotics 2025 - GNU
# v.20250817.2015

set -euo pipefail

# =====================
#  Globals & utilities
# =====================
SCRIPT_DIR="$(pwd)"
LOGFILE="$SCRIPT_DIR/zorin-postinstall.log"
: > "$LOGFILE"
exec > >(tee -a "$LOGFILE") 2>&1

echo "============================================================"
echo " ZorinOS Post-Install Script - Tailored for MacBook Air 2015 "
echo "============================================================"

export LC_ALL=C
export DEBIAN_FRONTEND=noninteractive

RED="\e[31m"; GREEN="\e[32m"; YELLOW="\e[33m"; BLUE="\e[34m"; NC="\e[0m"
log_info()    { echo -e "${BLUE}[INFO]${NC} $*"; }
log_success() { echo -e "${GREEN}[OK]${NC} $*"; }
log_warn()    { echo -e "${YELLOW}[WARN]${NC} $*"; }
log_error()   { echo -e "${RED}[ERROR]${NC} $*"; exit 1; }

trap 'log_error "Script interrupted. Exiting..."' INT TERM

# Root check
[[ $EUID -ne 0 ]] && log_error "This script must be run as root. Use: sudo $0"

# =====================
#  Flags (opt-in bits)
# =====================
WITH_NGROK=0
WITH_SERVEO=0
WITH_RUSTDESK=0
WITH_DROPBOX=0
WITH_CAMERA=0   # FaceTimeHD (DKMS + firmware)
HEADLESS=0      # Skip GUI extras

usage() {
  cat <<EOF
Usage: sudo $0 [options]
  --with-ngrok         Install ngrok (snapless not guaranteed; skipped by default)
  --with-serveo        Add Serveo convenience config (ssh remote forward alias)
  --with-rustdesk      Install RustDesk (repo with signed key; fallback direct .deb)
  --with-dropbox       Install Dropbox (Flatpak recommended; .deb avoided)
  --with-camera        Build FaceTime HD (Broadcom bcwc_pcie DKMS + firmware)
  --headless           Skip GUI apps (OnlyOffice/Bottles etc.)
  -h|--help            Show this help
EOF
}

for arg in "$@"; do
  case "$arg" in
    --with-ngrok)    WITH_NGROK=1 ;;
    --with-serveo)   WITH_SERVEO=1 ;;
    --with-rustdesk) WITH_RUSTDESK=1 ;;
    --with-dropbox)  WITH_DROPBOX=1 ;;
    --with-camera)   WITH_CAMERA=1 ;;
    --headless)      HEADLESS=1 ;;
    -h|--help) usage; exit 0 ;;
    *) log_warn "Unknown option: $arg" ;;
  esac
done

# =====================
#  Functions
# =====================
check_internet() {
  log_info "Verifying internet connection..."
  if ! ping -c 1 -W 3 1.1.1.1 &>/dev/null; then
    log_error "No internet connection. Exiting."
  fi
  log_success "Internet connection verified."
}

apt_update_upgrade() {
  log_info "Updating package lists and upgrading system..."
  apt-get -o Acquire::ForceIPv4=true update
  apt-get -o Dpkg::Options::=--force-confnew \
          -o Acquire::ForceIPv4=true \
          full-upgrade -y
  log_success "System updated."
}

configure_unattended_upgrades() {
  log_info "Configuring automatic updates (non-interactive)..."
  apt-get -o Acquire::ForceIPv4=true install -y unattended-upgrades
  install -m 644 /dev/stdin /etc/apt/apt.conf.d/20auto-upgrades <<'EOF'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
EOF
  log_success "Unattended upgrades enabled."
}

setup_ssh_server() {
  log_info "Installing and configuring OpenSSH Server..."
  apt-get -o Acquire::ForceIPv4=true install -y openssh-server
  install -m 644 /dev/stdin /etc/ssh/sshd_config.d/00-zorin.conf <<'EOF'
Port 22
PasswordAuthentication yes
PermitRootLogin no
ChallengeResponseAuthentication no
UsePAM yes
EOF
  systemctl enable --now ssh
  if command -v ufw &>/dev/null && ufw status | grep -q active; then
    ufw allow 22/tcp || true
  fi
  log_success "SSH ready (passwords allowed)."
}

install_security_tools() {
  log_info "Installing security tools (ClamAV, UFW, GUFW)..."
  apt-get -o Acquire::ForceIPv4=true install -y clamav clamav-daemon ufw gufw || log_warn "Some security tools failed"
  systemctl enable --now clamav-freshclam || true
}

configure_firewall_minimal() {
  if ! command -v ufw &>/dev/null; then
    log_warn "UFW not installed. Skipping firewall setup."
    return
  fi
  log_info "Applying minimal firewall policy: deny inbound, allow outbound, open SSH."
  ufw --force reset
  ufw default deny incoming
  ufw default allow outgoing
  ufw allow 22/tcp
  ufw --force enable
  log_success "Firewall enabled with safe defaults."
}

install_core_cli() {
  log_info "Installing core CLI utilities..."
  apt-get -o Acquire::ForceIPv4=true install -y \
    build-essential \
    dkms \
    linux-headers-"$(uname -r)" \
    inxi lshw lsb-release \
    unzip curl wget git \
    flatpak \
    timeshift \
    python3-pip python3-cryptography \
    fwupd software-properties-common || log_warn "Some CLI utilities failed"
  fwupdmgr refresh || true
}

install_macbook_air_drivers() {
  log_info "Installing MacBook Air 2015 specific drivers..."
  apt-get -o Acquire::ForceIPv4=true install -y bcmwl-kernel-source || log_warn "Broadcom wl driver install failed"
}

install_facetimehd_optional() {
  [[ $WITH_CAMERA -eq 1 ]] || { log_info "FaceTime HD support skipped (use --with-camera)."; return; }
  log_info "Installing FaceTime HD camera (DKMS + firmware)..."
  git clone https://github.com/patjak/facetimehd-firmware /opt/facetimehd-firmware || true
  (cd /opt/facetimehd-firmware && make && make install) || log_warn "facetimehd firmware install failed"
  git clone https://github.com/patjak/bcwc_pcie /usr/src/bcwc-pcie-1.0 || true
  (cd /usr/src/bcwc-pcie-1.0 && make -j"$(nproc)" || true)
  dkms add /usr/src/bcwc-pcie-1.0 || true
  dkms build bcwc-pcie/1.0 || true
  dkms install bcwc-pcie/1.0 || log_warn "facetimehd DKMS install failed"
  modprobe facetimehd || true
  log_success "FaceTime HD step completed (if no errors above)."
}

power_tweaks() {
  log_info "Applying power & thermal tweaks (Broadwell)..."
  apt-get -o Acquire::ForceIPv4=true install -y tlp tlp-rdw thermald intel-microcode powertop || true
  systemctl enable --now tlp thermald || true
  log_success "Power tweaks applied."
}

install_gui_apps() {
  [[ $HEADLESS -eq 1 ]] && { log_info "Headless mode: skipping GUI apps."; return; }
  log_info "Installing GUI apps via Flatpak (system-wide for all users)..."
  flatpak remote-add --if-not-exists --system flathub https://flathub.org/repo/flathub.flatpakrepo || true
  flatpak install -y --system flathub org.onlyoffice.desktopeditors || log_warn "OnlyOffice install failed"
  flatpak install -y --system flathub com.usebottles.bottles || log_warn "Bottles install failed"
  flatpak install -y --system flathub com.github.iiordanov.freerdp-wayland || true
}

install_wayvnc() {
  log_info "Installing WayVNC (for remote Wayland sessions)..."
  apt-get -o Acquire::ForceIPv4=true install -y wayvnc || log_warn "WayVNC install failed"
}

optional_dropbox() {
  [[ $WITH_DROPBOX -eq 1 ]] || { log_info "Dropbox skipped (use --with-dropbox)."; return; }
  log_info "Installing Dropbox via Flatpak (recommended)..."
  flatpak install -y --system flathub com.dropbox.Client || log_warn "Dropbox install failed"
}

optional_ngrok() {
  [[ $WITH_NGROK -eq 1 ]] || { log_info "ngrok skipped (use --with-ngrok)."; return; }
  log_info "Attempting ngrok install via snap (if available)..."
  if command -v snap &>/dev/null; then
    snap install ngrok || log_warn "ngrok snap install failed"
  else
    log_warn "snapd not present; skipping ngrok"
  fi
}

optional_serveo() {
  [[ $WITH_SERVEO -eq 1 ]] || { log_info "Serveo config skipped (use --with-serveo)."; return; }
  log_info "Adding Serveo convenience alias (system-wide)..."
  install -m 755 /dev/stdin /etc/profile.d/serveo.sh <<'EOF'
#!/usr/bin/env bash
alias serveo='ssh -p 2222 -R 80:localhost:80 serveo.net'
EOF
}

optional_rustdesk() {
  [[ $WITH_RUSTDESK -eq 1 ]] || { log_info "RustDesk skipped (use --with-rustdesk)."; return; }
  log_info "Installing RustDesk from official repo..."
  mkdir -p /usr/share/keyrings
  if curl -fsSL https://deb.rustdesk.com/repo.key -o /tmp/rustdesk.key; then
    gpg --dearmor /tmp/rustdesk.key -o /usr/share/keyrings/rustdesk.gpg
    echo "deb [arch=amd64 signed-by=/usr/share/keyrings/rustdesk.gpg] https://deb.rustdesk.com/ stable main" \
      > /etc/apt/sources.list.d/rustdesk.list
    apt-get -o Acquire::ForceIPv4=true update
    if ! apt-get -o Acquire::ForceIPv4=true install -y rustdesk; then
      log_warn "RustDesk repo install failed; attempting direct .deb"
      ARCH=$(dpkg --print-architecture)
      TMPD=$(mktemp -d); cd "$TMPD"
      curl -fL -o rustdesk.deb "https://github.com/rustdesk/rustdesk/releases/latest/download/rustdesk-${ARCH}.deb" \
        && apt-get install -y ./rustdesk.deb || log_warn "RustDesk direct install failed"
      rm -rf "$TMPD"
    fi
    systemctl enable --now rustdesk || true
  else
    log_warn "Failed to fetch RustDesk key; skipping"
  fi
}

verify_hardware() {
  log_info "Verifying key hardware bindings..."
  lspci -nnk | awk '/Network controller/ , /Kernel modules/'
  lspci -nnk | awk '/FaceTime HD|14e4:1570/ , /Kernel modules/' || true
  inxi -Fxz || true
}

fix_printer_issues() {
  log_info "(Optional) CUPS tweaks for Brother printers..."
  apt-get -o Acquire::ForceIPv4=true install -y printer-driver-brlaser printer-driver-c2esp || true
  systemctl restart cups || true
}

analyze_logs() {
  log_info "Scanning logs for errors (last boot)..."
  local REPORT="$SCRIPT_DIR/zorin-log-analysis.txt"
  journalctl -p 3 -b > "$REPORT" || true
  dmesg -T --level=err,crit >> "$REPORT" || true
  grep -qiE "error|fail|unclaimed|denied" "$REPORT" && \
    log_warn "Issues found; see $REPORT" || log_success "No critical errors in logs."
}

cleanup() {
  log_info "Cleaning up..."
  apt-get -o Acquire::ForceIPv4=true autoremove -y || true
  apt-get -o Acquire::ForceIPv4=true clean || true
}

# =====================
#  Main
# =====================
main() {
  check_internet
  apt_update_upgrade
  configure_unattended_upgrades
  setup_ssh_server
  install_security_tools
  configure_firewall_minimal
  install_core_cli
  install_macbook_air_drivers
  install_facetimehd_optional
  power_tweaks
  install_gui_apps
  install_wayvnc
  optional_dropbox
  optional_ngrok
  optional_serveo
  optional_rustdesk
  verify_hardware
  fix_printer_issues
  analyze_logs
  cleanup
  log_success "🎉 Post-install completed. Recommended: reboot the system."
}

main "$@"
