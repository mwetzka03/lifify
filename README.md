# Lifify

Lifify ist eine lokale iPhone-App für Konten, Buchungen, Budgets und private
Finanzplanung. Sie verwendet ausschließlich SwiftUI und SwiftData und benötigt
weder Backend noch Benutzerkonto oder Netzwerkzugriff.

Der fachliche Umfang und die gegenüber FinanzBuddy v0.3.6 getroffenen Annahmen
stehen in [FEATURES.md](FEATURES.md).

## Voraussetzungen

- macOS mit einer aktuellen Xcode-Version (Xcode 16 oder neuer)
- iPhone mit iOS 17 oder neuer
- kostenlose oder kostenpflichtige Apple-ID in Xcode

## In Xcode öffnen und auf einem iPhone starten

1. Dieses Repository auf den Mac klonen.
2. Im Finder `Lifify.xcodeproj` doppelklicken oder in Xcode
   **File → Open…** wählen und `Lifify.xcodeproj` öffnen.
3. In der Projektübersicht das Target **Lifify** und anschließend
   **Signing & Capabilities** öffnen.
4. Unter **Team** das eigene Apple-Entwicklerteam auswählen. Falls die
   Bundle-ID `com.mwetzka03.lifify` im eigenen Team bereits belegt ist, für
   einen rein privaten Build eine eindeutige Bundle-ID eintragen.
5. Das iPhone per Kabel verbinden (oder zuvor für drahtloses Debugging
   koppeln), entsperren und die Vertrauensabfrage bestätigen.
6. Oben in Xcode als Run Destination das verbundene iPhone auswählen.
7. Mit **Product → Run** oder `⌘R` bauen und installieren.
8. Falls iOS danach eine Entwicklerfreigabe verlangt:
   **Einstellungen → Allgemein → VPN & Geräteverwaltung** öffnen, dem
   Entwicklerprofil vertrauen und Lifify erneut starten.

Auf einem Simulator kann die App analog gestartet werden, indem in der
Run-Destination ein iPhone-Simulator mit iOS 17+ gewählt wird.

## Datenschutz und Import

Alle Daten liegen im lokalen SwiftData-Store des Geräts. JSON-Sicherungen sowie
CSV- oder einzelne CAMT-XML-Dateien werden über den iOS-Dateidialog gewählt.
Lifify unterstützt absichtlich weder ZIP noch MT940 und lädt keine Live-Kurse
oder Nachrichten.
