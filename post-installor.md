# 🛠️ Zorin Postinstall Script Manual

## 📦 Overview
The **Zorin Post-Install Script** automates the setup and configuration of a Zorin OS installation to ensure security, convenience, and useful utilities for general-purpose and remote-friendly computing. It is designed for use after a clean installation and must be run with root privileges.

---

## 🧰 Features Summary
| Category               | Tasks Performed |
|------------------------|-----------------|
| ✅ System Update       | - `apt update && full-upgrade`<br>- Installs and configures automatic updates |
| 🔐 Security Setup      | - Installs UFW and Gufw (GUI)<br>- Enables firewall with IoT-friendly settings<br>- Ports opened for RustDesk, SSH, mDNS, Google OAuth, IPP, SAMBA, NFS, Nextcloud, Home Assistant, Alexa, UPnP/STUN |
| 🖧 SSH & Remote Access | - Installs and secures OpenSSH for key-only login<br>- Reports current rules and offers override<br>- Configures Serveo.net for SSH tunneling |
| ⚙️ Utilities           | - Installs Timeshift, Wine, Bottles, Flatpak, Thonny, Dropbox, RustDesk |
| 📁 Office Replacement  | - Installs OnlyOffice (Flatpak)<br>- Removes LibreOffice suite |
| 🖨️ Printer Fixes       | - Fixes common issues<br>- Installs Brother drivers<br>- Reconfigures CUPS |
| 🧪 Hardware Checks     | - Uses `ubuntu-drivers` and `inxi` to detect unclaimed devices |
| 📜 Log Analysis        | - Parses system logs (`journalctl`, `dmesg`) for recent errors |
| 🧹 Cleanup             | - Runs `apt autoremove` and `apt clean` |

---

## 🚀 Execution Instructions
```bash
sudo ./zorin-postinstall.sh
```

### 🧷 Prerequisites
- Must be run as **root** (via `sudo`)
- Requires internet access
- Recommended on **fresh Zorin OS installations**

---

## 🔍 Script Flow
```text
1. check_internet
2. update_system
3. setup_ssh_server
4. install_security_tools
5. configure_firewall
6. install_serveo
7. install_core_utilities
8. install_onlyoffice
9. verify_hardware
10. fix_printer_issues
11. analyze_logs
12. cleanup
```

---

## ⚠️ Prompts During Execution
- Confirm override of **UFW** rules
- Ask if you want to enable **IoT ports** (Alexa, Google Home, Home Assistant, etc.)

---

## 📁 Log Files
- Script execution log: `/var/log/zorin-postinstall.log`
- Log analysis report: `/var/log/zorin-log-analysis.txt`

---

## 🧩 Customization Ideas
You can extend the script by adding:
- Your favorite dev tools (VS Code, Git, Docker)
- Backup configs (e.g., `rsync` + cronjobs)
- GUI theming or performance tweaks

---

## 📜 License
**Eurobotics 2025 – GNU License**  
Free to use and modify. Contributions welcome.

---

## 🧠 Maintainer Tips
- **Always test on a VM** before using in production
- Maintain a changelog and version (`v.YYYYMMDD.HHMM` format is used)
- Audit firewall and SSH changes periodically

---

## 🙌 Credits
Made with ❤️ by the Eurobotics team for streamlined deployments in labs, homes, or small organizations.
