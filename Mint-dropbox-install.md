# Linux Mint (Cinnamon) – rclone + Dropbox (User‑Scoped Mount)

Eurobotics Wiki – Proven, production‑grade setup
Issued: 2026‑02‑14
Patched: 2026‑02‑14 – incorporates 3 field errors (log dir, FUSE user_allow_other, Dropbox Business vs personal root)

This document captures a known‑good, battle‑tested configuration for mounting Dropbox using **rclone** on **Linux Mint (Cinnamon, Ubuntu‑based)**.
The command and systemd unit below are the result of weeks of trial‑and‑error and are intentionally preserved verbatim.

> **Important:** This is a *mount* (FUSE filesystem), not a sync. Dropbox remains the source of truth.

---

## Defaults – you MUST adapt to your needs before use

```bash
My_Dropbox_Folder="$HOME/Dpbx-V"   # Default local mount folder – change to your own path
My_rclone_dpbx_label="dpbx"        # Default rclone remote label – change to your own label
```

These are examples only. Every admin must review and adapt them to their own naming conventions and directory layout.

---

## 0. Changelog & known pitfalls (why this doc was patched)

This patch explicitly documents three real‑world failure modes that occurred during deployment on multiple laptops.

### 0.1 Log directory missing

**Symptom:** rclone service loops with:

```
Failed to open log file: open /home/<USER>/.local/share/rclone/dropbox-mount.log: no such file or directory
```

**Fix:**

* Create the directory once:

```bash
mkdir -p ~/.local/share/rclone
```

* In the systemd unit, add an **ExecStartPre** to create it automatically.

### 0.2 FUSE user_allow_other not enabled

**Symptom (in dropbox-mount.log):**

```
mount helper error: fusermount: option allow_other only allowed if 'user_allow_other' is set in /etc/fuse.conf
Fatal error: failed to mount FUSE fs: fusermount: exit status 1
```

**Fix (one‑time system change):**

Edit `/etc/fuse.conf` as root and uncomment/add:

```
user_allow_other
```

**Important:** This is a manual, one‑time system change. The installer script must not do this silently.

### 0.3 Dropbox Business vs personal root (remote semantics)

**Symptom:** one machine shows Business/Team root folders at the mount root, another only shows personal space.

**Cause:** the rclone remote name and its config in `rclone.conf` were different between machines.

Example: `dropbox:` on machine A had full Dropbox Business/Team scopes, while `DpBx:` on machine B was configured only for the personal account space.

**Fix / recommendation:**

On all machines that must behave identically, either:

* Copy the same `~/.config/rclone/rclone.conf` file from a known‑good machine, or
* Re‑run `rclone config` with the same Dropbox Business account and scopes.

Use the same remote name (e.g. `dropbox`) everywhere when you want the same Business/Team root.

> **Optional but often necessary (Business):** If Team folders still don’t appear, you may need to set a **root namespace** for the Dropbox remote. See section 5.

---

## 1. Scope and design philosophy

### 1.1 User‑scoped by design (important)

This setup is user‑level, not system‑level:

* rclone runs as the logged‑in user
* The mount lives in the user’s home directory
* The systemd unit is a systemd **user** service (`systemctl --user`)

Therefore it will NOT appear in `sudo service` output.

### 1.2 Why not a system service?

* Dropbox data is user‑owned
* Credentials are user‑scoped
* FUSE permissions (allow_other) are simpler
* Desktop sessions, file managers (Nemo), IDEs behave correctly

---

## 2. Mental model – how this works

```
Dropbox Cloud
     ↑↓ (API, polling)
  rclone mount
     ↑↓ (FUSE filesystem)
$My_Dropbox_Folder   ← behaves like a local folder
```

Key points:

* No data is copied by default (this is not a sync)
* Files are streamed on demand
* Writes are buffered locally (VFS cache) then committed to Dropbox
* Dropbox remains the source of truth

If Dropbox is unavailable:

* The mount stays present
* rclone retries automatically
* No silent data deletion occurs

---

## 3. Cloud trust & data safety

### 3.1 Is there a risk of data loss?

No, under normal operation:

* Dropbox remains authoritative
* rclone does not delete remote data unless explicitly instructed
* Local cache is disposable

Important notes:

* This is not bidirectional sync (no background reconciliation)
* Conflicts are handled by Dropbox, not rclone
* The VFS cache may temporarily hold modified files until upload completes

If the machine crashes:

* Dropbox data remains intact
* At worst, a partially uploaded file is retried

---

## 4. Install rclone (Linux Mint)

The future `mint-dpbx_install.sh` will not install or configure rclone for you. It will only check that rclone and FUSE are installed, and fail with an explicit message if they are missing.

### Option A – Official rclone install (recommended)

```bash
curl https://rclone.org/install.sh | sudo bash
```

```bash
sudo apt update
sudo apt install -y fuse3
```

Verify:

```bash
rclone version
```

---

## 5. Configure Dropbox remote

This step is manual, interactive, and mandatory. The script will not run `rclone config`.

Run:

```bash
rclone config
```

Steps:

* `n` – New remote
* Name: `$My_rclone_dpbx_label` (example: `dropbox`)
* Storage: `dropbox`
* Complete browser OAuth flow

Verify:

```bash
rclone lsd "$My_rclone_dpbx_label":/
```

### 5.1 Dropbox Business: keeping “Team/Business root” consistent

If you expect to see Business / Team root folders at the mount root, you must ensure this remote is configured with the **same account and scopes** as any other machine where it already works.

Recommended:

* Copy `~/.config/rclone/rclone.conf` from a known‑good machine.

### 5.2 Dropbox Business (advanced): root namespace

If Team folders don’t appear even with the right account/scopes, the Dropbox Business setup may require setting a **root namespace** for this remote.

Admin approach:

* Identify the correct namespace for your Dropbox Business/team root.
* Set it in the rclone remote advanced options (or pass it as a mount flag if your rclone version supports it).

This is environment‑specific; keep machine configs consistent.

---

## 6. FUSE prerequisite (mandatory for this setup)

Because this configuration uses `--allow-other`, the system must allow it.

Check:

```bash
grep -n "user_allow_other" /etc/fuse.conf
```

If commented or missing:

```bash
# Option 1 – edit manually (recommended)
sudo nano /etc/fuse.conf

# Ensure it contains:
# user_allow_other
```

Or (explicit, but still admin‑initiated):

```bash
sudo sed -i 's/^# *user_allow_other/user_allow_other/' /etc/fuse.conf
```

**Important:** This is a one‑time system change. The installer script must not modify `/etc/fuse.conf` silently.

---

## 7. Proven rclone mount command (DO NOT SIMPLIFY)

This command is known to work reliably with Dropbox.

Example (replace `<USER>` or use `$HOME`):

```bash
/usr/bin/rclone mount "$My_rclone_dpbx_label": /home/<USER>/Dropbox-V \
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
  --log-file=/home/<USER>/.local/share/rclone/dropbox-mount.log \
  --log-level=INFO
```

### 7.1 Why these options matter

* `--vfs-cache-mode=full` → POSIX‑like behavior (editors/IDEs, save‑in‑place)
* Chunk + buffer tuning → avoids Dropbox API stalls
* `--dir-cache-time=1h` → balances freshness vs API limits
* `--poll-interval=30s` → Dropbox‑safe polling cadence
* Retries → resilience to Wi‑Fi/network drops

If this command fails, check:

* Does the log directory exist? `mkdir -p ~/.local/share/rclone`
* Is `user_allow_other` enabled in `/etc/fuse.conf`?
* Wrong rclone remote (personal vs Business)?

---

## 8. systemd user service (canonical)

### 8.1 Service name (fixed) vs remote label (variable)

For operational simplicity, the service name is fixed:

* Unit filename: `~/.config/systemd/user/dropbox-rclone.service`
* Service name: `dropbox-rclone.service`

This is independent of the rclone remote label (`$My_rclone_dpbx_label`).

### 8.2 Canonical unit file

Create:

`~/.config/systemd/user/dropbox-rclone.service`

```ini
[Unit]
Description=Rclone mount for Dropbox (user scoped, rclone label = $My_rclone_dpbx_label)

# Start after the user session is up; network wait is handled in ExecStartPre
After=default.target

[Service]
Type=notify

# Wait up to 30s for NetworkManager to report online; fall back to retries if not
ExecStartPre=/usr/bin/nm-online -x -q -t 30

# Ensure the mount directory and log directory exist
ExecStartPre=/usr/bin/mkdir -p %h/Dropbox-V
ExecStartPre=/usr/bin/mkdir -p %h/.local/share/rclone

ExecStart=/usr/bin/rclone mount $My_rclone_dpbx_label:/ %h/Dropbox-V \
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

Restart=always
RestartSec=10

[Install]
WantedBy=default.target
```

Enable:

```bash
systemctl --user daemon-reload
systemctl --user enable --now dropbox-rclone.service
```

Check:

```bash
systemctl --user status dropbox-rclone.service
```

---

## 9. Why it does NOT appear in sudo service

Because this is a systemd user service.

* `sudo service` lists system‑scope services only
* User services live under `user@UID.service`
* Manage with `systemctl --user`

This is expected and correct.

---

## 10. Boot behavior (advanced)

By default, user services start when the user session starts.

If you want the mount available before GUI login:

```bash
loginctl enable-linger <USER>
```

This allows user units to start at boot without an active GUI session.

---

## 11. Logs & debugging

Log file:

```bash
~/.local/share/rclone/dropbox-mount.log
```

Journal:

```bash
journalctl --user -u dropbox-rclone.service
```

If the service fails, check:

* Missing log directory?
* Missing `user_allow_other` in `/etc/fuse.conf`?
* Wrong rclone remote (personal vs Business)?

---

## 12. Installer script specification: mint-dpbx_install.sh

This document is designed so that an AI or human can implement a robust installer script named:

`mint-dpbx_install.sh`

### 12.1 Responsibilities – what the script MUST do

1. Check prerequisites

* Verify rclone exists (`command -v rclone`).
* Verify FUSE is available (`command -v fusermount3`).

If any check fails, the script must:

* Print a clear error message:

  * `"rclone and/or FUSE are not installed. Please install rclone, fuse3, and configure your Dropbox remote manually (rclone config) before re-running this script."`
* Exit with a non‑zero status.

2. Check environment / defaults

* If `My_Dropbox_Folder` is not set, default to `$HOME/Dropbox-V` and print a notice.
* If `My_rclone_dpbx_label` is not set, default to `dropbox` and print a notice.
* Echo the effective values.

3. Create directories

* `mkdir -p "$My_Dropbox_Folder"`
* `mkdir -p "$HOME/.local/share/rclone"` (avoids the log‑dir error)
* `mkdir -p "$HOME/.config/systemd/user"`

4. Generate the systemd user unit

* Path: `~/.config/systemd/user/dropbox-rclone.service`
* Use the rclone options from section 8.
* Use `$My_rclone_dpbx_label` for the remote and `$My_Dropbox_Folder` for the mount directory.

5. Reload and enable the unit

* `systemctl --user daemon-reload`
* `systemctl --user enable --now dropbox-rclone.service`

### 12.2 Responsibilities – what the script MUST NOT do

It must not:

* Install rclone itself.
* Run `rclone config` or create the Dropbox remote.
* Modify `/etc/fuse.conf`.

Those operations are explicitly left to the administrator, following sections 4, 5 and 6.

This ensures:

* Credentials and OAuth flows remain under human control.
* System‑wide FUSE policy changes are not made silently.
* The script is safe to run on production workstations.

---

## Status: VERIFIED – production‑safe (with above patches)

Admin action required:

* Always review and customize `My_Dropbox_Folder` and `My_rclone_dpbx_label`.
* Ensure `/etc/fuse.conf` contains `user_allow_other` when using `--allow-other`.
* For Dropbox Business, ensure all machines share a consistent rclone remote configuration if they must see the same Team/Business root.

---

## Cinnamon/Nemo usability notes (recommended)

* Create the mount folder under `$HOME` so Nemo sees it.
* Add a bookmark in Nemo for quick access.
* If you want the mount visible under “Devices”, that is a separate udisks/desktop integration topic; do not mix it into this mount spec.
