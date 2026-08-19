# Universal Server Tools (`toolkit/server-tools/`)

General utilities for managing, updating, and compiling packages on any OPSI server.

---

## 🛠️ Tool Index

| Tool | Language | Purpose |
| :--- | :--- | :--- |
| **`build_packages.sh`** | Bash | Recursively searches for package directories and runs `opsi-makepackage` with automatic error trapping. |
| **`create_win11_opsi_netboot.sh`** | Bash | Generates the `win11-x64` netboot product structure on the OPSI server. |
| **`opsi-driver-sorter.sh`** | Bash | Parses vendor driver folders and categorizes `.inf` files into OPSI hardware directory hierarchies. |
| **`register_custom_package.sh`** | Bash | Registers and configures custom packages directly in the OPSI backend. |
| **`update_all.sh`** | Bash | High-level update orchestrator for OS packages, OPSI repositories, and installed products. |
| **`update_opsi_packages.sh`** | Bash | Synchronizes and updates core packages from upstream OPSI release depots. |
| **`repair.py`** | Python | Diagnostic and automatic remediation script for OPSI file permissions, depot ACLs, and service states. |
| **`install.sh`** | Bash | General installer bootstrapping script for server-side utilities. |
