# Image Setup - Autounattend Templates

Diese Dateien steuern die unbeaufsichtigte Windows 11 Installation.

## Dateien

| Datei | Verwendung |
|---|---|
| `Autounattend_OPSI.xml` | Fuer OPSI-basierte Netzwerkinstallation (PXE-Boot) |
| `Autounattend_USB.xml` | Fuer USB-Stick basierte Standalone-Installation |

## Hardening-Strategie

Die Autounattend-XML fuehrt **nur sichere** Registry-Aenderungen waehrend der Installation durch:
- Telemetrie deaktivieren (`AllowTelemetry=0`)
- Werbe-ID deaktivieren
- FastBoot deaktivieren
- BitLocker verhindern
- Hardware-Bypass (TPM/CPU/RAM) fuer VMs
- BypassNRO (OOBE ohne Microsoft-Konto)

**Alle weiteren Haertungen** erfolgen ueber das OPSI-Paket `win11-hardening/` nach der Installation.

## History

Konsolidiert aus `D:\temp\Image_Anpassung` Versionen V1-V9 (Oktober 2025 - Januar 2026).
Aeltere Versionen sind im `archive/` Ordner verfuegbar.
