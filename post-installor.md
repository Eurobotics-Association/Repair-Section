# 🛠️ Zorin Postinstall Script Manual (Zorin OS 18+)

## 📦 Overview
The **Zorin Post-Install Script** automates the setup and configuration of a Zorin OS installation (Zorin OS 18 or later) to ensure security, convenience, and useful utilities for general-purpose and remote-friendly computing. It is designed for use after a clean installation and must be run with root privileges.

---

## 🧰 Features Summary
| Category               | Tasks Performed |
|------------------------|-----------------|
| ✅ System Update       | - `apt update && full-upgrade`<br>- Enables unattended security updates without prompts |
| 🔐 Security Setup      | - Installs UFW and Gufw (GUI)<br>- Enables firewall with IoT-friendly settings<br>- Ports opened for SSH, Serveo, HTTP/S, STUN, mDNS, RustDesk, Apple ecosystem, and ZeroTier |
| 🖧 SSH & Remote Access | - Installs OpenSSH with password auth enabled<br>- Reports current rules and offers override<br>- Configures Serveo.net for SSH tunneling |
| 🧪 Malware Protection  | - Installs ClamAV with on-access Downloads scanning<br>- Schedules a low-priority monthly full scan of `/home` |
| ⚙️ Utilities           | - Installs Timeshift, Wine, Bottles, Flatpak, Thonny, rsync, RustDesk, Ngrok |
| 📁 Office Replacement  | - Installs OnlyOffice (official repo or Flatpak fallback)<br>- Removes LibreOffice suite (APT/Snap/Flatpak cleanup) |
| 🌐 Mesh Networking     | - Installs ZeroTier and enables service |
| 🖨️ Printer Fixes       | - Fixes common issues<br>- Installs Brother drivers<br>- Reconfigures CUPS |
| 🧪 Hardware Checks     | - Uses `ubuntu-drivers` and `inxi` to detect unclaimed devices |
| 📜 Log Analysis        | - Parses system logs (`journalctl`, `dmesg`) for recent errors |
| 🧹 Cleanup             | - Runs `apt autoremove` and `apt clean` |

---

## 🚀 Execution Instructions
```bash
sudo ./post-installor.sh
```

### 🧷 Prerequisites
- Must be run as **root** (via `sudo`)
- Requires internet access
- Recommended on **fresh Zorin OS 18+ installations**

---

## 🔍 Script Flow
```text
1. check_internet
2. update_system
3. setup_ssh_server
4. install_security_tools
5. configure_firewall
6. install_ngrok
7. install_serveo
8. install_core_utilities
9. install_onlyoffice
10. install_zerotier
11. verify_hardware
12. fix_printer_issues
13. analyze_logs
14. cleanup
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
