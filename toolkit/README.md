# Universal OPSI Automation Toolkit (`toolkit/`)

This directory contains universal automation tools, image generators, diagnostics, and test suites that operate independently of a specific deployment server.

---

## 📂 Subdirectories

- **[`winpe-builder/`](./winpe-builder)**: Complete Windows Preinstallation Environment (WinPE) generator with driver injection, recovery tools, and automated deployment to OPSI depots.
- **[`server-tools/`](./server-tools)**: Generic OPSI server maintenance scripts, batch package compiler, and automated driver sorter.
- **[`client-tools/`](./client-tools)**: Windows client-side log collectors, driver export utilities, and package test runners.
- **[`tests/`](./tests)**: Unified test suites (PowerShell Pester, Bats, Python).
- **[`archive/`](./archive)**: Historical and deprecated script iterations preserved with 100% Git history.

---

## 🚀 Key Workflows

### Build & Deploy WinPE Image
```powershell
cd toolkit\winpe-builder
.\Build-WinPE.ps1 -ConfigFile "..\..\system-config\environment.json" -Verbose
```

### Batch Compile Packages on Linux Server
```bash
cd toolkit/server-tools
bash build_packages.sh /path/to/packages
```

### Collect Panther & Setup Logs from Client
```powershell
cd toolkit\client-tools
.\Win_setup_log_collector.ps1 -OutputDir "C:\Logs\Setup"
```
