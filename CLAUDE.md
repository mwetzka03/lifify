# CLAUDE.md – Arbeitsanweisung für Lifify

Diese Datei liest Claude Code bei jedem Start. Sie hält fest, was mit dem
Eigentümer (mwetzka03) vereinbart wurde. Stand: 22.11.2026, Branch
`version0.5.5`, abgezweigt von `version0.5.0` (Commit c8973d2).

Die ausführliche Code-Analyse liegt als Claude Doc im Projekt „Lifify“:
„Lifify 0.5.0 – Code-Analyse und Rückfragen“.

---

## 1. Zusammenarbeit

- Ideen, Annahmen und Anweisungen kritisch prüfen. Nichts beschönigen,
  Schwachstellen, Trade-offs und Risiken klar benennen.
- Bei Unklarheiten vor der Umsetzung gezielt nachfragen. Zentrale
  Anforderungen nicht raten.
- Eigene Ideen sind erwünscht, werden aber **erst vorgeschlagen** (Nutzen,
  Aufwand) und nur nach Zustimmung umgesetzt.
- Jede Änderung nachvollziehbar dokumentieren: was, warum, Auswirkungen und
  Nebenwirkungen.
- Ton: sachlich, direkt, ehrlich, konstruktiv. Antworten auf Deutsch.
- **Funktionierendes Verhalten nicht entfernen.** Vieles wirkt verschachtelt,
  ist aber gewollt (siehe Abschnitt 3). Im Zweifel fragen.

## 2. Arbeitsweise im Repo

- Branch: `version0.5.5`. **Ein Commit pro abgeschlossenem Schritt**, mit
  aussagekräftiger Commit-Message.
- Vor jedem Commit: bauen und testen (siehe unten). Ein Schritt ist erst
  fertig, wenn Build und Tests grün sind.
- Pushen und Löschen von Dateien außerhalb des vereinbarten Umbaus nur nach
  Rückfrage.
- Version überall auf **0.5.5** setzen (`MARKETING_VERSION` im Projekt,
  angezeigte Version in den Einstellungen, README, FEATURES).
- Changelog: `Changes Documentation/CHANGES-0.5.0.md` wird zu
  `CHANGES-0.5.5.md` umbenannt und **direkt bearbeitet**. Informationen, die
  noch stimmen, bleiben. Was nicht mehr stimmt, wird korrigiert oder
  entfernt. Neue Änderungen kommen dazu. Englisch zuerst, dann Deutsch
  (RULES.md).
- README, FEATURES, FINANZEN, ERNAEHRUNG und RULES bei jeder betroffenen
  Änderung anpassen. Bekannte Widersprüche zwischen Doku und Code
  (Abschnitt 5) dabei mit beheben.
- Modular bauen: klare Zuständigkeiten, keine Fachlogik in Views.

### Bauen und testen (macOS, Xcode)

```bash
# Simulator-Namen ermitteln
xcrun simctl list devices available | grep iPhone

# Build
xcodebuild -project Lifify.xcodeproj -scheme Lifify \
  -destination 'platform=iOS Simulator,name=<iPhone-Name>' build

# Tests
xcodebuild -project Lifify.xcodeproj -scheme Lifify \
  -destination 'platform=iOS Simulator,name=<iPhone-Name>' test
```

Für den Simulator ist keine Signatur nötig. Für das echte iPhone wählt der
Eigentümer sein Team selbst in Xcode.

## 3. Bestätigte Fachregeln (nicht ändern)

### Challenges, Zeit-Slots und Gruppen

- Challenges können eine geschätzte Dauer in Minuten haben.
- Ein Kalendertermin ist ein Zeit-Slot. Ihm werden Challenges zugewiesen,
  bis die Minuten aufgebraucht sind (`ChallengeTimeRules.fitCount`,
  `remaining`).
- Ab zwei Challenges an einem Termin entsteht eine Gruppe. Ihr Name ist
  „Termin – Tag“. Gruppen lassen sich auch manuell anlegen und befüllen.
- **Sport und Abstinenz haben keine Minuten und belegen einen Termin immer
  exklusiv.**
- **Einen Termin teilen können sich nur einmalige Challenges.** Eine
  wiederkehrende Challenge darf nur einen leeren Termin allein belegen.
- **Sind alle Challenges eines Termins abgehakt, wird der Termin auf die
  tatsächliche Dauer verschoben** (Ende = letzter Haken, Start = Ende minus
  Ist-Minuten). Im iOS-Kalender wird der alte Termin gelöscht und neu
  angelegt (`ChallengeTimeService.resize`).
- Vergangene Tage sind nachträglich abhakbar.

### Training ↔ Challenge ↔ Termin

- Die Verknüpfung ist **n:m und gewollt** (`WorkoutLinkStore`). An einem
  wiederkehrenden Apple-Termin (z. B. Sport) können mehrere Trainingspläne
  hängen. Wird **einer** davon absolviert, gilt die Challenge als abgehakt.
- Nach dem Training wird der Termin auf die echte Trainingszeit gesetzt
  (auf 5 Minuten gerundet, `WorkoutCalendarSync`).
- **Vergangene Trainingstermine ohne passendes Training werden gelöscht**,
  auch im iOS-Kalender (`WorkoutCalendarSync.cleanup`). Gewollt.
- Eine Sport-Challenge mit verknüpftem Training wird nur durch das Beenden
  des Trainings erledigt, nicht von Hand.
- Streaks gelten auch hier.

### Coins und Shop

- Coins sind reine Gamification.
- **Das Wallet darf ins Minus gehen** (z. B. durch Entfernen eines Hakens
  nach einem Kauf oder durch die Ernährungs-Challenge).
- **Bei negativem Guthaben ist der Shop gesperrt**, bis das Guthaben wieder
  bei 0 oder darüber liegt. Das gilt für alle Käufe: Belohnungen,
  Streak-Freezes und den automatischen Fast-Food-Kauf. Zu prüfen ist, ob
  der automatische Fast-Food-Kauf bei Minus trotzdem buchen soll; vorher
  fragen.
- Neu umzusetzen: Die Sperre muss klar in der Oberfläche sichtbar sein.

### Depot und Sparplan-Prognose

- Die Prognose existiert bereits (`PortfolioActivity.futureShares`). Jede
  künftige Sparplan-Ausführung kauft Betrag ÷ **aktueller Kurs** Stücke.
  Es gibt keine Kursentwicklung in der Prognose. So bleibt es.

### Trade Republic

- Der Live-Login über die inoffizielle Web-API **bleibt**. Er funktioniert
  beim Eigentümer. Die Risiken (Bruch bei API-Änderungen,
  Nutzungsbedingungen) sind bekannt und akzeptiert.
- PIN wird nicht gespeichert, Sitzung wird nicht gespeichert, kein
  automatischer Abruf. Der PDF-Import bleibt.

### Kurzbefehle und URL-Schema

- `lifify://notice?account=…&text=…` und der AppIntent
  `RecordBankNoticeIntent` bleiben offen. Das ist für Apple Kurzbefehle
  gewollt (Bankmitteilung → Buchung).

### Onboarding

- Wird die App während der Ersteinrichtung geschlossen, beginnt die
  Einrichtung von vorn. Dabei gehen die Teildaten verloren. Gewollt.
- Nach abgeschlossener Einrichtung bleiben alle Daten erhalten.

## 4. Plan (in dieser Reihenfolge)

Jeder Schritt: umsetzen → bauen → testen → Doku anpassen → committen.

### Schritt 1 – Echtes Testgerüst

- Swift Testing (`import Testing`, `@Test`, `#expect`) im vorhandenen Target
  `LififyTests`.
- Eine Hilfsfunktion für einen In-Memory-`ModelContainer`
  (`ModelConfiguration(isStoredInMemoryOnly: true)`). Tests schreiben nie
  echte Nutzerdaten.
- UserDefaults in Tests über eine eigene Suite (`UserDefaults(suiteName:)`)
  isolieren. Wo Services fest `UserDefaults.standard` nutzen, die
  Abhängigkeit injizierbar machen. Das ist Vorarbeit für Schritt 3.
- Zuerst Tests für die Kernregeln: Coins und Wallet, Streaks und Freezes,
  Multiplikator, Abstinenz-Auszahlung, Zeit-Slots und Gruppen,
  Training-Verknüpfung, Fälligkeit (`ChallengeService.isDue`), Finanzsalden,
  Prognosen, Sparplan-Prognose, Backup-Rundlauf.

### Schritt 2 – In-App-Prüfseite entfernen

- `LififyChecks.swift`, `LififyCoverageChecks.swift`,
  `LififyFeatureChecks.swift`, `LififySessionChecks.swift`,
  `CheckStories.swift`, `CheckGuides.swift` sowie die Prüfseite in
  `SettingsView` entfernen. Freigabe des Eigentümers liegt vor.
- **Achtung:** Die Checks enthalten Regeln, die echte Tests abdecken müssen.
  Vor dem Löschen jede Check-Gruppe durchgehen. Was eine echte Regel prüft,
  wird als Test in Schritt 1 übernommen. Was nur Konstanten oder UI-Texte
  gegen sich selbst prüft, entfällt. Dazu zählen Konstanten-Enums wie
  `TradeRepublicRefresh`, `TradeRepublicGap` und `TradeRepublicSample`, die
  nur als „Dokumentation“ für die Checks existieren. Sie werden nur dann
  entfernt, wenn der Code sie nicht fachlich nutzt.
- `RULES.md`, Abschnitt „Checks“, auf echte Tests umschreiben.
- Laut Eigentümer schlagen derzeit einige In-App-Checks fehl. Vor dem
  Entfernen einmal alle ausführen und die Fehlschläge notieren. Jeder
  Fehlschlag wird untersucht: echter Fehler im Code oder nur ein veralteter
  Check?

### Schritt 3 – Wallet-Regel

- Shop-Sperre bei negativem Guthaben (Abschnitt 3) mit Tests umsetzen.

### Schritt 4 – Backup vollständig

Diese Daten werden beim Löschen zurückgesetzt, aber **nicht exportiert**.
Nach einem Restore fehlen sie:

- `TransferForecastStore` (Umbuchungsprognosen)
- `RefundLinkStore`
- `ForecastSkipStore`, `ForecastPeriodLinkStore`,
  `ForecastMatchRejectionStore`
- `NoticeTemplateStore` (Kurzbefehl-Vorlagen)
- `ChallengePinStore` (angepinnte Challenges und Gruppen)
- `VariableBudgetAccounts`
- `EventOffer` (`lifify.eventOffer.<id>`)
- Alle übrigen `lifify.*`-Schlüssel systematisch prüfen. Reine Caches wie
  `HistoricalPriceStore` gehören nicht ins Backup.

Ein Test exportiert einen vollständigen Datenbestand, setzt alles zurück,
stellt wieder her und vergleicht.

### Schritt 5 – Persistenz zusammenführen

Heute liegt Fachdatenbestand an drei Orten: SwiftData (Schema V2, seit
langem unverändert), rund 70 UserDefaults-Schlüssel (JSON-Blobs) und
JSON-Dateien (Trainings, Mahlzeiten-Fotos).

- Neues `LififySchemaV3` mit eigenen `@Model`-Typen für die Daten aus
  UserDefaults: Depot-Lots, Sparpläne, geschlossene Positionen,
  Prognose-Verknüpfungen, Streak-Zustände, Abstinenz, Mahlzeiten,
  Challenge-Dauern und Termin-Mitglieder, Workout-Links, Pins und so weiter.
- **Gruppen- und Terminzugehörigkeit steht heute an vier Stellen:**
  `ChallengeItem.groupID`, `ChallengeItem.groupIDsRaw` (Komma-Text),
  `ChallengeCalendarEvent.linkedChallengeID` bzw. `linkedChallengeGroupID`
  und `ChallengeTimeStore.memberIDs`. Das wird eine einzige Quelle. Das
  Verhalten aus Abschnitt 3 muss identisch bleiben; vorher Tests schreiben.
- Einmalige Übernahme der UserDefaults-Daten beim ersten Start von 0.5.5.
  Sie muss idempotent sein, und die alten Schlüssel werden erst nach
  erfolgreicher Übernahme gelöscht.
- `ModelContainer` mit `migrationPlan: LififyMigrationPlan` erzeugen. Heute
  fehlt das.
- `StoreRecoveryService`: **Kein stilles Wegschieben des Stores** mehr bei
  einer fertig eingerichteten App. Stattdessen eine klare Fehlermeldung mit
  der Möglichkeit, ein Backup wiederherzustellen. Das Onboarding-Verhalten
  aus Abschnitt 3 bleibt.
- Danach wird das Backup aus den Modellen erzeugt statt aus einer
  handgepflegten Liste. Schritt 4 bleibt als Test bestehen.
- Kein iCloud-Sync geplant. `@Attribute(.unique)` darf bleiben.
- Bereich für Bereich vorgehen, jeweils mit eigenem Commit.

### Schritt 6 – Performance

Am schlimmsten laut Eigentümer: **der erste Aufruf der Finanzen und alles
rund um Aktien und Depot.**

- Erst messen (Instruments: Time Profiler, SwiftUI), dann ändern. Messwerte
  vorher und nachher im Changelog festhalten.
- Bekannte Verdachtsfälle:
  - viele ungefilterte `@Query`, allein 22 in `TransactionsView`
  - Berechnungen im `body` (`FinanceService`, `PortfolioActivity`,
    Streak-Status über alle Perioden)
  - wiederholtes Dekodieren von UserDefaults-JSON
  - Kursabruf beim Start
- Der Ladebildschirm beim Zurückkehren in die App ist ein Symptom-Pflaster.
  Nach der Optimierung prüfen, ob er noch nötig ist.

### Schritt 7 – Modularisierung

- Freigegeben: lokale Swift Packages, etwa `LififyCore` (Modelle,
  Persistenz, Formatierung), `LififyFinance`, `LififyChallenges`,
  `LififyHealth` und `LififyTradeRepublic`. Dazu die App als dünne Hülle.
- Die genaue Aufteilung vorher als Vorschlag zur Freigabe vorlegen.

### Offene Punkte für später (nur vorschlagen, nicht umsetzen)

- Entwicklermodus mit simuliertem Tag: `AbstinenceService` zahlt Coins für
  simulierte Tage dauerhaft aus. Lösung vorschlagen.
- Altlasten: `SavedArticle` (Platzhalter) und Bucketlist (ausgeblendet).
  Klären, ob sie entfernt werden.
- Spätere Ideen des Eigentümers: Desktop-Version oder ein lokales Dashboard
  über localhost. Nur im Hinterkopf behalten.

## 5. Bekannte Widersprüche zwischen Doku und Code

- README: Die Trade-Republic-Sitzung liege im Schlüsselbund. Code:
  `storesSession = false`, gespeichert wird nichts.
- README: Ohne Schlüssel verlässt kein Foto das Gerät. Das stimmt. Mit
  Schlüssel gehen aber zusätzlich Größe, Gewicht, Alter, Geschlecht und Ziel
  an Gemini (`MealRecognition.prompt`). Ergänzen.
- `MealRecognition.send(thinking: true)` setzt `thinkingBudget: 0`, schaltet
  das Nachdenken also gerade aus. Die Benennung ist irreführend.
- FEATURES §14: Die Ernährung fehle noch. Sie ist umgesetzt.
- FEATURES, Annahme 1: Das Backup sichere sämtliche Nutzerdaten. Erst nach
  Schritt 4 wahr.

## 6. Technische Leitplanken

- iOS 17+, SwiftUI, SwiftData, Swift 6.
- Keine Drittanbieter-Abhängigkeiten, keine Secrets im Repo.
- Beträge als ganzzahlige Cent.
- Zweisprachige Texte über `L("Deutsch", "English")`.
- Stil: Grün, Blau, Bordeaux und Violett; kein Systemblau auf gestylten
  Flächen; positive Beträge grün, negative rot (RULES.md).
