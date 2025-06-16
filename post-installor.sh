#!/usr/bin/env bash
# Zorin Post-Install Script
# Eurobotics 2025 - GNU
# v.20250616.1700

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

# Set locale to C for consistent command output
export LC_ALL=C

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
    apt-get -o Acquire::ForceIPv4=true update && apt-get -o Acquire::ForceIPv4=true full-upgrade -y
    log_success "System updated successfully."
    
    log_info "Configuring automatic updates..."
    apt-get -o Acquire::ForceIPv4=true install -y unattended-upgrades
    dpkg-reconfigure -plow unattended-upgrades
    log_success "Automatic updates configured."
}

function setup_ssh_server() {
    log_info "Setting up OpenSSH Server..."
    
    # Install OpenSSH Server
    apt-get -o Acquire::ForceIPv4=true install -y openssh-server
    
    # Configure SSH - KEEP PASSWORD AUTHENTICATION ENABLED
    sed -i 's/#Port 22/Port 22/' /etc/ssh/sshd_config
    
    # Ensure password authentication is enabled
    sed -i 's/^#\?PasswordAuthentication .*/PasswordAuthentication yes/' /etc/ssh/sshd_config
    
    # Enable SSH service
    systemctl enable ssh
    systemctl restart ssh
    
    # Add SSH port to UFW (if UFW is active)
    if command -v ufw &>/dev/null && ufw status | grep -q active; then
        ufw allow 22/tcp
    fi
    
    log_success "SSH Server installed with password authentication enabled."
    log_warn "For improved security, consider setting up SSH key authentication later."
}

function install_security_tools() {
    log_info "Installing security tools..."
    apt-get -o Acquire::ForceIPv4=true install -y clamav clamav-daemon gufw ufw || log_warn "Partial installation of security tools"
    
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
        22/tcp     # SSH
        2222/tcp   # Serveo alternative port
        80/tcp     # HTTP
        443/tcp    # HTTPS
        3478/tcp   # STUN
        3478/udp
        5353/udp   # mDNS
    )

    # RustDesk ports
    declare -a rustdesk_ports=(
        21115:21117/tcp # RustDesk direct
        21116/udp       # RustDesk NAT traversal
    )

    # Apple ecosystem ports
    declare -a apple_ports=(
        3689/tcp    # iTunes/Apple Music sharing
        548/tcp     # AFP (Apple File Protocol)
        427/udp     # SLP (Service Location Protocol)
        427/tcp
        62078/tcp   # iOS device syncing (USB over IP)
        123/udp     # NTP (Time sync)
    )

    # Add all ports to UFW
    for port in "${ports[@]}" "${rustdesk_ports[@]}" "${apple_ports[@]}"; do
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

function install_ngrok() {
    log_info "Installing Ngrok via snap..."
    
    # Ensure snap is available
    if ! command -v snap &>/dev/null; then
        log_info "Installing snapd"
        apt-get -o Acquire::ForceIPv4=true install -y snapd
    fi
    
    # Check if already installed
    if snap list ngrok 2>/dev/null | grep -q ngrok; then
        log_info "Ngrok already installed via snap"
        return
    fi
    
    # Install ngrok via snap
    if snap install ngrok; then
        log_success "Ngrok installed via snap. Configure with: ngrok config add-authtoken <YOUR_TOKEN>"
    else
        log_warn "Ngrok installation failed via snap"
    fi
}

function install_serveo() {
    log_info "Setting up Serveo.net access..."
    
    # Create SSH config entry
    if ! grep -q "Host serveo" /etc/ssh/ssh_config; then
        echo -e "\n# Serveo.net configuration" >> /etc/ssh/ssh_config
        echo "Host serveo" >> /etc/ssh/ssh_config
        echo "  HostName serveo.net" >> /etc/ssh/ssh_config
        echo "  Port 2222" >> /etc/ssh/ssh_config
        echo "  RemoteForward 80 localhost:80" >> /etc/ssh/ssh_config
        echo "  ExitOnForwardFailure yes" >> /etc/ssh/ssh_config
        echo "  ServerAliveInterval 60" >> /etc/ssh/ssh_config
    fi
    
    # Create alias for all users
    echo "alias serveo='ssh -p 2222 -R 80:localhost:80 serveo'" > /etc/profile.d/serveo.sh
    chmod +x /etc/profile.d/serveo.sh
    
    log_success "Serveo configured. Use: serveo"
}

function install_core_utilities() {
    log_info "Installing core utilities..."
    
    # Install snapd if not present
    if ! command -v snap &>/dev/null; then
        log_info "Installing snapd"
        apt-get -o Acquire::ForceIPv4=true install -y snapd
    fi
    
    # Essential utilities
    apt-get -o Acquire::ForceIPv4=true install -y \
        timeshift \
        wine \
        inxi \
        thonny \
        flatpak \
        unzip \
        curl \
        magic-wormhole \
        python3-pip \
        python3-cryptography || log_warn "Some utilities failed to install"

    # Install Dropbox from official source (adds repo for updates)
    log_info "Installing Dropbox..."
    if ! command -v dropbox &>/dev/null; then
        curl -L -o /tmp/dropbox.deb "https://www.dropbox.com/download?dl=packages/ubuntu/dropbox_2020.03.04_amd64.deb"
        apt-get -o Acquire::ForceIPv4=true install -y /tmp/dropbox.deb
        rm -f /tmp/dropbox.deb
        
        # Ensure repository is added for updates
        if [ ! -f /etc/apt/sources.list.d/dropbox.list ]; then
            echo "deb [arch=i386,amd64] http://linux.dropbox.com/ubuntu $(lsb_release -sc) main" > /etc/apt/sources.list.d/dropbox.list
            apt-key adv --keyserver keyserver.ubuntu.com --recv-keys 1C61A2656FB57B7E4DE0F4C1FC918B335044912E
            apt-get -o Acquire::ForceIPv4=true update
        fi
        log_success "Dropbox installed. It will auto-update via its repository."
    else
        log_info "Dropbox already installed"
    fi

    # Install RustDesk from official repo
    log_info "Installing RustDesk..."
    if ! command -v rustdesk &>/dev/null; then
        # Download GPG key with curl
        curl -sS https://deb.rustdesk.com/repo.key | gpg --dearmor -o /usr/share/keyrings/rustdesk.gpg
        
        # Add repository
        echo "deb [arch=amd64 signed-by=/usr/share/keyrings/rustdesk.gpg] https://deb.rustdesk.com/ stable main" > /etc/apt/sources.list.d/rustdesk.list
        
        # Refresh and install
        apt-get -o Acquire::ForceIPv4=true update
        apt-get -o Acquire::ForceIPv4=true install -y rustdesk
        
        # Enable and start service
        systemctl enable rustdesk
        systemctl start rustdesk
        log_success "RustDesk installed via official repository. Will update with system updates."
    else
        log_info "RustDesk already installed"
    fi

    # Install Bottles via Flatpak
    log_info "Installing Bottles..."
    flatpak install -y --system flathub com.usebottles.bottles || log_warn "Bottles installation failed"

    # Configure Flatpak
    flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo
    
    # Upgrade Python tools and install crypto dependencies
    log_info "Configuring Python environment..."
    pip3 install --upgrade pip wheel
    pip3 install pycryptodome requests cryptography
    
    log_success "Core utilities installed."
}

function install_onlyoffice() {
    log_info "Installing OnlyOffice..."
    if flatpak install -y --system flathub org.onlyoffice.desktopeditors; then
        log_success "OnlyOffice installed."
        remove_libreoffice
    else
        log_warn "OnlyOffice installation failed"
    fi
}

function remove_libreoffice() {
    log_info "Removing LibreOffice suite..."
    
    # List of LibreOffice packages to remove
    local libreoffice_pkgs=(
        libreoffice-base 
        libreoffice-calc 
        libreoffice-core
        libreoffice-draw 
        libreoffice-gnome 
        libreoffice-gtk3 
        libreoffice-help-common 
        libreoffice-help-en-us 
        libreoffice-impress 
        libreoffice-math 
        libreoffice-ogltrans 
        libreoffice-pdfimport 
        libreoffice-style-colibre 
        libreoffice-style-elementary 
        libreoffice-style-tango 
        libreoffice-writer
        libreoffice-common
    )
    
    # Check if any LibreOffice packages are installed
    if dpkg -l | grep -q "libreoffice"; then
        # Purge LibreOffice packages
        apt-get -o Acquire::ForceIPv4=true purge -y "${libreoffice_pkgs[@]}" || log_warn "Some LibreOffice packages couldn't be removed"
        
        # Clean up dependencies
        apt-get -o Acquire::ForceIPv4=true autoremove -y
        log_success "LibreOffice removed and replaced by OnlyOffice"
    else
        log_info "LibreOffice not installed - nothing to remove"
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

function fix_printer_issues() {
    log_info "Fixing printer configuration issues..."
    
    # Fix cups-brf permissions
    if [[ -f /usr/lib/cups/filter/cups-brf ]]; then
        chown root:root /usr/lib/cups/filter/cups-brf
        chmod 755 /usr/lib/cups/filter/cups-brf
    fi
    
    # Restart printing services
    systemctl restart cups
    
    # Install Brother printer drivers
    apt-get -o Acquire::ForceIPv4=true install -y printer-driver-brlaser printer-driver-c2esp
    
    log_info "Reconfiguring printer system..."
    dpkg-reconfigure cups
    
    log_success "Printer issues addressed. Try printing again."
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
    apt-get -o Acquire::ForceIPv4=true autoremove -y
    apt-get -o Acquire::ForceIPv4=true clean
    log_success "Cleanup completed."
}

function main() {
    check_internet
    update_system
    setup_ssh_server
    install_security_tools
    configure_firewall
    install_ngrok
    install_serveo
    install_core_utilities
    install_onlyoffice
    verify_hardware
    fix_printer_issues
    analyze_logs
    cleanup
    log_success "🎉 Post-install completed. Recommended: Reboot system."
}

main
