#!/usr/bin/env bash
# Zorin Post-Install Script

# Eurobotics 2025 - GNU
# post-installor.sh 
# v.20250615.1928

set -euo pipefail
LOGFILE="/var/log/zorin-postinstall.log"
exec > >(tee -a "$LOGFILE") 2>&1

# --- Terminal Colors ---
RED="\e[31m"
GREEN="\e[32m"
YELLOW="\e[33m"
BLUE="\e[34m"
NC="\e[0m" # No Color

function log_info()    { echo -e "${BLUE}[INFO]${NC} $1"; }
function log_success() { echo -e "${GREEN}[OK]${NC} $1"; }
function log_warn()    { echo -e "${YELLOW}[WARN]${NC} $1"; }
function log_error()   { echo -e "${RED}[ERROR]${NC} $1"; }

function update_system() {
    log_info "Updating package lists and upgrading system..."
    apt update && apt full-upgrade -y
    log_success "System updated successfully."
    log_info "Installing unattended-upgrades..."
    apt install -y unattended-upgrades
    log_success "Unattended-upgrades installed."
}

function install_security_tools() {
    log_info "Installing ClamAV and GUFW..."
    apt install -y clamav clamav-daemon gufw ufw || log_error "Failed to install ClamAV/GUFW/UFW."
    systemctl enable clamav-freshclam
    systemctl start clamav-freshclam
    log_success "ClamAV and GUFW installed and configured."
}

function configure_firewall() {
    if ! command -v ufw &> /dev/null; then
        log_error "UFW is not installed. Aborting firewall configuration."
        return
    fi

    log_info "Checking existing UFW rules..."
    ufw status verbose || true

    read -p "Do you want to override current UFW rules with recommended configuration? (y/N): " -r
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_warn "UFW configuration aborted by user."
        return
    fi

    log_info "Applying UFW configuration..."
    ufw --force reset
    ufw default deny incoming
    ufw default allow outgoing
    log_success "UFW firewall configured and enabled."
}

function install_core_utilities() {
    log_info "Installing core utilities..."
    apt install -y p7zip-full p7zip-rar timeshift \
                   dropbox wine bottles rustdesk inxi flatpak software-properties-common || log_error "Some core utilities failed to install."
    log_success "Core utilities installed."
}
}

function install_onlyoffice() {
    log_info "Installing OnlyOffice Desktop Editors via Flatpak..."
    if flatpak install -y --system flathub org.onlyoffice.desktopeditors; then
        log_success "OnlyOffice installed."
    else
        log_warn "OnlyOffice may already be installed or installation failed."
    fi
}

function install_development_tools() {
    log_info "Installing Thonny Python IDE..."
    apt install -y thonny
    log_success "Thonny installed."
}

function verify_hardware() {
    log_info "Checking for missing drivers or unclaimed hardware..."
    ubuntu-drivers list
    inxi -Fxzc0 | grep -i unclaimed && log_warn "Some devices may be unclaimed." || log_success "No unclaimed devices found."
}

function analyze_logs() {
    log_info "Analyzing system logs for errors..."
    LOG_REPORT="/var/log/zorin-log-analysis.txt"
    journalctl -p 3 -xb > "$LOG_REPORT"
    dmesg --level=err,crit,alert,emerg >> "$LOG_REPORT"

    if grep -qiE "error|fail|unreachable|critical" "$LOG_REPORT"; then
        log_warn "Issues found in system logs. See $LOG_REPORT"
    else
        log_success "No critical issues found in system logs."
    fi
}

function report_guest_session() {
    log_info "Checking guest login session status..."
    CURRENT_SESSION=$(loginctl show-session $(loginctl | awk '/\*/ {print $1}') -p Type 2>/dev/null | cut -d= -f2)
    if [[ "$CURRENT_SESSION" == "wayland" || "$CURRENT_SESSION" == "x11" ]]; then
        log_info "Current session is $CURRENT_SESSION. LightDM guest login check skipped."
    else
        log_warn "Unable to determine session type or not using Wayland/X11."
    fi
}

function main() {
    update_system
    install_security_tools
    configure_firewall
    install_core_utilities
    install_onlyoffice
    install_development_tools
    verify_hardware
    analyze_logs
    report_guest_session
    log_success "🎉 Zorin post-install routine completed."
}

main
