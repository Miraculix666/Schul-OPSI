# OPSI Product Packages (`packages/`)

This directory contains the source definitions for custom OPSI software products.

---

## 📦 Anatomy of an OPSI Package

Each package directory follows standard OPSI product structure:

```
packages/<ProductName>/
├── OPSI/
│   └── control                   # Package metadata, version, dependencies, and product properties
├── CLIENT_DATA/
│   ├── setup.opsiscript          # Main installation script executed by opsi-client-agent
│   ├── uninstall.opsiscript      # Clean uninstallation logic
│   └── files/                    # Binaries, installers, or configuration files
└── README.md                     # Product-specific deployment and testing notes
```

---

## 🛠️ Available Packages

| Package | Description | Script Engine |
| :--- | :--- | :--- |
| **[`Xournalpp`](./Xournalpp)** | Xournal++ handwriting note-taking software installer. | OPSI-Script (`setup.opsiscript`) |
| **[`PS-Scripts`](./PS-Scripts)** | Generic PowerShell execution wrapper allowing modular PS1 execution via OPSI. | OPSI-Script + PowerShell (`run_wrapper.ps1`) |

---

## 🔨 Building and Publishing Packages

To build an `.opsi` package file from source on the server:

```bash
cd /path/to/packages/Xournalpp
opsi-makepackage

# Install into local depot
opsi-package-manager -i xournalpp_*.opsi
```
