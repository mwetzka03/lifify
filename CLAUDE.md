# Lifify – Rules

[English](#english) · [Deutsch](#deutsch)

These rules apply to every change in Lifify. Claude Code reads this file at the start of every session.

## English

### Working together

- Check ideas, assumptions, and instructions critically. Name weak spots,
  trade-offs, and risks plainly.
- Ask before building when a central requirement is unclear; do not guess it.
- Own ideas are welcome, but are proposed first (benefit, effort) and built
  only after the owner agrees.
- Document every change: what, why, effect, and side effects.
- Answers to the owner are in German: factual, direct, honest, constructive.
- Do not remove working behavior. Much that looks tangled is intended (see
  Confirmed rules). When in doubt, ask.

### Repository and workflow

- Work on the version branch. One commit per finished step, with a clear
  message. Push only to the version branch, never to `main`.
- Before each commit, build and run all tests. A step is finished only when
  both are green.
- Push and delete files outside the agreed work only after asking.
- A new version sets the version everywhere: `MARKETING_VERSION` of both
  targets, `AppVersion.current`, README, and GENERAL.md.
- Each version has its changelog in Documentation: an overview, then
  one section per area, short bullets with what, why, and effect.
- Update README, this file, and the area documents (FINANCE, CHALLENGES,
  HEALTH, GENERAL) with every change that affects them. New calculation rules
  belong in FINANCE.md.
- Business logic lives in the packages (`LififyCore`, `LififyFinance`,
  `LififyChallenges`, `LififyHealth`), never in views. Extensions such as the
  widgets use the same packages.
- The local signing team in the project file is the owner's and is never
  committed.

Build and test (macOS, Xcode):

```bash
xcrun simctl list devices available | grep iPhone
xcodebuild -project Lifify.xcodeproj -scheme Lifify -destination 'platform=iOS Simulator,name=<iPhone>' build
xcodebuild -project Lifify.xcodeproj -scheme Lifify -destination 'platform=iOS Simulator,name=<iPhone>' test
```

The Simulator needs no signing. For the owner's iPhone, the owner's team is
chosen in Xcode. Widgets, the App Group, HealthKit, and Live Activities need
entitlements. The owner's account is a free personal team: profiles last 7
days, and capabilities such as Family Controls are not available. Steps in the
Apple developer account are described to the owner, never guessed.

### Technical guardrails

- iOS 17 or newer, SwiftUI, SwiftData, Swift 6.
- No third-party dependencies and no secrets in the repository.
- Amounts are whole cents.
- Texts in both languages through `L("Deutsch", "English")`.
- Network only where needed: Yahoo Finance, Gemini with the person's key,
  Trade Republic, and the ETF holdings files of Xtrackers, VanEck, and
  iShares. Every external source is named in the README under privacy.
- The database stays in the app's own folder. Widgets read a snapshot in the
  App Group; only the app books.

### Confirmed rules (do not change)

**Challenges, time slots, and groups**

- A challenge can have an estimated duration in minutes.
- A calendar event is a time slot. Challenges are assigned to it until its
  minutes are used up (`ChallengeTimeRules.fitCount`, `remaining`).
- Two or more challenges on one event form a group named "Event – Day".
  Groups can also be made and filled by hand.
- Sport and abstinence have no minutes and always take an event alone.
- Only one-time challenges can share an event. A recurring challenge may only
  take an empty event alone.
- When all challenges of an event are checked, the event moves to the real
  duration (end = last check, start = end minus the actual minutes). In the
  iOS calendar the old event is deleted and created anew
  (`ChallengeTimeService.resize`).
- Past days can be checked afterward.
- The direct event link and the event's member list stay separate; only the
  direct link sets the streak target.
- Automatic challenges (calories, steps) cannot be checked by hand or placed
  in a time slot.

**Training, challenge, and event**

- The link is many-to-many on purpose. Several training plans can hang on one
  recurring event; finishing one of them checks the challenge.
- After training, the event is set to the real training time, rounded to five
  minutes (`WorkoutCalendarSync`).
- Past training events without a matching training are deleted, also in the
  iOS calendar (`WorkoutCalendarSync.cleanup`). Intended.
- A sport challenge with a linked training finishes only when the training
  ends, not by hand. Streaks apply.

**Coins and shop**

- Coins are pure gamification.
- The wallet may go below zero. With a negative balance the shop is locked
  until the balance is back at zero or above.
- The automatic fast-food purchase books even while the shop is locked.

**Depot forecast**

- Each future savings plan execution buys amount ÷ today's price. Without the
  return scenario there is no price movement; that stays the default view. The
  return scenario is an extra switch (FINANCE.md).

**Trade Republic**

- The live sign-in through the unofficial web API stays; its risks are known
  and accepted. The PIN and the session are not stored, and nothing is fetched
  automatically. The PDF import stays.

**Shortcuts and URL scheme**

- `lifify://notice?account=…&text=…` and `RecordBankNoticeIntent` stay open on
  purpose, so Apple Shortcuts can turn a bank notice into a booking.

**Setup**

- Closing the app during setup starts setup again and drops the partial data.
  Intended. After setup, all data stays.

### Decisions

- **Not wanted:** savings goals, the saver's allowance, a weight history next
  to the calorie balance, challenge statistics, a weekly review, an automatic
  test run (CI), and the app lock with Screen Time (dropped 24 Nov 2026).
- **Not decided, do not build:** checking a challenge off from its
  notification, and sleep from Apple Health.
- **Proposals first:** more automatic challenges from Health values beyond
  steps, a desktop version, a local dashboard over localhost.
- **Open work:** rebuild `DashboardView` and `TransactionsView` into screen
  models and split the remaining long methods (code rules); add a 0.6.0 store
  and backup as test fixtures before the next release.

### Language

Document a change in English and in German. English comes first. Each version
has its own changelog, as [CHANGES-0.6.0.md](Documentation/CHANGES-0.6.0.md) does for 0.6.0.
Only README.md and CLAUDE.md stay at the top. Every other document lives in
the Documentation folder and has an English name: the changelogs, and one file
per area that explains what it can do and how it works: FINANCE.md,
CHALLENGES.md, HEALTH.md (training, steps, and nutrition), and GENERAL.md (home,
widgets, Siri, notifications, settings, data, privacy). All of them are
bilingual in the same way.

### Tests

New behavior gets automated tests in `LififyTests`, written with Swift Testing
and grouped by topic. Test real rules, not constants or UI text against
themselves. Tests run through `withTestStore`, which provides an in-memory
database and a private UserDefaults suite, so they never write user data.
Services read UserDefaults through `AppDefaults.store`, never directly. A step
is finished when the build and all tests pass.

### Code

**Small methods, no duplication**

- A method does one thing. Guideline: at most about 30 lines. A longer
  method is split into helpers whose names say what they do, so the outer
  method reads like a short list of steps.
- Logic that appears a second time moves into one shared function or type in
  the right package. Copies are not allowed, including copied view code.
- Reuse goes through **protocols with default implementations** (protocol
  extensions), generics, and composition. This is Swift's form of
  inheritance and works for structs, enums, and classes alike.
- Class inheritance only where it really models an “is a” relationship or a
  framework requires it. SwiftData model inheritance needs iOS 26 and is not
  used while the app supports iOS 17.
- SwiftUI: shared look and behavior go into `ViewModifier`s and small
  subviews, not into repeated modifier chains.
- An `enum` with only static functions is fine as a namespace. Data with
  behavior is a `struct` (or a class where reference semantics are needed)
  that conforms to the right protocols.

**Documentation in the code**

- Every type (struct, class, enum, protocol, extension with its own purpose)
  and every method or property that is not trivially private gets a `///`
  comment above it: one or two sentences on what it does, and why when that
  is not obvious.
- Longer methods (more than about 15 lines) or methods with parameters whose
  meaning is not obvious also list their input and output in DocC form:

  ```swift
  /// Builds the forecast for one finance period.
  ///
  /// - Parameters:
  ///   - period: The salary or calendar period to forecast.
  ///   - entries: All bookings of the selected accounts.
  /// - Returns: Booked and open income and expenses of the period.
  func forecast(for period: FinancePeriod, entries: [LedgerEntry]) -> PeriodForecast
  ```

- Short, self-explanatory methods only get the summary line.
- Comments inside a method explain why, not what. Code comments are in
  English, like the rest of the code.
- Code that is touched for any reason is brought up to these rules in the
  same change.

### Compatibility from 0.6.0

Version 0.6.0 is the base the owner sets up anew. From then on, no version may
damage or lose data, on update or through a backup.

- **Database:** Every change to a stored model gets a new `VersionedSchema`
  and a migration stage. The previous schema is kept as a frozen copy. A store
  file written by the last released version is added as a test fixture and must
  open with all its data.
- **New fields** get a default value, so old stores and old backups fill them.
  Fields are not renamed or reused for another meaning. A field that is no
  longer used is removed only through a migration with a test.
- **Backup format:** A newer app reads every backup written since 0.6.0. New
  entries in a backup are optional when reading; a missing entry keeps today's
  behavior. Existing record layouts, keys, and meanings stay as they are.
- **Round trip:** Export and import of every scope (all, finance, challenges,
  health) must give back the same data. A test covers each new stored value
  in the round trip.
- **Settings and side files:** A new `AppStorage` key or file has a default
  that matches the behavior without it, and goes into the backup when the
  person sets it.
- **Changelog:** Every change to storage or backup names its migration and its
  test in the changelog.

### Design

The selected style is Green, Blue, Bordeaux, or Violet, and Appearance is
still System, Light, or Dark. The tab bar, the Home period control, settings
icons, links, highlighted rows, cards, and list or form rows use that style.
Do not leave system blue, or a plain black or white list background, on those
surfaces. Positive amounts stay green and negative amounts stay red. Symbols
the user picked for a challenge, and the icons on finance entries, keep their
own colors.

## Deutsch

### Zusammenarbeit

- Ideen, Annahmen und Anweisungen kritisch prüfen. Schwachstellen, Trade-offs
  und Risiken klar benennen.
- Ist eine zentrale Anforderung unklar, vor dem Bauen fragen, nicht raten.
- Eigene Ideen sind erwünscht, werden aber erst vorgeschlagen (Nutzen,
  Aufwand) und nur nach Zustimmung des Eigentümers gebaut.
- Jede Änderung dokumentieren: was, warum, Auswirkung und Nebenwirkungen.
- Antworten an den Eigentümer auf Deutsch: sachlich, direkt, ehrlich,
  konstruktiv.
- Funktionierendes Verhalten nicht entfernen. Vieles wirkt verschachtelt, ist
  aber gewollt (siehe Bestätigte Regeln). Im Zweifel fragen.

### Repository und Arbeitsweise

- Gearbeitet wird auf dem Versions-Branch. Ein Commit pro abgeschlossenem
  Schritt, mit klarer Nachricht. Gepusht wird nur auf den Versions-Branch, nie
  auf `main`.
- Vor jedem Commit bauen und alle Tests laufen lassen. Ein Schritt ist erst
  fertig, wenn beides grün ist.
- Pushen und Löschen von Dateien außerhalb der vereinbarten Arbeit nur nach
  Rückfrage.
- Eine neue Version setzt die Version überall: `MARKETING_VERSION` beider
  Targets, `AppVersion.current`, README und GENERAL.md.
- Jede Version hat ihren Changelog in Documentation: Überblick, dann
  ein Abschnitt pro Bereich, kurze Aufzählungen mit was, warum und Auswirkung.
- README, diese Datei und die Bereichsdokumente (FINANCE, CHALLENGES, HEALTH,
  GENERAL) bei jeder betroffenen Änderung anpassen. Neue Rechenregeln gehören
  nach FINANCE.md.
- Fachlogik liegt in den Packages (`LififyCore`, `LififyFinance`,
  `LififyChallenges`, `LififyHealth`), nie in Views. Erweiterungen wie die
  Widgets nutzen dieselben Packages.
- Das lokale Signier-Team in der Projektdatei gehört dem Eigentümer und wird
  nie committet.

Bauen und testen: die Befehle im englischen Abschnitt oben.

Der Simulator braucht keine Signatur. Fürs iPhone wählt der Eigentümer sein
Team in Xcode. Widgets, App Group, HealthKit und Live Activities brauchen
Entitlements. Das Konto des Eigentümers ist ein kostenloses persönliches Team:
Profile gelten 7 Tage, Berechtigungen wie Family Controls gibt es nicht.
Schritte im Apple-Entwicklerkonto werden dem Eigentümer beschrieben, nie
geraten.

### Technische Leitplanken

- iOS 17 oder neuer, SwiftUI, SwiftData, Swift 6.
- Keine Drittanbieter-Abhängigkeiten und keine Secrets im Repository.
- Beträge sind ganze Cent.
- Texte in beiden Sprachen über `L("Deutsch", "English")`.
- Netzwerk nur, wo nötig: Yahoo Finance, Gemini mit dem Schlüssel der Person,
  Trade Republic und die Bestandslisten von Xtrackers, VanEck und iShares.
  Jede externe Quelle steht in der README unter Datenschutz.
- Die Datenbank bleibt im App-Ordner. Widgets lesen einen Schnappschuss in der
  App Group; nur die App bucht.

### Bestätigte Regeln (nicht ändern)

**Challenges, Zeit-Slots und Gruppen**

- Eine Challenge kann eine geschätzte Dauer in Minuten haben.
- Ein Kalendertermin ist ein Zeit-Slot. Ihm werden Challenges zugewiesen, bis
  seine Minuten aufgebraucht sind (`ChallengeTimeRules.fitCount`, `remaining`).
- Ab zwei Challenges an einem Termin entsteht eine Gruppe „Termin – Tag“.
  Gruppen lassen sich auch von Hand anlegen und füllen.
- Sport und Abstinenz haben keine Minuten und belegen einen Termin immer
  allein.
- Einen Termin teilen können sich nur einmalige Challenges. Eine
  wiederkehrende Challenge darf nur einen leeren Termin allein belegen.
- Sind alle Challenges eines Termins abgehakt, rückt der Termin auf die echte
  Dauer (Ende = letzter Haken, Start = Ende minus Ist-Minuten). Im
  iOS-Kalender wird der alte Termin gelöscht und neu angelegt
  (`ChallengeTimeService.resize`).
- Vergangene Tage sind nachträglich abhakbar.
- Direkte Terminverknüpfung und Mitgliederliste des Termins bleiben getrennt;
  nur die direkte Verknüpfung bestimmt das Streak-Soll.
- Automatische Challenges (Kalorien, Schritte) sind weder von Hand abhakbar
  noch in einen Termin legbar.

**Training, Challenge und Termin**

- Die Verknüpfung ist bewusst n:m. An einem wiederkehrenden Termin können
  mehrere Trainingspläne hängen; wird einer absolviert, ist die Challenge
  abgehakt.
- Nach dem Training wird der Termin auf die echte Trainingszeit gesetzt, auf
  fünf Minuten gerundet (`WorkoutCalendarSync`).
- Vergangene Trainingstermine ohne passendes Training werden gelöscht, auch im
  iOS-Kalender (`WorkoutCalendarSync.cleanup`). Gewollt.
- Eine Sport-Challenge mit verknüpftem Training ist nur durch das Beenden des
  Trainings erledigt, nicht von Hand. Streaks gelten.

**Coins und Shop**

- Coins sind reine Gamification.
- Das Wallet darf ins Minus gehen. Bei negativem Guthaben ist der Shop
  gesperrt, bis es wieder bei null oder darüber liegt.
- Der automatische Fast-Food-Kauf bucht auch bei gesperrtem Shop.

**Depot-Prognose**

- Jede künftige Sparplan-Ausführung kauft Betrag ÷ heutiger Kurs. Ohne
  Renditeszenario gibt es keine Kursentwicklung; das bleibt die
  Standardansicht. Das Renditeszenario ist ein zusätzlicher Schalter
  (FINANCE.md).

**Trade Republic**

- Der Live-Login über die inoffizielle Web-API bleibt; die Risiken sind
  bekannt und akzeptiert. PIN und Sitzung werden nicht gespeichert, nichts wird
  automatisch abgerufen. Der PDF-Import bleibt.

**Kurzbefehle und URL-Schema**

- `lifify://notice?account=…&text=…` und `RecordBankNoticeIntent` bleiben
  bewusst offen, damit Apple Kurzbefehle aus einer Bankmitteilung eine Buchung
  machen.

**Einrichtung**

- Wird die App während der Einrichtung geschlossen, beginnt sie von vorn und
  verwirft die Teildaten. Gewollt. Nach der Einrichtung bleiben alle Daten.

### Entscheidungen

- **Nicht gewünscht:** Sparziele, Sparerpauschbetrag, Gewichtsverlauf neben
  der Kalorienbilanz, Challenge-Statistik, Wochen-Review, automatischer
  Testlauf (CI) und die App-Sperre über Bildschirmzeit (verworfen am
  24.11.2026).
- **Nicht entschieden, nicht bauen:** Abhaken aus der Mitteilung und Schlaf
  aus Apple Health.
- **Erst vorschlagen:** weitere automatische Challenges aus Health-Werten über
  Schritte hinaus, eine Desktop-Version, ein lokales Dashboard über localhost.
- **Offene Arbeit:** `DashboardView` und `TransactionsView` auf Screen-Modelle
  umbauen und die übrigen langen Methoden zerlegen (Code-Regeln); vor dem
  nächsten Release einen Store und ein Backup von 0.6.0 als Test-Fixtures
  ablegen.

### Sprache

Eine Änderung wird auf Englisch und auf Deutsch dokumentiert. Englisch steht
zuerst. Jede Version hat ihr eigenes Änderungsprotokoll, so wie
[CHANGES-0.6.0.md](Documentation/CHANGES-0.6.0.md) für 0.6.0. Nur README.md und
CLAUDE.md bleiben oben. Alle übrigen Dokumente liegen im Ordner Documentation
und haben englische Namen: die Changelogs und je Bereich eine Datei, die
erklärt, was er kann und wie er funktioniert: FINANCE.md, CHALLENGES.md,
HEALTH.md (Training, Schritte und Ernährung) und GENERAL.md (Home, Widgets,
Siri, Mitteilungen, Einstellungen, Daten, Datenschutz). Alle sind auf dieselbe
Weise zweisprachig.

### Tests

Neues Verhalten bekommt automatische Tests in `LififyTests`, geschrieben mit
Swift Testing und nach Thema gruppiert. Getestet werden echte Regeln, nicht
Konstanten oder UI-Texte gegen sich selbst. Tests laufen über `withTestStore`,
das eine In-Memory-Datenbank und eine eigene UserDefaults-Suite bereitstellt.
Sie schreiben also nie Nutzerdaten. Services lesen UserDefaults über
`AppDefaults.store`, nie direkt. Ein Schritt ist fertig, wenn Build und alle
Tests grün sind.

### Code

**Kleine Methoden, keine Doppelungen**

- Eine Methode erledigt eine Aufgabe. Richtwert: höchstens etwa 30 Zeilen.
  Eine längere Methode wird in Hilfsmethoden zerlegt, deren Namen sagen, was
  sie tun, so dass die äußere Methode wie eine kurze Liste von Schritten
  lesbar ist.
- Logik, die ein zweites Mal vorkommt, wandert in eine gemeinsame Funktion
  oder einen gemeinsamen Typ im passenden Package. Kopien sind nicht erlaubt,
  auch kein kopierter View-Code.
- Wiederverwendung läuft über **Protokolle mit Standard-Implementierungen**
  (Protocol Extensions), Generics und Komposition. Das ist die Swift-Form der
  Vererbung und funktioniert für Structs, Enums und Klassen gleichermaßen.
- Klassenvererbung nur, wo sie wirklich eine „ist ein“-Beziehung abbildet
  oder ein Framework sie verlangt. Vererbung bei SwiftData-Modellen braucht
  iOS 26 und wird nicht genutzt, solange die App iOS 17 unterstützt.
- SwiftUI: Gemeinsames Aussehen und Verhalten gehört in `ViewModifier` und
  kleine Unter-Views, nicht in wiederholte Modifier-Ketten.
- Ein `enum` nur mit statischen Funktionen ist als Namensraum in Ordnung.
  Daten mit Verhalten sind ein `struct` (oder eine Klasse, wo
  Referenzsemantik nötig ist), das die passenden Protokolle erfüllt.

**Dokumentation im Code**

- Jeder Typ (Struct, Klasse, Enum, Protokoll, Extension mit eigenem Zweck)
  und jede Methode oder Eigenschaft, die nicht trivial privat ist, bekommt
  darüber einen `///`-Kommentar: ein bis zwei Sätze, was sie tut, und warum,
  wenn das nicht offensichtlich ist.
- Längere Methoden (mehr als etwa 15 Zeilen) oder Methoden mit Parametern,
  deren Bedeutung nicht offensichtlich ist, nennen zusätzlich Eingabe und
  Ausgabe im DocC-Format (`- Parameters:`, `- Returns:`, ggf. `- Throws:`),
  wie im englischen Beispiel oben.
- Kurze, selbsterklärende Methoden bekommen nur die Zusammenfassung.
- Kommentare innerhalb einer Methode erklären das Warum, nicht das Was.
  Code-Kommentare sind wie der übrige Code auf Englisch.
- Code, der aus irgendeinem Grund angefasst wird, wird in derselben Änderung
  auf diese Regeln gebracht.

### Kompatibilität ab 0.6.0

Version 0.6.0 ist die Grundlage, die der Eigentümer neu einrichtet. Ab dann
darf keine Version Daten beschädigen oder verlieren, weder beim Update noch
über ein Backup.

- **Datenbank:** Jede Änderung an einem gespeicherten Modell bekommt ein neues
  `VersionedSchema` und eine Migrationsstufe. Das vorige Schema bleibt als
  eingefrorene Kopie erhalten. Eine Store-Datei der zuletzt ausgelieferten
  Version kommt als Test-Fixture dazu und muss mit allen Daten öffnen.
- **Neue Felder** bekommen einen Standardwert, damit alte Stores und alte
  Backups sie füllen. Felder werden nicht umbenannt und nicht für eine andere
  Bedeutung wiederverwendet. Ein nicht mehr genutztes Feld entfällt nur über
  eine Migration mit Test.
- **Backup-Format:** Eine neuere App liest jedes Backup seit 0.6.0. Neue
  Einträge im Backup sind beim Lesen optional; fehlt einer, bleibt das heutige
  Verhalten. Bestehende Satzaufbauten, Schlüssel und Bedeutungen bleiben, wie
  sie sind.
- **Hin und zurück:** Export und Import jedes Bereichs (alles, Finanzen,
  Challenges, Gesundheit) müssen dieselben Daten ergeben. Ein Test deckt jeden
  neuen gespeicherten Wert in diesem Kreislauf ab.
- **Einstellungen und Nebendateien:** Ein neuer `AppStorage`-Schlüssel oder eine
  neue Datei hat einen Standard, der dem Verhalten ohne ihn entspricht, und
  kommt ins Backup, sobald die Person ihn setzt.
- **Changelog:** Jede Änderung an Speicher oder Backup nennt im Changelog ihre
  Migration und ihren Test.

### Design

Der gewählte Stil ist Grün, Blau, Bordeaux oder Violett, und das
Erscheinungsbild bleibt System, Hell oder Dunkel. Die Tableiste, die
Zeitraumwahl auf Home, die Symbole in den Einstellungen, Links, hervorgehobene
Zeilen, Karten und die Zeilen von Listen oder Formularen nutzen diesen Stil.
Auf diesen Flächen bleibt kein Systemblau und kein schwarz-weißer
Listenhintergrund übrig. Positive Beträge bleiben grün, negative rot. Symbole,
die man für eine Challenge gewählt hat, und die Symbole an Finanzbuchungen
behalten ihre eigene Farbe.
