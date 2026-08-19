# System Configuration — Operated System (`sopsi`)

This directory contains the **environment-specific configuration**, network definitions, unattended answer files, and server scripts tailored for the operated training environment (**`sopsi`**).

---

## 📋 Directory Contents

- **`environment.json`**: Central JSON configuration read by `Build-WinPE.ps1`, unattended generation scripts, and server deployment helpers.
- **`unattended/`**: XML answer files for automated Windows 11 Enterprise LTSC 2024 installations.
- **`server-config/`**: Shell scripts for initial provisioning, depot migration, and backend maintenance on the `sopsi` OPSI server.

---

## ⚙️ `environment.json` Configuration Reference

| Section | Key | Description |
| :--- | :--- | :--- |
| **`Build`** | `IsoPath` | Source WinPE or ADK ISO path (`D:\temp\WinPE.ISO`) |
| | `WinImageIsoPath` | Windows 11 Enterprise LTSC 2024 source ISO |
| | `OutputPath` | Local directory for output artifacts (`C:\PSC_WinPE_Output`) |
| | `DriverSource` | Folder containing hardware drivers (`.inf`) to inject |
| | `ToolsSource` | Folder containing portable utility tools to inject |
| **`Product`** | `ProductId` | Netboot product identifier (`win11-x64`) |
| | `ProductName` | Display name (`Windows 11 LTSC Enterprise`) |
| **`Windows`** | `ProductKey` | KMS Volume License Key |
| | `Locale` | System language (`de-DE`) |
| | `TimeZone` | Timezone (`W. Europe Standard Time`) |
| **`OPSI`** | `ServerAddress` | Hostname / IP of OPSI server (`sopsi`) |
| | `DepotBasePath` | Linux depot path (`/var/lib/opsi/depot`) |
| | `DepotSharePath` | Windows SMB share path (`Y:\`) |

---

## 🔐 Credentials Policy

Passphrases and private tokens must **never** be hardcoded into `environment.json`.
Use environment variables or runtime prompts during deployment:
- `$env:OPSI_SERVER_PASSWORD`
- `$env:LOCAL_ADMIN_PASSWORD`
