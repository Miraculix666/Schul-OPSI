# Microsoft Office OPSI Paket (Fully Unattended & Telemetrie-gehärtet)

Dieses Paket stellt eine stumme, gehärtete und telemetriearme Installation von Microsoft Office auf Basis des Office Deployment Tools (ODT) bereit.

---

## 1. Übersicht & Eigenschaften

- **Installer:** Office Deployment Tool (`setup.exe`)
- **Konfiguration:** `CLIENT_DATA/configuration.xml` (basierend auf Polizei NRW LAFP Konfiguration)
- **Modus:** Fully Unattended (`Display Level="None" AcceptEULA="TRUE"`)
- **Architektur:** 64-Bit (standardmäßig) oder 32-Bit via Property steuerbar
- **Excludes:** OneDrive, Lync/Skype for Business, Teams, Bing Integrationen ausgeschlossen

---

## 2. Einschränkungen durch die Telemetrie-Härtung

Durch die angewendeten Härtungsrichtlinien (analog NTLite, O&O ShutUp10 und WindowsTelemetryBlocker) werden Datenabflüsse an Microsoft unterbunden. **Dadurch sind folgende Funktionen nicht oder nur eingeschränkt verfügbar:**

| Funktion | Status im gehärteten Modus | Auswirkung |
| :--- | :--- | :--- |
| **Connected Experiences** | Deaktiviert | Keine Online-Vorlagen, kein Online-Bildersuchdienst |
| **Cloud-Schriftarten** | Deaktiviert | Nur lokal installierte System-Schriftarten verfügbar |
| **Diktierfunktion & Übersetzer** | Deaktiviert | Benötigt Microsoft Online-Sprachverarbeitung |
| **Kundenfeedback (CEIP)** | Deaktiviert | Keine Übermittlung von Diagnose- & Nutzungsdaten |
| **Office Telemetry Agent** | Deaktiviert | Keine Hintergrund-Protokollierung & Uploads |
| **OneDrive Synchronisation** | Ausgeschlossen | Komponente nicht im Office-Paket installiert |

### Steuerung der Funktionen via PowerShell

Im Ordner `CLIENT_DATA/scripts/` steht das Skript `Toggle-OfficeFeatures.ps1` bereit, um die Richtlinien bei Bedarf anzupassen oder aufzuheben:

- **Härtung anwenden (Telemetrie aus):**
  ```powershell
  .\Toggle-OfficeFeatures.ps1 -DisableFeatures
  ```
- **Standardfunktionen freischalten:**
  ```powershell
  .\Toggle-OfficeFeatures.ps1 -EnableFeatures
  ```
- **Status prüfen:**
  ```powershell
  .\Toggle-OfficeFeatures.ps1 -Status
  ```

---

## 3. Konfiguration des Produktschlüssels & Lizenzierung

Das Paket bietet drei Flexibilitätsstufen für die Produktschlüssel-Eingabe:

### Option A: Key-Eingabe über die OPSI GUI (Standard)
1. In OPSI-Configed den gewünschten Client auswählen.
2. Bei der Produkt-Property `productkey` den 25-stelligen Produktschlüssel (MAK oder GVLK) eintragen (Format: `XXXXX-XXXXX-XXXXX-XXXXX-XXXXX`).
3. Bei der Installation wird der Schlüssel automatisch aus der OPSI-Datenbank ausgelesen und stumm injiziert.

### Option B: KMS-Server Aktivierung
1. Falls ein KMS-Server im Netzwerk genutzt wird, die Property `activation_type` auf `KMS` setzen.
2. In der Property `kms_server` den FQDN oder die IP-Adresse des KMS-Servers eintragen (z. B. `kms.domain.local`).
3. Alternativ wird der KMS-Server bei vorhandenem DNS SRV Record (`_vlmcs._tcp`) automatisch im Netzwerk gefunden.

### Option C: Manuelle Festeinbettung im Paket (Optional)
Soll der Schlüssel fest im Paket hinterlegt werden, damit keine OPSI GUI-Eingabe erforderlich ist:
1. Datei `CLIENT_DATA/configuration.xml` im Paketordner öffnen.
2. Im Tag `<Product ID="ProPlus2021Volume">` das Attribut `PIDKEY` hinzufügen:
   ```xml
   <Product ID="ProPlus2021Volume" PIDKEY="XXXXX-XXXXX-XXXXX-XXXXX-XXXXX">
   ```
3. Datei speichern und Paket mit `opsi-makepackage` neu bauen.

---

## 4. Dateistruktur des Pakets

```
msoffice2013/
├── CLIENT_DATA/
│   ├── configuration.xml   # ODT Hauptkonfiguration (Silent, Excludes)
│   ├── delsub.ins          # OPSI Deinstallationsskript
│   ├── scripts/
│   │   └── Toggle-OfficeFeatures.ps1  # Feature & Telemetrie Switcher
│   ├── setup.exe           # Office Deployment Tool Installer
│   ├── setup.ins           # OPSI Hauptinstallationsskript
│   └── uninstall.xml       # ODT Deinstallations-Konfiguration
├── OPSI/
│   └── control             # OPSI Metadaten & Property-Definitionen
└── README.md               # Dokumentation
```
