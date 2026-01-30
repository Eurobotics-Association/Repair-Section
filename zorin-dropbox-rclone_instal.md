# Zorin OS – rclone + Dropbox (User‑Scoped Mount)

> **Eurobotics Wiki** – Proven, production‑grade setup
> **Issued:** 2026‑01‑30 (Europe/Paris)
>
> This document captures a **known‑good, battle‑tested configuration** for mounting Dropbox using **rclone** on **Zorin OS (Ubuntu‑based)**.
> The command and systemd unit below are the result of **weeks of trial‑and‑error** and are intentionally preserved verbatim.
>
> **Defaults – you MUST adapt to your needs before use:**
>
> ```bash
> My_Dropbox_Folder="$HOME/Dropbox"       # Default local mount folder – change to your own path
> My_rclone_dpbx_label="DpBx"             # Default rclone remote label – change to your own label
> ```
>
> These are **examples only**. Every admin must review and adapt them to their own naming conventions and directory layout.

---

## 1. Scope and design philosophy

### User‑scoped by design (important)

This setup is **user‑level**, not system‑level:

* rclone runs as the **logged‑in user**
* The mount lives in the user’s home directory
* The systemd unit is a **systemd user service** (`systemctl --user`)
* Therefore it **will NOT appear in** `sudo service` output

This is the **correct and recommended model** for Dropbox on a workstation/laptop.

### Why not a system service?

* Dropbox data is user‑owned
* Credentials are user‑scoped
* FUSE permissions (`allow_other`) are simpler
* Desktop sessions, file managers, and IDEs behave correctly

---

## 2. Mental model – how this works

```text
Dropbox Cloud
     ↑↓ (API, polling)
  rclone mount
     ↑↓ (FUSE filesystem)
$My_Dropbox_Folder   ← behaves like a local folder
```

Key points:

* **No data is copied by default** (this is not a sync)
* Files are streamed on demand
* Writes are buffered locally (VFS cache) then committed to Dropbox
* Dropbox remains the **source of truth**

If Dropbox is unavailable:

* The mount stays present
* rclone retries automatically
* No silent data deletion occurs

---

## 3. Cloud trust & data safety

### Is there a risk of data loss?

**No**, under normal operation:

* Dropbox remains authoritative
* rclone does not delete remote data unless explicitly instructed
* Local cache is disposable

Important notes:

* This is **not bidirectional sync** (no background reconciliation)
* Conflicts are handled by Dropbox, not rclone
* The VFS cache may temporarily hold modified files until upload completes

If the machine crashes:

* Dropbox data remains intact
* At worst, a partially uploaded file is retried

---

## 4. Install rclone

> The future `zorin-dpbx_install.sh` **will not install or configure rclone for you**.
> It will only **check** that `rclone` and FUSE are installed, and **fail with an explicit message** if they are missing.

### Option A – Official rclone install (recommended)

```bash
curl https://rclone.org/install.sh | sudo bash
```

### Option B – APT (Zorin / Ubuntu)

```bash
sudo apt update
sudo apt install -y rclone fuse3 network-manager
```

Verify:

```bash
rclone version
```

---

## 5. Configure Dropbox remote

> This step is **manual, interactive, and mandatory**. The script will **not** run `rclone config`.

Run:

```bash
rclone config
```

Steps:

1. **n** – New remote
2. Name: `$My_rclone_dpbx_label` (example: `DpBx`, `dropbox`, etc.)
3. Storage: `dropbox`
4. Complete browser OAuth flow

Verify:

```bash
rclone lsd $My_rclone_dpbx_label:/
```

If this command fails, the installer script **must not** proceed.

---

## 6. FUSE prerequisite (mandatory for this setup)

Because this configuration uses `--allow-other`, the system must allow it.

Check:

```bash
grep -n "user_allow_other" /etc/fuse.conf
```

If commented or missing:

```bash
sudo sed -i 's/^# *user_allow_other/user_allow_other/' /etc/fuse.conf
```

This is a **one‑time system change**.

---

## 7. Proven rclone mount command (DO NOT SIMPLIFY)

> This command is known to work reliably with Dropbox.
> You MUST export the variables to match your environment before running it.

Export variables (example):

```bash
export My_Dropbox_Folder="$HOME/Dropbox"   # adapt to your path
export My_rclone_dpbx_label="DpBx"         # adapt to your rclone remote name
```

Mount command:

```bash
/usr/bin/rclone mount "$My_rclone_dpbx_label": "$My_Dropbox_Folder" \
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
  --log-file="$HOME/.local/share/rclone/dropbox-mount.log" \
  --log-level=INFO
```

### Why these options matter

* `--vfs-cache-mode=full` → POSIX‑like behavior (editors, IDEs, save‑in‑place)
* Chunk + buffer tuning → avoids Dropbox API stalls
* `--dir-cache-time=1h` → balances freshness vs API limits
* `--poll-interval=30s` → Dropbox‑safe polling cadence
* Retries → resilience to Wi‑Fi/network drops

---

## 8. systemd user service (canonical)

Location (for the default label `DpBx`):

```text
~/.config/systemd/user/DpBx-rclone.service
```

> The installer script will generate this file dynamically using the chosen values of `My_rclone_dpbx_label` and `My_Dropbox_Folder`.

Rendered example (for `My_rclone_dpbx_label="DpBx"` and `My_Dropbox_Folder="$HOME/Dropbox"`):

```ini
[Unit]
Description=Rclone mount for Dropbox (user scoped, rclone label = DpBx)

# Start after the user session is up; network wait is handled in ExecStartPre
After=default.target

[Service]
Type=notify

# Wait up to 30s for NetworkManager to report online; fall back to retries if not
ExecStartPre=/usr/bin/nm-online -x -q -t 30

# Ensure the mount directory exists (this path must match My_Dropbox_Folder)
ExecStartPre=/usr/bin/mkdir -p %h/Dropbox

ExecStart=/usr/bin/rclone mount DpBx:/ %h/Dropbox \
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

Enable (for the default label `DpBx`):

```bash
systemctl --user daemon-reload
systemctl --user enable --now DpBx-rclone.service
```

Check:

```bash
systemctl --user status DpBx-rclone.service
```

When you change `My_rclone_dpbx_label`, you must update:

* The unit filename: `~/.config/systemd/user/<label>-rclone.service`
* The `ExecStart` remote: `<label>:/`
* The `systemctl` commands: `enable --now <label>-rclone.service`

The installer script will handle this mapping.

---

## 9. Why it does NOT appear in `sudo service`

Because this is a **systemd user service**.

* `sudo service` lists **system‑scope services only**
* User services live under `user@UID.service`
* Manage with `systemctl --user`

This is expected and correct.

---

## 10. Boot behavior (advanced)

By default, user services start **when the user session starts**.

If you want the mount available **before GUI login**:

```bash
loginctl enable-linger <USER>
```

This allows user units to start at boot without an active GUI session.

---

## 11. Logs & debugging

Log file (for the example config):

```bash
~/.local/share/rclone/dropbox-mount.log
```

Journal:

```bash
journalctl --user -u DpBx-rclone.service
```

If you change the label, adjust the service name accordingly.

---

## 12. Installer script specification: `zorin-dpbx_install.sh`

This document is designed so that an AI or human can implement a robust installer script named:

```text
zorin-dpbx_install.sh
```

### 12.1 Responsibilities – what the script MUST do

1. **Check prerequisites**

   * Verify `rclone` exists (`command -v rclone`).
   * Verify FUSE is available (`command -v fusermount3` or package presence).
   * If any check fails, the script must:

     * Print a clear error message: e.g. "rclone and/or FUSE are not installed. Please install rclone, fuse3, and configure your Dropbox remote manually (rclone config) before re-running this script."
     * Exit with a non-zero status.

2. **Check environment / defaults**

   * If `My_Dropbox_Folder` is not set, default to `$HOME/Dropbox` and print a notice.
   * If `My_rclone_dpbx_label` is not set, default to `DpBx` and print a notice.
   * Echo the effective values and request a short confirmation (or provide a `--yes` flag for non-interactive use).

3. **Create the mount directory**

   * `mkdir -p "$My_Dropbox_Folder"`

4. **Generate the systemd user unit**

   * Path: `~/.config/systemd/user/${My_rclone_dpbx_label}-rclone.service`
   * Use the rclone options from section 7.
   * Replace `DpBx` and `Dropbox` paths with the effective values of `My_rclone_dpbx_label` and `My_Dropbox_Folder`.

5. **Reload and enable the unit**

   * `systemctl --user daemon-reload`
   * `systemctl --user enable --now ${My_rclone_dpbx_label}-rclone.service`

### 12.2 Responsibilities – what the script MUST NOT do

* It must **not**:

  * Install `rclone` itself.
  * Run `rclone config` or create the Dropbox remote.
  * Modify `/etc/fuse.conf`.
* Those operations are **explicitly left to the administrator**, following sections 4, 5 and 6.

This ensures:

* Credentials and OAuth flows remain under human control.
* System-wide FUSE policy changes are not made silently.
* The script is safe to run on production workstations.

---

**Status:** VERIFIED – production‑safe with defaults (after adaptation)
**Admin action required:** Always review and customize `My_Dropbox_Folder` and `My_rclone_dpbx_label` before using any generated installer script.
