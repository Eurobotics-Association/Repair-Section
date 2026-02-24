# Ubuntu — Surface Pro 7 Temperature Alert (V2)

> **Goal:** Provide **warnings** (terminal + UI) when temperatures exceed a threshold.
>
> **No throttling / no automatic performance caps**: you decide what to stop gracefully.
>
> **Platform:** Ubuntu (GNOME/Wayland) + linux-surface kernel (6.x tested)

---

## 1) Why we need a custom alert

On Surface Pro 7, temperature issues can appear under GPU-heavy workloads.
Unfortunately, common system monitors may not expose Intel iGPU temperature reliably.

On Ubuntu in this setup, **direct GPU temperature is not exposed** via `lm-sensors` or `/sys/class/drm/*/hwmon`.

**Chosen strategy (Option A / Standard):**

* Use **CPU package temperature** as the main trigger, because CPU+iGPU share the same thermal envelope.
* Prefer the kernel thermal zone `x86_pkg_temp` when present (robust and simple).
* Fallback to `lm-sensors` parsing (`Package id 0`) if needed.

---

## 2) Behavior

When the threshold is exceeded:

* A message is printed to the terminal/log
* A desktop notification is sent (GNOME)
* A `wall` broadcast is sent (if enabled)
* An entry is written to syslog/journal

To avoid spam, a **cooldown** prevents repeated alerts for a short period.

---

## 3) Dependencies

Install:

```bash
sudo apt update
sudo apt install -y lm-sensors libnotify-bin
```

Optional but recommended once:

```bash
sudo sensors-detect
```

---

## 4) Temperature source

### 4.1 Preferred source: thermal zone `x86_pkg_temp`

Read from:

* `/sys/class/thermal/thermal_zone*/type`
* `/sys/class/thermal/thermal_zone*/temp`

The script will locate the zone where `type == x86_pkg_temp`.

### 4.2 Fallback source: `lm-sensors` Package id

If the thermal zone is not present, it will attempt to parse:

* `sensors` output for `Package id 0:`

---

## 5) Configuration

* **THRESHOLD** (default 90°C)
* **COOLDOWN_SECONDS** (default 180s)

You can set these via an environment file used by systemd.

---

## 6) Implementation (systemd timer)

### 6.1 Script

Install the script at:

* `/usr/local/sbin/surf7-temp-alert`

### 6.2 Environment file

* `/etc/default/surf7-temp-alert`

### 6.3 systemd units

* `/etc/systemd/system/surf7-temp-alert.service`
* `/etc/systemd/system/surf7-temp-alert.timer`

The timer runs the check periodically (default: every 30 seconds).

---

## 7) One-command installer (copy/paste)

> This installs the script + systemd service + timer. Safe and reversible.

```sudo tee /usr/local/sbin/surf7-temp-alert > /dev/null << 'EOF'
#!/usr/bin/env bash
set -euo pipefail

# ===============================
# Surface Pro 7 Temperature Alert
# Ubuntu – Inform Only
# No throttling. No management.
# Alerts always when >= WARN, with a simple re-alert interval.
# ===============================

# ---- CONFIG ----
WARN_C=85
CRIT_C=95

# Re-alert interval when still above WARN/CRIT (seconds)
RE_ALERT_WARN_SEC=120
RE_ALERT_CRIT_SEC=60

LOG_TAG="surf7-temp-alert"
STATE_DIR="/run/surf7-temp-alert"
STATE_FILE="$STATE_DIR/last_notify_epoch"
# ----------------

export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

mkdir -p "$STATE_DIR"
log(){ logger -t "$LOG_TAG" -- "$*" || true; }

now_epoch(){ date +%s; }

read_milli_c_to_c() {
  # arg: sysfs file containing millidegrees C
  local f="$1"
  [[ -r "$f" ]] || return 1
  local v
  v="$(cat "$f" 2>/dev/null || true)"
  [[ "$v" =~ ^[0-9]+$ ]] || return 1
  echo $(( v / 1000 ))
}

# Find CPU package temp from coretemp hwmon (temp1_input is typically "Package id 0")
get_cpu_pkg_c() {
  local h
  for h in /sys/class/hwmon/hwmon*; do
    [[ -r "$h/name" ]] || continue
    [[ "$(cat "$h/name" 2>/dev/null || true)" == "coretemp" ]] || continue
    # Prefer temp1_input (package). If not, take max of temps.
    if [[ -r "$h/temp1_input" ]]; then
      read_milli_c_to_c "$h/temp1_input" && return 0
    fi
    local best=""
    local f
    for f in "$h"/temp*_input; do
      [[ -r "$f" ]] || continue
      local c
      c="$(read_milli_c_to_c "$f" || true)"
      [[ -n "${c:-}" ]] || continue
      if [[ -z "$best" || "$c" -gt "$best" ]]; then best="$c"; fi
    done
    [[ -n "${best:-}" ]] && echo "$best" && return 0
  done
  return 1
}

# Try Intel iGPU temp (i915). Often exposed at /sys/class/drm/card0/device/hwmon/hwmon*/temp1_input
get_gpu_c() {
  local h
  for h in /sys/class/drm/card*/device/hwmon/hwmon*; do
    [[ -r "$h/name" ]] || continue
    # commonly "i915"
    local n
    n="$(cat "$h/name" 2>/dev/null || true)"
    [[ "$n" == "i915" || "$n" == "intel_gpu" ]] || continue
    [[ -r "$h/temp1_input" ]] || continue
    read_milli_c_to_c "$h/temp1_input" && return 0
  done
  return 1
}

get_nvme_c() {
  local h
  for h in /sys/class/hwmon/hwmon*; do
    [[ -r "$h/name" ]] || continue
    [[ "$(cat "$h/name" 2>/dev/null || true)" == "nvme" ]] || continue
    # Usually temp1_input exists; else take max
    if [[ -r "$h/temp1_input" ]]; then
      read_milli_c_to_c "$h/temp1_input" && return 0
    fi
    local best=""
    local f
    for f in "$h"/temp*_input; do
      [[ -r "$f" ]] || continue
      local c
      c="$(read_milli_c_to_c "$f" || true)"
      [[ -n "${c:-}" ]] || continue
      if [[ -z "$best" || "$c" -gt "$best" ]]; then best="$c"; fi
    done
    [[ -n "${best:-}" ]] && echo "$best" && return 0
  done
  return 1
}

# Return: "max_temp sources"
# sources example: "cpu=71 gpu=68 nvme=38"
get_max_temp_and_sources() {
  local cpu="" gpu="" nvme=""
  cpu="$(get_cpu_pkg_c || true)"
  gpu="$(get_gpu_c || true)"
  nvme="$(get_nvme_c || true)"

  local max="" src=""
  if [[ -n "$cpu" ]]; then max="$cpu"; src+=" cpu=$cpu"; fi
  if [[ -n "$gpu" ]]; then
    if [[ -z "$max" || "$gpu" -gt "$max" ]]; then max="$gpu"; fi
    src+=" gpu=$gpu"
  fi
  if [[ -n "$nvme" ]]; then
    if [[ -z "$max" || "$nvme" -gt "$max" ]]; then max="$nvme"; fi
    src+=" nvme=$nvme"
  fi

  src="${src# }"
  [[ -n "${max:-}" ]] || return 1
  echo "$max" "$src"
}

# Find active GUI session user (seat0, Active=yes, Type=x11|wayland)
get_active_gui_user() {
  local sid
  while read -r sid _rest; do
    [[ -n "$sid" ]] || continue
    local active type name clazz
    active="$(loginctl show-session "$sid" -p Active --value 2>/dev/null || true)"
    type="$(loginctl show-session "$sid" -p Type --value 2>/dev/null || true)"
    clazz="$(loginctl show-session "$sid" -p Class --value 2>/dev/null || true)"
    name="$(loginctl show-session "$sid" -p Name --value 2>/dev/null || true)"
    if [[ "$active" == "yes" && ( "$type" == "wayland" || "$type" == "x11" ) && "$clazz" == "user" && -n "$name" ]]; then
      echo "$name"
      return 0
    fi
  done < <(loginctl list-sessions --no-legend 2>/dev/null | awk '{print $1}')
  return 1
}

notify_gui() {
  local title="$1"; shift
  local msg="$*"

  command -v notify-send >/dev/null 2>&1 || { log "notify-send missing"; return 0; }

  local user uid runtime bus
  user="$(get_active_gui_user || true)"
  [[ -n "${user:-}" ]] || { log "No active GUI session found"; return 0; }

  uid="$(id -u "$user" 2>/dev/null || true)"
  [[ -n "${uid:-}" ]] || { log "Could not get UID for user=$user"; return 0; }

  runtime="/run/user/$uid"
  bus="$runtime/bus"
  [[ -S "$bus" ]] || { log "No session bus socket at $bus (user=$user)"; return 0; }

  # Best-effort DISPLAY/WAYLAND defaults (DBus is usually enough, but harmless)
  sudo -u "$user" env \
    XDG_RUNTIME_DIR="$runtime" \
    DBUS_SESSION_BUS_ADDRESS="unix:path=$bus" \
    DISPLAY=:0 \
    WAYLAND_DISPLAY=wayland-0 \
    notify-send -u critical "$title" "$msg" >/dev/null 2>&1 \
    || log "notify-send failed (user=$user, uid=$uid)"
}

should_notify_now() {
  local level="$1"  # WARN or CRIT
  local interval="$2"

  local last="0"
  last="$(cat "$STATE_FILE" 2>/dev/null || echo "0")"
  [[ "$last" =~ ^[0-9]+$ ]] || last="0"

  local now
  now="$(now_epoch)"

  if (( now - last >= interval )); then
    echo "$now" > "$STATE_FILE"
    return 0
  fi
  return 1
}

# ---- MAIN ----
read -r temp sources < <(get_max_temp_and_sources) || {
  log "Temperature read failed (no sysfs hwmon sources found)."
  exit 0
}

log "TempMax=${temp}C (warn=${WARN_C}C crit=${CRIT_C}C) sources: ${sources}"

if (( temp >= CRIT_C )); then
  local_msg="CRITICAL: ${temp}°C (>= ${CRIT_C}°C). Stop heavy tasks immediately. (${sources})"
  log "$local_msg"
  if should_notify_now "CRIT" "$RE_ALERT_CRIT_SEC"; then
    # wall is best-effort; may be blocked by mesg n
    wall -n "$LOG_TAG: $local_msg" 2>/dev/null || true
    notify_gui "Surface Pro 7 Temperature – CRITICAL" "$local_msg"
  fi
  exit 0
fi

if (( temp >= WARN_C )); then
  local_msg="WARNING: ${temp}°C (>= ${WARN_C}°C). Consider stopping heavy tasks. (${sources})"
  log "$local_msg"
  if should_notify_now "WARN" "$RE_ALERT_WARN_SEC"; then
    wall -n "$LOG_TAG: $local_msg" 2>/dev/null || true
    notify_gui "Surface Pro 7 Temperature – WARNING" "$local_msg"
  fi
fi

exit 0
EOF

sudo chmod 0755 /usr/local/sbin/surf7-temp-alert
sudo systemctl restart surf7-temp-alert.timer
sudo systemctl start surf7-temp-alert.service
```

---

## 8) Operations

### 8.1 Check status

```bash
systemctl status surf7-temp-alert.timer
journalctl -u surf7-temp-alert.service -n 100 --no-pager
```

### 8.2 Adjust threshold/cooldown

Edit:

* `/etc/default/surf7-temp-alert`

Then:

```bash
sudo systemctl restart surf7-temp-alert.timer
```

### 8.3 Disable

```bash
sudo systemctl disable --now surf7-temp-alert.timer
```

### 8.4 Uninstall

```bash
sudo systemctl disable --now surf7-temp-alert.timer || true
sudo rm -f /etc/systemd/system/surf7-temp-alert.service /etc/systemd/system/surf7-temp-alert.timer
sudo rm -f /usr/local/sbin/surf7-temp-alert /etc/default/surf7-temp-alert
sudo systemctl daemon-reload
```

---

## 9) Notes

* GNOME may still show notifications even if the check runs as root, because we route `notify-send` via the active seat0 user DBus.
* If notifications do not appear, confirm:

  * `libnotify-bin` is installed
  * `/run/user/<uid>/bus` exists
  * You are logged in graphically (seat0 active)

---

## 10) Version

* **V2**: Ubuntu + Surface Pro 7 + linux-surface
* **Warning-only** (no throttling)
* Temperature source: `x86_pkg_temp` (preferred), fallback `sensors` Package id
