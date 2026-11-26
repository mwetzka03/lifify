# Lifify – Overview, settings, and data

[English](#english) · [Deutsch](#deutsch)

## English

Lifify 0.6.0 is a local iPhone app for money, challenges, and health. It needs no account and no server. The areas are explained in [FINANCE.md](FINANCE.md), [CHALLENGES.md](CHALLENGES.md), and [HEALTH.md](HEALTH.md); what changed per version is in the CHANGES files in this folder.

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

### Widgets, Siri, and notifications

- **Widgets:** daily budget, today's challenges (check off right in the
  widget), coins and streak, portfolio, next workout, an overview with steps,
  and three Lock Screen widgets. Finance amounts stay hidden while the Finance
  lock is on, unless you allow them.
  The widgets carry a soft wash of the chosen style and fill their room: the
  portfolio widget shows the budget ring in the medium size, the workout widget
  today's steps, and the Today and overview widgets coins and streak.
- **Loading:** a short start screen with the app name, and one loading
  animation without a box on every screen that loads: three rings in the style
  color turning at slightly different speeds.
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

Lifify 0.6.0 ist eine lokale iPhone-App für Geld, Challenges und Gesundheit. Sie braucht kein Konto und keinen Server. Die Bereiche erklären [FINANCE.md](FINANCE.md), [CHALLENGES.md](CHALLENGES.md) und [HEALTH.md](HEALTH.md); was sich je Version geändert hat, steht in den CHANGES-Dateien in diesem Ordner.

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

### Widgets, Siri und Mitteilungen

- **Widgets:** Tagesbudget, Challenges von heute (direkt im Widget abhakbar),
  Coins und Streak, Depot, nächstes Training, ein Überblick mit Schritten und
  drei Widgets für den Sperrbildschirm. Finanzbeträge bleiben bei aktiver
  Finanzsperre verborgen, außer du erlaubst sie.
  Die Widgets tragen einen leichten Verlauf im gewählten Stil und nutzen ihren
  Platz: das Depot-Widget zeigt in mittlerer Größe den Budgetring, das
  Trainings-Widget die Schritte von heute, die Widgets Heute und Überblick
  Coins und Streak.
- **Laden:** ein kurzer Startbildschirm mit dem App-Namen und eine
  Ladeanimation ohne Box auf jedem Bildschirm, der lädt: drei Ringe in der
  Stilfarbe, die sich unterschiedlich schnell drehen.
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
