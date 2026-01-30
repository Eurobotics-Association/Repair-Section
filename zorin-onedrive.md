# OneDrive on Zorin OS 18 – Decision Note

*Last updated: 2026-01-30*

## 1. Context & Requirements

Machine: **Surface Pro 5  laptop** (Zorin OS 18, Ubuntu 24.04 base).

Requirements:

* OneDrive **Personal / Microsoft 365 Family** account.
* **Cloud drive / on-demand access**:

  * Browse full OneDrive tree from the file manager.
  * Files downloaded **only when opened**.
  * New / edited files on the laptop should be pushed back to OneDrive.
* **No full sync** (disk constraint: ~100 GB free, OneDrive >> 100 GB).

Conclusion: classic sync clients are out; we need a **network / cloud filesystem** behaviour.

---

## 2. Options Considered (and Why We Don’t Use Them)

### 2.1 GNOME Online Accounts / Native OneDrive

**What it is**
GNOME Online Accounts (GOA) in GNOME 46 (used by Zorin 18) exposes a "Microsoft 365 / OneDrive" integration that mounts OneDrive directly in Nautilus.

**Why it’s not the default here**

* Experience on Zorin 17 with Microsoft accounts has been **unreliable** (auth OK but mount not usable, or flaky behaviour over time).
* For Family / Personal accounts, there are **known bugs** upstream (auth succeeds but no usable drive, or random failures after system updates).
* Debugging GOA/OneDrive is non-trivial; logs are scattered and behaviour is tightly coupled to GNOME internals.

**Decision**: keep GOA as a **fallback experiment**, but **do not rely on it** for day‑to‑day access on Anna’s laptop.

---

### 2.2 rclone mount (OneDrive)

**What it can do**
`rclone mount` can present OneDrive as a FUSE filesystem, with VFS caching so only opened files are downloaded. This would match the desired "cloud drive" behaviour.

**Problems observed / known issues**

* rclone + OneDrive currently suffers from **Microsoft Graph / OneDrive backend issues**:

  * `invalidRequest: invalidResourceId: ObjectHandle is Invalid` when listing root or entering certain folders (esp. **Personal Vault** and some **new Microsoft / Family accounts**).
  * Intermittent token / `invalid_grant` problems during OAuth.
* Bugs about these behaviours have been open for **months to years** with no definitive fix.
* We already use rclone+FUSE for **Dropbox** on another machine; adding another fragile OneDrive mount on Anna’s laptop is additional complexity with no guarantee of stability.

**Decision**: rclone remains a powerful tool for **backup and scripting**, but **not used as the primary OneDrive cloud drive** on Zorin 18.

---

### 2.3 Onedriver (FUSE, on‑demand)

**What it is**
Onedriver is a FUSE filesystem for OneDrive that:

* Mounts OneDrive at a local directory.
* Lists everything immediately.
* Downloads file content **on demand**, and caches locally.

This is conceptually the **ideal** solution for our use case.

**What happened in practice**

* On Zorin 17, auth fails with a Microsoft error:

  * `AADSTS70000: The provided value for the 'code' parameter is not valid... (invalid_grant)`
* This happens **after** login/consent in the browser, during token exchange.
* This strongly suggests a **broken OAuth flow / app registration** on onedriver’s side or a backend change by Microsoft.
* There is no local configuration knob that fixes this; it needs an upstream app / code update.

**Decision**: mark Onedriver as **currently broken for our account**. Do **not** use it on Zorin 18 until there is a confirmed upstream fix.

---

### 2.4 OneDrive Client for Linux (abraunegg)

**What it is**
A mature, actively maintained **sync client** for OneDrive (Personal, Business, M365, SharePoint).

**Why it’s not appropriate here**

* It is a **sync** client by design:

  * Mirrors selected OneDrive folders **locally**.
  * Even with selective sync, this consumes significant disk space.
* Anna’s laptop has only ~100 GB free; OneDrive storage is much larger.
* The goal is **cloud‑only access**, not a local mirror.

**Decision**: keep this in mind for **backup / server use**, but **not for a small HD laptop**.

---

## 3. Final Choice: ExpanDrive on Zorin 18

### 3.1 Why ExpanDrive

* ExpanDrive is a cross‑platform client that mounts cloud storage (including **OneDrive**) as a **network drive**, with on‑demand access.
* Behaviour matches our requirements:

  * Shows full OneDrive tree.
  * Downloads files when accessed.
  * No automatic full sync of the 500+ GB cloud.
* As of mid‑2025, the desktop client is **free for personal use**, which fits Anna’s usage.
* On **Zorin OS 18**, with Anna’s Microsoft account, ExpanDrive:

  * Installed cleanly from the `.deb` package.
  * OneDrive authentication worked **on the first try**.
  * The drive appeared and mounted as a cloud filesystem without additional tweaking.

**Policy decision**:

> On Zorin 18 laptops with Microsoft 365 Family / Personal accounts and limited disk, **ExpanDrive is the default OneDrive client**, providing cloud‑only access.

---

## 4. Installation & Setup Steps (Recap)

### 4.1 Install ExpanDrive (Zorin 18)

1. Download the latest Linux `.deb` from the ExpanDrive website.
2. In a terminal:

   ```bash
   cd "$HOME/Downloads"
   sudo apt install ./ExpanDrive_*_amd64.deb
   ```

   * This installs ExpanDrive and adds its apt repository for future updates.

### 4.2 First‑time configuration for Anna’s OneDrive

1. Launch **ExpanDrive** from the Zorin menu.
2. Create a **new drive**:

   * Provider: **OneDrive**.
   * Name: e.g. `OneDrive`.
   * Mode: leave as default network drive / mounted drive (no full sync).
3. Click **Connect / Authenticate**:

   * Browser opens Microsoft login.
   * Log in with Anna’s Microsoft account (OneDrive owner).
   * Accept requested permissions.
4. After closing the browser, ExpanDrive should show the new drive as **Connected**.

### 4.3 Using the drive as a cloud filesystem

* ExpanDrive mounts the drive under a directory in the user’s home, typically something like:

  ```text
  ~/ExpanDrive/OneDrive
  ```

* In **Files (Nautilus)**:

  * Navigate to `Home → ExpanDrive → OneDrive`.
  * Browse folders; files are **listed immediately**.
  * Opening a file causes ExpanDrive to download it on demand.
  * Creating or editing a file in this directory uploads changes back to OneDrive.

---

## 5. Start ExpanDrive on Login

To make the OneDrive cloud drive available automatically after login:

### 5.1 Inside ExpanDrive

* If ExpanDrive offers a **“Start at login”** or **“Launch at startup”** setting:

  * Enable it.

### 5.2 Via Zorin Startup Applications (fallback)

If needed, configure startup manually:

1. Open **Startup Applications** in Zorin.
2. Add a new entry:

   * **Name**: `ExpanDrive`
   * **Command**: `expandrive`
   * **Comment**: `Mount OneDrive via ExpanDrive on login`
3. Save.

At next login, ExpanDrive will start automatically and mount `Anna-OneDrive` as a cloud drive.

---

## 6. Operational Notes & Caveats

* This setup is **cloud‑only**: files reside in OneDrive; only accessed files are cached locally.
* If Microsoft changes Graph/OAuth behaviour again and ExpanDrive breaks:

  * First, update ExpanDrive via `apt upgrade` or re‑install the latest `.deb`.
  * If OneDrive no longer mounts, fall back (temporarily) to **web access** and reassess available clients.
* We **intentionally avoid**:

  * GNOME Online Accounts / OneDrive as the primary client.
  * rclone+OneDrive mounts for daily usage on this laptop.
  * Full‑sync clients (abraunegg `onedrive`) due to disk constraints.

This note is the reference for future reinstall / troubleshooting of OneDrive access on Zorin 18 machines with similar constraints.
