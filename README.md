# Lifify

[English](#english) · [Deutsch](#deutsch)

## English

Lifify 0.2.0 is a local iPhone app for finance, challenges, and training. It
is built with SwiftUI and SwiftData, and it needs neither a backend nor a user
account. German and English, and light, dark, and system appearance, can be
switched in Settings.

The finance rules are in [FINANZEN.md](FINANZEN.md).

### Areas

**Home** shows the budget ring, the remaining budget, the next payday, and the
daily budget. Tapping the budget opens the breakdown. Below that are the days
of the week and the day’s challenges.

**Finance** calculates the selected period for all accounts, one account, or
the portfolio. Period and account are one shared filter. The same filter
applies to transactions and to the income and expense lists. Transactions sit
at the bottom, forecasts above them. Further lists lead to fixed costs,
variable costs, the shopping list, savings plans, and budget pools.

**Challenges** combine a calendar, repeats, streaks, and a reward shop with a
coin wallet. Events and reminders from the iPhone can be imported after you
explicitly allow access.

**Health** holds workout plans. Exercises come from a local database, including
exercises you add yourself when they are not in that database. Nutrition is
not available yet.

**Settings** hold language, appearance, the workout chime, the default account
and fee for the portfolio, accounts, import, backup, and calendar and
reminders. The version shown there is 0.2.0.

### First launch

On the first launch Lifify asks, in order:

1. Language
2. Set up as new, or restore a JSON backup
3. Greeting name
4. Budget period, calendar month or payday
5. Main account, including its IBAN. The account is required and cannot be
   deleted later.
6. Optional CSV or CAMT for the main account. This import defines the first
   period.
7. Optional Trade Republic statement, as its own step. This creates a checking
   account with a linked portfolio.

“Delete all data” clears finance, challenge, and workout content and keeps
accounts and settings. “Reset app” also removes accounts and settings and
starts setup again.

### Run it on an iPhone

- macOS with Xcode 16 or newer
- an iPhone with iOS 17 or newer
- an Apple ID in Xcode

1. Clone this repository on the Mac.
2. Open `Lifify.xcodeproj`.
3. Select the **Lifify** target and open **Signing & Capabilities**.
4. Under **Team**, select your own developer team. Without a team the build
   stops with “Signing for Lifify requires a development team”. That is local
   signing, not a defect in the source. If the bundle ID
   `com.mwetzka03.lifify` is already taken in your team, enter your own bundle
   ID for a private build.
5. Connect the iPhone, unlock it, and accept the trust prompt.
6. At the top of Xcode, choose that iPhone as the run destination.
7. Build and install with **Product → Run** or `⌘R`.
8. If iOS then asks for approval: **Settings → General → VPN & Device
   Management**, trust the developer profile, and open Lifify again.

The same app runs in the Simulator when the destination is an iPhone with iOS
17 or newer.

### Data and import

Everything lives in the device’s SwiftData store. JSON backups, CSV files, and
single CAMT files are chosen through the system file dialog. A Trade Republic
PDF is its own import, not an ordinary bank import. ZIP and MT940 are not
read.

Portfolio prices come from Yahoo Finance, at launch and through **Update
prices**. A German listing is preferred. If the request fails, the manual
price stays. For this, the ISIN is sent to those public endpoints. No other
user data leaves the device.

Lifify reads calendars and reminders only after you explicitly allow it,
through the system. It does not store passwords for that.

## Deutsch

Lifify 0.2.0 ist eine lokale iPhone-App für Finanzen, Challenges und Training.
Sie ist mit SwiftUI und SwiftData gebaut, braucht kein Backend und kein
Benutzerkonto. Deutsch und Englisch sowie Hell, Dunkel und System lassen sich
in den Einstellungen umschalten.

Die Finanzregeln stehen in [FINANZEN.md](FINANZEN.md).

### Bereiche

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

### Ersteinrichtung

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

### Auf dem iPhone starten

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

### Daten und Import

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
