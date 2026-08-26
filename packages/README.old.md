# Richtlinien für OPSI-Produkte (Conventions)

Dieses Verzeichnis enthält die OPSI-Produkte für die opsi_scripts-Umgebung. Jedes Unterverzeichnis repräsentiert ein eigenständiges OPSI-Produkt. Das Verzeichnis `OPSI-Produkte` selbst ist kein OPSI-Produkt.

---

## 📂 Struktur eines OPSI-Produkts

Jedes OPSI-Produkt in diesem Ordner muss der standardmäßigen OPSI-Verzeichnisstruktur folgen:

```text
OPSI-Produkte/
└── <Produkt-ID>/                  # Eindeutige ID des Produkts (z. B. "xournalpp")
    ├── OPSI/
    │   └── control                # Metadaten, Abhängigkeiten und Produkt-Eigenschaften (Properties)
    ├── CLIENT_DATA/
    │   ├── setup.opsi             # Haupt-Installationsskript (OPSI Winst Script)
    │   ├── uninstall.opsiscript   # Deinstallationsskript (optional)
    │   └── ...                    # Weitere Hilfsskripte (z.B. run_wrapper.ps1), Installer, Scripte
    └── readme.md                  # Dokumentation und Beschreibung des Produkts
```

---

## 📝 Richtlinien & Best Practices

### 1. Eindeutige Produkt-IDs
* Verwenden Sie ausschließlich Kleinbuchstaben, Zahlen und Bindestriche (z. B. `ps-scripts`, `xournalpp`). Keine Sonderzeichen oder Leerzeichen.

### 2. Konfiguration über `OPSI/control`
* Nutzen Sie `[ProductProperty]`-Abschnitte im `control`-File, um das Produkt flexibel konfigurierbar zu machen (z. B. Parameter für Skripte, Silent-Flags, Installationspfade).
* Beispiel:
  ```ini
  [ProductProperty]
  name: silent
  description: Führe die Installation ohne GUI aus
  default: true
  values: ["true", "false"]
  ```

### 3. Skriptsteuerung & Parameter
* Das eigentliche Installations- und Konfigurations-Setup sollte über Skripte (z. B. PowerShell `.ps1` oder OPSI-Winst-Skripte `.opsi` / `.opsiscript`) gesteuert werden.
* Auslesbare Properties sollten als Argumente an die Skripte übergeben werden. Nutzen Sie dafür Wrapper wie `run_wrapper.ps1`, um Parameter strukturiert zu verarbeiten.

### 4. Dokumentation (`readme.md`)
* Jedes Produkt muss eine `readme.md` im Hauptverzeichnis des Produkts besitzen.
* Die README sollte mindestens folgende Informationen bereitstellen:
  * **Zweck**: Was macht das Produkt?
  * **Parameter**: Welche Konfigurationsmöglichkeiten (`ProductProperties`) gibt es und was bewirken sie?
  * **Hinweise**: Besondere Voraussetzungen oder Systemeingriffe.

