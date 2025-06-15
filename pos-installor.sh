#!/usr/bin/env bash
# Zorin Post-Install Script
# Eurobotics 2025 - GNU
# v.20250616.0930

set -euo pipefail
trap 'log_error "Script interrupted. Exiting..."; exit 1' INT TERM

LOGFILE="/var/log/zorin-postinstall.log"
exec > >(tee -a "$LOGFILE") 2>&1

# --- Terminal Colors ---
RED="\e[31m"
GREEN="\e[32m"
YELLOW="\e[33m"
BLUE="\e[34m"
NC="\e[0m"

function log_info()    { echo -e "${BLUE}[INFO]${NC} $1"; }
function log_success() { echo -e "${GREEN}[OK]${NC} $1"; }
function log_warn()    { echo -e "${YELLOW}[WARN]${NC} $1"; }
function log_error()   { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

# Validate root privileges
if [[ $EUID -ne 0 ]]; then
    log_error "This script must be run as root. Use: sudo $0"
fi

# Check internet connectivity
function check_internet() {
    log_info "Verifying internet connection..."
    if ! ping -c 1 -W 3 google.com &>/dev/null; then
        log_error "No internet connection. Exiting."
    fi
    log_success "Internet connection verified"
}

function update_system() {
    log_info "Updating package lists and upgrading system..."
    apt update && apt full-upgrade -y
    log_success "System updated successfully."
    
    log_info "Configuring automatic updates..."
    apt install -y unattended-upgrades
    dpkg-reconfigure -plow unattended-upgrades
    log_success "Automatic updates configured."
}

function install_security_tools() {
    log_info "Installing security tools..."
    apt install -y clamav clamav-daemon gufw ufw || log_warn "Partial installation of security tools"
    
    systemctl enable --now clamav-freshclam
    log_success "Security tools installed."
}

function configure_firewall() {
    if ! command -v ufw &>/dev/null; then
        log_warn "UFW not installed. Skipping firewall setup."
        return
    fi

    log_info "Current UFW rules:"
    ufw status verbose || true

    read -rp "Override UFW rules with recommended configuration? (y/N): " -n 1 reply
    echo
    if [[ ! $reply =~ ^[Yy]$ ]]; then
        log_warn "Firewall configuration aborted by user."
        return
    fi

    log_info "Configuring UFW firewall..."
    ufw --force reset
    ufw default deny incoming
    ufw default allow outgoing

    # Essential ports (safe defaults)
    declare -a ports=(
        80/tcp     # HTTP
        443/tcp    # HTTPS
        22/tcp     # SSH
        3478/tcp   # STUN
        3478/udp
        5353/udp   # mDNS
    )

    for port in "${ports[@]}"; do
        ufw allow "$port"
    done

    # Optional IoT ports (disabled by default)
    read -rp "Enable Alexa/Google Home ports? (security risk) [y/N]: " -n 1 iot_reply
    echo
    if [[ $iot_reply =~ ^[Yy]$ ]]; then
        log_warn "Opening IoT device ports - security risk!"
        ufw allow 4070/tcp    # Alexa streaming
        ufw allow 33434/udp   # Alexa/TuneIn
        ufw allow 40317/udp   # Alexa
        ufw allow 49317/udp   # Alexa
        ufw allow 8123/tcp    # Home Assistant
    fi

    ufw --force enable
    log_success "Firewall configured and enabled."
}

function install_core_utilities() {
    log_info "Installing core utilities..."
    
    # Essential utilities that might be missing
    apt install -y \
        timeshift \
        dropbox \
        wine \
        bottles \
        rustdesk \
        inxi \
        thonny || log_warn "Some utilities failed to install"

    # Ensure Flatpak is configured
    if ! command -v flatpak &>/dev/null; then
        log_warn "Flatpak not found - installing"
        apt install -y flatpak
    fi
    flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo
    
    log_success "Core utilities installed."
}

function install_onlyoffice() {
    log_info "Installing OnlyOffice..."
    if flatpak install -y --system flathub org.onlyoffice.desktopeditors; then
        log_success "OnlyOffice installed."
    else
        log_warn "OnlyOffice installation failed"
    fi
}

function verify_hardware() {
    log_info "Checking hardware drivers..."
    ubuntu-drivers list
    
    log_info "Scanning for unclaimed hardware..."
    if inxi -Fxz | grep -qi "unclaimed"; then
        log_warn "Unclaimed hardware detected. Check drivers:"
        inxi -Fxz | grep -i "unclaimed"
    else
        log_success "No unclaimed hardware found."
    fi
}

function analyze_logs() {
    log_info "Checking system logs for errors..."
    local LOG_REPORT="/var/log/zorin-log-analysis.txt"
    journalctl -p 3 -b --since "1 hour ago" > "$LOG_REPORT"
    dmesg -T --level=err,crit >> "$LOG_REPORT"

    if grep -qPi "error|fail|unclaimed|denied" "$LOG_REPORT"; then
        log_warn "Issues found in system logs. See $LOG_REPORT"
    else
        log_success "No critical errors found in logs."
    fi
}

function cleanup() {
    log_info "Performing system cleanup..."
    apt autoremove -y
    apt clean
    log_success "Cleanup completed."
}

function main() {
    check_internet
    update_system
    install_security_tools
    configure_firewall
    install_core_utilities
    install_onlyoffice
    verify_hardware
    analyze_logs
    cleanup
    log_success "🎉 Post-install completed. Recommended: Reboot system."
}

main
