# Lifify

Lifify 0.2.0 ist eine lokale iPhone-App für Finanzen, Challenges und Training.
Sie ist mit SwiftUI und SwiftData gebaut, braucht kein Backend und kein
Benutzerkonto. Deutsch und Englisch sowie Hell, Dunkel und System lassen sich
in den Einstellungen umschalten.

Die geltenden Finanzregeln stehen in [FINANZEN.md](FINANZEN.md). Die
ursprünglichen Annahmen gegenüber FinanzBuddy stehen in
[FEATURES.md](FEATURES.md).

## Bereiche

**Home** zeigt den Budgetring, das Restbudget, das nächste Gehalt und das
Tagesbudget. Ein Tipp auf das Budget öffnet die Aufschlüsselung. Darunter
liegen die Wochentage und die Challenges des Tages.

**Finanzen** rechnet den gewählten Zeitraum für alle Konten, ein einzelnes
Konto oder das Depot. Zeitraum und Konto sind ein gemeinsamer Filter und gelten
auch in den Buchungen und in den Listen für Einnahmen und Ausgaben. Unten
stehen die Buchungen, darüber die Prognosen. Weitere Listen führen zu
Fixkosten, variablen Kosten, Einkaufszettel, Sparplänen und Budgetpools.

**Challenges** verbinden Kalender, Wiederholungen, Streaks und einen
Belohnungsshop mit Coin-Wallet. Termine und Erinnerungen vom iPhone lassen
sich nach ausdrücklicher Freigabe übernehmen.

**Gesundheit** enthält Trainingspläne. Übungen kommen aus einer lokalen
Datenbank, inklusive eigener Übungen, die nicht in der Datenbank stehen.
Ernährung ist noch nicht verfügbar.

**Einstellungen** halten Sprache, Erscheinungsbild, Trainingsklingelton,
Standardkonto und Gebühr fürs Depot, Konten, Import, Sicherung sowie Kalender
und Erinnerungen. Die angezeigte Version ist 0.2.0.

## Ersteinrichtung

Beim ersten Start fragt Lifify nacheinander:

1. Sprache
2. Neue Einrichtung oder JSON-Sicherung
3. Begrüßungsname
4. Budgetzeitraum, Kalendermonat oder Gehalt
5. Hauptkonto mit IBAN. Das Konto ist verpflichtend und lässt sich später
   nicht löschen.
6. Optional CSV oder CAMT für das Hauptkonto. Dieser Import legt den ersten
   Zeitraum fest.
7. Optional ein Trade-Republic-Kontoauszug als eigener Schritt. Daraus entsteht
   ein Girokonto mit verknüpftem Depot.

„Alle Daten löschen“ räumt Finanz-, Challenge- und Trainingsinhalte ab und
behält Konten und Einstellungen. „App zurücksetzen“ entfernt auch Konten und
Einstellungen und startet die Einrichtung neu.

## Auf dem iPhone starten

- macOS mit Xcode 16 oder neuer
- iPhone mit iOS 17 oder neuer
- eine Apple-ID in Xcode

1. Dieses Repository auf den Mac klonen.
2. `Lifify.xcodeproj` öffnen.
3. Das Target **Lifify** wählen und **Signing & Capabilities** öffnen.
4. Unter **Team** das eigene Entwicklerteam auswählen. Ohne Team bricht der
   Build mit „Signing for Lifify requires a development team“ ab. Das ist die
   lokale Signatur, kein Fehler im Quelltext. Ist die Bundle-ID
   `com.mwetzka03.lifify` im eigenen Team belegt, für einen privaten Build eine
   eigene Bundle-ID eintragen.
5. Das iPhone verbinden, entsperren und der Vertrauensabfrage zustimmen.
6. Oben in Xcode dieses iPhone als Ziel wählen.
7. Mit **Product → Run** oder `⌘R` bauen und installieren.
8. Verlangt iOS danach eine Freigabe: **Einstellungen → Allgemein → VPN &
   Geräteverwaltung**, dem Entwicklerprofil vertrauen und Lifify erneut
   starten.

Dieselbe App läuft im Simulator, wenn als Ziel ein iPhone mit iOS 17 oder
neuer gewählt ist.

## Daten und Import

Alles liegt im SwiftData-Store auf dem Gerät. JSON-Sicherungen sowie CSV- und
einzelne CAMT-Dateien werden über den Dateidialog gewählt. Ein
Trade-Republic-PDF ist ein eigener Import und kein normaler Bankimport. ZIP
und MT940 werden nicht gelesen.

Depotkurse kommen von Yahoo Finance, beim Start und über **Kurse aktualisieren**.
Eine deutsche Notierung wird bevorzugt. Schlägt der Abruf fehl, bleibt der
manuelle Kurs. Dafür wird die ISIN an diese öffentlichen Endpunkte geschickt.
Andere Nutzerdaten verlassen das Gerät nicht.

Kalender und Erinnerungen liest Lifify nur nach ausdrücklicher Freigabe über
das System. Dafür werden keine Passwörter gespeichert.
