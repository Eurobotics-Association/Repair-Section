#!/usr/bin/env bash
# Audit and activate the standard Nextcloud rclone exclude policy on a laptop.
# Designed for Robert's Surface Pro 7 Ubuntu setup.
# v.20260627.0001

set -euo pipefail

RED="\e[31m"
GREEN="\e[32m"
YELLOW="\e[33m"
BLUE="\e[34m"
NC="\e[0m"

ASSUME_YES=0
AUDIT_ONLY=0

log_info()    { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[OK]${NC} $1"; }
log_warn()    { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error()   { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

usage() {
    cat <<EOF
Usage: $0 [--yes] [--audit-only]

Checks:
  - rclone binary location, version, and likely install source
  - rclone config and nextcloud remote presence
  - ~/.config/rclone/nextcloud-excludes.txt presence/content
  - active mounts mentioning rclone or nextcloud
  - user systemd services containing rclone
  - whether rclone mount services already use --exclude-from

Actions:
  - with confirmation, creates ~/.config/rclone/nextcloud-excludes.txt
  - with confirmation, patches writable direct user rclone mount units

Options:
  --yes        accept safe remediation prompts
  --audit-only only inspect; do not write anything
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --yes|-y)
            ASSUME_YES=1
            shift
            ;;
        --audit-only)
            AUDIT_ONLY=1
            shift
            ;;
        --help|-h)
            usage
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            ;;
    esac
done

if [[ ${EUID:-$(id -u)} -eq 0 ]]; then
    log_error "Run this as the desktop user, not with sudo. systemd --user belongs to the user session."
fi

RCLONE_CONFIG_DIR="$HOME/.config/rclone"
EXCLUDES_FILE="$RCLONE_CONFIG_DIR/nextcloud-excludes.txt"

confirm() {
    local prompt="$1"

    if [[ "$AUDIT_ONLY" -eq 1 ]]; then
        return 1
    fi
    if [[ "$ASSUME_YES" -eq 1 ]]; then
        return 0
    fi

    local reply
    read -r -p "$prompt [y/N]: " reply
    [[ "$reply" =~ ^[Yy]$ ]]
}

write_excludes_file() {
    mkdir -p "$RCLONE_CONFIG_DIR"
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
    chmod 644 "$EXCLUDES_FILE"
}

audit_rclone_binary() {
    echo
    log_info "Checking rclone binary and install source..."

    if ! command -v rclone >/dev/null 2>&1; then
        log_warn "rclone is not in PATH."
        return
    fi

    local rclone_bin
    rclone_bin="$(command -v rclone)"
    echo "rclone binary : $rclone_bin"
    readlink -f "$rclone_bin" 2>/dev/null | sed 's/^/resolved      : /' || true
    rclone version 2>/dev/null | sed -n '1,6p' || true

    if command -v dpkg >/dev/null 2>&1; then
        local resolved
        resolved="$(readlink -f "$rclone_bin" 2>/dev/null || printf '%s' "$rclone_bin")"
        if dpkg -S "$resolved" >/dev/null 2>&1; then
            log_success "rclone appears to be installed through apt/dpkg."
            dpkg -S "$resolved" | sed 's/^/dpkg owner   : /'
            apt-cache policy rclone 2>/dev/null | sed -n '1,8p' || true
        else
            log_warn "rclone binary is not owned by a dpkg package."
        fi
    fi

    if command -v snap >/dev/null 2>&1 && snap list rclone >/dev/null 2>&1; then
        log_warn "snap also reports an rclone package. Check PATH precedence carefully."
        snap list rclone
    fi
}

audit_rclone_config() {
    echo
    log_info "Checking rclone config and remotes..."

    if [[ -f "$RCLONE_CONFIG_DIR/rclone.conf" ]]; then
        log_success "rclone.conf exists at $RCLONE_CONFIG_DIR/rclone.conf"
    else
        log_warn "No rclone.conf found at $RCLONE_CONFIG_DIR/rclone.conf"
    fi

    if command -v rclone >/dev/null 2>&1; then
        echo "Configured remotes:"
        rclone listremotes 2>/dev/null | sed 's/^/  /' || log_warn "Could not list rclone remotes."
        if rclone listremotes 2>/dev/null | grep -qx 'nextcloud:'; then
            log_success "Remote 'nextcloud:' exists."
        else
            log_warn "Remote 'nextcloud:' was not found."
        fi
    fi
}

audit_excludes_file() {
    echo
    log_info "Checking standard exclude policy..."

    if [[ -f "$EXCLUDES_FILE" ]]; then
        log_success "Exclude file exists: $EXCLUDES_FILE"
        if grep -qxF '**/.htaccess' "$EXCLUDES_FILE" && grep -qxF '**/$RECYCLE.BIN/**' "$EXCLUDES_FILE"; then
            log_success "Exclude file contains the key Nextcloud and desktop metadata rules."
        else
            log_warn "Exclude file exists but may not contain the full standard policy."
            if confirm "Replace it with the standard homelab policy?"; then
                cp -p "$EXCLUDES_FILE" "$EXCLUDES_FILE.bak.$(date +%Y%m%d-%H%M%S)"
                write_excludes_file
                log_success "Exclude file replaced; backup kept next to it."
            fi
        fi
    else
        log_warn "Exclude file is missing: $EXCLUDES_FILE"
        if confirm "Create the standard exclude file now?"; then
            write_excludes_file
            log_success "Exclude file created."
        fi
    fi
}

audit_mounts() {
    echo
    log_info "Checking current mounts..."

    if mount | grep -Ei 'rclone|nextcloud' >/dev/null 2>&1; then
        mount | grep -Ei 'rclone|nextcloud'
    else
        log_warn "No active mount line mentions rclone or nextcloud."
    fi
}

normalize_unit_execstart() {
    local unit="$1"
    awk '
        /^[[:space:]]*ExecStart=/ {
            line=$0
            while (line ~ /\\[[:space:]]*$/ && (getline nextline) > 0) {
                sub(/\\[[:space:]]*$/, " ", line)
                line=line nextline
            }
            print line
        }
    ' "$unit"
}

patch_direct_unit() {
    local unit="$1"
    local backup="$unit.bak.$(date +%Y%m%d-%H%M%S)"
    local tmp
    tmp="$(mktemp)"

    cp -p "$unit" "$backup"

    awk '
        function flush_block(    i) {
            if (has_exclude == 1) {
                for (i = 1; i <= block_count; i++) {
                    print block[i]
                }
            } else if (block_count == 1) {
                print block[1] " --exclude-from %h/.config/rclone/nextcloud-excludes.txt"
                patched=1
            } else {
                for (i = 1; i < block_count; i++) {
                    print block[i]
                }
                print "  --exclude-from %h/.config/rclone/nextcloud-excludes.txt \\"
                print block[block_count]
                patched=1
            }
            block_count=0
            in_exec=0
            has_exclude=0
        }

        BEGIN { in_exec=0; block_count=0; has_exclude=0; patched=0 }

        in_exec == 1 {
            block[++block_count]=$0
            if ($0 ~ /--exclude-from/) {
                has_exclude=1
            }
            if ($0 !~ /\\[[:space:]]*$/) {
                flush_block()
            }
            next
        }

        /^[[:space:]]*ExecStart=.*rclone[[:space:]]+mount/ {
            block[++block_count]=$0
            if ($0 ~ /--exclude-from/) {
                has_exclude=1
            }
            if ($0 ~ /\\[[:space:]]*$/) {
                in_exec=1
            } else {
                flush_block()
            }
            next
        }

        { print }

        END {
            if (in_exec == 1) {
                flush_block()
            }
        }
    ' "$unit" > "$tmp"

    if cmp -s "$unit" "$tmp"; then
        rm -f "$tmp"
        log_warn "No patch was applied to $unit. Backup remains at $backup."
        return 1
    fi

    mv "$tmp" "$unit"
    chmod --reference="$backup" "$unit" 2>/dev/null || chmod 644 "$unit"
    log_success "Patched $unit"
    echo "Backup: $backup"
}

audit_user_services() {
    echo
    log_info "Checking systemd user services that mention rclone..."

    local service_dirs=(
        "$HOME/.config/systemd/user"
        "/etc/systemd/user"
        "/usr/lib/systemd/user"
        "/lib/systemd/user"
    )
    local units=()
    local dir

    for dir in "${service_dirs[@]}"; do
        [[ -d "$dir" ]] || continue
        while IFS= read -r -d '' unit; do
            if grep -Iq . "$unit" && grep -Eq 'rclone|nextcloud' "$unit"; then
                units+=("$unit")
            fi
        done < <(find "$dir" -maxdepth 1 -type f -name '*.service' -print0 2>/dev/null)
    done

    if [[ ${#units[@]} -eq 0 ]]; then
        log_warn "No user service files mentioning rclone or nextcloud were found in common locations."
    fi

    local unit execs script
    for unit in "${units[@]}"; do
        echo
        echo "Service file: $unit"
        normalize_unit_execstart "$unit" | sed 's/^/  /' || true

        if grep -Eq 'rclone[[:space:]]+mount' "$unit"; then
            if grep -Eq -- '--exclude-from[[:space:]]+.*nextcloud-excludes\.txt' "$unit"; then
                log_success "This direct rclone mount service already uses the standard exclude file."
            elif [[ "$unit" == "$HOME/.config/systemd/user/"* && -w "$unit" ]]; then
                log_warn "This direct rclone mount service does not use --exclude-from."
                if [[ -f "$EXCLUDES_FILE" ]] && confirm "Patch this user service to add the standard exclude file?"; then
                    patch_direct_unit "$unit" || true
                    systemctl --user daemon-reload || log_warn "systemctl --user daemon-reload failed."
                    log_warn "Restart the service after reviewing the patch: systemctl --user restart $(basename "$unit")"
                fi
            else
                log_warn "This direct rclone mount service lacks --exclude-from but is not a writable user unit."
            fi
        else
            execs="$(normalize_unit_execstart "$unit" || true)"
            script="$(printf '%s\n' "$execs" | sed -nE 's/.*ExecStart=([^ ]*\/[^ ]*\.(sh|bash))($| .*)/\1/p' | head -n 1)"
            if [[ -n "$script" ]]; then
                log_warn "This service appears to call a script. Inspect and adjust the script if it runs rclone:"
                echo "  $script"
                if [[ -r "$script" ]]; then
                    grep -nE 'rclone|exclude-from|nextcloud' "$script" || true
                fi
            else
                log_warn "This service mentions rclone/nextcloud but does not contain a direct rclone mount ExecStart."
            fi
        fi
    done

    echo
    log_info "Active user services mentioning rclone or nextcloud:"
    systemctl --user list-units --type=service --all --no-pager 2>/dev/null \
        | grep -Ei 'rclone|nextcloud' || log_warn "No active/listed user service mentions rclone or nextcloud."
}

print_next_steps() {
    echo
    log_info "Recommended next checks on Surface 7:"
    cat <<EOF
  time rclone lsd nextcloud:/
  time rclone lsjson nextcloud:/ --max-depth 1 --fast-list
  time ls -la /media/$USER/nextcloud | head
  journalctl --user -u nextcloud-rclone.service -n 200 --no-pager

If a service was patched:
  systemctl --user restart nextcloud-rclone.service
  systemctl --user status nextcloud-rclone.service --no-pager
EOF
}

main() {
    log_info "Surface 7 Nextcloud rclone audit for user '$USER' on host '$(hostname)'."
    audit_rclone_binary
    audit_rclone_config
    audit_excludes_file
    audit_mounts
    audit_user_services
    print_next_steps
    log_success "Audit completed."
}

main "$@"
