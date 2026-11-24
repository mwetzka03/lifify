# Lifify

[English](#english) · [Deutsch](#deutsch)

## English

Lifify 0.6.0 is a local iPhone app for finance, challenges, and training. It
is built with SwiftUI and SwiftData, and it needs neither a backend nor a user
account. German and English, and light, dark, and system appearance, can be
switched in Settings. Style adds Green, Blue, Bordeaux, and Violet, each with
its own light and dark wash. Cards keep their own fill. Finance uses the same
wash and the same card fill, and it keeps its tile arrangement. Positive
amounts stay green and negative amounts stay red. The links under More are
a step larger than the tile titles.

The finance rules are in [FINANZEN.md](FINANZEN.md). What changed in 0.6.0 is in [CHANGES-0.6.0.md](Changes%20Documentation/CHANGES-0.6.0.md). What changed in 0.5.5 is in [CHANGES-0.5.5.md](Changes%20Documentation/CHANGES-0.5.5.md). What changed in 0.4.0 is in [CHANGES-0.4.0.md](Changes%20Documentation/CHANGES-0.4.0.md). What changed in 0.3.0 is in [CHANGES-0.3.0.md](Changes%20Documentation/CHANGES-0.3.0.md). Each file is in English and German. How changes, checks, and the visual style are kept is in [RULES.md](RULES.md).

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
coin wallet. Built-in categories are sport, abstinence, and other. More
categories can be added, and a category can have its own heading. An abstinence
runs a timer, pays coins each day, and pays a bonus when a time step falls on
the current day. A challenge can carry a duration and share an event. Events
and reminders from the iPhone can be imported after you explicitly allow access.

**Health** holds workout plans. Starting a workout runs a timer. Exercises come
from a local database, including exercises you add yourself when they are not
in that database. Exercise pictures drop a near-white background and sit on a
tinted rounded tile. Nutrition is a day board for meals, calories, and the other
nutrients. The arrows move one day, and tapping the date jumps to another day.
A photo can be attached. With a Gemini key under Settings, Health, the photo
is read and classified. Without a key it stays on the device. Fast food buys
the Fast Food reward for 25 coins. The pinned nutrition challenge follows the
goal: Calorie deficit, Hold calories, or Build muscle. It cannot be checked
off by hand, and a later meal can take the coins back below zero. The requirements are in
[ERNAEHRUNG.md](ERNAEHRUNG.md). Abstinence lives with the challenges. A sport
challenge linked to a workout is completed only by finishing that workout.
Up to four challenges can be pinned above the filter on the challenges page.
The event picker opens on today. Groups have their own section, fold open on
the page, and are pinned only when you pin them. A finished challenge stays in
its group. A challenge linked afterwards joins that group and can keep a second
group. Single shows those challenges one by one. Linking sets the challenge's
day and time to the event. Several challenges share an event only when each of
them happens once, and the event is replaced after every one of them is checked off.
A long press on a group edits, pins, or deletes it. A group with no event can
take any challenge. A group tied to an event takes one-time challenges only
while time remains in the slot. Recurrence and duration share one line, such
as Once - 20 minutes, and that line, the calendar link, the check circle,
and the challenge marks on the month view use the chosen style color. Deleting asks whether to delete the challenges too.
A calorie day with no meals does not spend the two starting freezes.

**Settings** start with your name and profile photo. The line under the name
is User settings. That page holds the date of birth, height in centimetres, weight
in kilograms, sex, and the goal. The title sits on one line. Health holds the
Gemini key and the switch that saves a new photo to the library. The switch is
off. General holds language, appearance, style, a daily
briefing with its own time for each weekday, the workout chime, the default
account and fee for the portfolio, accounts, import, backup, and calendar and
reminders. Finance also holds the manual Trade Republic sign-in and the button
that refreshes the depot from the saved session. The birthday pays 500 coins once that year. The version shown there
is 0.6.0.

### First launch

On the first launch Lifify asks, in order:

1. Language
2. Set up as new, or restore a JSON backup
3. Greeting name and date of birth. The birthday pays 500 coins once a year.
4. Budget period, calendar month or payday
5. Main account, including its IBAN. The account is required and cannot be
   deleted later.
6. Optional CSV or CAMT for the main account. This import defines the first
   period.
7. Optional Trade Republic statement, as its own step. This creates a checking
   account with a linked portfolio. The PDF import stays.
8. Optional sign-in to Trade Republic, in popups. You enter the phone number and the PIN
   that opens the Trade Republic app, then confirm in that app. Positions, quantities, and the cost
   basis, when the session returns it, go into the existing depot. You can
   skip this step. The PIN is not saved.

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
   signing, not a defect in the source.
5. Connect the iPhone, unlock it, and accept the trust prompt.
6. At the top of Xcode, choose that iPhone as the run destination.
7. Build and install with **Product → Run** or `⌘R`.
8. If iOS then asks for approval: **Settings → General → VPN & Device
   Management**, trust the developer profile, and open Lifify again.

The same app runs in the Simulator when the destination is an iPhone with iOS
17 or newer.

Since 0.6.0 the project has a second target, **LififyWidgets**, and uses
capabilities that signing must know:

1. Select your team under **Signing & Capabilities** for **Lifify** and for
   **LififyWidgets**.
2. In both targets, check that **App Groups** lists
   `group.com.mwetzka03.lifify` and that it is ticked. If it is red, press the
   refresh button next to it.
3. In the **Lifify** target, check that **HealthKit** is listed.
4. If Xcode reports that your team cannot use a capability, the account type
   does not include it. Without the App Group the app runs, and widgets stay
   empty.

Widgets show the state of the last app update. A check-off in a widget is
booked the next time the app runs.

### Code structure

The logic lives in four local Swift packages under `Packages`: `LififyCore`
(shared models and storage), `LififyFinance` (including Trade Republic),
`LififyChallenges`, and `LififyHealth`. The app target holds the views,
navigation, backup, and the wiring between packages. Methods stay small and
call well-named helpers instead of growing; repeated logic is shared through
protocols with default implementations, generics, and composition. Every type
and method carries a `///` comment that says what it does; longer methods also
list their parameters and return value. The full rules are in
[RULES.md](RULES.md#code).

### Data and import

Apple Health is optional and off by default. After you allow it, Lifify reads weight and steps and writes each finished workout to Apple Health. These values stay on the device.

For the depot's deep analysis, Lifify downloads public holdings files from Xtrackers (DWS), VanEck, and iShares (BlackRock) at most once a week. Those requests contain only fund identifiers, never your holdings or amounts.

The Finance tab is locked with Face ID or the device passcode by default. It stays open until the app goes to the background. The switch is under Settings, Finance. Other tabs and the settings themselves are not locked.

Everything lives on the device. A JSON backup does not include meal or profile photos, exercise images, price caches, or anything in the Keychain. JSON backups, CSV files, and
single CAMT files are chosen through the system file dialog. A Trade Republic
PDF is its own import, not an ordinary bank import. ZIP and MT940 are not
read.

Portfolio prices come from Yahoo Finance, at launch and through **Update
prices**. A German listing is preferred. If the request fails, the manual
price stays. For this, the ISIN is sent to those public endpoints. A meal photo
is sent to Gemini only when a key is saved under Health. The key stays in the
keychain and is not part of a backup. Without a key, no photo leaves the device.
With a key, the photo is sent together with height, weight, age, sex, training
state, and body goal, so the estimate fits you. Neither the Trade Republic
session nor the PIN is stored; you sign in each time.

Lifify reads calendars and reminders only after you explicitly allow it,
through the system. It does not store passwords for that.

### Shortcuts

The Lifify action **Bankmitteilung buchen** books in the background and
answers, for example, "12,50 € gebucht: REWE". Lifify does not come to the
front. iOS offers no automation for another app's push notification, so use
one of these triggers:

1. **Wallet (card payments).** Automation **Wallet** (transaction) for your
   card, run immediately. Add a **Text** action such as "[amount] bei
   [merchant] ausgegeben", then **Bankmitteilung buchen** with that text and
   the matching **Konto**.
2. **SMS or email.** If the bank sends notices this way, use the **Message**
   or **Email** automation and pass the content to **Bankmitteilung buchen**.
3. **Push only.** Copy the notification text and run a shortcut that books the
   clipboard.

Under Settings, Finance, Shortcuts you store an example notice per checking
account and what to book. The Shortcut still sends the text; Lifify uses that
template. Lifify already includes templates for the Sparkasse balance alert and
for Trade Republic buys, sales, savings plans, dividends, card payments, and
cancelled orders. You can switch each one off, edit it, or delete it. A buy or
sale moves the cash. The share count updates with the next Trade Republic import.

The same call is the URL `lifify://notice?account=sparkasse&text=` with the
notification text in `text`. For Trade Republic the account is
`traderepublic`. Lifify reads the amount, the direction, and a short title,
then books it on that checking account. The same account, amount, and
direction inside six hours becomes one booking, so a Wallet notice and a bank
notice do not both count.

## Deutsch

Lifify 0.6.0 ist eine lokale iPhone-App für Finanzen, Challenges und Training.
Sie ist mit SwiftUI und SwiftData gebaut, braucht kein Backend und kein
Benutzerkonto. Deutsch und Englisch sowie Hell, Dunkel und System lassen sich
in den Einstellungen umschalten. Der Stil ergänzt Grün, Blau, Bordeaux und
Violett, jeweils mit eigener heller und dunkler Fläche. Die Karten behalten
eine eigene Füllung. Finanzen nutzt dieselbe Fläche und dieselbe Kartenfarbe
und behält die Anordnung der Kacheln. Positive Beträge bleiben grün, negative
rot. Die Links unter Weitere Bereiche sind eine Stufe größer als die Kacheltitel.
Was sich in 0.6.0 geändert hat, steht in [CHANGES-0.6.0.md](Changes%20Documentation/CHANGES-0.6.0.md). Was sich in 0.5.5 geändert hat, steht in [CHANGES-0.5.5.md](Changes%20Documentation/CHANGES-0.5.5.md),
was sich in 0.4.0 geändert hat in [CHANGES-0.4.0.md](Changes%20Documentation/CHANGES-0.4.0.md),
was sich in 0.3.0 geändert hat in [CHANGES-0.3.0.md](Changes%20Documentation/CHANGES-0.3.0.md). Jede Datei auf Englisch und Deutsch.
Wie Änderungen, Tests und der Stil gehalten werden, steht in [RULES.md](RULES.md).

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
Belohnungsshop mit Coin-Wallet. Fest dabei sind Sport, Abstinenz und Sonstiges.
Weitere Kategorien lassen sich anlegen, auch mit eigener Überschrift. Eine
Abstinenz läuft über einen Timer, zahlt jeden Tag Coins und einen Bonus, wenn
eine Zeitstufe auf den aktuellen Tag fällt. Eine Challenge kann eine Dauer
haben und sich einen Termin teilen. Termine und Erinnerungen vom iPhone lassen
sich nach ausdrücklicher Freigabe übernehmen.

**Gesundheit** enthält Trainingspläne. Ein Training startet einen Timer.
Übungen kommen aus einer lokalen Datenbank, inklusive eigener Übungen, die
nicht in der Datenbank stehen. Übungsbilder verlieren einen fast weißen Grund
und liegen auf einer gefärbten, abgerundeten Kachel. Ernährung ist eine
Tagesansicht für Mahlzeiten, Kalorien und die übrigen Nährstoffe. Die Pfeile
wechseln einen Tag, ein Tipp auf das Datum springt zu einem anderen Tag. Ein
Foto kann angehängt werden. Mit einem Gemini-Schlüssel unter Einstellungen,
Gesundheit, wird das Foto gelesen und eingeordnet. Ohne Schlüssel bleibt es
auf dem Gerät. Fast Food kauft die Belohnung Fast Food für 25 Coins. Die
angepinnte Ernährungs-Challenge folgt dem Ziel: Kaloriendefizit, Kalorien
halten oder Muskelaufbau. Sie lässt sich nicht von Hand abhaken, und eine
spätere Mahlzeit kann die Coins wieder unter null abziehen. Die Anforderungen stehen in [ERNAEHRUNG.md](ERNAEHRUNG.md).
Abstinenz liegt bei den Challenges. Eine Sport-Challenge mit einem verknüpften
Training gilt nur als erledigt, wenn dieses Training beendet wurde. Bis zu
vier Challenges lassen sich über dem Filter auf der Challenges-Seite anpinnen.
Die Terminauswahl öffnet beim heutigen Tag. Gruppen haben einen eigenen
Abschnitt, klappen auf der Seite auf und werden nur angepinnt, wenn man sie
anpinnt. Eine erledigte Challenge bleibt in ihrer Gruppe. Eine später
verknüpfte Challenge kommt in diese Gruppe und kann eine zweite Gruppe
behalten. Einzeln zeigt diese Challenges einzeln. Die Verknüpfung setzt Tag
und Uhrzeit der Challenge auf den Termin. Mehrere Challenges teilen sich einen
Termin nur, wenn jede einmalig ist, und der Termin wird ersetzt, sobald alle
abgehakt sind. Ein langes Drücken auf eine Gruppe bearbeitet sie, pinnt sie
an oder löscht sie. Eine Gruppe ohne Termin nimmt jede Challenge. Eine Gruppe
an einem Termin nimmt einmalige Challenges nur, solange im Slot noch Zeit ist.
Wiederholung und Dauer stehen in einer Zeile, zum Beispiel Einmalig - 20
Minuten, und diese Zeile, die Kalenderverknüpfung, der Hakenkreis und die
Challenge-Punkte in der Monatsansicht nutzen die Stilfarbe. Beim Löschen wird gefragt, ob die Challenges mit weg sollen.
Ein Tag ohne Mahlzeiten verbraucht die zwei Start-Freezes nicht.

**Einstellungen** beginnen mit dem Namen und dem Profilbild. Darunter steht
Nutzereinstellungen. Diese Seite hält Geburtsdatum, Größe in Zentimetern,
Gewicht in Kilogramm, Geschlecht und das Ziel. Die Überschrift steht in einer
Zeile. Gesundheit hält den Gemini-Schlüssel und den Schalter, ob eine
Aufnahme in die Galerie kommt. Der Schalter ist aus. Allgemein hält Sprache,
Erscheinungsbild, den Stil, das
tägliche Briefing mit einer eigenen Uhrzeit je Wochentag, den
Trainingsklingelton, Standardkonto und Gebühr fürs Depot, Konten, Import,
Sicherung sowie Kalender und Erinnerungen. Unter Finanzen liegt außerdem die
manuelle Anmeldung bei Trade Republic und der Knopf, der das Depot aus der
gespeicherten Sitzung aktualisiert. Am Geburtstag gibt es einmal im
Jahr 500 Coins. Die angezeigte Version ist 0.6.0.

### Ersteinrichtung

Beim ersten Start fragt Lifify nacheinander:

1. Sprache
2. Neue Einrichtung oder JSON-Sicherung
3. Begrüßungsname und Geburtsdatum. Am Geburtstag gibt es einmal im Jahr 500 Coins.
4. Budgetzeitraum, Kalendermonat oder Gehalt
5. Hauptkonto mit IBAN. Das Konto ist verpflichtend und lässt sich später
   nicht löschen.
6. Optional CSV oder CAMT für das Hauptkonto. Dieser Import legt den ersten
   Zeitraum fest.
7. Optional ein Trade-Republic-Kontoauszug als eigener Schritt. Daraus entsteht
   ein Girokonto mit verknüpftem Depot. Der PDF-Import bleibt.
8. Optional die Anmeldung bei Trade Republic, in Pop-ups. Du gibst Telefonnummer und die PIN
   ein, mit der du die Trade-Republic-App öffnest, und bestätigst in der App. Positionen, Mengen und der
   Einstand, wenn die Sitzung ihn liefert, kommen ins vorhandene Depot. Den
   Schritt kannst du überspringen. Die PIN wird nicht gespeichert.

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
   lokale Signatur, kein Fehler im Quelltext.
5. Das iPhone verbinden, entsperren und der Vertrauensabfrage zustimmen.
6. Oben in Xcode dieses iPhone als Ziel wählen.
7. Mit **Product → Run** oder `⌘R` bauen und installieren.
8. Verlangt iOS danach eine Freigabe: **Einstellungen → Allgemein → VPN &
   Geräteverwaltung**, dem Entwicklerprofil vertrauen und Lifify erneut
   starten.

Dieselbe App läuft im Simulator, wenn als Ziel ein iPhone mit iOS 17 oder
neuer gewählt ist.

Seit 0.6.0 hat das Projekt ein zweites Target, **LififyWidgets**, und nutzt
Capabilities, die die Signatur kennen muss:

1. Unter **Signing & Capabilities** für **Lifify** und **LififyWidgets** das
   eigene Team wählen.
2. In beiden Targets prüfen, dass unter **App Groups**
   `group.com.mwetzka03.lifify` steht und angehakt ist. Ist der Eintrag rot,
   den Aktualisieren-Knopf daneben drücken.
3. Im Target **Lifify** prüfen, dass **HealthKit** aufgeführt ist.
4. Meldet Xcode, dass das Team eine Capability nicht nutzen kann, enthält der
   Kontotyp sie nicht. Ohne App Group läuft die App, die Widgets bleiben leer.

Widgets zeigen den Stand der letzten App-Aktualisierung. Ein Haken im Widget
wird gebucht, sobald die App das nächste Mal läuft.

### Code-Struktur

Die Logik liegt in vier lokalen Swift Packages unter `Packages`: `LififyCore`
(gemeinsame Modelle und Speicher), `LififyFinance` (mit Trade Republic),
`LififyChallenges` und `LififyHealth`. Das App-Target enthält Views,
Navigation, Backup und das Zusammenschalten der Packages. Methoden bleiben
klein und rufen gut benannte Hilfsmethoden auf, statt zu wachsen;
wiederkehrende Logik wird über Protokolle mit Standard-Implementierungen,
Generics und Komposition geteilt. Jeder Typ und jede Methode trägt einen
`///`-Kommentar, der sagt, was sie tut; längere Methoden nennen zusätzlich
Parameter und Rückgabewert. Die vollständigen Regeln stehen in
[RULES.md](RULES.md#code-1).

### Daten und Import

Apple Health ist optional und standardmäßig aus. Nach deiner Freigabe liest Lifify Gewicht und Schritte und schreibt jedes beendete Training nach Apple Health. Diese Werte bleiben auf dem Gerät.

Für die Tiefenanalyse des Depots lädt Lifify höchstens einmal pro Woche öffentliche Bestandslisten von Xtrackers (DWS), VanEck und iShares (BlackRock). Diese Abrufe enthalten nur Fonds-Kennungen, nie deine Bestände oder Beträge.

Der Tab Finanzen ist standardmäßig mit Face ID oder dem Gerätecode gesperrt. Er bleibt offen, bis die App in den Hintergrund geht. Der Schalter liegt unter Einstellungen, Finanzen. Andere Tabs und die Einstellungen selbst sind nicht gesperrt.

Alles liegt auf dem Gerät. Eine JSON-Sicherung enthält keine Mahlzeiten- oder Profilfotos, Übungsbilder, Kurs-Caches und nichts aus dem Schlüsselbund. JSON-Sicherungen sowie CSV- und
einzelne CAMT-Dateien werden über den Dateidialog gewählt. Ein
Trade-Republic-PDF ist ein eigener Import und kein normaler Bankimport. ZIP
und MT940 werden nicht gelesen.

Depotkurse kommen von Yahoo Finance, beim Start und über **Kurse aktualisieren**.
Eine deutsche Notierung wird bevorzugt. Schlägt der Abruf fehl, bleibt der
manuelle Kurs. Dafür wird die ISIN an diese öffentlichen Endpunkte geschickt.
Ein Essensfoto geht nur dann an Gemini, wenn unter Gesundheit ein Schlüssel
steht. Der Schlüssel bleibt im Schlüsselbund und gehört nicht zur Sicherung.
Ohne Schlüssel verlässt kein Foto das Gerät. Mit Schlüssel gehen zusammen mit
dem Foto Größe, Gewicht, Alter, Geschlecht, Trainingsstand und Körperziel mit,
damit die Schätzung zu dir passt. Weder die Trade-Republic-Sitzung noch die PIN
werden gespeichert; du meldest dich jedes Mal neu an.

Kalender und Erinnerungen liest Lifify nur nach ausdrücklicher Freigabe über
das System. Dafür werden keine Passwörter gespeichert.

### Kurzbefehle

Die Lifify-Aktion **Bankmitteilung buchen** bucht im Hintergrund und
antwortet etwa mit „12,50 € gebucht: REWE“. Lifify kommt dabei nicht nach
vorn. iOS bietet keine Automation für die Push-Mitteilung einer anderen App,
deshalb einen dieser Auslöser nutzen:

1. **Wallet (Kartenzahlungen).** Automation **Wallet** (Transaktion) für deine
   Karte, sofort ausführen. Eine Aktion **Text** wie „[Betrag] bei [Händler]
   ausgegeben“ einfügen, dann **Bankmitteilung buchen** mit diesem Text und dem
   passenden **Konto**.
2. **SMS oder E-Mail.** Schickt die Bank Mitteilungen so, die Automation
   **Nachricht** oder **E-Mail** nutzen und den Inhalt an **Bankmitteilung
   buchen** geben.
3. **Nur Push.** Den Mitteilungstext kopieren und einen Kurzbefehl starten, der
   die Zwischenablage bucht.

Unter Einstellungen, Finanzen, Kurzbefehle hinterlegst du pro Girokonto eine
Beispielmitteilung und was gebucht werden soll. Der Kurzbefehl schickt weiter
den Text; Lifify nutzt diese Vorlage. Lifify bringt
Vorlagen für den Sparkassen-Umsatzwecker und für Käufe, Verkäufe, Sparpläne,
Dividenden, Kartenzahlungen und stornierte Orders von Trade Republic mit. Jede
lässt sich ausschalten, bearbeiten oder löschen. Ein Kauf oder Verkauf bewegt
das Geld. Die Stückzahl folgt mit dem nächsten Trade-Republic-Import.

Derselbe Aufruf ist die URL `lifify://notice?account=sparkasse&text=` mit dem
Mitteilungstext in `text`. Bei Trade Republic ist das Konto `traderepublic`.
Lifify liest Betrag, Richtung und einen kurzen Titel und bucht auf dieses
Girokonto. Dasselbe Konto, derselbe Betrag und dieselbe Richtung innerhalb
von sechs Stunden werden eine Buchung, damit eine Wallet-Mitteilung und eine
Bankmitteilung nicht doppelt zählen.
