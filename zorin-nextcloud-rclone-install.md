# ZorinOS — Nextcloud via rclone mount

This ZorinOS note intentionally reuses the standard Nextcloud installer and laptop audit/repair flow from:

```text
nextcloud-rclone-install.md
nextcloud-rclone-install.sh
surface7-nextcloud-rclone-audit.sh
```

ZorinOS is Ubuntu-family, so the same rclone/FUSE/WebDAV architecture is used:

```text
rclone mount → FUSE → WebDAV/Nextcloud → GNOME/GVfs/Zorin Files
```

The service profile for ZorinOS should match the validated Ubuntu laptop profile:

```text
--exclude-from %h/.config/rclone/nextcloud-excludes.txt
--daemon-timeout 20s
--poll-interval 0
```

Do **not** use `-o x-gvfs-hide` as a standard option for Ubuntu/ZorinOS apt rclone 1.60.x. On the validated Surface Pro 7 setup, apt rclone reported:

```text
-o/--option not supported with this FUSE backend
```

Do **not** add the Nextcloud exclude file to Dropbox services. Existing Zorin Dropbox rclone documentation and scripts are separate and must remain Dropbox-only.

## ZorinOS validation checklist

After installing or repairing the Nextcloud mount, run as the desktop user:

```bash
systemctl --user status nextcloud-rclone.service --no-pager
systemctl --user cat nextcloud-rclone.service | grep -E 'exclude-from|daemon-timeout|poll-interval|x-gvfs-hide'
journalctl --user -u nextcloud-rclone.service -n 120 --no-pager
time rclone lsd nextcloud:/
time ls -la /media/$USER/nextcloud | head
```

Expected service profile:

```text
present: --exclude-from %h/.config/rclone/nextcloud-excludes.txt
present: --daemon-timeout 20s
present: --poll-interval 0
absent : -o x-gvfs-hide
absent : --poll-interval 30s
```

Also test file dialogs and suspend/resume. ZorinOS may probe mounted filesystems differently from stock Ubuntu, so desktop behaviour must be validated on each laptop.
