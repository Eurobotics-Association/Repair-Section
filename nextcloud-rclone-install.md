# Ubuntu 24.04 / ZorinOS — Nextcloud via rclone mount (GNOME / Zorin Files integration)

This document describes a production-oriented setup to access a **Nextcloud** account on **Ubuntu 24.04** and **ZorinOS** using **rclone mount (FUSE)**, with a **systemd user service** so the mount is available through a stable local path and remains usable from **GNOME Files / Zorin Files** without letting the desktop probe it too aggressively.

This design follows the same operational spirit as the validated Dropbox Business rclone setup already used on your systems, while adapting the remote type and mount pathing for Nextcloud.

## Scope

* Access Nextcloud through `rclone mount`
* Make the mount accessible from Linux file managers without encouraging aggressive automatic probing
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
* ZorinOS on the Ubuntu package base
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
* `gvfs-backends` → desktop integration for GNOME Files / Zorin Files and file pickers
* `fuse3` → FUSE mount support
* `libnotify-bin` → optional desktop notifications

---

# 2.3 Ubuntu versus ZorinOS

Use the same Nextcloud rclone architecture on Ubuntu and ZorinOS:

```text
rclone mount → FUSE → WebDAV/Nextcloud → GNOME/GVfs/Zorin Files
```

The **rclone**, **FUSE**, **systemd user service**, and **Nextcloud WebDAV** parts should behave similarly. The difference is mainly in the desktop layer: Zorin Files, file pickers, portals, thumbnailers, and suspend/resume timing may probe the mount differently from stock Ubuntu GNOME.

Therefore the default service profile is the same on both systems, but every laptop should be validated with:

```bash
systemctl --user status nextcloud-rclone.service --no-pager
journalctl --user -u nextcloud-rclone.service -n 120 --no-pager
time rclone lsd nextcloud:/
time ls -la /media/$USER/nextcloud | head
```

Also test at least two suspend/resume cycles after the service is patched.

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
  -o x-gvfs-hide \
  --daemon-timeout 20s \
  --dir-cache-time 72h \
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
* `-o x-gvfs-hide` → asks GNOME/GVfs not to present the mount as a normal automatically-enumerated volume; the direct path remains usable
* `--daemon-timeout 20s` → caps blocked kernel/FUSE responses during network loss or suspend/resume races
* `--dir-cache-time 72h` → reduces repeated directory listing cost
* no `--poll-interval` → WebDAV/Nextcloud does not support rclone polling, so keeping it only adds log noise
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

## 11.5 Ubuntu / ZorinOS laptop-specific investigation

Ubuntu and ZorinOS laptops may behave differently from servers or fixed desktops because of Wi-Fi power management, suspend/resume behavior, FUSE state, kernel flavor, GNOME/Zorin desktop integration, and large interactive file-manager directory scans. ZorinOS is Ubuntu-family, so the rclone/FUSE/WebDAV layer is similar, but the file manager, portal, thumbnailer, and desktop probing behaviour can differ.

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

Useful diagnostics on the laptop:

```bash
systemctl --user status nextcloud-rclone.service --no-pager
journalctl --user -u nextcloud-rclone.service -n 200 --no-pager
rclone lsd nextcloud:/
time rclone lsjson nextcloud:/ --max-depth 1 --fast-list
```

If a specific directory is slow in the file manager, compare direct rclone versus FUSE mount access:

```bash
time rclone lsjson 'nextcloud:/PATH/TO/SLOW/FOLDER' --max-depth 1 --fast-list -vv
time ls -la '/media/<user>/nextcloud/PATH/TO/SLOW/FOLDER' | head
```

Interpretation:

* direct `rclone` slow → likely WebDAV / Nextcloud / remote-tree / server-side metadata issue
* direct `rclone` fast but `/media/...` slow → likely FUSE / VFS / file-manager interaction
* only GNOME/Zorin Files slow → likely thumbnails, previews, portals, or desktop probing

## 11.6 Ubuntu / ZorinOS laptop hardening profile

A laptop using Nextcloud through rclone mount is more exposed to suspend/resume races than a fixed server. This applies to Ubuntu and ZorinOS because the core path is the same: rclone mount → FUSE → WebDAV/Nextcloud → GNOME/GVfs/Zorin Files. On the Surface 7, the relevant failure sequence was:

```text
GNOME portal → statfs() on mounted filesystems → rclone FUSE
             → Nextcloud/ZeroTier did not answer
             → GNOME threads entered uninterruptible D state
             → suspend could not freeze those threads
```

The standard laptop profile is:

```text
-o x-gvfs-hide
--daemon-timeout 20s
```

Operational meaning:

* `-o x-gvfs-hide` reduces GNOME/GVfs automatic presentation and probing of the mount. The mount remains accessible at `/media/<user>/nextcloud`; bookmark the useful subfolders manually if needed.
* `--daemon-timeout 20s` prevents rclone from waiting indefinitely before answering the kernel during a network interruption.
* `--poll-interval 30s` is deliberately removed for Nextcloud/WebDAV because the remote reports that polling is not supported.

Recommended rollout:

1. Add `-o x-gvfs-hide`.
2. Add `--daemon-timeout 20s`.
3. Remove `--poll-interval 30s` from the Nextcloud service.
4. Restart the user service.
5. Test file dialogs and suspend/resume several times.
6. Only then evaluate `--vfs-cache-mode full`, if repeated reads or seeking are slow.

The laptop audit/repair script checks and can patch this profile on direct `rclone mount nextcloud:` user services. It is valid for Ubuntu/ZorinOS-style user services and does not modify Dropbox or any non-Nextcloud rclone mount.

## 11.7 Stale forbidden files in local rclone VFS cache

If a laptop previously tried to write or delete Nextcloud-forbidden files before the exclude policy was applied, rclone may keep stale upload attempts in its local VFS cache. The typical symptom is repeated journal entries such as:

```text
.htaccess: vfs cache: failed to upload
OCP\Files\ForbiddenException
Invalid path
```

The standard Ubuntu/ZorinOS laptop audit-repair script includes a dedicated pass for this case. It checks only the Nextcloud rclone cache roots:

```text
~/.local/share/rclone/cache/vfs/nextcloud
~/.local/share/rclone/cache/vfsMeta/nextcloud
```

and only removes stale server-forbidden filenames:

```text
.htaccess
.htpasswd
.user.ini
```

Manual equivalent:

```bash
systemctl --user stop nextcloud-rclone.service

find ~/.local/share/rclone/cache/vfs/nextcloud ~/.local/share/rclone/cache/vfsMeta/nextcloud \
  \( -name '.htaccess' -o -name '.htpasswd' -o -name '.user.ini' \) -print

find ~/.local/share/rclone/cache/vfs/nextcloud ~/.local/share/rclone/cache/vfsMeta/nextcloud \
  \( -name '.htaccess' -o -name '.htpasswd' -o -name '.user.ini' \) -delete

systemctl --user start nextcloud-rclone.service
```

When stale entries are found, the script asks before stopping `nextcloud-rclone.service`, deleting the stale cache entries, and restarting the service if it was active.

---

# 12) Summary recommendation

Use `rclone mount` for large Nextcloud trees where full local sync is not acceptable.

Use the Nextcloud desktop client only when selective sync with local copies is acceptable.

Use the standard homelab exclude policy everywhere to avoid Nextcloud/WebDAV reserved-file errors and inconsistent Linux laptop behavior.
