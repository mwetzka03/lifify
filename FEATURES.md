# Lifify – Funktionsumfang und Annahmen

## Referenz

Die Implementierung orientiert sich an:

- `mwetzka03/FinanzBuddy` Tag `v0.3.6` (Commit `98fa2c3`)
- `mwetzka03/live-life` Tag `v0.2.5` (Commit `e9cee29`)

Lifify verbindet beide fachlichen Konzepte in einer nativen, lokalen
iPhone-App mit SwiftUI und SwiftData.

## Umgesetzter Umfang

- Konten: Giro/Standard, Spartopf, Oberspartopf und Depot; Hauptkonto,
  Liquidität, IBAN und Elternkonto
- Buchungen: Einnahme, Ausgabe, Umbuchung und Saldo-Korrektur; Volltextsuche;
  Zuordnung zu Fixkosten, variablen Kosten und Einkäufen; Splits für variable
  Kosten und Budgetpools
- Fixkosten und Einnahmeprognosen mit monatlicher, jährlicher, wöchentlicher
  oder zweiwöchentlicher Wiederholung
- Fälligkeit am Kalendertag sowie am ersten oder letzten Bankarbeitstag in
  Rheinland-Pfalz (inklusive gesetzlicher Feiertage)
- Variable Monatsbudgets und Budgetpools pro Gehaltszeitraum oder Kalenderjahr;
  skalierbare Pools übertragen den Rest in die nächste Periode
- Einkaufszettel, Schulden, Ausgabengruppen und Depotpositionen mit manuell
  eingetragenem Kurs
- Deutsch und Englisch, Erscheinungsbild Hell/Dunkel/System
- Vollständige lokale JSON-Sicherung und Wiederherstellung
- CSV-Import und Import einer einzelnen CAMT-XML-Datei
- Gemeinsamer Home-Bildschirm mit Budgetring sowie umschaltbarer
  Tag-/Woche-/Monat-Kalenderübersicht; Wischgesten wechseln die Periode
- Challenge-Kalender mit lokalen Terminen sowie Challenge- und Belohnungsverknüpfung
- Challenges und Challenge-Gruppen mit Wiederholungen, Abschlüssen, Streaks und
  wachsendem Coin-Multiplikator
- Importierte iOS-Erinnerungen erscheinen zunächst als Empfehlungen und werden
  erst nach ausdrücklicher Übernahme zu Challenges
- Belohnungsshop und Wallet mit Coin-Transaktionen und Kaufhistorie
- Frei wählbare SF-Symbole für Buchungen, Fixkosten, Challenges und Belohnungen
- Lokal gespeicherte Bucketlist-Daten; die Oberfläche ist vorerst ausgeblendet
- Optionaler Import aus iOS-Kalendern und Erinnerungen über EventKit

## Annahmen gegenüber FinanzBuddy v0.3.6

1. **Sicherung:** Die v0.3.6-JSON-Sicherung lässt Budgetpools, Split-Zuordnungen
   und einige weitere Tabellen aus. Lifify sichert absichtlich sämtliche
   Nutzerdaten einschließlich Splits, damit eine Wiederherstellung vollständig
   ist.
2. **Geldbeträge:** Wie in FinanzBuddy werden Beträge intern als ganzzahlige
   Cent gespeichert. Ausgaben sind negativ; Umbuchungen und Saldo-Korrekturen
   speichern einen positiven Betrag.
3. **Saldo-Korrektur:** Die zeitlich letzte Korrektur eines Kontos ist der neue
   Saldo-Anker. Nur spätere Buchungen verändern diesen Wert.
4. **Oberspartopf:** Ein Oberspartopf gruppiert Spartöpfe. Er wird nicht noch
   einmal zur Gesamtsumme addiert, um Doppelzählungen zu vermeiden.
5. **Depot:** Ein Depotwert ist Stückzahl × manuell eingetragener Kurs. Es gibt
   keine Live-Kurse. Käufe und Verkäufe werden in dieser Version nicht
   automatisch in ein FIFO-Steuerlot umgerechnet; Geldbewegungen können separat
   als Buchung erfasst werden.
6. **Variable Kosten:** Monatswerte gelten ab dem Erstellungsmonat. Der in
   FinanzBuddy hart codierte Startmonat `2026-06` wird nicht übernommen.
7. **Budgetpool-Gehaltszeitraum:** Der Starttag ist je Pool einstellbar
   (standardmäßig der 1.). Eine Periode läuft vom Starttag bis zum Vortag
   desselben Tages im Folgemonat. Bei kurzen Monaten wird der Tag auf das
   Monatsende begrenzt.
8. **Skalierbarer Übertrag:** Rest = Grundbudget + bisheriger Übertrag −
   zugeordnete Ausgaben. Der Rest wird vollständig, auch wenn er negativ ist, in
   die nächste Periode übernommen.
9. **Import:** CSV erwartet eine Kopfzeile und erkennt deutsche sowie englische
    Spaltennamen für Datum, Betrag, Verwendungszweck und IBAN. CAMT verarbeitet
    genau eine XML-Datei und liest Buchungsdatum, Betrag, Soll/Haben,
    Beschreibung und Gegenkonto. ZIP und MT940 sind absichtlich nicht
    enthalten.
10. **Import-Deduplizierung:** Importierte Zeilen erhalten aus den Quelldaten
    einen stabilen Fingerabdruck. Derselbe Datensatz wird nicht erneut
    importiert.
11. **Datenschutz:** Es gibt weder Backend noch Kontoanmeldung, Telemetrie,
    Werbung oder Netzwerkzugriffe. Import und Export erfolgen ausschließlich
    über den systemeigenen Dateidialog.
12. **Challenge-Synchronisierung:** Die Desktop-Referenz speichert
    CalDAV-/iCloud-Passwörter und nutzt eine Python-Brücke. Lifify speichert
    keine solchen Zugangsdaten. Optional liest es nach ausdrücklicher
    iOS-Freigabe Termine und Erinnerungen über EventKit. Netzwerk- und
    Kontoverwaltung bleiben dabei dem Betriebssystem überlassen; ohne Freigabe
    funktionieren alle lokalen Funktionen.
13. **Visionboard und Bucketlist:** Das Visionboard ist auf Nutzerwunsch nicht
    Bestandteil von Lifify. Bucketlist-Daten und Sicherungslogik bleiben
    erhalten, ihre Oberfläche ist vorerst ausgeblendet.
14. **Home-Navigation:** Das bereitgestellte Mockup ist maßgeblich:
    Home, Finanzen, Challenges und Einstellungen sind die vier Haupttabs.
    Budgetring, Kalenderperioden und Schnellaktionen öffnen ihre jeweiligen
    Detailansichten.
15. **Erinnerungen:** Offene iOS-Erinnerungen werden nicht automatisch als
    erledigbare Challenges angelegt. Sie bleiben in „Empfehlungen“, bis sie
    übernommen werden. Bereits übernommene Erinnerungen werden bei späteren
    Synchronisierungen nicht erneut angeboten.
16. **Gespeicherte Artikel:** Die Artikelansicht und ihre Fachlogik wurden auf
    Nutzerwunsch entfernt. Das alte SwiftData-Modell bleibt ausschließlich als
    Kompatibilitätsplatzhalter erhalten, damit vorhandene Entwicklungsstores
    weiterhin geöffnet werden können.

## Technische Leitplanken

- iOS 17+, SwiftUI, SwiftData
- keine UIKit- oder Core-Data-Imports
- Bundle-ID `com.mwetzka03.lifify`, Anzeigename `Lifify`
- Views, ViewModels, Models und Services liegen in getrennten Dateien/Ordnern
- EventKit ausschließlich für die optionale iOS-Systemintegration
- keine Drittanbieter-Abhängigkeiten und keine Secrets
