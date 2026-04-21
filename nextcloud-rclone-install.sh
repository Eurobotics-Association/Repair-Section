#!/usr/bin/env bash
# Nextcloud rclone mount installer for Ubuntu 24.04
# Eurobotics 2026 - GNU
# v.20260421.0001

set -euo pipefail

RED="\e[31m"
GREEN="\e[32m"
YELLOW="\e[33m"
BLUE="\e[34m"
NC="\e[0m"

LOGFILE="/var/log/nextcloud-rclone-install.log"
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
        if [[ "${ID:-}" != "ubuntu" ]]; then
            log_warn "Detected OS ID='${ID:-unknown}'. This script is intended for Ubuntu 24.04."
        fi
        if [[ "${VERSION_ID:-}" != "24.04" ]]; then
            log_warn "Detected Ubuntu version '${VERSION_ID:-unknown}'. This script was designed for Ubuntu 24.04."
        fi
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
    awk -F: '($3 >= 1000 && $1 != "nobody") { print $1 }' /etc/passwd \
        | while read -r user; do
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
    CACHE_DIR="$TARGET_HOME/.local/share/rclone/cache"

    log_info "Creating mount and service directories..."

    mkdir -p "$MOUNT_ROOT" "$MOUNT_DIR" "$TECH_ROOT" "$USER_SYSTEMD_DIR" "$CACHE_DIR"
    chown "$TARGET_UID:$TARGET_GID" "$MOUNT_ROOT" "$MOUNT_DIR" "$TECH_ROOT" "$USER_SYSTEMD_DIR" "$CACHE_DIR"
    chmod 755 "$MOUNT_ROOT" "$MOUNT_DIR" "$TECH_ROOT"

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

write_service_unit() {
    SERVICE_FILE="$USER_SYSTEMD_DIR/nextcloud-rclone.service"

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
ExecStart=/usr/bin/rclone mount nextcloud:/ /media/%u/nextcloud \
  --allow-other \
  --dir-cache-time 72h \
  --poll-interval 30s \
  --vfs-cache-mode writes \
  --vfs-cache-max-age 24h \
  --vfs-cache-max-size 10G \
  --cache-dir %h/.local/share/rclone/cache \
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

ensure_linger() {
    if command -v loginctl >/dev/null 2>&1; then
        log_info "Ensuring linger is enabled for user '$TARGET_USER'..."
        loginctl enable-linger "$TARGET_USER" >/dev/null 2>&1 || log_warn "Could not enable linger for '$TARGET_USER'. User service should still work when user is logged in."
    fi
}

run_as_target_user() {
    local cmd="$1"
    sudo -H -u "$TARGET_USER" bash -lc "$cmd"
}

check_remote_exists() {
    if run_as_target_user 'rclone listremotes 2>/dev/null | grep -qx "nextcloud:"'; then
        log_success "rclone remote 'nextcloud' already exists for user '$TARGET_USER'."
        REMOTE_EXISTS=1
    else
        log_warn "rclone remote 'nextcloud' is not yet configured for user '$TARGET_USER'."
        REMOTE_EXISTS=0
    fi
}

enable_service_if_possible() {
    log_info "Reloading and enabling the user systemd service..."

    if run_as_target_user 'systemctl --user daemon-reload'; then
        log_success "User systemd daemon reloaded."
    else
        log_warn "Could not reload systemd user daemon automatically."
    fi

    if run_as_target_user 'systemctl --user enable nextcloud-rclone.service'; then
        log_success "User service enabled."
    else
        log_warn "Could not enable user service automatically."
    fi

    if [[ "$REMOTE_EXISTS" -eq 1 ]]; then
        if run_as_target_user 'systemctl --user restart nextcloud-rclone.service'; then
            log_success "User service started/restarted."
        else
            log_warn "Could not start the user service automatically."
        fi
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
Log file         : $LOGFILE

Next step for the target user:

  sudo -u $TARGET_USER -H bash -lc 'rclone config'

Create a remote with:
  name    : nextcloud
  type    : webdav
  vendor  : nextcloud
  url     : https://<your-nextcloud-host>/remote.php/dav/files/<username>/

Recommended:
  Use a Nextcloud app password rather than the main account password.

Validate remote:
  sudo -u $TARGET_USER -H bash -lc 'rclone lsd nextcloud:/'

Start or restart mount:
  sudo -u $TARGET_USER -H bash -lc 'systemctl --user restart nextcloud-rclone.service'

Check service status:
  sudo -u $TARGET_USER -H bash -lc 'systemctl --user status nextcloud-rclone.service'

Check recent logs:
  sudo -u $TARGET_USER -H bash -lc 'journalctl --user -u nextcloud-rclone.service -n 200 --no-pager'

If the mount becomes stale:
  fusermount3 -uz $MOUNT_DIR || true
  sudo -u $TARGET_USER -H bash -lc 'systemctl --user restart nextcloud-rclone.service'
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
    write_service_unit
    ensure_linger
    check_remote_exists
    enable_service_if_possible
    print_post_install
    log_success "Installer completed successfully."
}

main "$@"
