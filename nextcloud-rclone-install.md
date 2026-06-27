# Ubuntu 24.04 — Nextcloud via rclone mount (GNOME Files integration)

This document describes a production-oriented setup to access a **Nextcloud** account on **Ubuntu 24.04** using **rclone mount (FUSE)**, with a **systemd user service** so the mount appears as a local drive and is usable from **GNOME Files**.

This design follows the same operational spirit as the validated Dropbox Business rclone setup already used on your systems, while adapting the remote type and mount pathing for Nextcloud.

## Scope

* Access Nextcloud through `rclone mount`
* Make the mount visible in Linux file managers
* Run the mount reliably through a **systemd user service**
* Create a standard homelab rclone exclude policy for Nextcloud-backed storage
* Install with a root-run installer that prepares the target user environment
* Keep the setup suitable for production desktops and user laptops

This is **not** the Nextcloud desktop sync client. No full file replication is performed.

This is also **not** a Dropbox repair procedure. Existing Dropbox rclone mounts must be left unchanged.

---

# 1) Target behavior

The intended result is:

* Nextcloud remote mounted for one chosen desktop user
* Mount visible from file managers
* Mount automatically started when that user logs in
* Clean unmount on stop/restart
* Suitable for large trees where local sync would be inappropriate

Recommended mount path:

```text
/media/<user>/nextcloud
```

This path is generally convenient for GNOME / desktop use.

A compatibility symlink may also be created at:

```text
/mnt/<user>/nextcloud
```

This can be useful for scripts or users who prefer a stable technical path.

---

# 2) Prerequisites

## 2.1 Supported environment

* Ubuntu 24.04
* systemd user session available
* Internet connectivity
* A target desktop user already exists
* The installer is run as `root` or through `sudo`

## 2.2 Required packages

The installer should ensure these are present:

```bash
apt update
apt install -y rclone gvfs-backends fuse3 libnotify-bin
```

Purpose:

* `rclone` → remote access and mounting
* `gvfs-backends` → better integration with GNOME Files / desktop environment
* `fuse3` → FUSE mount support
* `libnotify-bin` → optional desktop notifications

---

# 3) FUSE configuration

For desktop-facing mounts, `allow_other` is often useful.

Ensure `/etc/fuse.conf` contains:

```text
user_allow_other
```

Example:

```bash
sudo sed -i 's/^# *user_allow_other/user_allow_other/' /etc/fuse.conf
```

---

# 4) Nextcloud rclone remote

The standard homelab rclone layout is:

```text
~/.config/rclone/
    rclone.conf
    nextcloud-excludes.txt
```

Create a remote with:

```bash
rclone config
```

Recommended remote settings:

* **name**: `nextcloud`
* **type**: `webdav`
* **vendor**: `nextcloud`
* **url**: your full Nextcloud WebDAV endpoint
* **user**: your Nextcloud username
* **password**: your Nextcloud password or app password

Typical endpoint pattern:

```text
https://<your-nextcloud-host>/remote.php/dav/files/<username>/
```

After configuration, validate with:

```bash
rclone lsd nextcloud:/
```

You should see top-level folders accessible for that user.

## 4.1 Standard Nextcloud exclude policy

The installer creates:

```text
~/.config/rclone/nextcloud-excludes.txt
```

Recommended content:

```text
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
```

Every rclone command that writes into Nextcloud-backed storage should reuse the same filter:

```bash
rclone copy <source> nextcloud:<path> --exclude-from ~/.config/rclone/nextcloud-excludes.txt
rclone sync <source> nextcloud:<path> --exclude-from ~/.config/rclone/nextcloud-excludes.txt
rclone bisync <source> nextcloud:<path> --exclude-from ~/.config/rclone/nextcloud-excludes.txt
rclone check <source> nextcloud:<path> --exclude-from ~/.config/rclone/nextcloud-excludes.txt
```

This keeps Linux desktops, laptops, and homelab servers aligned and avoids repeating fragile per-command exclusions.

---

# 5) Mount paths

For a target user such as `alice`, the installer should prepare:

```text
/media/alice/nextcloud
/mnt/alice/nextcloud
```

Recommended behavior:

* real mountpoint: `/media/alice/nextcloud`
* compatibility symlink: `/mnt/alice/nextcloud` → `/media/alice/nextcloud`

This keeps desktop UX clean while preserving a stable technical path.

---

# 6) systemd user service

The mount should run as a **user service**, because the mounted files belong in the user desktop session and should appear naturally in their file manager.

The unit file should be created at:

```text
/home/<user>/.config/systemd/user/nextcloud-rclone.service
```

Recommended service content:

```ini
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
  --exclude-from %h/.config/rclone/nextcloud-excludes.txt \
  --log-level INFO
Restart=on-failure
RestartSec=20
ExecStop=/bin/fusermount3 -uz /media/%u/nextcloud

[Install]
WantedBy=default.target
```

## Why these options

* `--allow-other` → helps visibility / usability in desktop context
* `--dir-cache-time 72h` → reduces repeated directory listing cost
* `--poll-interval 30s` → periodic refresh
* `--vfs-cache-mode writes` → safer writes than no VFS cache
* `--vfs-cache-max-age 24h` and `--vfs-cache-max-size 10G` → bounded cache
* `--exclude-from %h/.config/rclone/nextcloud-excludes.txt` → standard homelab policy for files that should not enter Nextcloud storage
* `Restart=on-failure` → resilience after temporary network issues
* `ExecStop` unmount → avoids stale FUSE endpoints on stop/restart

---

# 7) Service activation

Once the user unit exists, activate it as that user:

```bash
systemctl --user daemon-reload
systemctl --user enable --now nextcloud-rclone.service
systemctl --user status nextcloud-rclone.service
```

If the installer is running as root, it should execute these commands **in the context of the chosen user**.

---

# 8) Visibility in file managers

The mount should be visible from:

* GNOME Files
* standard file pickers
* terminal access

Checks:

```bash
mount | grep nextcloud || true
ls -la /media/<user>/nextcloud | head
ls -la /mnt/<user>/nextcloud | head
```

---

# 9) User selection and safety behavior for the installer

The installation script should:

1. Require root / sudo
2. Detect likely desktop users automatically
3. Propose a target user
4. Ask for confirmation
5. Allow override if the detected user is wrong
6. Refuse obviously invalid targets such as `root`
7. Create all required directories with correct ownership
8. Create `~/.config/rclone/nextcloud-excludes.txt`
9. Create the systemd user unit under the target user home
10. Trigger the user-level daemon reload and service enable/start
11. Print clear post-install instructions for `rclone config`

Important note:

`rclone config` is interactive and stores credentials in the target user profile. The installer can install everything else automatically, but the **remote itself** must either:

* already exist for that user, or
* be configured manually by the user after install, or
* be created by an administrator with care in that user context

---

# 10) Recommended production flow

## Initial deployment

1. Run installer as root
2. Confirm target user
3. Install packages
4. Prepare FUSE config
5. Create mount directories
6. Create the standard rclone exclude file
7. Create user service
8. In the target user session, run `rclone config`
9. Validate remote with `rclone lsd nextcloud:/`
10. Start / restart the service
11. Validate file manager visibility

## Later operations

Restart mount:

```bash
systemctl --user restart nextcloud-rclone.service
```

Stop mount:

```bash
systemctl --user stop nextcloud-rclone.service
```

Check logs:

```bash
journalctl --user -u nextcloud-rclone.service -n 200 --no-pager
```

---

# 11) Troubleshooting

## 11.1 Transport endpoint is not connected

Usually a stale FUSE mount:

```bash
fusermount3 -uz /media/<user>/nextcloud || true
systemctl --user restart nextcloud-rclone.service
```

## 11.2 Remote not configured yet

Symptoms:

* service starts then fails
* `rclone lsd nextcloud:/` fails

Fix:

```bash
rclone config
rclone lsd nextcloud:/
```

## 11.3 Service is enabled but not visible in GUI

Check:

* user logged into graphical session
* mountpoint ownership is correct
* `gvfs-backends` installed
* service really started in the user session

## 11.4 Wrong WebDAV URL

For Nextcloud, use the full WebDAV endpoint, typically:

```text
https://<host>/remote.php/dav/files/<username>/
```

Do not use a generic server root URL when the per-user path is required.

## 11.5 Surface Pro 7 / laptop-specific investigation

The Surface 7 may behave differently from servers or fixed desktops because of Wi-Fi power management, suspend/resume behavior, FUSE state, kernel flavor, and large interactive file-manager directory scans.

Known Surface Pro 7 Dropbox baseline, for reference only:

```ini
Service file: /home/rfv/.config/systemd/user/dropbox-rclone.service
Mount path  : /media/Dpbx-V
Remote      : dpbx:/

ExecStart=/usr/bin/rclone mount dpbx:/ /media/Dpbx-V \
  --vfs-cache-mode=full \
  --vfs-cache-max-size=2G \
  --vfs-read-chunk-size=32M \
  --vfs-read-chunk-size-limit=512M \
  --buffer-size=16M \
  --dir-cache-time=1h \
  --poll-interval=30s \
  --timeout=1m \
  --retries=5 \
  --low-level-retries=10 \
  --umask=022 \
  --allow-other \
  --log-file=%h/.local/share/rclone/dropbox-mount.log \
  --log-level=INFO
```

This Dropbox service is not part of the Nextcloud issue. Do not add `nextcloud-excludes.txt` to it. The Nextcloud reserved-file problem applies to the Nextcloud/WebDAV path, especially files such as `.htaccess`, `.htpasswd`, and `.user.ini`.

First confirm the exact command that feels slow. Capture the command type and full command line with credentials redacted:

```bash
rclone sync ...
rclone bisync ...
rclone mount ...
rclone copy ...
rclone check ...
```

Then run a small timing baseline:

```bash
time rclone lsd nextcloud:/
time rclone lsjson nextcloud:/ --max-depth 1 --fast-list
time rclone about nextcloud:
```

If a write operation is slow, compare a tiny file and a directory traversal:

```bash
tmpfile="$(mktemp)"
printf 'nextcloud-rclone-test\n' > "$tmpfile"
time rclone copy "$tmpfile" nextcloud:/rclone-test/ --exclude-from ~/.config/rclone/nextcloud-excludes.txt -vv
time rclone check "$tmpfile" nextcloud:/rclone-test/ --exclude-from ~/.config/rclone/nextcloud-excludes.txt -vv
rm -f "$tmpfile"
```

If `rclone mount` is the slow part, check whether the delay is mount startup, first directory listing, or GNOME Files scanning:

```bash
time systemctl --user restart nextcloud-rclone.service
systemctl --user status nextcloud-rclone.service --no-pager
journalctl --user -u nextcloud-rclone.service -n 200 --no-pager
time ls -la /media/$USER/nextcloud | head
```

The key diagnostic question is whether slowness appears only with a large tree, only through the mounted filesystem, or also with direct `rclone` WebDAV commands. A fast simple WebDAV test, such as a sub-second command, usually means the delay is caused by traversal, cache warm-up, file-manager probing, or command options rather than basic Nextcloud connectivity.

---

# 12) Uninstall / cleanup

Disable service:

```bash
systemctl --user disable --now nextcloud-rclone.service
```

Remove unit file:

```bash
rm -f ~/.config/systemd/user/nextcloud-rclone.service
systemctl --user daemon-reload
```

Remove symlink and mountpoint:

```bash
rm -f /mnt/<user>/nextcloud
rmdir /media/<user>/nextcloud
```

Optional cache cleanup:

```bash
rm -rf ~/.local/share/rclone/cache
```

---

# 13) Operational notes

* This approach is appropriate when you need **full tree visibility without full local sync**.
* It is well suited for admin verification, migration validation, and desktop browsing of large repositories.
* It avoids the storage explosion of the official Nextcloud sync client on very large datasets.
* For sensitive or production environments, prefer **Nextcloud app passwords** over normal user passwords when configuring the WebDAV remote.

---

# 14) Summary

This setup provides:

* no full local replication
* GNOME-visible mount
* systemd-managed reliability
* a predictable user-scoped service model
* a technical path suitable for large Nextcloud datasets

It is the appropriate model when the goal is **access and verification**, not desktop synchronization.
