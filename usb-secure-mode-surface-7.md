# USB Secure Mode

## Surface Pro 7 – Linux Mint 22 – Cinnamon

---

## 1. Objective

Implement a selective USB data blocking mechanism on a Microsoft Surface Pro 7 running Linux Mint 22 (Cinnamon).

### Goals

* Block USB-A and USB-C external data access
* Prevent:

  * USB mass storage attacks
  * Rubber Ducky / fake keyboard injection
  * USB Ethernet injection
  * Composite malicious USB devices
* Keep:

  * Internal SD card functional
  * Internal Bluetooth functional (keyboard + mouse)
  * System stable (no controller disable)
* Provide:

  * Manual ON/OFF control
  * Persistence across reboot when enabled
  * Safe rollback

---

## 2. Hardware Mapping (Surface Pro 7)

### USB Topology Identified

| Component      | Bus     | Devpath    | Notes    |
| -------------- | ------- | ---------- | -------- |
| USB-A          | Bus 003 | devpath 2  | External |
| USB-C          | Bus 003 | devpath 4  | External |
| Bluetooth      | Bus 003 | devpath 10 | Internal |
| SD Card Reader | Bus 004 | devpath 6  | Internal |

Important:

* External ports are on Bus 003
* SD reader is on Bus 004
* Bluetooth is on Bus 003 but at devpath 10
* We must NOT disable entire controller

---

## 3. Security Model

We use a udev rule that:

* Blocks any device added on:

  * Bus 3, devpath 2 (USB-A)
  * Bus 3, devpath 4 (USB-C)
* Sets `authorized=0`
* Prevents driver binding
* Prevents HID injection
* Prevents storage mounting
* Keeps power present

This approach:

* Does NOT disable USB controller
* Does NOT break Bluetooth
* Does NOT break SD card
* Is reversible

---

## 4. Installation Procedure

### 4.1 Create Wrapper Script

```bash
sudo tee /usr/local/sbin/usb-secure-mode >/dev/null <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

RULE_FILE="/etc/udev/rules.d/90-surface-usb-port-block.rules"

usage() {
  echo "Usage: usb-secure-mode {on|off|status|reload}"
}

require_root() {
  if [[ "${EUID}" -ne 0 ]]; then
    echo "ERROR: must be run as root. Try: sudo usb-secure-mode $*" >&2
    exit 1
  fi
}

write_rule() {
  cat > "${RULE_FILE}" <<'RULE'
# Surface Pro 7 (Mint): block external physical ports while keeping internal USB devices.
ACTION=="add", SUBSYSTEM=="usb", ATTR{busnum}=="3", ATTR{devpath}=="2*", ATTR{authorized}="0"
ACTION=="add", SUBSYSTEM=="usb", ATTR{busnum}=="3", ATTR{devpath}=="4*", ATTR{authorized}="0"
RULE
}

reload_udev() {
  udevadm control --reload-rules
  udevadm trigger --subsystem-match=usb --action=add || true
}

is_on() {
  [[ -f "${RULE_FILE}" ]]
}

cmd="${1:-}"
case "${cmd}" in
  on)
    require_root "$@"
    write_rule
    reload_udev
    echo "usb-secure: ON"
    ;;
  off)
    require_root "$@"
    rm -f "${RULE_FILE}"
    reload_udev
    echo "usb-secure: OFF"
    ;;
  status)
    if is_on; then
      echo "usb-secure: ON"
    else
      echo "usb-secure: OFF"
    fi
    ;;
  reload)
    require_root "$@"
    reload_udev
    echo "usb-secure: reloaded"
    ;;
  *)
    usage
    exit 2
    ;;
esac
EOF

sudo chmod +x /usr/local/sbin/usb-secure-mode
```

---

## 5. Usage

### Enable Secure Mode

```bash
sudo usb-secure-mode on
```

### Disable Secure Mode

```bash
sudo usb-secure-mode off
```

### Check Status

```bash
usb-secure-mode status
```

---

## 6. Behavior Verification

### When Secure Mode is ON:

* USB storage will not mount
* USB keyboard will not generate input events
* USB devices may appear in `lsusb`
* No data communication possible
* Bluetooth remains functional
* SD card remains functional

### Test Keyboard Blocking

```bash
sudo evtest
```

USB keyboard should NOT appear as input device.

---

## 7. Cinnamon Desktop Integration

### USB Secure ON Launcher

Create:

`~/.local/share/applications/usb-secure-on.desktop`

```ini
[Desktop Entry]
Type=Application
Name=USB Secure ON
Exec=pkexec /usr/local/sbin/usb-secure-mode on
Icon=security-high
Terminal=false
Categories=System;Security;
```

### USB Secure OFF Launcher

`~/.local/share/applications/usb-secure-off.desktop`

```ini
[Desktop Entry]
Type=Application
Name=USB Secure OFF
Exec=pkexec /usr/local/sbin/usb-secure-mode off
Icon=security-low
Terminal=false
Categories=System;Security;
```

Make executable:

```bash
chmod +x ~/.local/share/applications/usb-secure-*.desktop
```

---

## 8. Recovery Procedure (Emergency)

If something goes wrong:

```bash
sudo usb-secure-mode off
```

Or manually remove rule:

```bash
sudo rm -f /etc/udev/rules.d/90-surface-usb-port-block.rules
sudo udevadm control --reload-rules
sudo udevadm trigger
```

Reboot if needed.

---

## 9. Security Coverage

Blocks:

* USB storage exfiltration
* Rubber Ducky attacks
* Fake keyboard injection
* USB Ethernet
* Malicious composite devices
* HID spoofing

Does NOT protect against:

* Physical internal tampering
* Thunderbolt DMA (if enabled)
* Kernel-level exploitation
* Firmware-level attacks

---

## 10. Operational Recommendation

Recommended use:

* Enable when:

  * Traveling
  * Conferences
  * Shared environments
  * Public exposure
* Disable when:

  * You need legitimate USB access

---

## 11. Design Philosophy

* Minimal kernel interference
* No module blacklisting
* No controller shutdown
* Safe rollback
* Deterministic behavior
* Surface-specific mapping
* Cinnamon-compatible workflow

---

## Status

Tested on:

* Surface Pro 7
* Linux Mint 22
* Cinnamon
* Kernel 6.x series

---

End of document
