#!/usr/bin/env bash
# Audit and repair the standard Nextcloud rclone exclude policy on a laptop.
# Designed for Ubuntu/ZorinOS family laptops; originally validated on Robert's Surface Pro 7.
# v.20260627.0006

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

Purpose:
  Audit and repair a laptop Nextcloud rclone mount only.
  Dropbox and other rclone mounts are deliberately out of scope.

Checks:
  - rclone binary location, version, and likely install source
  - rclone config and nextcloud remote presence
  - ~/.config/rclone/nextcloud-excludes.txt presence/content
  - active mounts mentioning nextcloud
  - user systemd services containing nextcloud
  - whether Nextcloud rclone mount services use the standard hardening options
    (--exclude-from, -o x-gvfs-hide, --daemon-timeout 20s, no unsupported WebDAV --poll-interval)
  - stale forbidden files already queued in the Nextcloud rclone VFS cache

Actions:
  - with confirmation, creates ~/.config/rclone/nextcloud-excludes.txt
  - with confirmation, patches writable direct user Nextcloud rclone mount units
    to add the standard exclude and desktop/suspend hardening options
  - with confirmation, removes stale .htaccess/.htpasswd/.user.ini entries from the Nextcloud VFS cache
  - never patches Dropbox or other non-Nextcloud rclone services

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
NEXTCLOUD_SERVICE="nextcloud-rclone.service"
NEXTCLOUD_CACHE_ROOTS=(
    "$HOME/.local/share/rclone/cache/vfs/nextcloud"
    "$HOME/.local/share/rclone/cache/vfsMeta/nextcloud"
)

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

find_stale_forbidden_cache_entries() {
    local root
    for root in "${NEXTCLOUD_CACHE_ROOTS[@]}"; do
        [[ -d "$root" ]] || continue
        find "$root" \( -name '.htaccess' -o -name '.htpasswd' -o -name '.user.ini' \) -print 2>/dev/null
    done
}

delete_stale_forbidden_cache_entries() {
    local root
    for root in "${NEXTCLOUD_CACHE_ROOTS[@]}"; do
        [[ -d "$root" ]] || continue
        find "$root" \( -name '.htaccess' -o -name '.htpasswd' -o -name '.user.ini' \) -delete 2>/dev/null
    done
}

is_nextcloud_service_active() {
    systemctl --user is-active --quiet "$NEXTCLOUD_SERVICE" 2>/dev/null
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

audit_nextcloud_mounts() {
    echo
    log_info "Checking current Nextcloud mounts..."

    if mount | grep -Ei 'nextcloud' >/dev/null 2>&1; then
        mount | grep -Ei 'nextcloud'
    else
        log_warn "No active mount line mentions nextcloud."
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

    if ! grep -Eq 'rclone[[:space:]]+mount[[:space:]]+nextcloud:' "$unit"; then
        rm -f "$tmp"
        log_warn "Refusing to patch non-Nextcloud unit: $unit"
        return 1
    fi

    if ! command -v python3 >/dev/null 2>&1; then
        rm -f "$tmp"
        log_error "python3 is required to safely rewrite a systemd ExecStart line."
    fi

    cp -p "$unit" "$backup"

    python3 - "$unit" > "$tmp" <<'PYSYSTEMD'
import shlex
import sys
from pathlib import Path

unit = Path(sys.argv[1])
lines = unit.read_text().splitlines()

REQUIRED = [
    ["--exclude-from", "%h/.config/rclone/nextcloud-excludes.txt"],
    ["--daemon-timeout", "20s"],
]
REQUIRED_FUSE = ["-o", "x-gvfs-hide"]


def is_execstart_start(line: str) -> bool:
    return line.lstrip().startswith("ExecStart=")


def collect_block(start: int):
    block = [lines[start]]
    i = start
    while block[-1].rstrip().endswith("\\") and i + 1 < len(lines):
        i += 1
        block.append(lines[i])
    return block, i


def block_to_command(block):
    return " ".join(part.rstrip().rstrip("\\").strip() for part in block)


def has_pair(tokens, opt, value):
    return any(tokens[i] == opt and tokens[i + 1] == value for i in range(len(tokens) - 1))


def remove_option_with_value(tokens, opt):
    out = []
    i = 0
    while i < len(tokens):
        if tokens[i] == opt:
            i += 2
        else:
            out.append(tokens[i])
            i += 1
    return out


def render_execstart(tokens):
    prefix = "ExecStart=" + " ".join(shlex.quote(t) for t in tokens[:4])
    rest = tokens[4:]
    if not rest:
        return [prefix]

    grouped = []
    i = 0
    value_options = {
        "--dir-cache-time", "--vfs-cache-mode", "--vfs-cache-max-age",
        "--vfs-cache-max-size", "--cache-dir", "--log-level",
        "--exclude-from", "--daemon-timeout", "-o",
    }
    while i < len(rest):
        if rest[i] in value_options and i + 1 < len(rest):
            grouped.append([rest[i], rest[i + 1]])
            i += 2
        else:
            grouped.append([rest[i]])
            i += 1

    rendered = [prefix + " \\"]
    for idx, group in enumerate(grouped):
        suffix = " \\" if idx < len(grouped) - 1 else ""
        rendered.append("  " + " ".join(shlex.quote(t) for t in group) + suffix)
    return rendered

out = []
i = 0
while i < len(lines):
    line = lines[i]
    if not is_execstart_start(line):
        out.append(line)
        i += 1
        continue

    block, end = collect_block(i)
    command = block_to_command(block)
    if "rclone" not in command or " mount " not in command or "nextcloud:" not in command:
        out.extend(block)
        i = end + 1
        continue

    try:
        _prefix, rhs = command.split("=", 1)
        tokens = shlex.split(rhs)
    except ValueError:
        out.extend(block)
        i = end + 1
        continue

    tokens = remove_option_with_value(tokens, "--poll-interval")

    for opt, value in REQUIRED:
        if not has_pair(tokens, opt, value):
            tokens.extend([opt, value])

    if not has_pair(tokens, "-o", "x-gvfs-hide"):
        tokens.extend(REQUIRED_FUSE)

    out.extend(render_execstart(tokens))
    i = end + 1

print("\n".join(out))
PYSYSTEMD

    if cmp -s "$unit" "$tmp"; then
        rm -f "$tmp"
        log_warn "No patch was applied to $unit. Backup remains at $backup."
        return 1
    fi

    mv "$tmp" "$unit"
    chmod --reference="$backup" "$unit" 2>/dev/null || chmod 644 "$unit"
    log_success "Patched $unit with the standard Nextcloud hardening profile."
    echo "Backup: $backup"
}

unit_has_standard_nextcloud_hardening() {
    local unit="$1"
    local execs
    execs="$(normalize_unit_execstart "$unit" || true)"
    grep -Eq -- '--exclude-from[[:space:]]+.*nextcloud-excludes\.txt' <<<"$execs" \
        && grep -Eq -- '(^|[[:space:]])-o[[:space:]]+x-gvfs-hide([[:space:]]|$)' <<<"$execs" \
        && grep -Eq -- '--daemon-timeout[[:space:]]+20s' <<<"$execs" \
        && ! grep -Eq -- '--poll-interval[[:space:]]+30s' <<<"$execs"
}

audit_nextcloud_user_services() {
    echo
    log_info "Checking systemd user services that mention Nextcloud..."

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
            if grep -Iq . "$unit" && grep -Eiq 'nextcloud' "$unit"; then
                units+=("$unit")
            fi
        done < <(find "$dir" -maxdepth 1 -type f -name '*.service' -print0 2>/dev/null)
    done

    if [[ ${#units[@]} -eq 0 ]]; then
        log_warn "No user service files mentioning Nextcloud were found in common locations."
    fi

    local unit execs script
    for unit in "${units[@]}"; do
        echo
        echo "Service file: $unit"
        normalize_unit_execstart "$unit" | sed 's/^/  /' || true

        if grep -Eq 'rclone[[:space:]]+mount[[:space:]]+nextcloud:' "$unit"; then
            if unit_has_standard_nextcloud_hardening "$unit"; then
                log_success "This direct Nextcloud rclone mount service already uses the standard hardening profile."
            elif [[ "$unit" == "$HOME/.config/systemd/user/"* && -w "$unit" ]]; then
                log_warn "This direct Nextcloud rclone mount service is missing part of the standard hardening profile."
                echo "  Required: --exclude-from nextcloud-excludes.txt, -o x-gvfs-hide, --daemon-timeout 20s, no --poll-interval 30s"
                if [[ -f "$EXCLUDES_FILE" ]] && confirm "Patch this user service with the standard Nextcloud hardening profile?"; then
                    patch_direct_unit "$unit" || true
                    systemctl --user daemon-reload || log_warn "systemctl --user daemon-reload failed."
                    log_warn "Restart the service after reviewing the patch: systemctl --user restart $(basename "$unit")"
                fi
            else
                log_warn "This direct Nextcloud rclone mount service lacks the standard hardening profile but is not a writable user unit."
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
                log_warn "This service mentions Nextcloud but does not contain a direct Nextcloud rclone mount ExecStart."
            fi
        fi
    done

    echo
    log_info "Active user services mentioning Nextcloud:"
    systemctl --user list-units --type=service --all --no-pager 2>/dev/null \
        | grep -Ei 'nextcloud' || log_warn "No active/listed user service mentions Nextcloud."
}

audit_stale_forbidden_vfs_cache() {
    echo
    log_info "Checking stale forbidden files in the Nextcloud rclone VFS cache..."

    local stale_entries
    stale_entries="$(find_stale_forbidden_cache_entries || true)"

    if [[ -z "$stale_entries" ]]; then
        log_success "No stale .htaccess/.htpasswd/.user.ini entries found in the Nextcloud rclone VFS cache."
        return
    fi

    log_warn "Found stale forbidden files in the Nextcloud rclone VFS cache:"
    printf '%s\n' "$stale_entries" | sed 's/^/  /'

    if [[ "$AUDIT_ONLY" -eq 1 ]]; then
        log_warn "Audit-only mode: leaving stale cache entries untouched."
        return
    fi

    if ! confirm "Stop $NEXTCLOUD_SERVICE, remove these stale cache entries, and restart it if it was active?"; then
        log_warn "Leaving stale cache entries untouched."
        return
    fi

    local was_active=0
    if is_nextcloud_service_active; then
        was_active=1
        log_info "Stopping $NEXTCLOUD_SERVICE before cache cleanup..."
        systemctl --user stop "$NEXTCLOUD_SERVICE" || log_warn "Could not stop $NEXTCLOUD_SERVICE cleanly."
    else
        log_info "$NEXTCLOUD_SERVICE is not active; cache cleanup can proceed without stopping it."
    fi

    delete_stale_forbidden_cache_entries

    local remaining
    remaining="$(find_stale_forbidden_cache_entries || true)"
    if [[ -z "$remaining" ]]; then
        log_success "Stale forbidden cache entries removed."
    else
        log_warn "Some stale forbidden cache entries remain:"
        printf '%s\n' "$remaining" | sed 's/^/  /'
    fi

    if [[ "$was_active" -eq 1 ]]; then
        log_info "Restarting $NEXTCLOUD_SERVICE..."
        systemctl --user start "$NEXTCLOUD_SERVICE" || log_warn "Could not restart $NEXTCLOUD_SERVICE."
    fi
}

print_next_steps() {
    echo
    log_info "Recommended next checks on this Ubuntu/ZorinOS laptop:"
    cat <<EOF
  time rclone lsd nextcloud:/
  time rclone lsjson nextcloud:/ --max-depth 1 --fast-list
  time ls -la /media/$USER/nextcloud | head
  systemctl --user cat nextcloud-rclone.service | grep -E 'exclude-from|x-gvfs-hide|daemon-timeout|poll-interval'
  journalctl --user -u nextcloud-rclone.service -n 200 --no-pager
  find ~/.local/share/rclone/cache/vfs/nextcloud ~/.local/share/rclone/cache/vfsMeta/nextcloud -name '.htaccess' -print

If a service was patched:
  systemctl --user restart nextcloud-rclone.service
  systemctl --user status nextcloud-rclone.service --no-pager
EOF
}

main() {
    log_info "Ubuntu/ZorinOS laptop Nextcloud rclone audit for user '$USER' on host '$(hostname)'."
    audit_rclone_binary
    audit_rclone_config
    audit_excludes_file
    audit_nextcloud_mounts
    audit_nextcloud_user_services
    audit_stale_forbidden_vfs_cache
    print_next_steps
    log_success "Nextcloud audit/repair completed."
}

main "$@"
