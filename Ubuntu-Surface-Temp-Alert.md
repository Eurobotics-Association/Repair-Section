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

```bash
bash -lc 'set -euo pipefail

sudo -v
sudo apt update
sudo apt install -y lm-sensors libnotify-bin

# 1) Script
sudo tee /usr/local/sbin/surf7-temp-alert >/dev/null <<"SH"
#!/usr/bin/env bash
set -euo pipefail

THRESHOLD="${THRESHOLD:-90}"            # °C
COOLDOWN_SECONDS="${COOLDOWN_SECONDS:-180}"
STATE_FILE="/run/surf7-temp-alert.last"

log(){ logger -t surf7-temp-alert "$*" || true; }

now_epoch(){ date +%s; }

cooldown_ok(){
  local now last
  now="$(now_epoch)"
  last="0"
  [[ -f "$STATE_FILE" ]] && last="$(cat "$STATE_FILE" 2>/dev/null || echo 0)"
  # ok if enough time elapsed
  (( now - last >= COOLDOWN_SECONDS ))
}

set_cooldown(){
  now_epoch > "$STATE_FILE" 2>/dev/null || true
}

# Return temperature in millidegrees C if possible
read_pkg_temp_millic(){
  # Preferred: thermal zone type x86_pkg_temp
  local z typefile tempfile
  for z in /sys/class/thermal/thermal_zone*; do
    typefile="$z/type"; tempfile="$z/temp"
    [[ -r "$typefile" && -r "$tempfile" ]] || continue
    if [[ "$(cat "$typefile" 2>/dev/null || true)" == "x86_pkg_temp" ]]; then
      cat "$tempfile" 2>/dev/null || true
      return 0
    fi
  done

  # Fallback: sensors parse Package id 0
  # sensors returns something like: "Package id 0:  +72.0°C"
  if command -v sensors >/dev/null 2>&1; then
    LC_ALL=C sensors 2>/dev/null | awk '/^Package id 0:/ {gsub(/[^0-9.]/,"",$4); if($4!="") printf("%d\n", $4*1000); exit}' || true
    return 0
  fi

  return 1
}

millic="$(read_pkg_temp_millic || true)"
if [[ -z "$millic" ]]; then
  echo "surf7-temp-alert: could not read package temperature" >&2
  log "could not read package temperature"
  exit 0
fi

# Convert to integer °C
c=$(( millic / 1000 ))

if (( c >= THRESHOLD )); then
  if cooldown_ok; then
    msg="SURFACE7 TEMP WARNING: package ${c}°C (threshold ${THRESHOLD}°C)"
    echo "$msg"
    log "$msg"

    # Terminal broadcast (optional; depends on wall permissions)
    wall "$msg" 2>/dev/null || true

    # GNOME notification (Wayland OK when systemd user session exists; we run as root but call notify-send as active user)
    # Find active seat0 user
    active_user=""
    active_user="$(loginctl list-sessions --no-legend 2>/dev/null | awk '$3=="seat0" && $5=="yes" {print $2; exit}')"
    if [[ -n "$active_user" ]]; then
      uid="$(id -u "$active_user" 2>/dev/null || echo "")"
      if [[ -n "$uid" && -S "/run/user/$uid/bus" ]]; then
        # Run notify-send in the user context with DBUS
        runuser -u "$active_user" -- env DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$uid/bus" \
          notify-send -u critical "Surface Pro 7 temperature" "$msg" 2>/dev/null || true
      fi
    fi

    set_cooldown
  fi
fi
SH
sudo chmod 0755 /usr/local/sbin/surf7-temp-alert

# 2) Default config
sudo tee /etc/default/surf7-temp-alert >/dev/null <<"CFG"
# Threshold in °C
THRESHOLD=90

# Cooldown between notifications (seconds)
COOLDOWN_SECONDS=180
CFG
sudo chmod 0644 /etc/default/surf7-temp-alert

# 3) systemd service
sudo tee /etc/systemd/system/surf7-temp-alert.service >/dev/null <<"UNIT"
[Unit]
Description=Surface Pro 7 Temperature Alert (warning only)

[Service]
Type=oneshot
EnvironmentFile=-/etc/default/surf7-temp-alert
ExecStart=/usr/local/sbin/surf7-temp-alert
UNIT
sudo chmod 0644 /etc/systemd/system/surf7-temp-alert.service

# 4) systemd timer
sudo tee /etc/systemd/system/surf7-temp-alert.timer >/dev/null <<"TIMER"
[Unit]
Description=Run Surface Pro 7 Temperature Alert periodically

[Timer]
OnBootSec=45s
OnUnitActiveSec=30s
AccuracySec=5s
Unit=surf7-temp-alert.service

[Install]
WantedBy=timers.target
TIMER
sudo chmod 0644 /etc/systemd/system/surf7-temp-alert.timer

sudo systemctl daemon-reload
sudo systemctl enable --now surf7-temp-alert.timer

echo "Installed. Check status with: systemctl status surf7-temp-alert.timer"
'
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
