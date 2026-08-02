# Ubuntu 24.04 / ZorinOS — Nextcloud via rclone mount

This document describes the validated homelab setup to access **Nextcloud** from **Ubuntu 24.04** and **ZorinOS** laptops using **rclone mount (FUSE)** and a **systemd user service**.

The design is for large Nextcloud trees where local sync is not acceptable. It is **not** the Nextcloud desktop sync client and does not create a full local copy.

This is also **not** a Dropbox repair procedure. Existing Dropbox rclone mounts must be left unchanged.

---

## 1. Validated profile

Validated on Robert's Surface Pro 7 with Ubuntu 24.04 apt rclone `1.60.1+dfsg`.

The compatible Nextcloud service profile is:

```text
--allow-other
--dir-cache-time 72h
--poll-interval 0
--vfs-cache-mode writes
--vfs-cache-max-age 24h
--vfs-cache-max-size 10G
--cache-dir %h/.local/share/rclone/cache
--exclude-from %h/.config/rclone/nextcloud-excludes.txt
--daemon-timeout 20s
--log-level INFO
```

Important compatibility note:

```text
-o x-gvfs-hide
```

must **not** be used as a default option for Ubuntu/ZorinOS apt rclone 1.60.x. On the validated Surface Pro 7, rclone failed with:

```text
-o/--option not supported with this FUSE backend
```

Therefore the current standard is:

```text
present: --exclude-from %h/.config/rclone/nextcloud-excludes.txt
present: --daemon-timeout 20s
present: --poll-interval 0
absent : -o x-gvfs-hide
absent : --poll-interval 30s
```

`--poll-interval 0` is intentional. Nextcloud/WebDAV does not support polling. Without an explicit value, rclone may still log that polling is unsupported. Setting it to `0` disables polling explicitly.

---

## 2. Ubuntu versus ZorinOS

Use the same architecture on Ubuntu and ZorinOS:

```text
rclone mount → FUSE → WebDAV/Nextcloud → GNOME/GVfs/Zorin Files
```

The rclone/FUSE/WebDAV layer should behave similarly. The desktop layer may differ: Zorin Files, file pickers, portals, thumbnailers, and suspend/resume timing may probe the mount differently from stock Ubuntu GNOME.

So the default service is the same, but validate every laptop with:

```bash
systemctl --user status nextcloud-rclone.service --no-pager
systemctl --user cat nextcloud-rclone.service | grep -E 'exclude-from|daemon-timeout|poll-interval|x-gvfs-hide'
journalctl --user -u nextcloud-rclone.service -n 120 --no-pager
time rclone lsd nextcloud:/
time ls -la /media/$USER/nextcloud | head
```

Also test at least two suspend/resume cycles.

---

## 3. Required packages

```bash
sudo apt update
sudo apt install -y rclone gvfs-backends fuse3 libnotify-bin
```

Purpose:

* `rclone` — WebDAV remote access and FUSE mount
* `gvfs-backends` — desktop integration
* `fuse3` — FUSE support
* `libnotify-bin` — optional notifications

---

## 4. FUSE configuration

For `--allow-other`, `/etc/fuse.conf` must contain exactly:

```text
user_allow_other
```

Check/fix:

```bash
sudo cp /etc/fuse.conf /etc/fuse.conf.bak.$(date +%Y%m%d-%H%M%S)
sudo sed -i 's/^user_allow_other.*/user_allow_other/' /etc/fuse.conf
sudo grep -qx 'user_allow_other' /etc/fuse.conf || echo user_allow_other | sudo tee -a /etc/fuse.conf
```

---

## 5. Standard rclone layout

```text
~/.config/rclone/
    rclone.conf
    nextcloud-excludes.txt
```

The Nextcloud remote should be named:

```text
nextcloud:
```

Recommended WebDAV settings:

```text
name   : nextcloud
type   : webdav
vendor : nextcloud
url    : https://<your-nextcloud-host>/remote.php/dav/files/<username>/
```

Use a Nextcloud app password rather than the main account password.

Validate:

```bash
rclone lsd nextcloud:/
```

---

## 6. Standard Nextcloud exclude policy

The installer creates:

```text
~/.config/rclone/nextcloud-excludes.txt
```

Content:

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

Reuse this on write operations:

```bash
rclone copy <source> nextcloud:<path> --exclude-from ~/.config/rclone/nextcloud-excludes.txt
rclone sync <source> nextcloud:<path> --exclude-from ~/.config/rclone/nextcloud-excludes.txt
rclone bisync <source> nextcloud:<path> --exclude-from ~/.config/rclone/nextcloud-excludes.txt
rclone check <source> nextcloud:<path> --exclude-from ~/.config/rclone/nextcloud-excludes.txt
```

This avoids Nextcloud/WebDAV reserved-file errors such as `.htaccess`, `.htpasswd`, and `.user.ini`.

---

## 7. Mount paths

Recommended mount path:

```text
/media/<user>/nextcloud
```

Optional technical symlink:

```text
/mnt/<user>/nextcloud -> /media/<user>/nextcloud
```

---

## 8. systemd user service

Create:

```text
/home/<user>/.config/systemd/user/nextcloud-rclone.service
```

Recommended content:

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
  --poll-interval 0 \
  --vfs-cache-mode writes \
  --vfs-cache-max-age 24h \
  --vfs-cache-max-size 10G \
  --cache-dir %h/.local/share/rclone/cache \
  --exclude-from %h/.config/rclone/nextcloud-excludes.txt \
  --daemon-timeout 20s \
  --log-level INFO
Restart=on-failure
RestartSec=20
ExecStop=/bin/fusermount3 -uz /media/%u/nextcloud

[Install]
WantedBy=default.target
```

Critical formatting rule: only option lines inside `ExecStart` should end with `\`. The final `--log-level INFO` line must **not** end with `\`; otherwise systemd lines such as `Restart=on-failure` can be swallowed into the rclone command.

Activate:

```bash
systemctl --user daemon-reload
systemctl --user enable --now nextcloud-rclone.service
systemctl --user status nextcloud-rclone.service --no-pager
```

---

## 9. Laptop audit/repair script

Use:

```bash
./surface7-nextcloud-rclone-audit.sh --audit-only
```

Then repair interactively:

```bash
./surface7-nextcloud-rclone-audit.sh
```

Despite the historical filename, the script is now an Ubuntu/ZorinOS family laptop Nextcloud audit/repair tool.

It checks and repairs only `nextcloud:` user services. It must never patch:

```text
dropbox-rclone.service
dpbx:
any non-Nextcloud rclone mount
```

It checks for:

```text
--exclude-from %h/.config/rclone/nextcloud-excludes.txt
--daemon-timeout 20s
--poll-interval 0
no -o x-gvfs-hide
no --poll-interval 30s
```

It also checks for stale forbidden files in:

```text
~/.local/share/rclone/cache/vfs/nextcloud
~/.local/share/rclone/cache/vfsMeta/nextcloud
```

and can remove only:

```text
.htaccess
.htpasswd
.user.ini
```

---

## 10. Intermittent stale view or disconnect in GNOME/Zorin Files

Observed behaviour on the Surface Pro 7:

```text
Direct WebDAV / GNOME network access sees the current Nextcloud files.
The rclone FUSE mount sometimes shows an older directory view or appears disconnected.
After a few minutes, the rclone mount can come back by itself and show the correct files again.
```

This does **not** necessarily mean Nextcloud lost data or that WebDAV is down. It usually means there are two different access paths:

```text
GNOME direct WebDAV access     → live WebDAV view
/media/<user>/nextcloud       → rclone FUSE/VFS cached mount
```

`rclone mount` is not a synchronization client. It is a filesystem bridge with VFS and directory caches. If the FUSE process, network path, ZeroTier path, or desktop file manager stalls temporarily, the mounted view can look stale while direct WebDAV remains correct.

When this happens, collect evidence before rebooting:

```bash
date
systemctl --user status nextcloud-rclone.service --no-pager
journalctl --user -u nextcloud-rclone.service --since '10 minutes ago' --no-pager
mount | grep -i nextcloud || true
time rclone lsd nextcloud:/ --timeout 20s --contimeout 10s
time rclone lsjson nextcloud:/ --max-depth 1 --fast-list --timeout 20s --contimeout 10s
time ls -la /media/$USER/nextcloud | head -50
```

Interpretation:

* direct `rclone lsd nextcloud:/` is fresh, but `/media/$USER/nextcloud` is stale → FUSE/VFS/service/cache issue
* direct `rclone lsd nextcloud:/` is stale or blocked → WebDAV/Nextcloud/network/ZeroTier path issue
* GNOME direct WebDAV is fresh, but rclone is stale → rclone mount cache or FUSE state issue, not Nextcloud data loss
* the mount comes back after a few minutes → likely transient network/FUSE recovery or rclone retry behaviour

Low-impact refresh procedure:

```bash
systemctl --user restart nextcloud-rclone.service
```

Stronger refresh if the mount is disconnected:

```bash
systemctl --user stop nextcloud-rclone.service
fusermount3 -uz /media/$USER/nextcloud || true
systemctl --user start nextcloud-rclone.service
```

Do not delete the full rclone cache as a first reaction. Start with the service restart and the targeted stale forbidden-file cleanup described below.

---

## 11. Troubleshooting

### Transport endpoint is not connected

```bash
systemctl --user stop nextcloud-rclone.service
fusermount3 -uz /media/$USER/nextcloud || true
systemctl --user start nextcloud-rclone.service
```

### Direct remote versus mounted view

```bash
time rclone lsd nextcloud:/ --timeout 20s --contimeout 10s
time ls -la /media/$USER/nextcloud | head -50
```

Interpretation:

* direct `rclone` slow or stale → remote/network/Nextcloud/ZeroTier issue
* direct `rclone` fresh but mount stale → FUSE/VFS/service/cache issue
* only file manager slow → desktop probing, thumbnails, portals, or stale FUSE state

### Check service profile

```bash
systemctl --user cat nextcloud-rclone.service | grep -E 'exclude-from|daemon-timeout|poll-interval|x-gvfs-hide'
```

Expected:

```text
--exclude-from %h/.config/rclone/nextcloud-excludes.txt
--daemon-timeout 20s
--poll-interval 0
```

No `x-gvfs-hide` should appear.

### Stale forbidden VFS cache entries

```bash
find ~/.local/share/rclone/cache/vfs/nextcloud ~/.local/share/rclone/cache/vfsMeta/nextcloud \
  \( -name '.htaccess' -o -name '.htpasswd' -o -name '.user.ini' \) -print
```

If needed:

```bash
systemctl --user stop nextcloud-rclone.service
find ~/.local/share/rclone/cache/vfs/nextcloud ~/.local/share/rclone/cache/vfsMeta/nextcloud \
  \( -name '.htaccess' -o -name '.htpasswd' -o -name '.user.ini' \) -delete
systemctl --user start nextcloud-rclone.service
```

---

## 12. Known Surface Pro 7 Dropbox baseline — reference only

The Surface has a separate Dropbox service:

```text
/home/rfv/.config/systemd/user/dropbox-rclone.service
remote: dpbx:/
mount : /media/Dpbx-V
```

This Dropbox service is not part of the Nextcloud issue. Do not add `nextcloud-excludes.txt` to it and do not patch it with the Nextcloud audit/repair script.

---

## 13. Public troubleshooting note

The Surface experiments may be useful to other Linux users because they document real rclone/Nextcloud/WebDAV/FUSE behaviour on Ubuntu-family laptops:

* Nextcloud Linux desktop sync is not a mature placeholder/on-demand solution for multi-terabyte trees.
* `rclone mount` is a practical alternative, but it is a FUSE/VFS cached mount, not a sync client.
* Direct WebDAV and rclone mount can temporarily disagree because they are different access paths.
* Ubuntu apt rclone 1.60.x did not accept `-o x-gvfs-hide` in this setup.
* Nextcloud/WebDAV should use `--poll-interval 0`.
* `.htaccess`, `.htpasswd`, and `.user.ini` should be excluded and stale VFS cache entries may need targeted cleanup.

A public Reddit/forum post should avoid exposing private hostnames, IPs, usernames, family names, repository secrets, or file paths containing personal information.

---

## 14. Summary

For Ubuntu/ZorinOS laptops using Nextcloud over rclone mount:

* use `rclone mount`, not full desktop sync, for very large trees
* keep the Nextcloud exclude policy standard
* use `--daemon-timeout 20s`
* use `--poll-interval 0`
* do not use `-o x-gvfs-hide` with Ubuntu apt rclone 1.60.x
* understand that rclone mount can temporarily show a stale cached view while direct WebDAV is fresh
* keep Dropbox completely out of scope
