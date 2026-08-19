# Client Tools & Diagnostics (`toolkit/client-tools/`)

Windows PowerShell utilities for extracting drivers, diagnosing installation failures, and verifying client status.

---

## 🛠️ Tool Index

| Tool | Purpose | Output |
| :--- | :--- | :--- |
| **`Win_setup_log_collector.ps1`** | Collects Windows setup logs (`setupact.log`, `setuperr.log`, Panther directory, DISM logs). | ZIP archive or output folder |
| **`Get-WindowsSetupLogs.ps1`** | Lightweight log retrieval script for rapid troubleshooting during OOBE / post-install phases. | Console / text summary |
| **`Export-DriversForOpsi.ps1`** | Exports all third-party drivers from the running Windows client using `Export-WindowsDriver` in `.inf` format. | Structured driver directory |
| **`Test-OpsiProducts.ps1`** | Validates product installation states against the local registry and WMI objects. | Pass/Fail report |
| **`Extract-OpsiData.ps1`** | Extracts metadata and package files from local client agent caches. | Extracted payloads |

---

## 💡 Usage Example

### Export Drivers for OPSI Integration:
```powershell
.\Export-DriversForOpsi.ps1 -Destination "C:\ExportedDrivers" -Verbose
```

### Collect Panther Failure Logs:
```powershell
.\Win_setup_log_collector.ps1 -OutputDir "C:\SetupLogs"
```
