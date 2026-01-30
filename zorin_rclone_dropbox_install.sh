#!/usr/bin/env bash
# zorin_rclone_dropbox_install_patched.sh
# Eurobotics – Zorin OS rclone+Dropbox user-mounted setup (patched 2026-01-30)
#
# This version fixes three field issues:
#   1) Ensures the rclone log directory (~/.local/share/rclone) exists.
#   2) Warns clearly about missing FUSE 'user_allow_other' without changing /etc/fuse.conf.
#   3) Emphasizes that the rclone remote label MUST be configured consistently
#      across machines for Dropbox Business / Team root to appear identically.

set -euo pipefail

###############################################
# Configurable defaults (ADAPT TO YOUR NEEDS) #
###############################################

# rclone remote name (must already exist in `rclone config`)
# For Dropbox Business, it is strongly recommended to use the SAME label
# and SAME rclone config (rclone.conf) across machines that must see the
# same Business / Team root.
My_rclone_dpbx_label="${My_rclone_dpbx_label:-dropbox}"

# Local mount folder
My_Dropbox_Folder="${My_Dropbox_Folder:-"$HOME/Dropbox-V"}"

# Fixed user service name (per admin convention)
SYSTEMD_USER_SERVICE_NAME="dropbox-rclone.service"

# Non-interactive mode flag
ASSUME_YES=false

###############################################
# Helper functions                           #
###############################################

log_info()  { printf "[INFO ] %s\n" "$*"; }
log_warn()  { printf "[WARN ] %s\n" "$*" >&2; }
log_error() { printf "[ERROR] %s\n" "$*" >&2; }

usage() {
  cat <<EOF
zorin_rclone_dropbox_install_patched.sh - Install user-scoped rclone+Dropbox mount on Zorin OS

This script:
  - Checks that rclone and FUSE are installed
  - Checks that the rclone remote exists
  - Creates the mount folder and the rclone log directory
  - Writes a systemd user unit named 'dropbox-rclone.service'
  - Enables and starts the user service

It does NOT:
  - Install rclone or FUSE
  - Run 'rclone config' or create the Dropbox remote
  - Modify /etc/fuse.conf

Environment variables (optional, override defaults):
  My_rclone_dpbx_label   rclone remote name (default: dropbox)
  My_Dropbox_Folder      mount folder (default: \$HOME/Dropbox-V)

Options:
  -y, --yes    Run non-interactively (assume yes)
  -h, --help   Show this help
EOF
}

###############################################
# Argument parsing                            #
###############################################

while [[ "${1-}" != "" ]]; do
  case "$1" in
    -y|--yes)
      ASSUME_YES=true
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      log_error "Unknown option: $1"
      usage
      exit 1
      ;;
  esac
done

###############################################
# Pre-flight checks                          #
###############################################

if [[ "$EUID" -eq 0 ]]; then
  log_error "Do not run this script as root. Run it as the target user (the Dropbox owner)."
  exit 1
fi

if ! command -v systemctl >/dev/null 2>&1; then
  log_error "systemctl not found. This script requires systemd (Zorin/Ubuntu with systemd)."
  exit 1
fi

if ! systemctl --user show >/dev/null 2>&1; then
  log_warn "systemd user instance not fully available yet. If this runs from a non-graphical shell, make sure user systemd is running."
fi

log_info "Using rclone remote label     : ${My_rclone_dpbx_label}"
log_info "Using local mount folder      : ${My_Dropbox_Folder}"
log_info "Systemd user service name     : ${SYSTEMD_USER_SERVICE_NAME}"

log_warn "For Dropbox Business: ensure the remote '${My_rclone_dpbx_label}' is configured with the correct account and scopes."
log_warn "If a different remote or config is used compared to another machine, you may only see personal space instead of the Business / Team root."

if [[ "$ASSUME_YES" = false ]]; then
  printf "\nThese values will be used. Continue? [y/N] "
  read -r ans || ans="n"
  case "$ans" in
    y|Y|yes|YES)
      ;;
    *)
      log_info "Aborted by user. No changes made."
      exit 0
      ;;
  esac
fi

log_info "Checking prerequisites (rclone, FUSE)..."

if ! command -v rclone >/dev/null 2>&1; then
  log_error "rclone is not installed. Please install rclone and configure your Dropbox remote before re-running this script."
  exit 1
fi

if ! command -v fusermount3 >/dev/null 2>&1 && ! command -v fusermount >/dev/null 2>&1; then
  log_error "FUSE (fusermount/fusermount3) not found. Please install fuse3 (or equivalent) before re-running this script."
  exit 1
fi

log_info "Checking that rclone remote '${My_rclone_dpbx_label}' exists..."
if ! rclone config show "${My_rclone_dpbx_label}" >/dev/null 2>&1; then
  log_error "rclone remote '${My_rclone_dpbx_label}' not found. Run 'rclone config' and create it, then re-run this script."
  exit 1
fi

log_info "Checking FUSE 'user_allow_other' (for --allow-other)..."
if ! grep -Eq '^[[:space:]]*user_allow_other' /etc/fuse.conf 2>/dev/null; then
  log_warn "'/etc/fuse.conf' does not contain 'user_allow_other'. --allow-other may fail until you enable it manually."
  log_warn "Edit /etc/fuse.conf as root and uncomment or add 'user_allow_other', then restart the service if needed."
fi

###############################################
# Create mount & log directories             #
###############################################

log_info "Creating mount directory: ${My_Dropbox_Folder}"
mkdir -p "${My_Dropbox_Folder}"

RCLONE_LOG_DIR="$HOME/.local/share/rclone"
log_info "Ensuring rclone log directory exists: ${RCLONE_LOG_DIR}"
mkdir -p "${RCLONE_LOG_DIR}"

###############################################
# Generate systemd user unit                 #
###############################################

SYSTEMD_USER_DIR="$HOME/.config/systemd/user"
UNIT_PATH="${SYSTEMD_USER_DIR}/${SYSTEMD_USER_SERVICE_NAME}"

log_info "Ensuring systemd user dir exists: ${SYSTEMD_USER_DIR}"
mkdir -p "${SYSTEMD_USER_DIR}"

log_info "Writing systemd user unit: ${UNIT_PATH}"

NM_ONLINE_PATH="$(command -v nm-online 2>/dev/null || true)"

{
  echo "[Unit]"
  echo "Description=Rclone mount for Dropbox (user scoped, rclone label = ${My_rclone_dpbx_label})"
  echo "After=default.target"
  echo
  echo "[Service]"
  echo "Type=notify"
  if [[ -n "${NM_ONLINE_PATH}" ]]; then
    echo "ExecStartPre=${NM_ONLINE_PATH} -x -q -t 30"
  else
    echo "# nm-online not found; consider installing network-manager for robust network-waiting"
  fi
  echo "ExecStartPre=/usr/bin/mkdir -p ${My_Dropbox_Folder}"
  echo "ExecStartPre=/usr/bin/mkdir -p ${RCLONE_LOG_DIR}"
  echo
  echo "ExecStart=/usr/bin/rclone mount ${My_rclone_dpbx_label}: ${My_Dropbox_Folder} \\" 
  echo "  --vfs-cache-mode=full \\" 
  echo "  --vfs-cache-max-size=2G \\" 
  echo "  --vfs-read-chunk-size=32M \\" 
  echo "  --vfs-read-chunk-size-limit=512M \\" 
  echo "  --buffer-size=16M \\" 
  echo "  --dir-cache-time=1h \\" 
  echo "  --poll-interval=30s \\" 
  echo "  --timeout=1m \\" 
  echo "  --retries=5 \\" 
  echo "  --low-level-retries=10 \\" 
  echo "  --umask=022 \\" 
  echo "  --allow-other \\" 
  echo "  --log-file=${RCLONE_LOG_DIR}/dropbox-mount.log \\" 
  echo "  --log-level=INFO"
  echo
  echo "Restart=always"
  echo "RestartSec=10"
  echo
  echo "[Install]"
  echo "WantedBy=default.target"
} >"${UNIT_PATH}"

log_info "Systemd user unit created." 

###############################################
# Enable and start user service              #
###############################################

log_info "Reloading systemd user units..."
systemctl --user daemon-reload

log_info "Enabling user service: ${SYSTEMD_USER_SERVICE_NAME}"
systemctl --user enable "${SYSTEMD_USER_SERVICE_NAME}" >/dev/null

log_info "Starting user service: ${SYSTEMD_USER_SERVICE_NAME}"
if ! systemctl --user start "${SYSTEMD_USER_SERVICE_NAME}"; then
  log_error "Failed to start ${SYSTEMD_USER_SERVICE_NAME}. Check 'journalctl --user -u ${SYSTEMD_USER_SERVICE_NAME}' for details."
  exit 1
fi

log_info "Service started. Current status:"
systemctl --user status "${SYSTEMD_USER_SERVICE_NAME}" --no-pager --lines=10 || true

cat <<EOF

============================================================
Installation finished.

- rclone remote      : ${My_rclone_dpbx_label}
- Mount folder       : ${My_Dropbox_Folder}
- User service       : ${SYSTEMD_USER_SERVICE_NAME}

Remember:
- This is a USER-level service: use 'systemctl --user ...' to manage it.
- It will NOT appear in 'sudo service'.
- To inspect logs:  journalctl --user -u ${SYSTEMD_USER_SERVICE_NAME}

If you want the service to start even without GUI login, consider:
  loginctl enable-linger "${USER}"

For Dropbox Business:
- Ensure all machines that must see the same Team/Business root share a consistent rclone remote configuration (same label, same rclone.conf).
============================================================
EOF
