# Ubuntu 24.04 (Surface Pro 7) — Dropbox Business via rclone mount (GNOME Files integration)

This document describes a **validated** setup to access **Dropbox Business** (team root folders) on Ubuntu 24.04 using **rclone mount (FUSE)**, with a **systemd user service** so the mount appears as a local drive (e.g. `/media/Dpbx-V`) and is usable from **GNOME Files**.

> Scope: **Mount + access** (not Dropbox’s official client).
>
> Note: If you also use an `rsync`-based workflow, keep your existing rsync parameters unchanged unless you explicitly decide to revise them.

---

## 1) Prerequisites

### 1.1 Packages

```bash
sudo apt update
sudo apt install -y gvfs-backends libnotify-bin
```

* `gvfs-backends` helps GNOME Files / desktop integration.
* `libnotify-bin` provides `notify-send` (optional, but useful for desktop notifications).

### 1.2 rclone install

Two supported approaches:

#### Option A — Snap (recommended for newer rclone)

```bash
sudo snap install rclone
rclone version
```

#### Option B — apt (Ubuntu repo)

```bash
sudo apt install -y rclone
rclone version
```

> In the validated setup, rclone `v1.73.1` was used.

### 1.3 Allow FUSE `allow_other` (required for some desktop use cases)

Enable `user_allow_other`:

```bash
sudo sed -i 's/^# *user_allow_other/user_allow_other/' /etc/fuse.conf
grep -n '^user_allow_other' /etc/fuse.conf
```

---

## 2) Configure the Dropbox remote

Run:

```bash
rclone config
```

Create (or verify) a remote such as:

* Name: `dpbx`
* Type: `dropbox`

Then validate that you can see your Dropbox Business root folders:

```bash
rclone lsd dpbx:/
```

You should see your top-level folders (including Team folders where applicable).

---

## 3) Create the mount point

Example mount path:

```bash
sudo mkdir -p /media/Dpbx-V
sudo chown "$USER:$USER" /media/Dpbx-V
sudo chmod 755 /media/Dpbx-V
```

---

## 4) systemd user service (auto-mount when you log in)

### 4.1 Create the unit file

Create the user systemd directory (if missing):

```bash
mkdir -p ~/.config/systemd/user
```

Create:

```bash
nano ~/.config/systemd/user/dropbox-rclone.service
```

Paste the following:

```ini
[Unit]
Description=Rclone mount for Dropbox (user scoped)
Wants=network-online.target
After=network-online.target

[Service]
Type=simple

# Optional: wait for NetworkManager to report network-online
ExecStartPre=/usr/bin/bash -lc 'command -v nm-online >/dev/null 2>&1 && nm-online -q -t 30 || true'

ExecStartPre=/usr/bin/mkdir -p /media/Dpbx-V
ExecStartPre=/usr/bin/mkdir -p %h/.local/share/rclone/cache

# IMPORTANT: keep mount arguments stable unless you explicitly decide to change them.
ExecStart=/usr/bin/rclone mount dpbx:/ /media/Dpbx-V \
  --allow-other \
  --dir-cache-time 72h \
  --poll-interval 30s \
  --vfs-cache-mode writes \
  --vfs-cache-max-age 24h \
  --vfs-cache-max-size 10G \
  --cache-dir %h/.local/share/rclone/cache \
  --log-level INFO

# Make it resilient if Dropbox/network is not ready at login
Restart=on-failure
RestartSec=20

# Clean unmount on stop/restart
ExecStop=/bin/fusermount3 -uz /media/Dpbx-V

[Install]
WantedBy=default.target
```

### 4.2 Enable + start

```bash
systemctl --user daemon-reload
systemctl --user enable --now dropbox-rclone.service
systemctl --user status dropbox-rclone.service
```

### 4.3 Confirm the mount

```bash
mount | grep Dpbx-V || true
ls -la /media/Dpbx-V | head
```

In GNOME Files, it should appear as a mounted location/drive.

---

## 5) What happens if there is no network at boot/login?

### Default behavior

* This is a **user service**, so it normally starts when you **log in**.
* If your network is not ready yet, the unit uses:

  * `nm-online -t 30` (best effort)
  * `Restart=on-failure` with a short delay

This means:

* If the mount fails at login, systemd will retry automatically.

### Recommended checks

```bash
systemctl --user status dropbox-rclone.service
journalctl --user -u dropbox-rclone.service -n 200 --no-pager
```

---

## 6) Manual restart command (no launcher required)

If you ever need to force a remount:

```bash
systemctl --user restart dropbox-rclone.service
```

To stop:

```bash
systemctl --user stop dropbox-rclone.service
```

---

## 7) Desktop launcher (a real file on the Desktop)

If you want an **actual launcher icon on the Desktop** (not pinned to the dash), create:

```bash
nano ~/Desktop/Restart-Dropbox-Mount.desktop
```

Paste:

```ini
[Desktop Entry]
Type=Application
Name=Restart Dropbox Mount
Comment=Restart rclone Dropbox mount (user service)
Exec=systemctl --user restart dropbox-rclone.service
Icon=folder-remote
Terminal=false
Categories=Utility;
```

Make it executable:

```bash
chmod +x ~/Desktop/Restart-Dropbox-Mount.desktop
```

On Ubuntu/GNOME, you may need to right-click the desktop icon and choose **“Allow Launching”**.

---

## 8) Troubleshooting

### 8.1 “Transport endpoint is not connected”

Usually means the FUSE mount got stuck.

```bash
fusermount3 -uz /media/Dpbx-V || true
systemctl --user restart dropbox-rclone.service
```

### 8.2 Check rclone auth and remote

```bash
rclone about dpbx:/
rclone lsd dpbx:/
```

### 8.3 Verify FUSE config

```bash
grep -n 'user_allow_other' /etc/fuse.conf
```

---

## 9) Notes for Surface Pro 7

* This approach is lightweight and works well with a Surface Linux kernel.
* For stability, keep:

  * a reasonable VFS cache
  * restart on failure
  * explicit unmount in `ExecStop`

---

## Appendix — Uninstall / cleanup

Disable service:

```bash
systemctl --user disable --now dropbox-rclone.service
```

Remove unit file:

```bash
rm -f ~/.config/systemd/user/dropbox-rclone.service
systemctl --user daemon-reload
```

Remove mountpoint (optional):

```bash
sudo rmdir /media/Dpbx-V
```

Remove cache (optional):

```bash
rm -rf ~/.local/share/rclone/cache
```


