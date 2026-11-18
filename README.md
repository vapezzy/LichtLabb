# LichtLab – BMW-Diagnose für die F-Serie

iPhone-App (iOS 16.4+), die sich per Bluetooth LE mit einem **vLinker BM+** (ELM327-kompatibel) verbindet und
über D-CAN den **Fehlerspeicher aller Steuergeräte ausliest und löscht**. Getestet mit einem BMW F36.

## Funktionen

- **Fehlerspeicher auslesen:** Schnell-Scan (bekannte F-Serien-Adressen, ca. 10 s) oder Vollscan (alle Adressen
  01–7F, ca. 1 min). Pro Steuergerät die BMW-Fehlercodes mit Status (aktiv, gespeichert, sporadisch, Warnlampe),
  dazu die genormten OBD-II-Codes (P0300 …) und die Fahrgestellnummer.
- **Fehler löschen:** pro Steuergerät, „Alle Fehler löschen“ (alle Steuergeräte mit Einträgen) und OBD-II separat –
  jeweils nur nach Sicherheitsabfrage. Danach wird automatisch neu ausgelesen; kommt ein Fehler sofort wieder,
  sagt die App, dass die Ursache noch besteht.
- **Bericht teilen:** alle Steuergeräte und Codes als Text, z. B. vor dem Löschen sichern.
- **Beispielmodus:** Ansicht ohne Auto ausprobieren.
- **Diagnose-Konsole:** freie AT-/UDS-Befehle, Protokoll teilen – hilfreich, wenn etwas nicht klappt.

## Installation mit TrollStore

Die neueste IPA wird bei jedem Push automatisch gebaut (nachdem die Simulator-Tests bestanden sind):

https://github.com/vapezzy/LichtLabb/releases/latest/download/LichtLab.ipa

Den Link auf dem iPhone in Safari öffnen → Datei laden → *Teilen* → **TrollStore** → Installieren.

## Benutzung

1. Zündung an (Start/Stopp ohne Bremse), Motor aus, vLinker in die OBD-Buchse.
2. Oben rechts auf **„Nicht verbunden“** tippen → „Adapter suchen“ → vLinker wählen.
3. **Scan starten** – danach Steuergeräte antippen, um die Codes zu sehen.
4. Zum Löschen: Steuergerät aufklappen → **Fehler löschen**, oder **Alle Fehler löschen**.

## Vor dem Löschen

- Erst auslesen und den Bericht teilen – gelöschte Codes sind weg.
- Löschen behebt keine Ursache. Kommt ein Fehler sofort wieder, besteht das Problem noch.
- Airbag- und Bremsfehler nicht einfach löschen, sondern prüfen lassen.
- OBD-II-Löschen (Modus 04) setzt die Bereitschaftstests zurück – vor einer AU/HU erst wieder ein Stück fahren.

## Technik

| Datei | Inhalt |
|---|---|
| `BLEManager.swift` | Bluetooth-Verbindung zum Adapter (vLinker: Service 18F0) |
| `ELMSession.swift` | ELM327-Befehle, BMW-Adressierung (Tester 6F1, erweiterte Adresse), UDS 19/14, OBD 03/07/04 |
| `FaultScanner.swift` | Scan, Löschen mit Nachkontrolle, Bericht, Beispieldaten |
| `FaultsView.swift`, `RootView.swift` | Oberfläche |
| `ConsoleView.swift`, `ConnectionView.swift`, `SettingsView.swift` | Konsole, Verbindung, Einstellungen |
| `Tests/` | ELM327/BMW-Simulator mit Ende-zu-Ende-Tests: `sh tools/run_tests.sh` |
| `tools/generate_project.py` | Erzeugt das Xcode-Projekt neu (nach neuen Swift-Dateien ausführen) |
| `.github/workflows/build-ipa.yml` | Tests + unsignierte IPA für TrollStore + Release |

Die frühere Licht-, 3D- und Musik-Version liegt in der Git-Historie (bis Commit `8777094`).
