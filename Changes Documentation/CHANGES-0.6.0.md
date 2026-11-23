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
