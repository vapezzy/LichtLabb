# RideReader – Dein Auto spricht. Wir übersetzen.

iPhone-App (iOS 16.4+), die sich per Bluetooth LE mit einem **vLinker BM+** (ELM327-kompatibel) verbindet und
über D-CAN den **Fehlerspeicher aller Steuergeräte ausliest und löscht**. Getestet mit einem BMW F36.

## Funktionen

- **Kino-Intro:** Das Auto wird Linie für Linie gezeichnet, dann fliegt der Schriftzug RideReader ein (120 Hz).
- **Zuhause:** großer Knopf **Kontrolle** – Schnell (wichtigste Steuergeräte, ca. 10 s) oder Gründlich (alle Adressen, ca. 1 min).
- **Ladeanimation:** drei Anime-Mechaniker schrauben am Motor; einer rollt einen Reifen über den Fortschrittsbalken.
- **Fehler:** Hintergrund wird unscharf, **Orange = Fehler**, **Rot = schwerwiegend** (Airbag, Bremse, Lenkung,
  Zündaussetzer, aktive Fehler mit Warnlampe …). Jeder Fehler hat eine Erklärung und einen **Web-Knopf**, der den
  Code im In-App-Browser nachschlägt (ohne Fahrgestellnummer).
- **Löschen:** pro Steuergerät, alle auf einmal oder OBD-II – immer erst nach dem Hinweis
  „Löschen ersetzt keine Reparatur“. Danach wird automatisch neu ausgelesen.
- **Einstellungen:** OBD-Stecker verbinden, Scan-Art, Diagnose-Konsole, Beispiel-Kontrolle ohne Auto.

### Zu den Erklärungen

- Genormte OBD-II-Codes (P0300 …): häufige Codes mit Klartext, der Rest wird über den Nummernbereich eingeordnet.
- BMW-Herstellercodes (z. B. 801C20) sind nicht öffentlich dokumentiert. Die App erklärt, aus welchem Steuergerät
  der Code stammt und was das bedeutet; den genauen Wortlaut liefert der Web-Knopf.

## Installation mit TrollStore

Bei jedem Push wird automatisch gebaut (nach den Simulator-Tests), inklusive Screenshots im Release:

https://github.com/vapezzy/LichtLabb/releases/latest/download/RideReader.ipa

Den Link auf dem iPhone in Safari öffnen → Datei laden → *Teilen* → **TrollStore** → Installieren.

## Technik

| Datei | Inhalt |
|---|---|
| `BLEManager.swift` | Bluetooth-Verbindung zum Adapter (vLinker: Service 18F0) |
| `ELMSession.swift` | ELM327-Befehle, BMW-Adressierung (Tester 6F1), UDS 19/14, OBD 03/07/04 |
| `FaultScanner.swift` | Scan, Löschen mit Nachkontrolle, Bericht, Beispieldaten |
| `FaultCatalog.swift` | Erklärungen, Schweregrad (Orange/Rot), Websuche |
| `IntroView.swift`, `CarArt.swift` | Intro und Auto als Vektorgrafik |
| `MechanicsLoader.swift` | Mechaniker-Ladeanimation (Canvas) |
| `HomeView.swift`, `FaultViews.swift`, `SettingsTab.swift`, `RideReaderApp.swift` | Oberfläche |
| `Tests/` | ELM327/BMW-Simulator mit Ende-zu-Ende-Tests: `sh tools/run_tests.sh` |
| `tools/generate_project.py` | Erzeugt das Xcode-Projekt neu (nach neuen Swift-Dateien ausführen) |

Screenshots ohne Auto: App mit `-shot intro|home|loading|results|clear|settings` starten (`-introTime 2.4` hält das Intro an).
