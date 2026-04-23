# Changelog

## [2.0.0] - 2026-04-23 - Grosse Restrukturierung

### Repository-Struktur
- **NEU:** `config/environment.json` - Zentrale Konfiguration (Single Source of Truth)
- **NEU:** `winpe-builder/` - WinPE Builder (vorher WinPE/)
- **NEU:** `win11-hardening/` - OPSI-Paket (vorher Y:\ und onOPSIServer/)
- **NEU:** `image-setup/` - Autounattend Templates (aus D:\temp\Image_Anpassung)
- **NEU:** `tools/` - Standalone-Werkzeuge (BCD Repair, Deploy, Driver Export)
- **NEU:** `server-scripts/` - OPSI-Server Bash-Skripte
- **NEU:** `archive/` - Alte Skript-Versionen mit History
- **ENTFERNT:** 7 redundante WinPE-Skripte konsolidiert
- **ENTFERNT:** R109C00 Debug-Logs (nach dump/ verschoben)
- **ENTFERNT:** onOPSIServer/ Duplikat-Kopien

### Build-WinPE.ps1 (v3.0)
- `-Env` Parameter fuer Quick-Start ohne interaktives Menue
- Pfade lesen aus zentraler `config/environment.json`
- Interaktiver Modus bleibt Standard (ohne -Env)

### Apply_Hardening.ps1 (V10.0)
- Konsolidiert aus V1-V9 (Image_Anpassung History)
- **NEU:** Modul D: Remote-Setup (RDP, WinRM, WOL) - aus V3 uebernommen
- **NEU:** Modul E: Store vollstaendig deaktiviert
- **NEU:** Defender-Deaktivierung mit Popup-Warnung
- **NEU:** Credential Guard ohne Hardware-Check
- **NEU:** Windows Capabilities Entfernung (QuickAssist, IE, Wordpad etc.)
- **FIX:** setup.opsi referenzierte falschen Dateinamen (PS_Apply_Harden_Policies.ps1)

### Deploy-ToServer.ps1 (NEU)
- Automatisierte Build-und-Transfer-Pipeline
- `-DryRun` und `-SkipWinPE` Flags
- Robocopy-Sync nach Y:\ mit Server-Befehlsanzeige

## [1.0.0] - 2026-04-23
- Initial repository setup and framework integration.
