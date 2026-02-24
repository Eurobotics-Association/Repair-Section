# Ubuntu USB Secure Mode (V2) — Surface Pro 7

> **Goal:** Block USB **data** on the Surface Pro 7 external ports while still allowing **power/charging**.
>
> **Platform:** Ubuntu (GNOME/Wayland) + linux-surface kernel (tested on 6.x)
>
> **Security model:** Kernel-level USB **authorization** (`authorized=0`) on specific **physical port chains**.

---

## 1) Why this approach

Linux exposes a per-port/per-device authorization flag:

* `authorized=1` → device is allowed to enumerate and exchange data
* `authorized=0` → device is de-authorized (power remains, but **data is blocked**)

This is not a “userspace block”; it is enforced by the kernel USB stack.

**Key principle:** do **not** match USB devices by vendor/product IDs, and do **not** disable the whole controller.

* Vendor/product IDs are easy to change or bypass.
* Disabling the whole xHCI controller may break internal devices (Bluetooth, SD reader).

Instead, match **physical port chains** such as:

* `3-2` (USB-A external)
* `3-4` (USB-C external)

These chains are typically stable across reboots and kernel updates (on the same machine), but you must validate them.

---

## 2) Investigation procedure (human-in-the-loop)

This section is critical: Surface Pro 7 ports share controllers with internal devices (Bluetooth). You must identify the correct physical chains before blocking.

### 2.1 Baseline (nothing connected to external ports)

Run:

```bash
lsusb -t
```

You will usually see:

* One bus containing **Bluetooth** (btusb)
* One bus containing the **internal SD reader**

Record which entries correspond to internal devices. These must remain authorized.

### 2.2 Identify USB-C chain

1. Plug a known device into **USB-C** (phone, USB key, etc.).

2. Find the device numbers:

```bash
lsusb
```

Example:

* `Bus 003 Device 010: ...`

3. Extract the physical chain (look for `KERNEL=="3-4"` style):

```bash
udevadm info --attribute-walk --name=/dev/bus/usb/003/010 | sed -n '1,140p'
```

Look for:

* `looking at device '.../usbX/3-4':`
* `KERNEL=="3-4"`

Record that chain as:

* **USB-C_CHAIN = 3-4** (example)

### 2.3 Identify USB-A chain

Repeat the same process with a device plugged into **USB-A**.

```bash
lsusb
udevadm info --attribute-walk --name=/dev/bus/usb/BBB/DDD | sed -n '1,140p'
```

Record the chain as:

* **USB_A_CHAIN = 3-2** (example)

### 2.4 Surface Pro 7 typical mapping (example only)

On one tested Surface Pro 7 (Ubuntu + linux-surface):

* USB-A → `3-2`
* USB-C → `3-4`
* Bluetooth (internal) → `3-10`
* SD reader (internal) → `4-6`

⚠️ **Do not copy blindly.** Always confirm with the steps above.

---

## 3) Implementation design

### 3.1 What we implement

1. A small helper command:

* `usb-secure-mode enable`  → de-authorize the external ports
* `usb-secure-mode disable` → authorize the external ports
* `usb-secure-mode apply`   → enforce current state (used by udev and boot)
* `usb-secure-mode status`  → show current state and current `authorized` values

2. A udev rule that triggers on USB add/change for the target chains and calls `usb-secure-mode apply`.

3. A systemd oneshot service that runs at boot to enforce the current state.

### 3.2 Expected user-visible behavior on GNOME

When secure mode is enabled and you plug a phone:

* The phone will **charge**.
* GNOME may show a notification like:

  * “Failed to mount … Unable to open MTP device …”

This is expected: GNOME attempts MTP; kernel authorization blocks it.

---

## 4) Validation checklist

1. Enable secure mode:

```bash
sudo usb-secure-mode enable
```

2. Confirm status:

```bash
sudo usb-secure-mode status
```

Expect (example):

* `3-2: authorized=0`
* `3-4: authorized=0`

3. Plug into USB-A and USB-C:

* device charges
* no mount

4. Disable secure mode:

```bash
sudo usb-secure-mode disable
```

Confirm `authorized=1` and normal operation returns.

---

## 5) Safety notes

* Do **not** block the entire USB controller: Bluetooth is often on the same controller.
* Always validate internal device chains (Bluetooth / SD reader) before enabling rules.
* Prefer physical chains (`3-2`, `3-4`) over bus numbers (`busnum`) and device numbers (`devnum`).

---

## 6) One-command example installer (template)

> This is a **single command** that installs a **template** implementation.
>
> You **must edit the two port chains** at the top of the script after your investigation.

```bash
bash -lc 'set -euo pipefail

# ====== EDIT THESE AFTER YOU VALIDATE PORT CHAINS ======
USB_A_CHAIN="3-2"   # example
USB_C_CHAIN="3-4"   # example
# =======================================================

sudo -v

# Helper
sudo tee /usr/local/sbin/usb-secure-mode >/dev/null <<"SH"
#!/usr/bin/env bash
set -euo pipefail
STATE_DIR="/etc/usb-secure-mode"
ENABLED_FILE="$STATE_DIR/enabled"
USB_A_CHAIN="'"$USB_A_CHAIN"'"
USB_C_CHAIN="'"$USB_C_CHAIN"'"
PORTS=("$USB_A_CHAIN" "$USB_C_CHAIN")

need_root(){ [[ "$(id -u)" -eq 0 ]] || { echo "Must be root" >&2; exit 1; }; }

write_auth(){
  local v="$1" p
  for p in "${PORTS[@]}"; do
    local node="/sys/bus/usb/devices/${p}/authorized"
    [[ -e "$node" ]] && echo "$v" > "$node" || true
  done
}

case "${1:-}" in
  enable)
    need_root
    install -d -m 0755 "$STATE_DIR"
    : > "$ENABLED_FILE"; chmod 0644 "$ENABLED_FILE"
    write_auth 0
    ;;
  disable)
    need_root
    rm -f "$ENABLED_FILE"
    write_auth 1
    ;;
  apply)
    need_root
    [[ -f "$ENABLED_FILE" ]] && write_auth 0 || write_auth 1
    ;;
  status)
    echo "Secure mode: $([[ -f "$ENABLED_FILE" ]] && echo ENABLED || echo DISABLED)"
    for p in "${PORTS[@]}"; do
      node="/sys/bus/usb/devices/${p}/authorized"
      [[ -e "$node" ]] && echo "$p: authorized=$(cat "$node")" || echo "$p: (not present)"
    done
    ;;
  *)
    echo "Usage: usb-secure-mode {enable|disable|apply|status}" >&2
    exit 2
    ;;
esac
SH
sudo chmod 0755 /usr/local/sbin/usb-secure-mode

# Udev rules (trigger apply on add/change on those chains)
sudo tee /etc/udev/rules.d/99-usb-secure-mode-surface7.rules >/dev/null <<UDEV
ACTION=="add|change", SUBSYSTEM=="usb", KERNEL=="${USB_A_CHAIN}*", RUN+="/usr/local/sbin/usb-secure-mode apply"
ACTION=="add|change", SUBSYSTEM=="usb", KERNEL=="${USB_C_CHAIN}*", RUN+="/usr/local/sbin/usb-secure-mode apply"
UDEV
sudo chmod 0644 /etc/udev/rules.d/99-usb-secure-mode-surface7.rules
sudo udevadm control --reload-rules

# Boot enforcement
sudo tee /etc/systemd/system/usb-secure-mode.service >/dev/null <<UNIT
[Unit]
Description=USB Secure Mode (Surface Pro 7)
After=systemd-udev-settle.service
Wants=systemd-udev-settle.service

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/usb-secure-mode apply

[Install]
WantedBy=multi-user.target
UNIT
sudo chmod 0644 /etc/systemd/system/usb-secure-mode.service
sudo systemctl daemon-reload
sudo systemctl enable usb-secure-mode.service

echo "Installed. Next: sudo usb-secure-mode enable  (or disable/status)"'
```

---

## 7) Notes for GitHub maintenance

* Keep this doc versioned (V2, V3…) with the exact kernel and Ubuntu release you validated.
* After a major kernel or firmware update, re-run the investigation (Section 2) to confirm port chains.
* If you start using a USB-C dock/hub, validate whether the dock enumerates under the same chain and decide whether it should be blocked.
