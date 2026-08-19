# Automated Test Suites (`toolkit/tests/`)

This directory unifies automated unit, integration, and regression tests across the OPSI toolchain.

---

## 🧪 Test Structure

- **`pester/`**: PowerShell unit and integration tests for WinPE building, driver export, and log collection (`*.Tests.ps1`).
- **`bats/`**: Bash Automated Testing System test suites for Linux server scripts (`*.bats`).
- **`python/`**: Python test cases for server repair and automation modules (`test_*.py`).

---

## ▶️ Running Tests

### Running PowerShell Pester Tests (Windows)
```powershell
Invoke-Pester -Path toolkit\tests\pester\*.Tests.ps1 -Output Detailed
```

### Running Bats Tests (Linux / WSL)
```bash
bats toolkit/tests/bats/opsi-driver-sorter.bats
bats toolkit/tests/bats/opsi-repo-config.bats
```

### Running Python Tests
```bash
python3 -m unittest discover -s toolkit/tests/python -p "test_*.py"
```
