> [!CAUTION]
> **DEPRECATED / ARCHIVED REPOSITORY**
> This monolithic repository has been split into three modular, specialized repositories:
> - ⚙️ **[opsi_config](file:///c:/GitHub/opsi_config)**: Server configurations, environment parameters, unattended XML answer files.
> - 📦 **[opsi_packages](file:///c:/GitHub/opsi_packages)**: OPSI product package definitions (`Xournalpp`, `PS-Scripts`, `msoffice2013`) & compilation tools.
> - 🛠️ **[opsi_infra](file:///c:/GitHub/opsi_infra)**: WinPE builder, server health repair tools, client diagnostics, and test suites.
>
> All new development and maintenance MUST occur in the modular repositories above using `pyinfra` and `just`.

# opsi_scripts — Enterprise Deployment & Automation Infrastructure

> **Architecture Split SSOT**: This repository is structured into two cleanly separated domains:
> 1. **`system-config/`**: Specific environment configuration, server endpoints, and unattend files for the operated training system (`sopsi`).
> 2. **`packages/` & `toolkit/`**: Universal, reusable OPSI product definitions, WinPE image generator tools, client diagnostics, and automated test suites.

---

## 📂 Repository Structure

```
opsi_scripts/
│
├── 📂 system-config/               # 1. SPECIFIC SYSTEM CONFIGURATION (Operated System 'sopsi')
│   ├── README.md                   # Environment architecture, endpoints, and deployment guide
│   ├── environment.json            # Central system settings (Depot paths, KMS keys, build options)
│   ├── 📂 unattended/              # Windows unattended setup files
│   │   ├── Autounattend_OPSI.xml   # Network-based OPSI unattended setup
│   │   ├── Autounattend_USB.xml    # Standalone USB deployment answer file
│   │   ├── wim.xml                 # WIM image metadata for Windows 11 Enterprise LTSC 2024
│   │   └── [1].xml                 # Image index 1 XML definition
│   └── 📂 server-config/           # Server-specific configurations & depot migration scripts
│       ├── set_opsi_defaults.sh    # Apply default configurations on 'sopsi' server
│       ├── opsi-repo-config.sh     # Repo URL and proxy configuration
│       ├── install_o4i_repo.sh     # OPSI 4.1/4.2 repository installation
│       ├── migrate_depot.sh        # Depot migration and sync
│       ├── redis_fix.sh            # OPSI redis backend repair
│       ├── remote_fix.sh           # SSH and remote execution permission fixes
│       └── update_eurooffice.sh    # EuroOffice package updater
│
├── 📂 packages/                    # 2. OPSI PRODUCT PACKAGES (Reusable Packaging Sources)
│   ├── README.md                   # OPSI product creation, control schema, and build guide
│   ├── 📂 Xournalpp/               # Xournal++ packaging (setup, uninstall, control)
│   └── 📂 PS-Scripts/              # Generic PowerShell wrapper package for custom scripts
│
├── 📂 toolkit/                     # 3. UNIVERSAL OPSI TOOLKIT & AUTOMATION
│   ├── README.md                   # Master toolkit documentation & CLI execution
│   ├── 📂 winpe-builder/           # Complete WinPE image creator, BCD repair & deploy engine
│   │   ├── Build-WinPE.ps1         # Modular WinPE builder with driver & tools injection
│   │   ├── copyWinPE.ps1           # ISO / WIM deployment helper
│   │   ├── WinPE_bootfix.ps1       # BCD / UEFI boot repair utility
│   │   ├── Deploy-ToServer.ps1     # Push generated WinPE to OPSI depot
│   │   └── 🚀_WinPE_ADK_Auto.bat    # Automated Windows ADK build launcher
│   ├── 📂 server-tools/            # Generic OPSI server maintenance & package management
│   │   ├── build_packages.sh       # Multi-package compile utility
│   │   ├── create_win11_opsi_netboot.sh # Windows 11 netboot product builder
│   │   ├── opsi-driver-sorter.sh   # Automated driver extraction & categorization
│   │   ├── register_custom_package.sh # Package registration helper
│   │   ├── update_all.sh           # Comprehensive server & package update
│   │   └── repair.py               # Automated server health repair tool
│   ├── 📂 client-tools/            # Windows client diagnostics & log collection
│   │   ├── Win_setup_log_collector.ps1 # Setupact / panther log collector
│   │   ├── Get-WindowsSetupLogs.ps1    # Automated setup log retrieval
│   │   ├── Export-DriversForOpsi.ps1   # Export installed client drivers to .inf
│   │   └── Test-OpsiProducts.ps1       # Client package verification
│   ├── 📂 tests/                   # Unified automated test suites
│   │   ├── 📂 pester/              # PowerShell Pester tests (*.Tests.ps1)
│   │   ├── 📂 bats/                # Bash Automated Testing System (*.bats)
│   │   └── 📂 python/              # Python unit tests
│   └── 📂 archive/                 # Historical script versions (preserved with 100% git history)
│
└── README.md                       # Master overview (this file)
```

---

## 🚀 Quick Start

### 1. Build a Custom WinPE Image
```powershell
cd toolkit\winpe-builder
.\Build-WinPE.ps1 -ConfigFile "..\..\system-config\environment.json"
```

### 2. Collect Client Logs on Failure
```powershell
cd toolkit\client-tools
.\Win_setup_log_collector.ps1 -OutputDir "C:\SetupLogs"
```

### 3. Run Automated Tests
```powershell
# Run Pester test suites
Invoke-Pester -Path toolkit\tests\pester\*.Tests.ps1

# Run Bats tests on Linux / WSL
bats toolkit/tests/bats/*.bats
```

---

## 🔒 Secrets & Environment Management

Real credentials, server passwords, and private tokens must **never** be committed to Git.
- Real environment configurations are gitignored or referenced via environment variables (`OPSI_PASSWORD`, `HF_TOKEN`).
- See [`system-config/environment.json`](file:///c:/GitHub/opsi_scripts/system-config/environment.json) for the configuration schema.

