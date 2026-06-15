# PowerShell Script Runner (ps-scripts)

Dieses OPSI-Produkt ermöglicht es, beliebige PowerShell-Skripte auf den Clients auszuführen. Die Skripte werden über einen Wrapper (`run_wrapper.ps1`) ausgeführt, der die Steuerung der ExecutionPolicy und die verdeckte Ausführung (Silent-Modus) übernimmt.

## ⚙️ Parameter (Product Properties)

* **execution_policy**: Die PowerShell-ExecutionPolicy für die Ausführung (Standard: `Bypass`).
* **silent**: Gibt an, ob die Skripte unsichtbar ausgeführt werden (Standard: `true`).
* **script_filter**: Filter für auszuführende Skripte im `scripts`-Ordner (Standard: `*.ps1`).
* **script_parameters**: Zusätzliche Parameter, die an die PowerShell-Skripte übergeben werden.
