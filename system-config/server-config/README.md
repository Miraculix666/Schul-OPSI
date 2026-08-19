# Server Configuration Scripts (`sopsi`)

This folder contains operational shell scripts designed specifically for the **`sopsi`** OPSI Linux server.

---

## 🛠️ Script Reference

| Script | Purpose |
| :--- | :--- |
| **`set_opsi_defaults.sh`** | Applies standard depot paths, user permissions, and default client settings. |
| **`opsi-repo-config.sh`** | Configures upstream OPSI repositories, mirror URLs, and network proxy rules. |
| **`install_o4i_repo.sh`** | Registers and installs the OPSI 4.1/4.2 package repository on the server. |
| **`migrate_depot.sh`** | Facilitates migrating packages and client states from a legacy depot to the current server. |
| **`migrate_opsi_depot.sh`** | Rsync-based depot synchronization helper with permission preservation. |
| **`redis_fix.sh`** | Reinitializes or repairs the OPSI Redis state cache backend. |
| **`remote_fix.sh`** | Fixes SSH permissions, sudoer privileges, and remote management access. |
| **`terminal_fix.sh`** | Corrects terminal locale (`UTF-8`), character encodings, and console prompt formatting. |
| **`update_eurooffice.sh`** | Updates the EuroOffice software package on the depot. |
| **`examples.desktop`** | Desktop shortcut configuration for the server administrator interface. |

---

## 💻 Execution on `sopsi`

Execute these scripts directly on the server as `root` or using `sudo`:

```bash
# Apply default server settings
sudo bash set_opsi_defaults.sh

# Configure repository mirrors
sudo bash opsi-repo-config.sh
```
