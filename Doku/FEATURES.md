# Lifify – What the app can do

[English](#english) · [Deutsch](#deutsch)

## English

Lifify 0.6.0 is a local iPhone app for money, challenges, and health. It needs
no account and no server. Everything stays on the device unless a feature below
says it fetches something. How the numbers are calculated is in
[FINANZEN.md](FINANZEN.md), how nutrition targets work in
[ERNAEHRUNG.md](ERNAEHRUNG.md), and what changed per version in the CHANGES
files in this folder.

### Home

- A budget ring with the remaining budget of the period, the next payday, and
  the daily budget. A negative remaining budget is shown as negative. Tapping
  it opens the breakdown.
- A calendar by day, week, or month with events and the day's challenges.
  Linked events can be checked off in the morning.
- Under the calendar: steps and planned workouts of the chosen day, week, or
  month. Workouts come from calendar events with a linked plan and get a check
  once that plan was trained that day.
- The bookings of the shown period.

### Finance

- **Accounts:** checking, savings pot, savings group, and portfolio, with a
  required main account, liquidity, IBAN, and parent account.
- **Bookings:** income, expense, transfer, and balance adjustment; full-text
  search; assignment to fixed costs, variable costs, and shopping items; splits
  for variable costs and budget pools.
- **Period filter:** calendar month or salary period, for all accounts, one
  account, or the portfolio. The same filter applies everywhere in Finance.
- **Income:** income forecasts and the real income of the period. Below the
  forecasts, folded: dividends received, the next twelve months, and the
  positions that still pay. With a switch, expected dividends count as planned
  income.
- **Expenses:** forecast expenses and the real expenses of the period.
- **Fixed costs** with weekly, biweekly, monthly, or yearly repeats, due on a
  calendar day or the first or last bank working day (Rhineland-Palatinate,
  with public holidays). Subscription suggestions sit folded on top: repeated
  payments to the same payee that are not fixed costs yet. One tap makes a
  fixed cost; a dismissed suggestion does not come back.
- **Variable costs and budget pools** per calendar month or year; "scalable"
  carries the rest, even a negative one, into the next period.
- **Shopping list, debts, expense groups, transfer forecasts, savings plans.**
- **Portfolio:** positions with ISIN and automatic prices from Yahoo Finance,
  gain today or since purchase, in percent or euros, sorted by value, purchase
  date, or name. Future periods show the forecast value; with the return
  scenario, each ETF grows by its own historic return, and gains count all
  money put in. A position's details show only the lots held through the
  selected day, plus forecast savings plan purchases.
- **Shares and deep analysis:** a pie and a list of the portfolio, normally by
  position, or broken down into single companies through the ETF holdings
  (Xtrackers, VanEck, iShares). The pie combines slices below 0.5 %, the list
  below 0.1 %.
- **Trade Republic:** sign in by hand to read positions, trades, cashback, and
  cash; or import a PDF statement. Saveback counts as cashback. The PIN and the
  session are not stored.
- **Bank import:** CSV and CAMT files. Known rows are skipped, the last day and
  days with extra rows are reviewed, and older months can be added later.
- **Period review:** spending per category against the average of earlier
  periods, largest differences first.
- **Forecasts:** optional interest on the depot's cash account (2.5 % a year
  unless changed), compounded monthly.
- **Face ID:** the Finance tab can be locked; it unlocks until the app goes to
  the background.

### Challenges

- Challenges and groups with repeats, check-offs, streaks, freezes, and a
  growing coin multiplier. Categories: sport, abstinence, other, and your own.
- A calendar event is a time slot: challenges with minutes fill it, several
  one-time challenges can share it, and it moves to the real duration once all
  are checked.
- Abstinence runs a timer, pays coins each day, and pays bonuses at milestones.
- Automatic challenges: the calorie challenge follows the meals, and the step
  challenge follows Apple Health. Neither can be checked by hand.
- A reward shop and a wallet. The wallet may go below zero; the shop is then
  locked. Rewards can be one-time or repeatable.
- iPhone reminders appear as suggestions and become challenges only when you
  take them; their done state is written back.
- Up to four challenges can be pinned. Symbols can be chosen freely.

### Health

- **Training:** plans from a local exercise database, plus your own
  exercises. A session runs a timer with sets and rest. A weight suggestion
  rises by a set step after all target reps were reached. History, records, and
  volume per exercise.
- **Live Activity:** the running workout on the Lock Screen and in the Dynamic
  Island, with exercise, set, time, and rest.
- **Steps:** a chart of 7 or 30 days that pages back by swipe, today, averages,
  and the best day. A daily step goal becomes a challenge with coins, streak,
  freezes, and an evening note.
- **Nutrition:** a day board of meals with calories and nutrients, favorites,
  and "recently eaten". A photo can be read by Gemini with your own key. The
  calorie challenge follows the body goal and sends an evening note with the
  day's calories.
- **Apple Health** (after you allow it): reads weight and steps, writes each
  finished workout, and updates steps in the background about once an hour.

### Widgets, Siri, and notifications

- **Widgets:** daily budget, today's challenges (check off right in the
  widget), coins and streak, portfolio, next workout, an overview with steps,
  and three Lock Screen widgets. Finance amounts stay hidden while the Finance
  lock is on, unless you allow them.
- **Siri and Shortcuts:** check off a challenge, log a meal, ask for the
  remaining budget, and book a bank notice in the background. Triggers such as
  Wallet transactions, messages, or emails can run these.
- **Notifications:** a daily briefing per weekday, challenge reminders, streak
  warnings, abstinence milestones, budget alerts at 80 % and 100 % and for the
  daily budget, the calorie and step notes, and an optional note for the
  period review.

### Settings and data

- Language (German, English), appearance (system, light, dark), and style
  (green, blue, bordeaux, violet).
- User settings: name, photo, birthday (500 coins once a year), height,
  weight, sex, goal, and step goal.
- Backup as JSON for the whole app or one area (finance, challenges, health).
  Photos, exercise pictures, price caches, and keychain items are not included.
- "Delete all data" keeps accounts and settings; "Reset app" removes them too
  and starts setup again.
- Setup asks for language, new or restore, name and birthday, period, main
  account, an optional bank file, an optional Trade Republic statement and
  sign-in. Closing the app during setup starts it again.
- A store that cannot be read is never moved away silently after setup; the
  app offers to restore a full backup.

### Privacy

- No account, telemetry, or ads. Data stays on the device.
- External requests: Yahoo Finance (ISIN or symbol), Gemini (photo, only with
  your key), Trade Republic (your sign-in), and the public ETF holdings files
  of Xtrackers, VanEck, and iShares (fund identifiers only).
- Calendar, reminders, and Apple Health are used only after you allow them.

## Deutsch

Lifify 0.6.0 ist eine lokale iPhone-App für Geld, Challenges und Gesundheit.
Sie braucht kein Konto und keinen Server. Alles bleibt auf dem Gerät, außer eine
Funktion unten nennt einen Abruf. Wie gerechnet wird, steht in
[FINANZEN.md](FINANZEN.md), wie die Ernährungsziele funktionieren in
[ERNAEHRUNG.md](ERNAEHRUNG.md), und was sich je Version geändert hat in den
CHANGES-Dateien in diesem Ordner.

### Home

- Ein Budgetring mit dem Restbudget des Zeitraums, dem nächsten Gehalt und dem
  Tagesbudget. Ein negatives Restbudget wird negativ gezeigt. Ein Tipp öffnet
  die Aufschlüsselung.
- Ein Kalender nach Tag, Woche oder Monat mit Terminen und den Challenges des
  Tages. Verknüpfte Termine lassen sich morgens abhaken.
- Unter dem Kalender: Schritte und geplante Trainings des gewählten Tages, der
  Woche oder des Monats. Trainings kommen aus Kalenderterminen mit verknüpftem
  Plan und bekommen einen Haken, sobald dieser Plan am Tag trainiert wurde.
- Die Buchungen des gezeigten Zeitraums.

### Finanzen

- **Konten:** Giro, Spartopf, Oberspartopf und Depot, mit Pflicht-Hauptkonto,
  Liquidität, IBAN und Elternkonto.
- **Buchungen:** Einnahme, Ausgabe, Umbuchung und Saldo-Korrektur; Volltextsuche;
  Zuordnung zu Fixkosten, variablen Kosten und Einkäufen; Splits für variable
  Kosten und Budgetpools.
- **Zeitraumfilter:** Kalendermonat oder Gehaltszeitraum, für alle Konten, ein
  Konto oder das Depot. Derselbe Filter gilt überall in Finanzen.
- **Einnahmen:** Einnahmeprognosen und die echten Einnahmen des Zeitraums. Unter
  den Prognosen, eingeklappt: erhaltene Dividenden, die nächsten zwölf Monate
  und die Positionen, die noch zahlen. Mit einem Schalter zählen erwartete
  Dividenden als geplante Einnahme.
- **Ausgaben:** Prognoseausgaben und die echten Ausgaben des Zeitraums.
- **Fixkosten** mit wöchentlicher, zweiwöchentlicher, monatlicher oder
  jährlicher Wiederholung, fällig am Kalendertag oder am ersten oder letzten
  Bankarbeitstag (Rheinland-Pfalz, mit Feiertagen). Oben stehen eingeklappt die
  Abo-Vorschläge: wiederkehrende Zahlungen an denselben Empfänger, die noch
  keine Fixkosten sind. Ein Tipp legt sie an; ein abgelehnter Vorschlag kommt
  nicht wieder.
- **Variable Kosten und Budgetpools** pro Kalendermonat oder Jahr; „skalierbar“
  überträgt den Rest, auch einen negativen, in den nächsten Zeitraum.
- **Einkaufszettel, Schulden, Ausgabengruppen, Umbuchungsprognosen, Sparpläne.**
- **Depot:** Positionen mit ISIN und automatischem Kurs von Yahoo Finance,
  Veränderung heute oder seit Kauf, in Prozent oder Euro, sortiert nach Wert,
  Kaufdatum oder Name. Künftige Zeiträume zeigen den Prognosewert; mit dem
  Renditeszenario wächst jeder ETF mit seiner eigenen historischen Rendite, und
  der Gewinn rechnet alles Eingezahlte mit. Die Details einer Position zeigen
  nur die Einzelpositionen bis zum gewählten Tag, dazu die erwarteten
  Sparplan-Käufe.
- **Anteile und Tiefenanalyse:** Grafik und Liste des Depots, normal nach
  Position oder über die ETF-Zusammensetzungen in einzelne Unternehmen
  aufgeteilt (Xtrackers, VanEck, iShares). Die Grafik fasst Anteile unter
  0,5 % zusammen, die Liste unter 0,1 %.
- **Trade Republic:** Anmeldung von Hand, um Positionen, Käufe, Cashback und
  Guthaben zu lesen; oder Import einer PDF-Abrechnung. Saveback zählt als
  Cashback. PIN und Sitzung werden nicht gespeichert.
- **Bankimport:** CSV- und CAMT-Dateien. Bekannte Zeilen werden übersprungen,
  der letzte Tag und Tage mit zusätzlichen Zeilen werden geprüft, und ältere
  Monate lassen sich später ergänzen.
- **Monatsrückblick:** Ausgaben je Kategorie gegen den Durchschnitt früherer
  Zeiträume, größte Abweichungen zuerst.
- **Prognosen:** optionale Zinsen auf das Depot-Verrechnungskonto (2,5 % pro
  Jahr, solange nicht geändert), monatlich mit Zinseszins.
- **Face ID:** Der Finanzen-Tab lässt sich sperren; er bleibt entsperrt, bis
  die App in den Hintergrund geht.

### Challenges

- Challenges und Gruppen mit Wiederholungen, Haken, Streaks, Freezes und einem
  wachsenden Coin-Multiplikator. Kategorien: Sport, Abstinenz, Sonstiges und
  eigene.
- Ein Kalendertermin ist ein Zeit-Slot: Challenges mit Minuten füllen ihn,
  mehrere einmalige Challenges können ihn teilen, und er rückt auf die echte
  Dauer, sobald alle abgehakt sind.
- Abstinenz läuft mit Timer, zahlt täglich Coins und Boni an Meilensteinen.
- Automatische Challenges: Die Kalorien-Challenge folgt den Mahlzeiten, die
  Schritt-Challenge Apple Health. Beide lassen sich nicht von Hand abhaken.
- Belohnungsshop und Wallet. Das Wallet darf ins Minus; dann ist der Shop
  gesperrt. Belohnungen sind einmalig oder mehrfach einlösbar.
- iPhone-Erinnerungen erscheinen als Empfehlungen und werden erst durch
  Übernahme zu Challenges; ihr Erledigt-Status wird zurückgeschrieben.
- Bis zu vier Challenges lassen sich anheften. Symbole sind frei wählbar.

### Gesundheit

- **Training:** Pläne aus einer lokalen Übungsdatenbank, dazu eigene Übungen.
  Eine Session läuft mit Timer, Sätzen und Pausen. Ein Gewichtsvorschlag steigt
  um eine eingestellte Stufe, wenn alle Zielwiederholungen geschafft wurden.
  Verlauf, Bestleistungen und Volumen je Übung.
- **Live Activity:** das laufende Training auf Sperrbildschirm und Dynamic
  Island, mit Übung, Satz, Zeit und Pause.
- **Schritte:** ein Diagramm über 7 oder 30 Tage, per Wisch zurückblätterbar,
  heute, Durchschnitte und bester Tag. Ein tägliches Schrittziel wird zur
  Challenge mit Coins, Streak, Freezes und Abendmitteilung.
- **Ernährung:** eine Tagesansicht der Mahlzeiten mit Kalorien und Nährwerten,
  Favoriten und „zuletzt gegessen“. Ein Foto kann mit eigenem Schlüssel von
  Gemini gelesen werden. Die Kalorien-Challenge folgt dem Körperziel und schickt
  abends eine Mitteilung mit dem Tagesstand.
- **Apple Health** (nach Freigabe): liest Gewicht und Schritte, schreibt jedes
  beendete Training und aktualisiert die Schritte im Hintergrund etwa einmal pro
  Stunde.

### Widgets, Siri und Mitteilungen

- **Widgets:** Tagesbudget, Challenges von heute (direkt im Widget abhakbar),
  Coins und Streak, Depot, nächstes Training, ein Überblick mit Schritten und
  drei Widgets für den Sperrbildschirm. Finanzbeträge bleiben bei aktiver
  Finanzsperre verborgen, außer du erlaubst sie.
- **Siri und Kurzbefehle:** Challenge abhaken, Mahlzeit eintragen, Restbudget
  abfragen und eine Bankmitteilung im Hintergrund buchen. Auslöser wie
  Wallet-Zahlungen, Nachrichten oder E-Mails können das starten.
- **Mitteilungen:** ein Tagesbriefing je Wochentag, Challenge-Erinnerungen,
  Streak-Warnungen, Abstinenz-Meilensteine, Budget-Warnungen bei 80 % und 100 %
  und fürs Tagesbudget, die Kalorien- und Schritt-Mitteilungen und optional
  eine Mitteilung zum Monatsrückblick.

### Einstellungen und Daten

- Sprache (Deutsch, Englisch), Erscheinungsbild (System, Hell, Dunkel) und Stil
  (Grün, Blau, Bordeaux, Violett).
- Nutzereinstellungen: Name, Foto, Geburtstag (500 Coins einmal im Jahr),
  Größe, Gewicht, Geschlecht, Ziel und Schrittziel.
- Sicherung als JSON für die ganze App oder einen Bereich (Finanzen,
  Challenges, Gesundheit). Fotos, Übungsbilder, Kurs-Caches und Einträge im
  Schlüsselbund sind nicht enthalten.
- „Alle Daten löschen“ behält Konten und Einstellungen; „App zurücksetzen“
  entfernt auch diese und startet die Einrichtung neu.
- Die Einrichtung fragt Sprache, neu oder wiederherstellen, Name und Geburtstag,
  Zeitraum, Hauptkonto, eine optionale Bankdatei sowie optional
  Trade-Republic-Abrechnung und -Anmeldung ab. Wird die App dabei geschlossen,
  beginnt sie von vorn.
- Ein nicht lesbarer Datenspeicher wird nach der Einrichtung nie still
  verschoben; die App bietet an, eine Gesamtsicherung wiederherzustellen.

### Datenschutz

- Kein Konto, keine Telemetrie, keine Werbung. Die Daten bleiben auf dem Gerät.
- Externe Abrufe: Yahoo Finance (ISIN oder Symbol), Gemini (Foto, nur mit
  deinem Schlüssel), Trade Republic (deine Anmeldung) und die öffentlichen
  Bestandslisten von Xtrackers, VanEck und iShares (nur Fonds-Kennungen).
- Kalender, Erinnerungen und Apple Health werden nur nach deiner Freigabe
  genutzt.
