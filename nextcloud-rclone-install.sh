#!/usr/bin/env bash
# Nextcloud rclone mount installer for Ubuntu 24.04 and ZorinOS laptops
# Scope: Nextcloud only. This script must not modify Dropbox or other rclone services.
# Eurobotics 2026 - GNU
# v.20260821.0001

set -euo pipefail

RED="\e[31m"
GREEN="\e[32m"
YELLOW="\e[33m"
BLUE="\e[34m"
NC="\e[0m"

LOGFILE="/var/log/nextcloud-rclone-install.log"
NEXTCLOUD_REMOTE="nextcloud"
NEXTCLOUD_SERVICE="nextcloud-rclone.service"
NEXTCLOUD_EXCLUDES_NAME="nextcloud-excludes.txt"
NEXTCLOUD_RESTART_SCRIPT="restart-nextcloud-rclone.sh"
NEXTCLOUD_RESTART_DESKTOP="restart-nextcloud-rclone.desktop"
NEXTCLOUD_RESTART_ICON="nextcloud-rclone-restart.svg"
mkdir -p "$(dirname "$LOGFILE")"
exec > >(tee -a "$LOGFILE") 2>&1

trap 'echo -e "${RED}[ERROR]${NC} Script interrupted."; exit 1' INT TERM

log_info()    { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[OK]${NC} $1"; }
log_warn()    { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error()   { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

require_root() {
    [[ ${EUID:-$(id -u)} -eq 0 ]] || log_error "This script must be run as root. Use: sudo $0"
}

check_os() {
    if [[ -r /etc/os-release ]]; then
        . /etc/os-release
        local os_id="${ID:-unknown}"
        local os_like="${ID_LIKE:-}"
        local pretty="${PRETTY_NAME:-$os_id}"
        case "$os_id" in
            ubuntu)
                if [[ "${VERSION_ID:-}" != "24.04" ]]; then
                    log_warn "Detected $pretty. This script is validated on Ubuntu 24.04; continue only if you accept testing on this Ubuntu version."
                else
                    log_success "Detected supported OS: $pretty."
                fi
                ;;
            zorin)
                log_success "Detected ZorinOS: $pretty. Treating it as Ubuntu-family for the Nextcloud rclone mount."
                log_warn "ZorinOS desktop behaviour can differ from stock Ubuntu; validate file dialogs and suspend/resume after install."
                ;;
            *)
                if [[ "$os_like" == *ubuntu* || "$os_like" == *debian* ]]; then
                    log_warn "Detected Ubuntu/Debian-like OS: $pretty. Script may work, but is validated only for Ubuntu 24.04 and ZorinOS."
                else
                    log_warn "Detected OS ID='$os_id'. This script is intended for Ubuntu 24.04 or ZorinOS."
                fi
                ;;
        esac
    else
        log_warn "/etc/os-release not found. Cannot verify OS."
    fi
}

check_internet() {
    log_info "Checking internet connectivity..."
    if ping -c 1 -W 3 1.1.1.1 >/dev/null 2>&1 || ping -c 1 -W 3 google.com >/dev/null 2>&1; then
        log_success "Internet connectivity verified."
    else
        log_error "No working internet connection detected."
    fi
}

apt_install_deps() {
    export DEBIAN_FRONTEND=noninteractive
    log_info "Installing required packages..."
    apt-get update
    apt-get install -y rclone gvfs-backends fuse3 libnotify-bin
    log_success "Required packages installed."
}

ensure_fuse_conf() {
    log_info "Ensuring /etc/fuse.conf allows user_allow_other..."
    touch /etc/fuse.conf
    if grep -Eq '^[[:space:]]*user_allow_other[[:space:]]*$' /etc/fuse.conf; then
        log_success "user_allow_other already enabled in /etc/fuse.conf."
        return
    fi
    if grep -Eq '^[[:space:]]*#.*user_allow_other' /etc/fuse.conf; then
        sed -i 's/^[[:space:]]*#\s*user_allow_other\s*$/user_allow_other/' /etc/fuse.conf
    else
        printf '\nuser_allow_other\n' >> /etc/fuse.conf
    fi
    grep -Eq '^[[:space:]]*user_allow_other[[:space:]]*$' /etc/fuse.conf || log_error "Failed to enable user_allow_other in /etc/fuse.conf"
    log_success "user_allow_other enabled in /etc/fuse.conf."
}

get_candidate_users() {
    awk -F: '($3 >= 1000 && $1 != "nobody") { print $1 }' /etc/passwd |
        while read -r user; do
            local home shell
            home=$(getent passwd "$user" | cut -d: -f6)
            shell=$(getent passwd "$user" | cut -d: -f7)
            [[ -d "$home" ]] || continue
            [[ "$shell" =~ (false|nologin)$ ]] && continue
            echo "$user"
        done
}

detect_target_user() {
    local detected=""
    if [[ -n "${SUDO_USER:-}" && "${SUDO_USER}" != "root" ]]; then
        detected="$SUDO_USER"
    else
        detected=$(loginctl list-users --no-legend 2>/dev/null | awk '$1 >= 1000 {print $2; exit}') || true
    fi
    local candidates=()
    mapfile -t candidates < <(get_candidate_users)
    [[ ${#candidates[@]} -gt 0 ]] || log_error "No suitable non-system users detected."
    echo
    log_info "Candidate desktop users detected: ${candidates[*]}"
    if [[ -n "$detected" ]]; then
        read -r -p "Detected target user '${detected}'. Is this correct? [Y/n]: " reply
        reply=${reply:-Y}
        if [[ "$reply" =~ ^[Yy]$ ]]; then
            TARGET_USER="$detected"
            return
        fi
    fi
    read -r -p "Enter target username: " TARGET_USER
    [[ -n "${TARGET_USER:-}" ]] || log_error "No username provided."
}

validate_target_user() {
    id "$TARGET_USER" >/dev/null 2>&1 || log_error "User '$TARGET_USER' does not exist."
    [[ "$TARGET_USER" != "root" ]] || log_error "Refusing to install for root."
    TARGET_UID=$(id -u "$TARGET_USER")
    TARGET_GID=$(id -g "$TARGET_USER")
    TARGET_HOME=$(getent passwd "$TARGET_USER" | cut -d: -f6)
    TARGET_SHELL=$(getent passwd "$TARGET_USER" | cut -d: -f7)
    [[ -n "$TARGET_HOME" && -d "$TARGET_HOME" ]] || log_error "Home directory for '$TARGET_USER' not found."
    [[ ! "$TARGET_SHELL" =~ (false|nologin)$ ]] || log_error "User '$TARGET_USER' does not have a valid login shell."
    log_success "Using target user '$TARGET_USER' (uid=$TARGET_UID gid=$TARGET_GID home=$TARGET_HOME)."
}

prepare_directories() {
    MOUNT_ROOT="/media/$TARGET_USER"
    MOUNT_DIR="$MOUNT_ROOT/nextcloud"
    TECH_ROOT="/mnt/$TARGET_USER"
    TECH_PATH="$TECH_ROOT/nextcloud"
    USER_SYSTEMD_DIR="$TARGET_HOME/.config/systemd/user"
    RCLONE_CONFIG_DIR="$TARGET_HOME/.config/rclone"
    EXCLUDES_FILE="$RCLONE_CONFIG_DIR/$NEXTCLOUD_EXCLUDES_NAME"
    CACHE_DIR="$TARGET_HOME/.local/share/rclone/cache"
    USER_BIN_DIR="$TARGET_HOME/.local/bin"
    USER_ICON_DIR="$TARGET_HOME/.local/share/icons/hicolor/scalable/apps"
    USER_DESKTOP_DIR=$(sudo -H -u "$TARGET_USER" bash -lc 'xdg-user-dir DESKTOP 2>/dev/null || printf "%s/Desktop" "$HOME"')
    [[ -n "$USER_DESKTOP_DIR" ]] || USER_DESKTOP_DIR="$TARGET_HOME/Desktop"

    log_info "Creating mount, service, icon, and launcher directories..."
    mkdir -p "$MOUNT_ROOT" "$MOUNT_DIR" "$TECH_ROOT" "$USER_SYSTEMD_DIR" "$RCLONE_CONFIG_DIR" "$CACHE_DIR" "$USER_BIN_DIR" "$USER_ICON_DIR" "$USER_DESKTOP_DIR"
    chown "$TARGET_UID:$TARGET_GID" "$MOUNT_ROOT" "$MOUNT_DIR" "$TECH_ROOT" "$USER_SYSTEMD_DIR" "$RCLONE_CONFIG_DIR" "$CACHE_DIR" "$USER_BIN_DIR" "$USER_ICON_DIR" "$USER_DESKTOP_DIR"
    chmod 755 "$MOUNT_ROOT" "$MOUNT_DIR" "$TECH_ROOT" "$USER_BIN_DIR" "$USER_ICON_DIR" "$USER_DESKTOP_DIR"
    if [[ -L "$TECH_PATH" || -e "$TECH_PATH" ]]; then
        if [[ -L "$TECH_PATH" ]]; then
            local current_target
            current_target=$(readlink -f "$TECH_PATH" || true)
            if [[ "$current_target" != "$MOUNT_DIR" ]]; then
                rm -f "$TECH_PATH"
                ln -s "$MOUNT_DIR" "$TECH_PATH"
            fi
        elif [[ -d "$TECH_PATH" && -z "$(ls -A "$TECH_PATH" 2>/dev/null || true)" ]]; then
            rmdir "$TECH_PATH"
            ln -s "$MOUNT_DIR" "$TECH_PATH"
        else
            log_warn "$TECH_PATH already exists and is not a removable empty directory/symlink. Leaving it unchanged."
        fi
    else
        ln -s "$MOUNT_DIR" "$TECH_PATH"
    fi
    chown -h "$TARGET_UID:$TARGET_GID" "$TECH_PATH" 2>/dev/null || true
    log_success "Directories prepared."
}

write_rclone_excludes() {
    log_info "Writing homelab Nextcloud rclone exclude policy to $EXCLUDES_FILE ..."
    cat > "$EXCLUDES_FILE" <<'EOF'
# Nextcloud / WebDAV reserved or desktop-generated files.
# Reuse with: --exclude-from ~/.config/rclone/nextcloud-excludes.txt
**/.htaccess
**/.htpasswd
**/.user.ini

# macOS metadata.
**/.DS_Store
**/.Spotlight-V100/**
**/.TemporaryItems/**

# Windows metadata and recycle bin folders.
**/Thumbs.db
**/desktop.ini
**/$RECYCLE.BIN/**

# Linux / desktop trash folders.
**/.Trash-*/
EOF
    chown "$TARGET_UID:$TARGET_GID" "$EXCLUDES_FILE"
    chmod 644 "$EXCLUDES_FILE"
    log_success "rclone exclude policy written."
}

write_service_unit() {
    SERVICE_FILE="$USER_SYSTEMD_DIR/$NEXTCLOUD_SERVICE"
    log_info "Writing systemd user service to $SERVICE_FILE ..."
    cat > "$SERVICE_FILE" <<EOF
[Unit]
Description=Rclone mount for Nextcloud (user scoped)
Wants=network-online.target
After=network-online.target

[Service]
Type=simple
ExecStartPre=/usr/bin/bash -lc 'command -v nm-online >/dev/null 2>&1 && nm-online -q -t 30 || true'
ExecStartPre=/usr/bin/mkdir -p /media/%u/nextcloud
ExecStartPre=/usr/bin/mkdir -p %h/.local/share/rclone/cache
ExecStart=/usr/bin/rclone mount ${NEXTCLOUD_REMOTE}:/ /media/%u/nextcloud \
  --allow-other \
  --dir-cache-time 5m \
  --poll-interval 0 \
  --vfs-cache-mode writes \
  --vfs-cache-max-age 24h \
  --vfs-cache-max-size 10G \
  --cache-dir %h/.local/share/rclone/cache \
  --exclude-from %h/.config/rclone/${NEXTCLOUD_EXCLUDES_NAME} \
  --daemon-timeout 20s \
  --log-level INFO
Restart=on-failure
RestartSec=20
ExecStop=/bin/fusermount3 -uz /media/%u/nextcloud

[Install]
WantedBy=default.target
EOF
    chown "$TARGET_UID:$TARGET_GID" "$SERVICE_FILE"
    chmod 644 "$SERVICE_FILE"
    log_success "Service unit written."
}

write_restart_launcher() {
    RESTART_SCRIPT="$USER_BIN_DIR/$NEXTCLOUD_RESTART_SCRIPT"
    RESTART_ICON="$USER_ICON_DIR/$NEXTCLOUD_RESTART_ICON"
    RESTART_DESKTOP="$USER_DESKTOP_DIR/$NEXTCLOUD_RESTART_DESKTOP"

    log_info "Writing Nextcloud restart helper script, icon, and desktop launcher..."

    cat > "$RESTART_SCRIPT" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

SERVICE="nextcloud-rclone.service"
MOUNT="/media/$USER/nextcloud"

notify() {
  if command -v notify-send >/dev/null 2>&1; then
    notify-send "Nextcloud rclone" "$1"
  fi
}

notify "Restarting Nextcloud rclone mount..."

systemctl --user stop "$SERVICE" || true
sleep 1
fusermount3 -uz "$MOUNT" 2>/dev/null || true
sleep 1
systemctl --user daemon-reload
systemctl --user start "$SERVICE"
sleep 2

if systemctl --user is-active --quiet "$SERVICE"; then
  notify "Nextcloud rclone restarted successfully."
  xdg-open "$MOUNT" >/dev/null 2>&1 || true
  exit 0
else
  notify "Nextcloud rclone restart failed. Check journalctl."
  systemctl --user status "$SERVICE" --no-pager
  exit 1
fi
EOF

    cat > "$RESTART_ICON" <<'EOF'
<svg xmlns="http://www.w3.org/2000/svg" width="128" height="128" viewBox="0 0 128 128">
  <defs>
    <linearGradient id="bg" x1="0" y1="0" x2="1" y2="1">
      <stop offset="0%" stop-color="#0082c9"/>
      <stop offset="100%" stop-color="#005f95"/>
    </linearGradient>
  </defs>
  <circle cx="64" cy="64" r="60" fill="url(#bg)"/>
  <circle cx="46" cy="64" r="14" fill="white"/>
  <circle cx="64" cy="64" r="20" fill="white"/>
  <circle cx="82" cy="64" r="14" fill="white"/>
  <circle cx="46" cy="64" r="7" fill="#0082c9"/>
  <circle cx="82" cy="64" r="7" fill="#0082c9"/>
  <circle cx="64" cy="64" r="10" fill="#0082c9"/>
  <path d="M88 35 A38 38 0 1 0 102 64" fill="none" stroke="white" stroke-width="8" stroke-linecap="round"/>
  <path d="M88 23 L106 35 L86 45 Z" fill="white"/>
  <rect x="39" y="91" width="50" height="12" rx="4" fill="white" opacity="0.95"/>
  <rect x="47" y="96" width="34" height="2.5" rx="1" fill="#0082c9"/>
</svg>
EOF

    cat > "$RESTART_DESKTOP" <<EOF
[Desktop Entry]
Type=Application
Name=Restart Nextcloud rclone
Comment=Stop, lazy-unmount, and restart the Nextcloud rclone mount
Exec=$RESTART_SCRIPT
Icon=nextcloud-rclone-restart
Terminal=true
Categories=Utility;System;
EOF

    chown "$TARGET_UID:$TARGET_GID" "$RESTART_SCRIPT" "$RESTART_ICON" "$RESTART_DESKTOP"
    chmod 755 "$RESTART_SCRIPT"
    chmod 644 "$RESTART_ICON"
    chmod 755 "$RESTART_DESKTOP"

    sudo -H -u "$TARGET_USER" gio set "$RESTART_DESKTOP" metadata::trusted true 2>/dev/null || true
    sudo -H -u "$TARGET_USER" gtk-update-icon-cache "$TARGET_HOME/.local/share/icons/hicolor" 2>/dev/null || true

    log_success "Nextcloud restart launcher written: $RESTART_DESKTOP"
}

ensure_linger() {
    if command -v loginctl >/dev/null 2>&1; then
        log_info "Ensuring linger is enabled for user '$TARGET_USER'..."
        loginctl enable-linger "$TARGET_USER" >/dev/null 2>&1 || log_warn "Could not enable linger for '$TARGET_USER'. User service should still work when user is logged in."
    fi
}

run_as_target_user() { sudo -H -u "$TARGET_USER" bash -lc "$1"; }

check_remote_exists() {
    if run_as_target_user "rclone listremotes 2>/dev/null | grep -qx '${NEXTCLOUD_REMOTE}:'"; then
        log_success "rclone remote '$NEXTCLOUD_REMOTE' already exists for user '$TARGET_USER'."
        REMOTE_EXISTS=1
    else
        log_warn "rclone remote '$NEXTCLOUD_REMOTE' is not yet configured for user '$TARGET_USER'."
        REMOTE_EXISTS=0
    fi
}

enable_service_if_possible() {
    log_info "Reloading and enabling the user systemd service..."
    run_as_target_user 'systemctl --user daemon-reload' && log_success "User systemd daemon reloaded." || log_warn "Could not reload systemd user daemon automatically."
    run_as_target_user "systemctl --user enable $NEXTCLOUD_SERVICE" && log_success "User service enabled." || log_warn "Could not enable user service automatically."
    if [[ "$REMOTE_EXISTS" -eq 1 ]]; then
        run_as_target_user "systemctl --user restart $NEXTCLOUD_SERVICE" && log_success "User service started/restarted." || log_warn "Could not start the user service automatically."
    else
        log_warn "Service not started because the rclone remote is not configured yet."
    fi
}

print_post_install() {
    cat <<EOF

============================================================
Nextcloud rclone mount installation completed
============================================================
Target user      : $TARGET_USER
User home        : $TARGET_HOME
Mount path       : $MOUNT_DIR
Technical path   : $TECH_PATH
Service file     : $SERVICE_FILE
Exclude policy   : $EXCLUDES_FILE
Restart helper   : $RESTART_SCRIPT
Desktop launcher : $RESTART_DESKTOP
Log file         : $LOGFILE

Create/validate the remote as the target user:
  sudo -u $TARGET_USER -H bash -lc 'rclone config'
  sudo -u $TARGET_USER -H bash -lc 'rclone lsd nextcloud:/'

Service profile:
  --dir-cache-time 5m
  --exclude-from %h/.config/rclone/nextcloud-excludes.txt
  --daemon-timeout 20s
  --poll-interval 0

Note: -o x-gvfs-hide is deliberately NOT used because Ubuntu apt rclone 1.60.x reports:
  -o/--option not supported with this FUSE backend

Start or restart mount:
  sudo -u $TARGET_USER -H bash -lc 'systemctl --user restart nextcloud-rclone.service'

Desktop restart launcher:
  Use the "Restart Nextcloud rclone" icon on the desktop.
  If the desktop asks, right-click it and choose "Allow Launching".

Check logs:
  sudo -u $TARGET_USER -H bash -lc 'journalctl --user -u nextcloud-rclone.service -n 200 --no-pager'
============================================================
EOF
}

main() {
    require_root
    check_os
    check_internet
    apt_install_deps
    ensure_fuse_conf
    detect_target_user
    validate_target_user
    echo
    read -r -p "Proceed with installation for user '$TARGET_USER'? [Y/n]: " proceed
    proceed=${proceed:-Y}
    [[ "$proceed" =~ ^[Yy]$ ]] || log_error "Installation cancelled by user."
    prepare_directories
    write_rclone_excludes
    write_service_unit
    write_restart_launcher
    ensure_linger
    check_remote_exists
    enable_service_if_possible
    print_post_install
    log_success "Installer completed successfully."
}

main "$@"
