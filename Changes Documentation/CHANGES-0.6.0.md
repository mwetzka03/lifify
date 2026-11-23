# Changes in 0.6.0

[English](#english) · [Deutsch](#deutsch)

## English

### Overview

Version 0.6.0 first improves the code base (part A) and then adds new features
(part B). This file grows with each finished step.

### 0.6.0: Testable calendar access (A1)

- **What:** All access to the system calendar and Reminders now goes through
  the `CalendarGateway` protocol. The app uses `EventKitCalendarGateway`. Tests
  use a stand-in that records every call.
- **Why:** The paths that rewrite or delete real calendar events had no tests.
- **Effect:** No visible change. New tests cover the event rewrite after
  checking off, `WorkoutCalendarSync.apply` and `cleanup`, abstinence bonuses
  through `settle` and a relapse, the calendar import, and restoring full and
  Health backups.
- **Side effects:** Tests can no longer reach a real calendar. When several
  events move at once, their calendar rewrites now run one after another
  instead of in parallel. The duplicated recurrence translation is now shared.

### 0.6.0: Leaner screens (A2, in progress)

- **What:** The depot and the challenge board calculate through screen models
  (`PortfolioScreenModel`, `ChallengeBoardModel`). A booking row resolves its
  category and sale result once per render.
- **Why:** The depot repeated its calculations for every row. Every challenge
  card searched the completions of all challenges.
- **Effect:** Same values and same look, with faster first opens. Release build
  in the iPhone 17 simulator with 5,000 bookings, 30 holdings, 1,200 lots, 365
  prices per holding, 100 challenges, and 3,000 completions:

  | Screen | Before (median) | After (median) |
  | --- | ---: | ---: |
  | Depot | 1.9 s | 0.5 s |
  | Challenges, run 1 | 1.8 s | 0.6 s |
  | Challenges, run 2 | 3.6 s | 0.35 s |

- **Limits:** Simulator runs vary widely, so only clear differences count. The
  finance overview, transactions, and data management showed no measurable
  change. An extra forecast cache for the overview brought no gain and was
  removed again.
- **Measuring:** `ScreenPerformanceTests` is skipped in normal test runs and
  starts with `TEST_RUNNER_LIFIFY_MEASURE=1`.

### 0.6.0: Old group column removed (A3)

- **What:** Database schema V4 removes `ChallengeItem.groupID`. Before the
  column is dropped, the migration copies a group that exists only there into
  `groupIDsRaw`.
- **Why:** Group membership was stored twice.
- **Deviation from the plan:** `groupIDsRaw` stays, because it is the current
  source of all group memberships. Removing it would lose them. No other
  column turned out to be unused and safe to remove.
- **Effect:** No visible change. A database written by the real 0.5.5 code is
  now a test fixture with invented data. It opens with all data and groups.
- **Tests changed:** The single-group test now checks `groupIDs`. The old
  normalization test was replaced by the migration tests, because a record
  with only the old column can no longer exist after the migration.

### 0.6.0: Readable documents (A5)

- **What:** Long passages in `FINANZEN.md` are now lists. The setup screen says
  Health (workouts and meals) instead of Training for a partial restore.
- **Why:** The rules were hard to scan, and the area has been called Health
  since 0.5.5.
- **Effect:** The wording of every finance rule is unchanged. A script compared
  all words before and after the reformatting.

### 0.6.0: Developer mode no longer changes real coins (A6)

- **What:** While developer mode shows another day, Lifify records coin
  bookings, check-offs, purchases, freezes, abstinence bonuses, and the
  birthday bonus. Back on the real day, at launch, or when the mode is turned
  off, exactly these changes are undone.
- **Why:** Simulated days used to pay coins permanently.
- **Effect:** Developer mode can be used for testing without changing the real
  wallet. Bonuses can be earned again on their real day.
- **Today:** Meal rewards now follow the simulated day.
- **Deliberately on the real clock:** The cleanup of past training events
  stays on the real date, so a simulated day can never delete real events from
  the iOS calendar.
- **Limits:** Meals entered on a simulated day stay, only their coins and
  fast-food charges are undone. A real booking removed during a simulation is
  not restored. A backup made during a simulation contains the simulated
  bookings as normal data.

## Deutsch

### Überblick

Version 0.6.0 verbessert zuerst die Codebasis (Teil A) und ergänzt danach neue
Funktionen (Teil B). Diese Datei wächst mit jedem abgeschlossenen Schritt.

### 0.6.0: Testbarer Kalenderzugriff (A1)

- **Was:** Alle Zugriffe auf den Systemkalender und die Erinnerungen laufen
  jetzt über das Protokoll `CalendarGateway`. Die App nutzt
  `EventKitCalendarGateway`, Tests eine Attrappe, die jeden Aufruf aufzeichnet.
- **Warum:** Die Pfade, die echte Kalendertermine umschreiben oder löschen,
  hatten keine Tests.
- **Auswirkung:** Sichtbar ändert sich nichts. Neue Tests decken das
  Umschreiben nach dem Abhaken, `WorkoutCalendarSync.apply` und `cleanup`,
  Abstinenz-Boni über `settle` und Rückfall, den Kalenderimport sowie die
  Wiederherstellung von Gesamt- und Gesundheits-Backup ab.
- **Nebenwirkungen:** Tests erreichen keinen echten Kalender mehr. Verschieben
  sich mehrere Termine gleichzeitig, werden sie im Kalender jetzt nacheinander
  statt parallel umgeschrieben. Die doppelte Übersetzung der Wiederholungen ist
  zusammengeführt.

### 0.6.0: Schlankere Screens (A2, in Arbeit)

- **Was:** Depot und Challenge-Übersicht rechnen über Screen-Modelle
  (`PortfolioScreenModel`, `ChallengeBoardModel`). Eine Buchungszeile ermittelt
  Kategorie und Verkaufsergebnis nur noch einmal pro Darstellung.
- **Warum:** Das Depot wiederholte seine Berechnungen für jede Zeile. Jede
  Challenge-Karte durchsuchte die Abschlüsse aller Challenges.
- **Auswirkung:** Gleiche Werte und gleiches Aussehen, aber schnellere erste
  Aufrufe. Release-Build im iPhone-17-Simulator mit 5.000 Buchungen, 30
  Positionen, 1.200 Lots, 365 Kursen je Position, 100 Challenges und 3.000
  Abschlüssen:

  | Screen | Vorher (Median) | Nachher (Median) |
  | --- | ---: | ---: |
  | Depot | 1,9 s | 0,5 s |
  | Challenges, Lauf 1 | 1,8 s | 0,6 s |
  | Challenges, Lauf 2 | 3,6 s | 0,35 s |

- **Grenzen:** Simulatorläufe schwanken stark, deshalb zählen nur deutliche
  Unterschiede. Finanzübersicht, Buchungen und Datenverwaltung zeigten keine
  messbare Änderung. Ein zusätzlicher Prognose-Zwischenspeicher für die
  Übersicht brachte nichts und wurde wieder entfernt.
- **Messen:** `ScreenPerformanceTests` wird in normalen Testläufen übersprungen
  und startet mit `TEST_RUNNER_LIFIFY_MEASURE=1`.

### 0.6.0: Alte Gruppenspalte entfernt (A3)

- **Was:** Das Datenbankschema V4 entfernt `ChallengeItem.groupID`. Bevor die
  Spalte wegfällt, kopiert die Migration eine Gruppe, die nur dort steht, nach
  `groupIDsRaw`.
- **Warum:** Die Gruppenzugehörigkeit lag doppelt vor.
- **Abweichung vom Plan:** `groupIDsRaw` bleibt, weil diese Spalte die aktuelle
  Quelle aller Gruppenzugehörigkeiten ist. Ohne sie gingen sie verloren. Keine
  weitere Spalte erwies sich als ungenutzt und sicher entfernbar.
- **Auswirkung:** Sichtbar ändert sich nichts. Eine mit dem echten 0.5.5-Code
  geschriebene Datenbank mit erfundenen Daten ist jetzt Testbestand. Sie öffnet
  mit allen Daten und Gruppen.
- **Geänderte Tests:** Der Test zur Einzelgruppe prüft jetzt `groupIDs`. Der
  alte Normalisierungstest wurde durch die Migrationstests ersetzt, weil es
  nach der Migration keinen Eintrag mehr gibt, der nur die alte Spalte kennt.

### 0.6.0: Lesbare Dokumente (A5)

- **Was:** Lange Passagen in `FINANZEN.md` sind jetzt Listen. Die Einrichtung
  nennt beim teilweisen Wiederherstellen Gesundheit (Trainings und Mahlzeiten)
  statt Training.
- **Warum:** Die Regeln waren schwer zu überblicken, und der Bereich heißt seit
  0.5.5 Gesundheit.
- **Auswirkung:** Der Wortlaut aller Finanzregeln bleibt gleich. Ein Skript hat
  alle Wörter vor und nach der Umformatierung verglichen.

### 0.6.0: Entwicklermodus verändert keine echten Coins mehr (A6)

- **Was:** Solange der Entwicklermodus einen anderen Tag zeigt, merkt sich
  Lifify Coin-Buchungen, Abhaken, Käufe, Freezes, Abstinenz-Boni und den
  Geburtstagsbonus. Zurück auf dem echten Tag, beim Start oder beim Ausschalten
  des Modus werden genau diese Änderungen rückgängig gemacht.
- **Warum:** Simulierte Tage haben bisher dauerhaft Coins ausgezahlt.
- **Auswirkung:** Der Entwicklermodus lässt sich zum Testen nutzen, ohne das
  echte Wallet zu verändern. Boni lassen sich an ihrem echten Tag wieder
  verdienen.
- **Heute:** Mahlzeiten-Belohnungen folgen jetzt dem simulierten Tag.
- **Bewusst auf der echten Uhr:** Das Aufräumen vergangener Trainingstermine
  bleibt beim echten Datum, damit ein simulierter Tag nie echte Termine aus dem
  iOS-Kalender löscht.
- **Grenzen:** Mahlzeiten, die an einem simulierten Tag eingetragen wurden,
  bleiben, nur ihre Coins und Fast-Food-Abbuchungen werden zurückgenommen. Eine
  echte Buchung, die während der Simulation entfernt wird, kommt nicht zurück.
  Ein Backup aus einer laufenden Simulation enthält die simulierten Buchungen
  als normale Daten.
