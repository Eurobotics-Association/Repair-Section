# Surface Pro 7 – Thermal Monitoring & Alert System (Linux Mint Cinnamon)

## Executive Summary

This document describes a **working, reproducible, minimal** CPU temperature alert system for:

* Microsoft Surface Pro 7
* Linux Mint (Cinnamon)
* OEM / Ubuntu-based kernels
* French locale systems (comma decimal separator)

The goal is:

* ✅ Notify user when CPU reaches 90°C
* ✅ Desktop notification (Cinnamon)
* ✅ `wall` broadcast to logged-in terminals
* ❌ No automatic throttling
* ❌ No governor modification

This guide includes all issues encountered and why they happened, so another human or AI can recreate the setup quickly and correctly.

---

# 1️⃣ Why thermald Did Not Work

On this Surface Pro 7:

```
NO RAPL sysfs present
Thermal DTS: No coretemp sysfs found
Thermal DTS or hwmon: No Zones present
```

Meaning:

* Firmware does not expose proper thermal zones
* RAPL power interface unavailable
* thermald has nothing to control

Conclusion:

✔ thermald runs
✖ thermald does not manage thermals on this hardware

Therefore a user-space monitoring script is required.

---

# 2️⃣ Major Issues Encountered (And Root Causes)

## Issue A — Locale Decimal Separator (CRITICAL)

System locale was French.

`sensors` output used comma decimals:

```
+57,0°C
```

Bash arithmetic does not accept commas:

```
(( 57,0 >= 90 ))   → syntax failure
```

Because `set -e` was enabled, the script exited silently before triggering.

### Fix

Force C locale and output an **integer temperature**:

```
LC_ALL=C sensors ...
printf "%d\n", int(max+0.5)
```

Never rely on floating point or locale-sensitive parsing.

---

## Issue B — mawk vs gawk Compatibility

Mint uses `mawk` by default.

`match(..., ..., array)` is not portable across awk implementations.

This caused syntax errors in earlier versions.

### Fix

Use simple field extraction (`$4`) instead of regex capture arrays.

---

## Issue C — Environment Variable Override Not Working

Earlier script hard-coded:

```
THRESHOLD=90
```

So test overrides like:

```
sudo THRESHOLD=0 script.sh
```

did nothing.

### Fix

Use default-from-env pattern:

```
THRESHOLD="${THRESHOLD:-90}"
```

---

## Issue D — `wall` Behavior Misunderstood

`wall` does NOT send to “all open terminal windows”.

It sends to:

* Logged-in TTY sessions listed in `who`
* Only if `mesg y`

Graphical desktop sessions (tty7) are single controlling TTYs.

Terminal emulator windows are not separate login sessions.

Conclusion:

`wall` works correctly, but only for logged-in sessions.

We keep `wall` as intended Unix behavior.

---

## Issue E — systemd + DBus Context

Desktop notifications work only if:

* DBUS_SESSION_BUS_ADDRESS is set
* XDG_RUNTIME_DIR is correct
* notify-send runs as the logged-in user

The script explicitly switches to the seat0 user via `runuser`.

---

# 3️⃣ Final Working Script

Location:

```
/usr/local/bin/temp-alert.sh
```

```bash
#!/bin/bash
set -euo pipefail

THRESHOLD="${THRESHOLD:-90}"
COOLDOWN_SECONDS="${COOLDOWN_SECONDS:-120}"
STATE_FILE="/run/temp-alert.last"

ACTIVE_USER="$(loginctl list-sessions --no-legend | awk '$4=="seat0"{print $3; exit}')"
ACTIVE_UID="$(id -u "$ACTIVE_USER" 2>/dev/null || true)"

MAX_INT="$(
  LC_ALL=C sensors coretemp-isa-0000 2>/dev/null | awk '
    /^Package id 0:|^Core [0-9]+:/ {
      t=$4
      gsub(/[+°C]/,"",t)
      if (t+0 > max) max=t+0
    }
    END { if (max=="") max=0; printf "%d\n", int(max+0.5) }
  '
)"

now="$(date +%s)"
last=0
[[ -f "$STATE_FILE" ]] && last="$(cat "$STATE_FILE" 2>/dev/null || echo 0)"

if (( MAX_INT >= THRESHOLD )) && (( now - last >= COOLDOWN_SECONDS )); then
  echo "$now" > "$STATE_FILE"

  logger -t temp-alert "TEMP ALERT: CPU max ${MAX_INT}°C (>= ${THRESHOLD}°C)"

  wall "🔥 TEMP ALERT: CPU max ${MAX_INT}°C (>= ${THRESHOLD}°C). Close heavy apps/tabs."

  if [[ -n "${ACTIVE_UID:-}" ]]; then
    export DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/${ACTIVE_UID}/bus"
    export XDG_RUNTIME_DIR="/run/user/${ACTIVE_UID}"
    runuser -u "$ACTIVE_USER" -- notify-send -u critical \
      "🔥 Temperature Alert" "CPU reached ${MAX_INT}°C (≥ ${THRESHOLD}°C)"
  fi
fi
```

---

# 4️⃣ systemd Service + Timer

## Service

`/etc/systemd/system/temp-alert.service`

```ini
[Unit]
Description=CPU temperature alert (notify only)

[Service]
Type=oneshot
ExecStart=/usr/local/bin/temp-alert.sh
```

## Timer

`/etc/systemd/system/temp-alert.timer`

```ini
[Unit]
Description=Run CPU temperature alert check every 10s

[Timer]
OnBootSec=30
OnUnitActiveSec=10
AccuracySec=1

[Install]
WantedBy=timers.target
```

Enable:

```bash
sudo systemctl daemon-reload
sudo systemctl enable --now temp-alert.timer
```

---

# 5️⃣ Testing

Force trigger:

```bash
sudo rm -f /run/temp-alert.last
sudo THRESHOLD=0 COOLDOWN_SECONDS=0 /usr/local/bin/temp-alert.sh
```

Verify:

```bash
journalctl -t temp-alert -n 20 --no-pager
```

---

# 6️⃣ Operational Notes

* Surface Pro 7 runs hot under burst turbo
* Gmail + Brave + HiDPI + external display can spike one core
* Sustained 90°C is undesirable
* Alert-only strategy preserves full user control

---

# 7️⃣ Reproduction Checklist (Rapid Deployment)

1. Install lm-sensors
2. Copy script to `/usr/local/bin/`
3. `chmod +x`
4. Create systemd service + timer
5. `daemon-reload`
6. `enable --now timer`
7. Force test

Total time: < 5 minutes if followed exactly.

---

End of document.
